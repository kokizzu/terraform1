GO ?= go
GOVULNCHECK ?= govulncheck
TF ?= terraform
CMD ?=
.PHONY: test terraform-fmt update-vulnerable-dependencies verify-dependency-security run vulncheck

test:
	$(GO) test ./...
	@if command -v $(TF) >/dev/null 2>&1; then $(TF) fmt -check -recursive; else echo "terraform not installed; skipping terraform fmt"; fi

terraform-fmt:
	$(TF) fmt -recursive

update-vulnerable-dependencies:
	bash ./scripts/update-vulnerable-dependencies.sh

verify-dependency-security:
	GOFLAGS=-mod=mod bash ./scripts/verify-dependency-security.sh

vulncheck:
	$(GOVULNCHECK) ./...

run:
	@test -n "$(CMD)" || (echo "usage: make run CMD='go test ./...'" >&2; exit 2)
	$(CMD)
