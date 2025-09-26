# Makefile for try - Fresh directories for every vibe

SHELL := /bin/bash
RUBY := ruby
SCRIPT := try.rb
TEST_DIR := tests

# Default target
.PHONY: help
help: ## Show this help message
	@echo "try - Fresh directories for every vibe"
	@echo ""
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

.PHONY: test
test: ## Run all tests
	@echo "Running tests..."
	cd $(TEST_DIR) && $(RUBY) -I.. -e "require 'rake'; load 'Rakefile'; Rake::Task['test'].invoke"

.PHONY: test-pr
test-pr: ## Run only PR command tests
	@echo "Running PR command tests..."
	$(RUBY) $(TEST_DIR)/test_pr_command.rb

.PHONY: lint
lint: ## Check Ruby syntax
	@echo "Checking Ruby syntax..."
	$(RUBY) -c $(SCRIPT)
	@for file in $(TEST_DIR)/test_*.rb; do \
		echo "Checking $$file..."; \
		$(RUBY) -c "$$file"; \
	done

.PHONY: install
install: ## Install try.rb to ~/.local/
	@echo "Installing $(SCRIPT) to ~/.local/..."
	@mkdir -p ~/.local
	@cp $(SCRIPT) ~/.local/
	@chmod +x ~/.local/$(SCRIPT)
	@echo "Installed! Add to your shell:"
	@echo "  eval \"\$$(~/.local/$(SCRIPT) init ~/src/tries)\""

.PHONY: install-global
install-global: ## Install try.rb to /usr/local/bin/
	@echo "Installing $(SCRIPT) to /usr/local/bin/..."
	@sudo cp $(SCRIPT) /usr/local/bin/try
	@sudo chmod +x /usr/local/bin/try
	@echo "Installed globally! Add to your shell:"
	@echo "  eval \"\$$(try init ~/src/tries)\""

.PHONY: demo
demo: ## Show example commands
	@echo "try - Example commands:"
	@echo ""
	@echo "Basic usage:"
	@echo "  ./$(SCRIPT) --help                                # Show help"
	@echo "  ./$(SCRIPT) init ~/src/tries                     # Generate shell integration"
	@echo ""
	@echo "Clone repositories:"
	@echo "  ./$(SCRIPT) clone https://github.com/user/repo.git"
	@echo "  ./$(SCRIPT) clone git@github.com:user/repo.git my-fork"
	@echo ""
	@echo "Work with PRs:"
	@echo "  ./$(SCRIPT) pr 123                               # PR from current repo"
	@echo "  ./$(SCRIPT) pr user/repo#456                     # PR from specific repo"
	@echo "  ./$(SCRIPT) pr https://github.com/user/repo/pull/789"
	@echo ""
	@echo "Worktrees:"
	@echo "  ./$(SCRIPT) worktree dir                         # From current repo"
	@echo "  ./$(SCRIPT) worktree ~/path/to/repo my-branch    # From specific repo"

.PHONY: version
version: ## Show version information  
	@echo "try.rb - Fresh directories for every vibe"
	@echo "Ruby version: $$($(RUBY) --version)"
	@echo "Script: $(SCRIPT)"

.PHONY: clean
clean: ## Clean up temporary files
	@echo "Cleaning up..."
	@find . -name "*.tmp" -delete
	@find . -name "*~" -delete
	@echo "Clean complete"

.PHONY: check-deps
check-deps: ## Check for required dependencies
	@echo "Checking dependencies..."
	@command -v $(RUBY) >/dev/null 2>&1 || { echo "Ruby is required but not installed"; exit 1; }
	@echo "✓ Ruby found: $$($(RUBY) --version)"
	@command -v git >/dev/null 2>&1 || { echo "Git is required but not installed"; exit 1; }
	@echo "✓ Git found: $$(git --version)"
	@command -v gh >/dev/null 2>&1 && echo "✓ GitHub CLI found: $$(gh --version | head -1)" || echo "! GitHub CLI not found (optional for PR features)"
	@echo "Dependencies check complete"

.PHONY: dev-setup
dev-setup: check-deps ## Set up development environment
	@echo "Setting up development environment..."
	@echo "All dependencies satisfied"
	@echo ""
	@echo "To test locally:"
	@echo "  make test"
	@echo ""
	@echo "To install locally:"
	@echo "  make install"

.PHONY: all
all: lint test ## Run all checks and tests

# Development shortcuts
.PHONY: t
t: test ## Shortcut for test

.PHONY: l  
l: lint ## Shortcut for lint

.PHONY: i
i: install ## Shortcut for install