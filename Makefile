.PHONY: update-vulnerable-dependencies verify-dependency-security

update-vulnerable-dependencies:
	bash ./scripts/update-vulnerable-dependencies.sh

verify-dependency-security:
	GOFLAGS=-mod=mod bash ./scripts/verify-dependency-security.sh
