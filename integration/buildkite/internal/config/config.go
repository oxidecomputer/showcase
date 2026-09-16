package config

import (
	"fmt"
	"math"
	"os"
	"time"

	"gopkg.in/yaml.v3"
)

type Config struct {
	Buildkite Buildkite `yaml:"buildkite"`
	Oxide     Oxide     `yaml:"oxide"`
	Poll      Duration  `yaml:"poll_interval"`
	MaxJobs   int       `yaml:"max_jobs"`
}

type Buildkite struct {
	TokenEnv string   `yaml:"token_env"`
	StackKey string   `yaml:"stack_key"`
	QueueKey string   `yaml:"queue_key"`
	Tags     []string `yaml:"tags"`
}

type Oxide struct {
	HostEnv     string `yaml:"host_env"`
	TokenEnv    string `yaml:"token_env"`
	Project     string `yaml:"project"`
	Image       string `yaml:"image"`
	VPC         string `yaml:"vpc"`
	Subnet      string `yaml:"subnet"`
	CPUs        uint   `yaml:"cpus"`
	MemoryGiB   uint   `yaml:"memory_gib"`
	BootDiskGiB uint   `yaml:"boot_disk_gib"`
}

type Duration struct{ time.Duration }

func (d *Duration) UnmarshalYAML(node *yaml.Node) error {
	value, err := time.ParseDuration(node.Value)
	if err != nil {
		return err
	}
	d.Duration = value
	return nil
}

func Load(path string) (Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return Config{}, err
	}
	var cfg Config
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return Config{}, err
	}
	cfg.defaults()
	if err := cfg.Validate(); err != nil {
		return Config{}, err
	}
	return cfg, nil
}

func (c *Config) defaults() {
	if c.Buildkite.TokenEnv == "" {
		c.Buildkite.TokenEnv = "BUILDKITE_AGENT_TOKEN"
	}
	if c.Buildkite.QueueKey == "" {
		c.Buildkite.QueueKey = "_default"
	}
	if c.Oxide.HostEnv == "" {
		c.Oxide.HostEnv = "OXIDE_HOST"
	}
	if c.Oxide.TokenEnv == "" {
		c.Oxide.TokenEnv = "OXIDE_TOKEN"
	}
	if c.Poll.Duration == 0 {
		c.Poll.Duration = 10 * time.Second
	}
	if c.MaxJobs == 0 {
		c.MaxJobs = 10
	}
}

func (c Config) Validate() error {
	switch {
	case c.Buildkite.StackKey == "":
		return fmt.Errorf("buildkite.stack_key is required")
	case c.Poll.Duration < time.Second:
		return fmt.Errorf("poll_interval must be at least 1s")
	case c.Poll.Duration > 30*time.Second:
		return fmt.Errorf("poll_interval must be at most 30s")
	case c.MaxJobs < 1:
		return fmt.Errorf("max_jobs must be at least 1")
	case c.Oxide.Project == "":
		return fmt.Errorf("oxide.project is required")
	case c.Oxide.Image == "":
		return fmt.Errorf("oxide.image is required")
	case c.Oxide.VPC == "":
		return fmt.Errorf("oxide.vpc is required")
	case c.Oxide.Subnet == "":
		return fmt.Errorf("oxide.subnet is required")
	case c.Oxide.CPUs == 0 || c.Oxide.CPUs > math.MaxUint16:
		return fmt.Errorf("oxide.cpus must be between 1 and %d", math.MaxUint16)
	case c.Oxide.MemoryGiB == 0:
		return fmt.Errorf("oxide.memory_gib must be at least 1")
	case os.Getenv(c.Buildkite.TokenEnv) == "":
		return fmt.Errorf("environment variable %s is required", c.Buildkite.TokenEnv)
	case os.Getenv(c.Oxide.HostEnv) == "":
		return fmt.Errorf("environment variable %s is required", c.Oxide.HostEnv)
	case os.Getenv(c.Oxide.TokenEnv) == "":
		return fmt.Errorf("environment variable %s is required", c.Oxide.TokenEnv)
	}
	return nil
}
