package app

// Evicting images the box no longer references.
//
// A deploy pulls a new image and the old one stays. Nothing removed it, so a box that
// deploys often fills its disk with layers nobody can name — the most common way an
// otherwise healthy unattended machine dies.
//
// **The local image store is a cache, not a record.** The record is the app spec, which
// names its image by digest, and which `backup` captures and `restore` replays through
// `runDeploy` — so a restored box *re-pulls* what it needs. Because the reference is a
// digest and not a tag, what comes back is byte-identical. An evicted image is therefore
// not lost, and pruning is not destruction.
//
// Two are kept per app: `Image` (what the active colour runs) and `PrevImage` (what
// `rollback` re-deploys). Rollback is the emergency path — 3am, something is broken, and
// the last thing it should need is a reachable registry. Restore can afford that
// dependency because it is planned; rollback cannot, so its image stays local.
//
// Nothing here is allowed to fail a deploy. Cleanup that can break the act it follows is
// worse than the garbage it collects.

import (
	"fmt"
	"strings"
)

// referencedImageIDs is every image any app on this box still needs, resolved to Podman
// image IDs rather than compared as strings: the same image can be named by tag, by
// digest, or by a repository the operator has since renamed, and only the ID is stable.
func referencedImageIDs() map[string]bool {
	apps, err := listApps()
	if err != nil {
		return nil
	}
	keep := map[string]bool{}
	for _, a := range apps {
		for _, ref := range []string{a.Image, a.PrevImage} {
			if ref == "" {
				continue
			}
			if id := imageID(ref); id != "" {
				keep[id] = true
			}
		}
	}
	return keep
}

// imageID resolves a reference to its local image ID, or "" when the box does not have
// it (already gone, or never pulled).
func imageID(ref string) string {
	out, err := podmanOutput("image", "inspect", ref, "--format", "{{.Id}}")
	if err != nil {
		return ""
	}
	return strings.TrimSpace(out)
}

// localImageIDs is every image this box is holding.
func localImageIDs() []string {
	out, err := podmanOutput("images", "--quiet", "--no-trunc")
	if err != nil {
		return nil
	}
	var ids []string
	for _, line := range strings.Split(out, "\n") {
		if id := strings.TrimSpace(line); id != "" {
			ids = append(ids, id)
		}
	}
	return ids
}

// pruneImages drops every local image no app still references, and reports what it
// removed. Best-effort throughout: a failure to resolve, list, or remove is not an error
// worth surfacing, because nothing downstream depends on the space being freed.
//
// Safety rests on `podman rmi` *without* --force: Podman refuses to remove an image any
// container still uses, even a stopped one. So the worst case for an image we misjudged
// is a refusal we ignore, never a running app losing its layers.
func pruneImages() (removed int, note string) {
	keep := referencedImageIDs()
	if keep == nil {
		return 0, "" // could not read the specs — say nothing rather than guess
	}
	for _, id := range localImageIDs() {
		if keep[id] {
			continue
		}
		if err := userExec("podman", "rmi", id).Run(); err == nil {
			removed++
		}
	}
	if removed == 0 {
		return 0, ""
	}
	return removed, fmt.Sprintf("pruned %d unreferenced image%s", removed, plural(removed))
}

// unreferencedImageCount is the read-only half, for `doctor`: how many images the box is
// holding that nothing references. Counting is safe where removing might not be, so this
// never touches anything.
func unreferencedImageCount() (unreferenced, total int) {
	keep := referencedImageIDs()
	ids := localImageIDs()
	for _, id := range ids {
		if !keep[id] {
			unreferenced++
		}
	}
	return unreferenced, len(ids)
}
