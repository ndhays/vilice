// Command steward is the one door to a box's power: every action arrives as a
// named command from a scoped actor, and is recorded before it runs. There is no
// daemon — sshd invokes steward for privileged actions (over a scoped key pinned
// to a forced command) and systemd invokes it on a timer to keep the record.
//
// Callers are clients, never peers: the console, a CI job, and a person at a shell
// all come through the same door. Each concern is specified in blueprint/steward/.
//
// This file is the whole of the wiring: register the packs, then hand argv to the
// core. Everything a pack contributes still enters through the core's gate.
package main

import (
	"os"

	"steward/internal/core"
	"steward/internal/pack/app"
)

func main() {
	core.Register(app.New())
	os.Exit(core.Main(os.Args[1:]))
}
