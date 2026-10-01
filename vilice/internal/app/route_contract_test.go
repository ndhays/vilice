package app

import (
	"encoding/json"
	"os"
	"strings"
	"testing"
)

// The contract between the console and this verb, pinned.
//
// testdata/console-route-envelope.json is not hand-written: it is the literal output of
// the console's `RoutingTable.envelope`, captured from a running app. The two halves live
// in different languages and different release cycles, so a field renamed on one side
// would otherwise fail silently on a box rather than in anyone's test suite. Regenerate
// it from the console when the shape genuinely changes; do not edit it by hand.
func TestConsoleEnvelopeIsAValidTable(t *testing.T) {
	data, err := os.ReadFile("testdata/console-route-envelope.json")
	if err != nil {
		t.Fatal(err)
	}

	var tbl routeTable
	if err := json.Unmarshal(data, &tbl); err != nil {
		t.Fatalf("the console's envelope no longer parses here: %v", err)
	}
	if err := validateTable(tbl); err != nil {
		t.Fatalf("the console's envelope is not a table this verb accepts: %v", err)
	}

	// Field names carried, not just valid JSON: an envelope that parsed into an empty
	// table would pass the checks above and route nothing.
	if len(tbl.Routes) == 0 {
		t.Fatal("parsed to zero routes — the field names have drifted apart")
	}
	for _, r := range tbl.Routes {
		if len(r.Hostnames) == 0 || len(r.Upstreams) == 0 {
			t.Fatalf("a route lost its hostnames or upstreams in translation: %+v", r)
		}
	}

	got := renderRoutes(tbl)
	if !strings.Contains(got, "reverse_proxy") {
		t.Errorf("rendered no proxy directive:\n%s", got)
	}
	// The console addresses backends at their own edge, never loopback.
	if strings.Contains(got, "127.0.0.1") {
		t.Errorf("console upstreams should be other boxes:\n%s", got)
	}
}
