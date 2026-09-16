BINARY ?= oxide-buildkite-stack

.PHONY: check fmt fmt-check packer-check packer-init tidy test build

check: fmt-check packer-check tidy test build

fmt:
	gofmt -w $$(find . -name '*.go')

fmt-check:
	test -z "$$(gofmt -l $$(find . -name '*.go'))"

packer-init:
	packer init packer

packer-check: packer-init
	packer fmt -check -recursive packer
	shellcheck packer/scripts/*.sh
	packer validate \
		-var source_image_name=validation-source \
		-var project=validation-project \
		packer

tidy:
	go mod tidy

test:
	go test ./...

build:
	go build -trimpath -o $(BINARY) ./cmd/oxide-buildkite-stack
