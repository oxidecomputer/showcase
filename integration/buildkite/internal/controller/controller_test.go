package controller

import (
	"context"
	"io"
	"log/slog"
	"strings"
	"testing"
	"time"
)

type fakeBuildkite struct {
	jobs       []Job
	states     map[string]string
	paused     bool
	reserved   []string
	stateCalls [][]string
}

func (f *fakeBuildkite) Register(context.Context) (string, error) { return "queue-id", nil }
func (f *fakeBuildkite) Deregister(context.Context) error         { return nil }
func (f *fakeBuildkite) ScheduledJobs(context.Context, string) ([]Job, bool, error) {
	return f.jobs, f.paused, nil
}
func (f *fakeBuildkite) Reserve(_ context.Context, id string) (bool, error) {
	f.reserved = append(f.reserved, id)
	return true, nil
}
func (f *fakeBuildkite) JobStates(_ context.Context, ids []string) (map[string]string, error) {
	f.stateCalls = append(f.stateCalls, ids)
	return f.states, nil
}

type provisionCall struct {
	jobID    string
	userData string
}

type fakeOxide struct {
	resources []Resource
	provision []provisionCall
	cleanup   []Resource
}

func (f *fakeOxide) Resources(context.Context) ([]Resource, error) {
	return f.resources, nil
}
func (f *fakeOxide) Provision(_ context.Context, id string, data []byte) error {
	f.provision = append(f.provision, provisionCall{id, string(data)})
	return nil
}
func (f *fakeOxide) Cleanup(_ context.Context, resource Resource) error {
	f.cleanup = append(f.cleanup, resource)
	return nil
}

func newTestController(t *testing.T, bk *fakeBuildkite, ox *fakeOxide, maxJobs int) *Controller {
	t.Helper()
	controller, err := New(
		bk,
		ox,
		slog.New(slog.NewTextHandler(io.Discard, nil)),
		Config{
			PollInterval: time.Second,
			MaxJobs:      maxJobs,
			QueueKey:     "oxide",
			AgentToken:   "secret-token",
			Tags:         []string{"os=linux"},
		},
	)
	if err != nil {
		t.Fatal(err)
	}
	return controller
}

func TestReconcileReservesSpecificMatchingJob(t *testing.T) {
	bk := &fakeBuildkite{jobs: []Job{
		{ID: "wrong-shape", Priority: 100, AgentQueryRules: []string{"shape=large"}},
		{ID: "low", Priority: 1, AgentQueryRules: []string{"os=linux", "queue=oxide"}},
		{ID: "high", Priority: 10, AgentQueryRules: []string{"os=linux", "queue=oxide"}},
	}}
	ox := &fakeOxide{}
	controller := newTestController(t, bk, ox, 1)

	if err := controller.reconcile(context.Background(), "queue-id"); err != nil {
		t.Fatal(err)
	}
	if len(bk.reserved) != 1 || bk.reserved[0] != "high" {
		t.Fatalf("reserved jobs = %v, want [high]", bk.reserved)
	}
	if len(ox.provision) != 1 || ox.provision[0].jobID != "high" {
		t.Fatalf("provision calls = %v", ox.provision)
	}
	userData := ox.provision[0].userData
	for _, want := range []string{
		`--acquire-job="high"`,
		"--disconnect-after-job",
		`--tags="os=linux,queue=oxide"`,
		"export BUILDKITE_AGENT_TOKEN=",
		"--reuid=buildkite-agent",
		"--regid=buildkite-agent",
	} {
		if !strings.Contains(userData, want) {
			t.Errorf("user data does not contain %q:\n%s", want, userData)
		}
	}
	if strings.Contains(userData, "--token") {
		t.Fatal("user data passes the agent token as a process argument")
	}
	if strings.Contains(userData, "secret-token") {
		t.Fatal("user data contains the plaintext agent token")
	}
}

func TestReconcileRecoversAndCleansCompletedJob(t *testing.T) {
	bk := &fakeBuildkite{states: map[string]string{"job-1": "finished"}}
	ox := &fakeOxide{resources: []Resource{
		{JobID: "job-1", InstanceState: "running"},
		{JobID: "job-1", DiskState: "attached"},
	}}
	controller := newTestController(t, bk, ox, 2)

	if err := controller.reconcile(context.Background(), "queue-id"); err != nil {
		t.Fatal(err)
	}
	if len(bk.stateCalls) != 1 || len(bk.stateCalls[0]) != 1 || bk.stateCalls[0][0] != "job-1" {
		t.Fatalf("state calls = %v", bk.stateCalls)
	}
	if len(ox.cleanup) != 1 || ox.cleanup[0].JobID != "job-1" {
		t.Fatalf("cleanup calls = %v", ox.cleanup)
	}
}

func TestReconcileCleansOrphanedDiskAfterProvisioningFailure(t *testing.T) {
	bk := &fakeBuildkite{states: map[string]string{"job-1": "reserved"}}
	ox := &fakeOxide{resources: []Resource{{
		JobID: "job-1", DiskState: "detached",
	}}}
	controller := newTestController(t, bk, ox, 2)

	if err := controller.reconcile(context.Background(), "queue-id"); err != nil {
		t.Fatal(err)
	}
	if len(ox.cleanup) != 1 || ox.cleanup[0].JobID != "job-1" {
		t.Fatalf("cleanup calls = %v", ox.cleanup)
	}
}

func TestReconcileDoesNotDuplicateRecoveredJob(t *testing.T) {
	bk := &fakeBuildkite{
		jobs:   []Job{{ID: "job-1", AgentQueryRules: []string{"queue=oxide"}}},
		states: map[string]string{"job-1": "running"},
	}
	ox := &fakeOxide{resources: []Resource{{JobID: "job-1", InstanceState: "running"}}}
	controller := newTestController(t, bk, ox, 2)

	if err := controller.reconcile(context.Background(), "queue-id"); err != nil {
		t.Fatal(err)
	}
	if len(bk.reserved) != 0 || len(ox.provision) != 0 || len(ox.cleanup) != 0 {
		t.Fatalf("unexpected actions: reserve=%v provision=%v cleanup=%v", bk.reserved, ox.provision, ox.cleanup)
	}
}

func TestReconcileHonorsQueuePause(t *testing.T) {
	bk := &fakeBuildkite{paused: true, jobs: []Job{{ID: "job-1"}}}
	ox := &fakeOxide{}
	controller := newTestController(t, bk, ox, 2)

	if err := controller.reconcile(context.Background(), "queue-id"); err != nil {
		t.Fatal(err)
	}
	if len(bk.reserved) != 0 || len(ox.provision) != 0 {
		t.Fatal("paused queue caused new work")
	}
}

func TestNewRejectsMalformedTag(t *testing.T) {
	_, err := New(nil, nil, slog.Default(), Config{Tags: []string{"linux"}})
	if err == nil {
		t.Fatal("New accepted a malformed tag")
	}
}
