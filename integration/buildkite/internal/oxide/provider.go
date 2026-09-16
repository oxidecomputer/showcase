package oxide

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"

	"github.com/oxidecomputer/oxide.go/oxide"

	"github.com/oxidecomputer/showcase/integration/buildkite/internal/config"
	"github.com/oxidecomputer/showcase/integration/buildkite/internal/controller"
)

type API interface {
	DiskDelete(context.Context, oxide.DiskDeleteParams) error
	DiskListAllPages(context.Context, oxide.DiskListParams) ([]oxide.Disk, error)
	ImageView(context.Context, oxide.ImageViewParams) (*oxide.Image, error)
	InstanceCreate(context.Context, oxide.InstanceCreateParams) (*oxide.Instance, error)
	InstanceDelete(context.Context, oxide.InstanceDeleteParams) error
	InstanceListAllPages(context.Context, oxide.InstanceListParams) ([]oxide.Instance, error)
	InstanceStop(context.Context, oxide.InstanceStopParams) (*oxide.Instance, error)
}

type Provider struct {
	api    API
	config config.Oxide
	prefix string
}

func New(api API, cfg config.Oxide, stackKey string) *Provider {
	digest := sha256.Sum256([]byte(stackKey))
	return &Provider{
		api:    api,
		config: cfg,
		prefix: "bk-" + hex.EncodeToString(digest[:4]) + "-",
	}
}

func (p *Provider) Resources(ctx context.Context) ([]controller.Resource, error) {
	instances, err := p.api.InstanceListAllPages(ctx, oxide.InstanceListParams{
		Project: oxide.NameOrId(p.config.Project),
	})
	if err != nil {
		return nil, err
	}
	disks, err := p.api.DiskListAllPages(ctx, oxide.DiskListParams{
		Project: oxide.NameOrId(p.config.Project),
	})
	if err != nil {
		return nil, err
	}
	resources := make([]controller.Resource, 0, len(instances)+len(disks))
	for _, instance := range instances {
		if jobID, ok := p.jobID(string(instance.Name)); ok {
			resources = append(resources, controller.Resource{
				JobID:         jobID,
				InstanceState: string(instance.RunState),
			})
		}
	}
	for _, disk := range disks {
		if jobID, ok := p.jobID(string(disk.Name)); ok {
			resources = append(resources, controller.Resource{
				JobID:     jobID,
				DiskState: string(disk.State.State()),
			})
		}
	}
	return resources, nil
}

func (p *Provider) Provision(ctx context.Context, jobID string, userData []byte) error {
	if len(userData) > 32*1024 {
		return fmt.Errorf("user data exceeds Oxide's 32 KiB limit")
	}
	image, err := p.api.ImageView(ctx, oxide.ImageViewParams{
		Project: oxide.NameOrId(p.config.Project),
		Image:   oxide.NameOrId(p.config.Image),
	})
	if err != nil && errors.Is(err, oxide.ErrObjectNotFound) {
		image, err = p.api.ImageView(ctx, oxide.ImageViewParams{
			Image: oxide.NameOrId(p.config.Image),
		})
	}
	if err != nil {
		return fmt.Errorf("resolving image: %w", err)
	}

	const gib = oxide.ByteCount(1024 * 1024 * 1024)
	imageGiB := image.Size / gib
	if image.Size%gib != 0 {
		imageGiB++
	}
	diskGiB := max(oxide.ByteCount(p.config.BootDiskGiB), imageGiB)
	name := p.name(jobID)
	description := "Ephemeral Buildkite agent for job " + jobID
	start := true
	_, err = p.api.InstanceCreate(ctx, oxide.InstanceCreateParams{
		Project: oxide.NameOrId(p.config.Project),
		Body: &oxide.InstanceCreate{
			AutoRestartPolicy: oxide.InstanceAutoRestartPolicyNever,
			BootDisk: oxide.InstanceDiskAttachment{
				Value: oxide.InstanceDiskAttachmentCreate{
					Name:        oxide.Name(name),
					Description: description,
					Size:        diskGiB * gib,
					DiskBackend: oxide.DiskBackend{
						Value: oxide.DiskBackendDistributed{
							DiskSource: oxide.DiskSource{
								Value: oxide.DiskSourceImage{ImageId: image.Id},
							},
						},
					},
				},
			},
			Description: description,
			Hostname:    oxide.Hostname(name),
			Memory:      oxide.ByteCount(p.config.MemoryGiB) * gib,
			Name:        oxide.Name(name),
			Ncpus:       oxide.InstanceCpuCount(p.config.CPUs),
			NetworkInterfaces: oxide.InstanceNetworkInterfaceAttachment{
				Value: oxide.InstanceNetworkInterfaceAttachmentCreate{
					Params: []oxide.InstanceNetworkInterfaceCreate{{
						Name:        oxide.Name(name),
						Description: description,
						IpConfig: oxide.PrivateIpStackCreate{
							Value: oxide.PrivateIpStackCreateDualStack{
								Value: oxide.PrivateIpStackCreateDualStackValue{
									V4: oxide.PrivateIpv4StackCreate{Ip: oxide.Ipv4Assignment{Value: oxide.Ipv4AssignmentAuto{}}},
									V6: oxide.PrivateIpv6StackCreate{Ip: oxide.Ipv6Assignment{Value: oxide.Ipv6AssignmentAuto{}}},
								},
							},
						},
						SubnetName: oxide.Name(p.config.Subnet),
						VpcName:    oxide.Name(p.config.VPC),
					}},
				},
			},
			Start:    &start,
			UserData: base64.StdEncoding.EncodeToString(userData),
		},
	})
	return err
}

func (p *Provider) Cleanup(ctx context.Context, resource controller.Resource) error {
	name := p.name(resource.JobID)
	if resource.InstanceState != "" {
		switch resource.InstanceState {
		case string(oxide.InstanceStateStopped), string(oxide.InstanceStateFailed), string(oxide.InstanceStateDestroyed):
			if resource.InstanceState != string(oxide.InstanceStateDestroyed) {
				if err := p.deleteInstance(ctx, name); err != nil {
					return err
				}
			}
			if resource.DiskState != "" {
				return p.deleteDisk(ctx, name)
			}
			return nil
		case string(oxide.InstanceStateStopping):
			return nil
		default:
			_, err := p.api.InstanceStop(ctx, oxide.InstanceStopParams{
				Project:  oxide.NameOrId(p.config.Project),
				Instance: oxide.NameOrId(name),
			})
			if errors.Is(err, oxide.ErrObjectNotFound) {
				return nil
			}
			return err
		}
	}
	if resource.DiskState == string(oxide.DiskStateStateDetached) ||
		resource.DiskState == string(oxide.DiskStateStateFaulted) {
		return p.deleteDisk(ctx, name)
	}
	return nil
}

func (p *Provider) deleteInstance(ctx context.Context, name string) error {
	err := p.api.InstanceDelete(ctx, oxide.InstanceDeleteParams{
		Project: oxide.NameOrId(p.config.Project), Instance: oxide.NameOrId(name),
	})
	if errors.Is(err, oxide.ErrObjectNotFound) {
		return nil
	}
	return err
}

func (p *Provider) deleteDisk(ctx context.Context, name string) error {
	err := p.api.DiskDelete(ctx, oxide.DiskDeleteParams{
		Project: oxide.NameOrId(p.config.Project), Disk: oxide.NameOrId(name),
	})
	if errors.Is(err, oxide.ErrObjectNotFound) {
		return nil
	}
	return err
}

func (p *Provider) name(jobID string) string { return p.prefix + jobID }

func (p *Provider) jobID(name string) (string, bool) {
	if !strings.HasPrefix(name, p.prefix) {
		return "", false
	}
	jobID := strings.TrimPrefix(name, p.prefix)
	return jobID, jobID != ""
}
