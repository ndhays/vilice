package app

// An app's secrets in the Podman secret store: names in state, values only here.

import (
	"fmt"
	"os"
	"sort"
	"strings"
)

// secretRef namespaces a secret to its app (Podman secret names are global).
func secretRef(app, name string) string { return app + "__" + name }

func sortedKeys(m map[string]string) []string {
	ks := make([]string, 0, len(m))
	for k := range m {
		ks = append(ks, k)
	}
	sort.Strings(ks)
	return ks
}

// declaredSecretNames is every secret an app declares — env (Secrets) and file
// (SecretFiles) alike. Both share one Podman store under secretRef, so storing and
// removing must cover the same set; routing remove through this helper keeps a file
// secret from orphaning in the store when its app is removed.
func declaredSecretNames(st appState) []string {
	names := make([]string, 0, len(st.Secrets)+len(st.SecretFiles))
	names = append(names, st.Secrets...)
	for n := range st.SecretFiles {
		names = append(names, n)
	}
	// An accessory's secrets ride the same envelope — one sweep carries everything this
	// app needs, the database password included. They are namespaced *in the store* by
	// the accessory's container (accessorySecretRef) but declared by their plain name
	// here, because that is the name the value arrives under.
	for _, a := range st.Accessories {
		names = append(names, a.Secrets...)
	}
	return names
}

// putSecrets stores each declared secret's value in the Podman secret store. Env
// secrets and file secrets share one store and one delivery (values arrive with the
// deploy, never recorded); only how the unit consumes them differs (env vs mount). An
// undeclared value, or a declared secret with no value, is an error.
func putSecrets(st appState, values map[string]string) error {
	declared := map[string]bool{}
	for _, n := range declaredSecretNames(st) {
		declared[n] = true
	}
	for name := range values {
		if !declared[name] {
			return fmt.Errorf("secret_values has %q, not declared in app.secrets or app.secret_files", name)
		}
	}
	// Where each declared name is stored. An accessory's secret lands under its own
	// container's namespace, so the app's POSTGRES_PASSWORD and the database's cannot
	// collide in a store whose names are global.
	ref := map[string]string{}
	for _, n := range st.Secrets {
		ref[n] = secretRef(st.Name, n)
	}
	for n := range st.SecretFiles {
		ref[n] = secretRef(st.Name, n)
	}
	for _, a := range st.Accessories {
		for _, n := range a.Secrets {
			ref[n] = accessorySecretRef(st.Name, a.Name, n)
		}
	}
	for name := range declared {
		val, ok := values[name]
		if !ok {
			return fmt.Errorf("no value provided for declared secret %q", name)
		}
		if err := putSecret(ref[name], val); err != nil {
			return fmt.Errorf("store secret %q: %w", name, err)
		}
	}
	return nil
}

// putSecret writes one value into the Podman secret store via stdin (never argv).
// rm-then-create makes it rotation-safe across Podman versions.
func putSecret(ref, value string) error {
	_ = userExec("podman", "secret", "rm", ref).Run() // ignore "no such secret"
	c := userExec("podman", "secret", "create", ref, "-")
	c.Stdin = strings.NewReader(value)
	c.Stderr = os.Stderr
	return c.Run()
}
