package controller

import (
	"context"
	"encoding/base64"
	"fmt"
	"log/slog"
	"sort"
	"strings"
	"time"
)

type Job struct {
	ID              string
	Priority        int
	AgentQueryRules []string
}

type Resource struct {
	JobID         string
	InstanceState string
	DiskState     string
}

type Buildkite interface {
	Register(context.Context) (string, error)
	Deregister(context.Context) error
	ScheduledJobs(context.Context, string) ([]Job, bool, error)
	Reserve(context.Context, string) (bool, error)
	JobStates(context.Context, []string) (map[string]string, error)
}

type Oxide interface {
	Resources(context.Context) ([]Resource, error)
	Provision(context.Context, string, []byte) error
	Cleanup(context.Context, Resource) error
}

type Config struct {
	PollInterval time.Duration
	MaxJobs      int
	QueueKey     string
	AgentToken   string
	Tags         []string
}

type Controller struct {
	buildkite Buildkite
	oxide     Oxide
	logger    *slog.Logger
	config    Config
	tags      map[string]string
}

func New(b Buildkite, o Oxide, logger *slog.Logger, cfg Config) (*Controller, error) {
	tags, err := tagMap(cfg.Tags)
	if err != nil {
		return nil, err
	}
	tags["queue"] = cfg.QueueKey
	return &Controller{buildkite: b, oxide: o, logger: logger, config: cfg, tags: tags}, nil
}

func (c *Controller) Run(ctx context.Context) error {
	queueKey, err := c.buildkite.Register(ctx)
	if err != nil {
		return fmt.Errorf("registering Buildkite stack: %w", err)
	}
	c.logger.Info("registered Buildkite stack", "cluster_queue_key", queueKey)

	defer func() {
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if err := c.buildkite.Deregister(shutdownCtx); err != nil {
			c.logger.Warn("deregistering Buildkite stack", "error", err)
		}
	}()

	if err := c.reconcile(ctx, queueKey); err != nil {
		c.logger.Error("initial reconciliation failed", "error", err)
	}
	ticker := time.NewTicker(c.config.PollInterval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-ticker.C:
			if err := c.reconcile(ctx, queueKey); err != nil {
				c.logger.Error("reconciliation failed", "error", err)
			}
		}
	}
}

func (c *Controller) reconcile(ctx context.Context, queueKey string) error {
	resources, err := c.oxide.Resources(ctx)
	if err != nil {
		return fmt.Errorf("listing Oxide resources: %w", err)
	}
	byJob := make(map[string]Resource, len(resources))
	jobIDs := make([]string, 0, len(resources))
	for _, resource := range resources {
		byJob[resource.JobID] = mergeResource(byJob[resource.JobID], resource)
		jobIDs = append(jobIDs, resource.JobID)
	}
	jobIDs = unique(jobIDs)

	if len(jobIDs) > 0 {
		states, err := c.buildkite.JobStates(ctx, jobIDs)
		if err != nil {
			return fmt.Errorf("observing Buildkite job states: %w", err)
		}
		for id, resource := range byJob {
			state, known := states[id]
			orphanedDisk := resource.InstanceState == "" &&
				(resource.DiskState == "detached" || resource.DiskState == "faulted")
			if (known && terminal(state)) ||
				resource.InstanceState == "failed" || orphanedDisk {
				c.logger.Info("cleaning up job instance", "job_id", id, "job_state", state)
				if err := c.oxide.Cleanup(ctx, resource); err != nil {
					c.logger.Error("cleaning up job instance failed", "job_id", id, "error", err)
				}
			}
		}
	}

	jobs, paused, err := c.buildkite.ScheduledJobs(ctx, queueKey)
	if err != nil {
		return fmt.Errorf("polling scheduled jobs: %w", err)
	}
	if paused {
		c.logger.Info("queue dispatch is paused")
		return nil
	}

	capacity := c.config.MaxJobs - activeInstances(resources)
	for _, job := range filterJobs(jobs, c.tags, byJob) {
		if capacity <= 0 {
			break
		}
		reserved, err := c.buildkite.Reserve(ctx, job.ID)
		if err != nil {
			c.logger.Error("reserving job failed", "job_id", job.ID, "error", err)
			continue
		}
		if !reserved {
			continue
		}
		userData := renderUserData(job.ID, c.config.AgentToken, c.agentTags())
		if err := c.oxide.Provision(ctx, job.ID, userData); err != nil {
			c.logger.Error("provisioning job instance failed", "job_id", job.ID, "error", err)
			continue
		}
		capacity--
		c.logger.Info("provisioned job instance", "job_id", job.ID)
	}
	return nil
}

func filterJobs(jobs []Job, tags map[string]string, existing map[string]Resource) []Job {
	result := make([]Job, 0, len(jobs))
	for _, job := range jobs {
		if _, ok := existing[job.ID]; ok || !matches(tags, job.AgentQueryRules) {
			continue
		}
		result = append(result, job)
	}
	sort.SliceStable(result, func(i, j int) bool { return result[i].Priority > result[j].Priority })
	return result
}

func matches(tags map[string]string, rules []string) bool {
	for _, rule := range rules {
		key, value, ok := strings.Cut(rule, "=")
		if !ok || key == "" || tags[key] != value {
			return false
		}
	}
	return true
}

func tagMap(tags []string) (map[string]string, error) {
	result := make(map[string]string, len(tags))
	for _, tag := range tags {
		key, value, ok := strings.Cut(tag, "=")
		if !ok || key == "" || value == "" {
			return nil, fmt.Errorf("invalid Buildkite agent tag %q; expected key=value", tag)
		}
		result[key] = value
	}
	return result, nil
}

func (c *Controller) agentTags() []string {
	result := make([]string, 0, len(c.tags))
	for key, value := range c.tags {
		result = append(result, key+"="+value)
	}
	sort.Strings(result)
	return result
}

func renderUserData(jobID, token string, tags []string) []byte {
	encode := func(value string) string {
		return base64.StdEncoding.EncodeToString([]byte(value))
	}
	return fmt.Appendf(nil, `#!/bin/sh
set -eu
token="$(printf '%%s' '%s' | base64 -d)"
export BUILDKITE_AGENT_TOKEN="$token"
unset token
export HOME=/var/lib/buildkite-agent
cd "$HOME"
exec setpriv \
  --reuid=buildkite-agent \
  --regid=buildkite-agent \
  --init-groups \
  buildkite-agent start \
  --name="oxide-%s" \
  --tags="%s" \
  --acquire-job="%s" \
  --disconnect-after-job
`, encode(token), jobID, strings.Join(tags, ","), jobID)
}

func terminal(state string) bool {
	switch state {
	case "finished", "canceled", "expired", "timed_out", "broken", "skipped":
		return true
	default:
		return false
	}
}

func activeInstances(resources []Resource) int {
	jobs := make(map[string]bool)
	for _, resource := range resources {
		if resource.InstanceState != "" {
			jobs[resource.JobID] = true
		}
	}
	return len(jobs)
}

func mergeResource(a, b Resource) Resource {
	if a.JobID == "" {
		a.JobID = b.JobID
	}
	if b.InstanceState != "" {
		a.InstanceState = b.InstanceState
	}
	if b.DiskState != "" {
		a.DiskState = b.DiskState
	}
	return a
}

func unique(values []string) []string {
	seen := make(map[string]bool, len(values))
	result := make([]string, 0, len(values))
	for _, value := range values {
		if !seen[value] {
			seen[value] = true
			result = append(result, value)
		}
	}
	return result
}
