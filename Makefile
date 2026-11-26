.PHONY: help check test lint fetch-fastpathsign build-probe

help: ## Show available targets
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z0-9_-]+:.*##/ {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

check: test ## Run full offline verification suite (syntax, shellcheck, synthetic tests, privacy, links)

test: ## Execute ./tests/run.sh
	./tests/run.sh

lint: ## Run shell syntax and shellcheck only
	@for s in scripts/*.sh tests/*.sh; do sh -n "$$s"; done
	shellcheck -S warning scripts/*.sh tests/*.sh

fetch-fastpathsign: ## Reproducibly compile host macOS vendor/fastPathSign (f1ebe52)
	./scripts/fetch-fastpathsign.sh

build-probe: ## Compile clean-room tvOS arm64 Demo.app diagnostic probe
	./scripts/build-probe.sh
