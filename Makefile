.PHONY: hooks

hooks: ## enable the Conventional Commits hook
	git config core.hooksPath .githooks
