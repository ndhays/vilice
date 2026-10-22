# The SSH gate — a request for outside review

Not yet reviewed by anyone outside the project. This is the note to send with the ask.

## What it is

Vilice is a self-hosting tool that records every state-changing action to a hash-chained
log before running it. It has no daemon and no network listener. Every remote caller
arrives over OpenSSH with a key pinned to a forced command:

```
command="/usr/local/bin/vilice _exec --client <name> --scope <observe|operate|grant>",restrict ssh-ed25519 AAAA…
```

`_exec` reads `SSH_ORIGINAL_COMMAND`, resolves it to one named command, checks the
command's scope against the key's, writes the record, and runs it. That is the whole gate.
Most of the code was written by an LLM, which is why a person should read this part.

## The claim to break

1. A key can run only the named commands at or below its scope. No key gets a shell.
2. Every state-changing command is written to the record before it runs. If the record
   cannot be written, the command does not run.
3. A request the gate denies (wrong scope, unknown command, no command) is recorded too.
4. `prepare`, `harden` and `uninstall` (root) and `snapshot` (systemd) cannot be reached
   with any key.

## What to read

About 900 lines of Go, standard library only, plus the tests.

| File | What is in it |
|---|---|
| `vilice/internal/core/auth.go` | `authorize`, `revoke`, the forced-command line, and `_exec` (`decideExec`, `authExec`) |
| `vilice/internal/core/dispatch.go` | `Main`, `enter` (the one door), the account gate, `Dispatch` (record, then run), flag checks |
| `vilice/internal/core/commands.go` | The command table: each command's scope and flags |
| `vilice/internal/core/harden/10-ssh.sh` | What `harden` sets in sshd |
| `vilice/internal/core/auth_test.go`, `gate_test.go`, `inject_test.go` | The tests, including the fuzz target `FuzzForcedLineIsOneLine` |
| `blueprint/vilice/auth.md` | The spec the code is meant to match |
| `decisions/no-key-gets-a-shell.md`, `decisions/rendered-config-is-a-boundary.md` | Why it is this shape |

## Where I would look first

These are the places I am least sure of. Each is a question, not a known bug.

**Writing the ledger (`authorized_keys`)**

1. `looksLikePubkey` is what keeps a key to one line. It checks for control characters, a
   known type prefix, a base64 charset, and at most three fields. It does not decode the
   blob. Can any input that passes it put a second entry, or extra options, into the file?
2. `forcedLine` quotes the command with Go's `%q`. sshd parses the option with its own
   rules. Do the two agree for every binary path `os.Executable()` can return?
3. `removeClient` finds a client's line by the substring `--client <name> ` anywhere in
   the line. Can a line be made to match a client it does not belong to, or to escape
   `revoke`?
4. `authorize` removes the old line and then appends the new one, with `os.WriteFile` and
   no lock. What can a second `authorize`, or an sshd login, see in between?
5. `actors` reports lines Vilice did not write. Is there a line sshd would honour that
   `actors` would show as pinned?

**Reading the request (`_exec`)**

6. `SSH_ORIGINAL_COMMAND` is split with `strings.Fields` and never reaches a shell.
   Confirm nothing downstream of `Dispatch` hands those words to one.
7. `--json` is stripped from any position, including where a flag's value would sit. Can
   that change what a command is asked to do?
8. `help`, `version`, `_exec`, `_man` and `_commands` are handled in `Main` before the
   command table. Over SSH the request goes to `decideExec`, not `Main`. Is there a way to
   reach the `Main` cases with a key?
9. The scope check is `scopeRank(cmd.Scope) > scopeRank(granted)`, and an unknown scope
   ranks 0. Is there any command or grant value for which that comparison lets something
   through?
10. Flags are checked against the command's declared list before the record is written.
    The app name is checked against `[A-Za-z0-9_-]`. What other argument reaches a file
    path, a unit name, or a rendered config without a check?

**The environment**

11. Many paths the binary trusts can be set by an environment variable
    (`VILICE_AUTHORIZED_KEYS`, `VILICE_RECORD`, `VILICE_APPS_DIR`, `VILICE_BIND_ROOTS`
    and others), for tests. The gate relies on sshd not passing a client's environment
    through: `restrict`, and the stock `AcceptEnv` and `PermitUserEnvironment` settings.
    `harden` is optional and does not set either. Is that enough?
12. Which sshd settings outside the key line could undo the forced command for the
    `_vilice` account: a second `AuthorizedKeysFile`, a `Match` block, `ForceCommand`,
    certificates and `TrustedUserCAKeys`, `authorized_principals`?
13. Does `restrict` cover everything it should on the OpenSSH versions Ubuntu 24.04 and
    26.04 ship, including anything added to OpenSSH after `restrict` was?

**Recording**

14. `Dispatch` writes the record and then runs the command. Find a state-changing path
    that runs without a record: a command whose scope makes `recordable` return false, or
    a failure between the two steps.
15. A denied request is recorded best-effort, and the error is dropped. Can a caller make
    that write fail on purpose and probe without leaving a trace?
16. `deploy` takes its spec, with secret values, on stdin. Confirm no secret value reaches
    the record, argv, or a log.

**The account gate**

17. Non-root commands must run as `_vilice`. Where no `_vilice` account exists, only bare
    root is refused. Is there a state of a real box where that fallback applies?
18. The binary is checked against a digest recorded at `prepare`. A few commands skip the
    check so a box can be repaired. Is any of them a way to act with a swapped binary?

## What is out of scope

The console (the Rails app), the container and Caddy config that `deploy` renders, and the
release signing. They matter, and they are not this request.

## What I would like back

A list of findings, each with the input or state that shows it. "I read it and found
nothing in these areas" is a useful answer too. Reports go to the address in
[`SECURITY.md`](../SECURITY.md), privately.

## Run it

```bash
git clone https://github.com/ndhays/vilice && cd vilice
make check          # format, vet, tests
make -C vilice fuzz # the fuzz targets, 30s each
```
