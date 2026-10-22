package app

// App state on disk: one JSON file per app.

import (
	"vilice/internal/core"

	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// --- app state (one JSON file per app) ---

// validAppName is the charset an app name may use. It is the same rule as a client
// name today, but they are different things and will drift; keeping them apart means
// neither one loosens the other by accident.
//

func appPath(name string) string { return filepath.Join(appsDir(), name+".json") }

// saveApp is the chokepoint the renderers stand behind: every app state that reaches a
// Caddy site block or a Quadlet unit was either just validated by stateFromSpec or
// loaded from a file that passed through here. It checks *renderability* rather than the
// full spec, because it is also on the path for state that came off disk — a `rollback`
// re-persists a spec the box already had, and re-writing it unchanged should not be the
// moment a policy rule introduced later condemns it.
func saveApp(st appState) error {
	if err := validateRenderable(st); err != nil {
		return fmt.Errorf("refusing to persist an invalid app state: %w", err)
	}
	if err := os.MkdirAll(appsDir(), 0o750); err != nil {
		return err
	}
	b, err := json.MarshalIndent(st, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(appPath(st.Name), b, 0o640)
}

func loadApp(name string) (appState, bool) {
	if !core.ValidAppName(name) {
		return appState{}, false
	}
	b, err := os.ReadFile(appPath(name))
	if err != nil {
		return appState{}, false
	}
	var st appState
	if json.Unmarshal(b, &st) != nil {
		return appState{}, false
	}
	return st, true
}

func removeApp(name string) error {
	if !core.ValidAppName(name) {
		return fmt.Errorf("refusing to remove state for invalid app name %q", name)
	}
	err := os.Remove(appPath(name))
	if os.IsNotExist(err) {
		return nil
	}
	return err
}

func listApps() ([]appState, error) {
	entries, err := os.ReadDir(appsDir())
	if os.IsNotExist(err) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var apps []appState
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".json") {
			continue
		}
		if st, ok := loadApp(strings.TrimSuffix(e.Name(), ".json")); ok {
			apps = append(apps, st)
		}
	}
	return apps, nil
}
