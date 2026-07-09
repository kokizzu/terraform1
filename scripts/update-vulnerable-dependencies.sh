#!/usr/bin/env bash
set -euo pipefail

GOFLAGS=-mod=mod go get golang.org/x/crypto@v0.53.0
go mod edit -droprequire=golang.org/x/image
go mod edit -exclude=golang.org/x/crypto@v0.14.0
go mod edit -exclude=golang.org/x/image@v0.0.0-20190227222117-0694c2d4d067
go mod edit -exclude=golang.org/x/image@v0.0.0-20190802002840-cff245a6509b
GOFLAGS=-mod=mod go mod tidy
go mod edit -require=golang.org/x/crypto@v0.53.0
GOFLAGS=-mod=mod go mod download golang.org/x/crypto
