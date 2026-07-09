#!/usr/bin/env bash
set -euo pipefail

GOFLAGS=-mod=mod go get golang.org/x/crypto@v0.53.0 golang.org/x/image@v0.44.0
go mod edit -exclude=golang.org/x/crypto@v0.14.0
GOFLAGS=-mod=mod go mod tidy
go mod edit -require=golang.org/x/crypto@v0.53.0
go mod edit -require=golang.org/x/image@v0.44.0
GOFLAGS=-mod=mod go mod download golang.org/x/crypto golang.org/x/image
GOFLAGS=-mod=mod go mod vendor
