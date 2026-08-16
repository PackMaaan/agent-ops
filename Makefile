.DEFAULT_GOAL := help
SHELL := /usr/bin/env bash

# Keep this list in sync with the shellcheck job in .github/workflows/ci.yml.
SHELL_FILES := bin/agent-ops $(shell find scripts tests -type f -name '*.sh' 2>/dev/null)

.PHONY: help
help: ## Show this help
	@printf 'Agent Ops — make targets\n\n'
	@grep -hE '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "} {printf "  \033[1m%-16s\033[0m %s\n", $$1, $$2}'
	@printf '\n'

.PHONY: init
init: ## Check out every pinned module
	git submodule update --init --recursive

.PHONY: install
install: ## Install module skills into the host repository
	./bin/agent-ops install

.PHONY: doctor
doctor: ## Diagnose tooling, registry, and installed state
	./bin/agent-ops doctor

.PHONY: modules
modules: ## Show the module registry
	./bin/agent-ops module list

.PHONY: sync
sync: ## Update modules to their tracked branch tips (does not commit)
	./bin/agent-ops module sync

.PHONY: test
test: ## Run the test suite
	bash tests/run.sh

.PHONY: lint
lint: shellcheck yamllint markdownlint ## Run every linter

.PHONY: shellcheck
shellcheck: ## Lint shell scripts
	@command -v shellcheck >/dev/null || { echo "shellcheck not installed: brew install shellcheck"; exit 1; }
	shellcheck -x --source-path=SCRIPTDIR --severity=style --format=gcc $(SHELL_FILES)

.PHONY: yamllint
yamllint: ## Lint YAML
	@command -v yamllint >/dev/null || { echo "yamllint not installed: pipx install yamllint"; exit 1; }
	yamllint --strict .

.PHONY: markdownlint
markdownlint: ## Lint Markdown
	@command -v markdownlint-cli2 >/dev/null || { echo "markdownlint-cli2 not installed: npm i -g markdownlint-cli2"; exit 1; }
	markdownlint-cli2

.PHONY: actionlint
actionlint: ## Lint GitHub Actions workflows
	@command -v actionlint >/dev/null || { echo "actionlint not installed: brew install actionlint"; exit 1; }
	actionlint

.PHONY: schema
schema: ## Validate the module registry against its JSON Schema
	@command -v check-jsonschema >/dev/null || { echo "check-jsonschema not installed: pipx install check-jsonschema"; exit 1; }
	check-jsonschema --schemafile registry/schema/modules.schema.json registry/modules.json

.PHONY: version
version: ## Check that the declared versions agree
	bash scripts/check-version.sh

.PHONY: check
check: version schema test ## Everything CI runs that needs no extra tooling
