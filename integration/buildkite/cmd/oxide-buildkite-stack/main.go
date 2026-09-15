package main

import (
	"context"
	"flag"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"syscall"

	oxidesdk "github.com/oxidecomputer/oxide.go/oxide"

	"github.com/oxidecomputer/showcase/integration/buildkite/internal/buildkite"
	"github.com/oxidecomputer/showcase/integration/buildkite/internal/config"
	"github.com/oxidecomputer/showcase/integration/buildkite/internal/controller"
	oxideprovider "github.com/oxidecomputer/showcase/integration/buildkite/internal/oxide"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run() error {
	configPath := flag.String("config", "config.yaml", "path to YAML configuration")
	flag.Parse()

	cfg, err := config.Load(*configPath)
	if err != nil {
		return fmt.Errorf("loading configuration: %w", err)
	}

	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))

	bk, err := buildkite.New(
		os.Getenv(cfg.Buildkite.TokenEnv),
		cfg.Buildkite.StackKey,
		cfg.Buildkite.QueueKey,
		logger,
	)
	if err != nil {
		return fmt.Errorf("creating Buildkite client: %w", err)
	}

	oxideClient, err := oxidesdk.NewClient(
		oxidesdk.WithHost(os.Getenv(cfg.Oxide.HostEnv)),
		oxidesdk.WithToken(os.Getenv(cfg.Oxide.TokenEnv)),
		oxidesdk.WithUserAgent("oxide-buildkite-stack"),
	)
	if err != nil {
		return fmt.Errorf("creating Oxide client: %w", err)
	}

	provider := oxideprovider.New(oxideClient, cfg.Oxide, cfg.Buildkite.StackKey)

	ctrl, err := controller.New(bk, provider, logger, controller.Config{
		PollInterval: cfg.Poll.Duration,
		MaxJobs:      cfg.MaxJobs,
		QueueKey:     cfg.Buildkite.QueueKey,
		AgentToken:   os.Getenv(cfg.Buildkite.TokenEnv),
		Tags:         cfg.Buildkite.Tags,
	})
	if err != nil {
		return fmt.Errorf("creating controller: %w", err)
	}

	ctx, stop := signal.NotifyContext(
		context.Background(), os.Interrupt, syscall.SIGTERM,
	)

	defer stop()

	return ctrl.Run(ctx)
}
