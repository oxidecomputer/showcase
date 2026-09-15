package oxide

import (
	"testing"

	"github.com/oxidecomputer/showcase/integration/buildkite/internal/config"
)

func TestResourceNameRoundTrip(t *testing.T) {
	provider := New(nil, config.Oxide{}, "oxide-production")
	jobID := "12345678-1234-1234-1234-123456789abc"
	name := provider.name(jobID)
	if len(name) > 63 {
		t.Fatalf("resource name is %d characters", len(name))
	}
	got, ok := provider.jobID(name)
	if !ok || got != jobID {
		t.Fatalf("jobID(%q) = %q, %v", name, got, ok)
	}
	if _, ok := provider.jobID("someone-elses-instance"); ok {
		t.Fatal("provider claimed an unowned resource")
	}
}
