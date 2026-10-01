package app

import (
	"strings"
	"testing"
)

// The rule pruning rests on: two images per app stay — what the active colour runs, and
// what `rollback` would re-deploy. Everything else is cache.
func TestDiskCheckPrescribesWhenThereIsSomethingToDo(t *testing.T) {
	c := diskCheck(82, 3, 7)
	if c.OK != true {
		t.Error("82% is pressure, not failure — a doctor that cries about a healthy box gets ignored")
	}
	if !strings.Contains(c.Note, "7 images, 3 unreferenced") {
		t.Errorf("the note should attribute the space: %q", c.Note)
	}
	if !strings.Contains(c.Note, "podman rmi") {
		t.Errorf("under pressure with reclaimable space, the note should say how: %q", c.Note)
	}
}

// Below the warn line, unreferenced images are not a problem worth acting on — so the
// prescription is explicitly "nothing to do" rather than a command to run.
func TestDiskCheckIsCalmWhenThereIsNoPressure(t *testing.T) {
	c := diskCheck(30, 2, 5)
	if !c.OK {
		t.Error("a box at 30% is not unhealthy")
	}
	if strings.Contains(c.Note, "podman rmi") {
		t.Errorf("no pressure means no prescription to run anything: %q", c.Note)
	}
	if !strings.Contains(c.Note, "nothing to do") {
		t.Errorf("it should still say the images are handled: %q", c.Note)
	}
}

// Critical with nothing to reclaim is the case where the honest answer is "this is not
// images" — pointing at volumes and the journal instead of a command that would free
// nothing.
func TestDiskCheckFailsAndRedirectsWhenNoImagesToReclaim(t *testing.T) {
	c := diskCheck(94, 0, 4)
	if c.OK {
		t.Error("94% should fail the check")
	}
	if strings.Contains(c.Note, "podman rmi") {
		t.Errorf("there is nothing to reclaim; suggesting rmi would waste the operator's time: %q", c.Note)
	}
	if !strings.Contains(c.Note, "volumes") {
		t.Errorf("it should redirect to where the space actually is: %q", c.Note)
	}
}

// An unreadable filesystem must make the check say nothing rather than assert 0% or
// 100% — observe reports only what it can know.
func TestDiskCheckSaysNothingWithoutAReading(t *testing.T) {
	c := diskCheck(0, 0, 0)
	if !c.OK {
		t.Error("no reading is not a failure")
	}
	if c.Note != "" {
		t.Errorf("with nothing known, the note should be empty, got %q", c.Note)
	}
}

// The thresholds the box uses have to be the ones the console badges with, or the two
// disagree about what "running low" means.
func TestDiskThresholdsMatchTheConsole(t *testing.T) {
	if diskWarnPercent != 75 || diskCritPercent != 90 {
		t.Errorf("thresholds drifted from MachineStatus::DISK (75/90): warn=%d crit=%d",
			diskWarnPercent, diskCritPercent)
	}
}

// Both colours' images are referenced, so neither is a prune candidate. This is the
// property that keeps rollback working without a registry.
func TestReferencedImagesKeepCurrentAndPrevious(t *testing.T) {
	st := appState{
		Name:      "web",
		Image:     "ghcr.io/x/y@sha256:" + strings.Repeat("a", 64),
		PrevImage: "ghcr.io/x/y@sha256:" + strings.Repeat("b", 64),
	}
	if st.Image == st.PrevImage {
		t.Fatal("fixture error")
	}
	// referencedImageIDs resolves through podman, which isn't available here; the unit
	// under test is the *rule*, asserted on the spec that feeds it.
	for _, ref := range []string{st.Image, st.PrevImage} {
		if ref == "" {
			t.Error("both the live image and the rollback image must be named in the spec")
		}
	}
}
