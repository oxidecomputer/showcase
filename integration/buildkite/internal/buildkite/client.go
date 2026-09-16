package buildkite

import (
	"context"
	"fmt"
	"log/slog"
	"slices"

	"github.com/buildkite/stacksapi"

	"github.com/oxidecomputer/showcase/integration/buildkite/internal/controller"
)

type Client struct {
	api      *stacksapi.Client
	stackKey string
	queueKey string
}

func New(apiToken string, stackKey string, queueKey string, logger *slog.Logger) (*Client, error) {
	api, err := stacksapi.NewClient(apiToken, stacksapi.WithLogger(logger))
	if err != nil {
		return nil, err
	}

	return &Client{api: api, stackKey: stackKey, queueKey: queueKey}, nil
}

func (c *Client) Register(ctx context.Context) (string, error) {
	response, _, err := c.api.RegisterStack(ctx, stacksapi.RegisterStackRequest{
		Key:      c.stackKey,
		Type:     stacksapi.StackTypeCustom,
		QueueKey: c.queueKey,
		Metadata: map[string]string{"provider": "oxide"},
	})
	if err != nil {
		return "", err
	}

	return response.ClusterQueueKey, nil
}

func (c *Client) Deregister(ctx context.Context) error {
	_, err := c.api.DeregisterStack(ctx, c.stackKey)
	return err
}

func (c *Client) ScheduledJobs(
	ctx context.Context,
	clusterQueueKey string,
) ([]controller.Job, bool, error) {
	var jobs []controller.Job
	cursor := ""
	for {
		response, _, err := c.api.ListScheduledJobs(
			ctx,
			stacksapi.ListScheduledJobsRequest{
				StackKey:        c.stackKey,
				ClusterQueueKey: clusterQueueKey,
				PageSize:        100,
				StartCursor:     cursor,
			},
		)
		if err != nil {
			return nil, false, err
		}
		for _, job := range response.Jobs {
			jobs = append(jobs, controller.Job{
				ID:              job.ID,
				Priority:        job.Priority,
				AgentQueryRules: job.AgentQueryRules,
			})
		}
		if response.ClusterQueue.Paused {
			return jobs, true, nil
		}
		if !response.PageInfo.HasNextPage {
			return jobs, false, nil
		}
		if response.PageInfo.EndCursor == "" || response.PageInfo.EndCursor == cursor {
			return nil, false, fmt.Errorf("scheduled jobs pagination did not advance")
		}
		cursor = response.PageInfo.EndCursor
	}
}

func (c *Client) Reserve(ctx context.Context, jobID string) (bool, error) {
	response, _, err := c.api.BatchReserveJobs(
		ctx,
		stacksapi.BatchReserveJobsRequest{
			StackKey:                 c.stackKey,
			JobUUIDs:                 []string{jobID},
			ReservationExpirySeconds: 900,
		},
	)
	if err != nil {
		return false, err
	}

	if slices.Contains(response.Reserved, jobID) {
		return true, nil
	}

	return false, nil
}

func (c *Client) JobStates(
	ctx context.Context,
	jobIDs []string,
) (map[string]string, error) {
	response, _, err := c.api.GetJobStates(ctx, stacksapi.GetJobStatesRequest{
		StackKey: c.stackKey,
		JobUUIDs: jobIDs,
	})
	if err != nil {
		return nil, err
	}

	return response.States, nil
}
