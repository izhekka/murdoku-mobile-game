# Agent factory
#
# Canonical agent definitions live in .agents/agents/ (portable core: name,
# description, optional tools, body). `make init <zcode|claude>` projects them
# into each harness's native directory:
#
#   make init zcode  -> .zcode/agents/   (adds ZCode-only `color` chip)
#   make init claude -> .claude/agents/  (tools array -> Claude's comma form)
#
# Both projections are regenerated local files, not symlinks and not tracked:
# git ignores /.zcode/ and /.claude/ entirely, and a fresh clone has neither
# until you run `make init zcode claude` there. ZCode scans only
# .zcode/agents/ for agents (no .agents/agents fallback, and its scanner skips
# symlinks), while Claude Code scans .claude/agents/. Re-run after editing
# anything in .agents/agents/.

AGENTS_SRC := .agents/agents
ZCODE_DST  := .zcode/agents
CLAUDE_DST := .claude/agents

# ZCode-only frontmatter key: UI chip color per agent (name=color)
ZCODE_COLORS := task-executor=green issue-triage=orange code-reviewer=cyan ux-verifier=purple

# Test steps of the quality gate, serialized per checkout by the lock in
# tool/flutter_test_lock.dart (issue 43): overlapping quality runs wait here
# instead of racing build/unit_test_assets and coverage/lcov.info.
QUALITY_TEST_PIPELINE := flutter test --coverage && dart run tool/coverage_filter.dart --lcov coverage/lcov.info && dart run tool/crap_check.dart --lcov coverage/lcov.info

.PHONY: init zcode claude hooks quality

hooks: ## install the pre-commit quality gate: git config core.hooksPath .githooks
	git config core.hooksPath .githooks
	@echo "Pre-commit hook installed (core.hooksPath=.githooks)"

quality: ## one-command local gate: format check + analyze + test --coverage (checkout-locked) + lcov l10n filter + CRAP ratchet
	dart format --output=none --set-exit-if-changed .
	flutter analyze
	dart run tool/flutter_test_lock.dart -- sh -c '$(QUALITY_TEST_PIPELINE)'

init: ## usage: make init <zcode|claude> — project .agents/agents/ into a harness dir
	@if [ -z "$(filter-out init,$(MAKECMDGOALS))" ]; then \
		echo "usage: make init <zcode|claude>" >&2; exit 2; \
	fi

zcode: ## project canonical agents into .zcode/agents/
	@mkdir -p $(ZCODE_DST)
	@found=0; \
	for f in $(AGENTS_SRC)/*.md; do \
		[ -e "$$f" ] || continue; \
		found=1; \
		n=$$(basename "$$f" .md); \
		c=""; \
		for kv in $(ZCODE_COLORS); do \
			[ "$${kv%%=*}" = "$$n" ] && c="$${kv##*=}"; \
		done; \
		awk -v color="$$c" 'BEGIN{fm=0;cl=0} !cl && /^---[[:space:]]*$$/{if(fm){if(color!="")print "color: " color; print "---"; cl=1; next} fm=1; print "---"; next} !cl && fm {if($$1=="name:"||$$1=="description:"||$$1=="tools:")print; next} {print}' "$$f" > "$(ZCODE_DST)/$$n.md" || exit 1; \
		echo "  zcode: $$n.md"; \
	done; \
	[ "$$found" = 1 ] || { echo "no agents found in $(AGENTS_SRC)/" >&2; exit 1; }
	@echo "ZCode agents projected into $(ZCODE_DST)/"

claude: ## project canonical agents into .claude/agents/
	@mkdir -p $(CLAUDE_DST)
	@found=0; \
	for f in $(AGENTS_SRC)/*.md; do \
		[ -e "$$f" ] || continue; \
		found=1; \
		n=$$(basename "$$f" .md); \
		awk 'BEGIN{fm=0;cl=0} !cl && /^---[[:space:]]*$$/{if(fm){print "---"; cl=1; next} fm=1; print "---"; next} !cl && fm {if($$1=="name:"||$$1=="description:")print; if($$1=="tools:"){t=$$0; sub(/^tools:[[:space:]]*\[/,"",t); sub(/\][[:space:]]*$$/,"",t); print "tools: " t} next} {print}' "$$f" > "$(CLAUDE_DST)/$$n.md" || exit 1; \
		echo "  claude: $$n.md"; \
	done; \
	[ "$$found" = 1 ] || { echo "no agents found in $(AGENTS_SRC)/" >&2; exit 1; }
	@echo "Claude Code agents projected into $(CLAUDE_DST)/"
