package app

// The release step: run an app's declared command once, from the new image, before the
// new color starts serving. Migrations are the case this exists for.
//
// The whole design is in decisions/open/release-command.md; the parts that constrain
// this file:
//
//   - **Declared, never passed.** `Release` is a field on the app spec, alongside port
//     and health, covered by the spec digest. There is no `--release` flag and no
//     `vilice exec`: a per-invocation command would mean the same digest behaving
//     differently depending on what somebody typed, and a standing exec verb would be
//     a shell by another name.
//   - **argv, never a shell.** Exec'd directly, so the recorded line is unambiguous and
//     a multi-step release has to live in a script inside the image — where the digest
//     covers what it does.
//   - **Before the new color starts.** A failed release then changes nothing: no unit
//     written, no color started, the old one still serving.
//   - **Detached, and not `--rm`.** An interrupted migration is worse than a failed one,
//     and this is the only step in a deploy where that is true. Run detached and the
//     work survives a dropped SSH connection; keep the container on failure and its
//     logs are still there to read.

import (
	"fmt"
	"strconv"
	"strings"
	"time"

	"vilice/internal/core"
)

const (
	// Long enough for a real migration on a real database, short enough that a wedged
	// one does not hold a deploy open forever. A constant until an app needs otherwise.
	releaseTimeout = 10 * time.Minute
	releasePoll    = 2 * time.Second
	// How much of a failed run to hand back. The whole point is that the operator reads
	// the error without leaving for a shell, so it is a tail rather than a summary.
	releaseLogLines = "50"
)

// releaseContainer names the run after the spec it belongs to, so a retry can tell
// "already running" from "already succeeded" from "failed" instead of blindly running a
// migration again that may be half applied. The digest is the spec's own.
func releaseContainer(app, digest string) string {
	short := strings.TrimPrefix(digest, "sha256:")
	if len(short) > 12 {
		short = short[:12]
	}
	if short == "" {
		short = "nodigest"
	}
	return app + "-release-" + short
}

// runRelease executes st.Release from st.Image and returns nil when it exits 0.
// A no-op when nothing is declared, which is the common case.
func runRelease(st appState) error {
	if len(st.Release) == 0 {
		return nil
	}
	name := releaseContainer(st.Name, st.Digest)

	// A container from a previous attempt at *this same spec* is either still running —
	// in which case joining it beats starting a second migration beside it — or finished,
	// in which case its verdict already stands. Neither is a reason to run again.
	switch status := inspectField(name, "{{.State.Status}}"); status {
	case "running":
		return waitRelease(name)
	case "exited":
		if code := inspectField(name, "{{.State.ExitCode}}"); code == "0" {
			return nil // this spec's release already succeeded on this box
		}
		// A failed run is kept as evidence; clear it so the retry is a fresh attempt.
		_ = userExec("podman", "rm", "-f", name).Run()
	case "":
		// No such container. The ordinary path.
	default:
		_ = userExec("podman", "rm", "-f", name).Run()
	}

	args := []string{"run", "--detach", "--name", name}
	args = append(args, releaseFlags(st)...)
	args = append(args, st.Image)
	args = append(args, st.Release...)

	if out, err := podmanOutput(args...); err != nil {
		// Nothing ran, so trying again is safe — this one is retryable.
		return &codedError{code: "release_failed", retryable: true,
			msg: "release: could not start: " + strings.TrimSpace(out)}
	}
	return waitRelease(name)
}

// releaseFlags builds the container's environment from the app's own declaration — the
// same env, secrets and volumes the app runs with, because a migration that cannot reach
// the database is not a migration. **Vilice constructs every flag**; none is ever passed
// through from a caller, which is what keeps `--privileged` from arriving with one.
//
// The ceiling matches the app's unit (see renderQuadletUnit): a release step is not a
// chance to run with more than the app has.
func releaseFlags(st appState) []string {
	args := []string{
		"--security-opt", "no-new-privileges",
		"--cap-drop", "CAP_NET_BIND_SERVICE",
		"--cap-drop", "CAP_SETFCAP",
		"--cap-drop", "CAP_SETPCAP",
		"--cap-drop", "CAP_SYS_CHROOT",
		"--env", "PORT=" + strconv.Itoa(st.Port),
	}
	for _, k := range sortedKeys(st.Env) {
		args = append(args, "--env", k+"="+st.Env[k])
	}
	for _, name := range st.Secrets {
		args = append(args, "--secret", secretRef(st.Name, name)+",type=env,target="+name)
	}
	for _, name := range sortedKeys(st.SecretFiles) {
		args = append(args, "--secret", secretRef(st.Name, name)+",type=mount,target="+st.SecretFiles[name])
	}
	for _, v := range st.Volumes {
		args = append(args, "--volume", v)
	}
	return args
}

// waitRelease polls until the container exits, then reads its verdict. Polling rather
// than attaching is the point: the run is detached, so a dropped connection or a
// restarted Vilice leaves the migration running instead of severing it mid-statement.
func waitRelease(name string) error {
	deadline := time.Now().Add(releaseTimeout)
	for {
		switch inspectField(name, "{{.State.Status}}") {
		case "exited":
			return releaseVerdict(name)
		case "":
			return &codedError{code: "release_failed", retryable: false,
				msg: fmt.Sprintf("release: container %s vanished before it finished", name)}
		}
		if time.Now().After(deadline) {
			// Left running on purpose. Killing a migration at the timeout is the
			// half-applied schema this design exists to avoid; the operator decides.
			// **Not retryable**: something should look at it before anything runs again.
			return &codedError{code: "release_timeout", retryable: false,
				msg: fmt.Sprintf("release: still running after %s — it was left alone rather "+
					"than interrupted; check `podman logs %s` on the box", releaseTimeout, name)}
		}
		time.Sleep(releasePoll)
	}
}

// releaseVerdict turns an exited container into an error or a nil, and reaps it on
// success. A failure is kept: the stopped container is the evidence, and the next
// successful attempt at the same spec clears it.
func releaseVerdict(name string) error {
	if code := inspectField(name, "{{.State.ExitCode}}"); code != "0" {
		out, _ := podmanOutput("logs", "--tail", releaseLogLines, name)
		// **Never retryable.** A migration that failed will fail the same way next time,
		// and an orchestrator that reruns it is the thing to design against.
		return &codedError{code: "release_failed", retryable: false,
			msg: fmt.Sprintf("release exited %s, nothing was deployed:\n%s",
				code, strings.TrimSpace(out))}
	}
	_ = userExec("podman", "rm", name).Run()
	return nil
}

// inspectField reads one field of a container, or "" when there is no such container.
func inspectField(name, format string) string {
	out, err := podmanOutput("inspect", "--format", format, name)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(out)
}

// validRelease checks the declared command's shape. It is argv, so the only things that
// can be wrong are structural — and a control character still gets refused, because this
// text is echoed into a record entry and an error message.
func validRelease(argv []string) error {
	if len(argv) == 0 {
		return nil
	}
	if strings.TrimSpace(argv[0]) == "" {
		return fmt.Errorf("release: the first element must be the program to run")
	}
	for _, a := range argv {
		if core.HasControlChar(a) {
			return fmt.Errorf("release argument %q contains a control character", a)
		}
	}
	return nil
}
