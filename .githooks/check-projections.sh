#!/bin/sh
# Projection-drift guard (issue #78). Runs inside .githooks/pre-commit BEFORE
# the format/analyze gates, and only when staged files match
# .agents/agents/**:
#
# Canonical agent definitions live in .agents/agents/; `make init zcode
# claude` projects them into .zcode/agents/ and .claude/agents/. Those two
# projection dirs are gitignored-local, so CI cannot check projection drift —
# this hook is the only gate. Silent drift is what this script makes
# impossible: when .agents/agents/** is committed without regenerated
# projections, the commit is rejected and the out-of-sync file is named.
#
# Mechanics: copy the STAGED (index) content of each staged canonical file
# into a scratch dir (`git show :path` — never the working tree, which
# `git add -p` partial staging could decouple from the committed blob),
# re-project the copies via make (single-sourced transforms — the hook never
# reimplements the awk), and compare each file's fresh projection against the
# on-disk projection. The comparison deletes `color: ` lines ONLY inside the
# frontmatter (the injected transform chip); body lines starting with
# `color: ` are real content and compare literally. A missing on-disk
# projection (fresh clone) is out of sync too.
#
# .agents/skills/** needs no guard: ZCode reads skills live from
# .agents/skills (verified 2026-11-25) — there is no projection to drift.
# No-such-repo / no staged agent files exit 0; make unavailable while agent
# files are staged fails closed (the guard is the only gate).
set -u

toplevel=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$toplevel" || exit 0

staged=$(git diff --cached --name-only --diff-filter=ACMR -- .agents/agents/)
if [ $? -ne 0 ]; then
	echo "pre-commit: git diff --cached failed" >&2
	exit 1
fi
[ -n "$staged" ] || exit 0

if ! command -v make >/dev/null 2>&1; then
	echo "pre-commit: cannot verify agent projections (make unavailable) — install make, or run: make init zcode claude" >&2
	exit 1
fi

scratch=$(mktemp -d "${TMPDIR:-/tmp}/agent-projections.XXXXXX") || exit 1
trap 'rm -rf "$scratch"' EXIT INT TERM

printf '%s\n' "$staged" > "$scratch/staged"
mkdir -p "$scratch/src"
while IFS= read -r f; do
	[ -n "$f" ] || continue
	n=$(basename "$f" .md)
	git show ":$f" > "$scratch/src/$n.md" 2>/dev/null || {
		echo "pre-commit: cannot read the staged content of $f" >&2
		exit 1
	}
done < "$scratch/staged"

if ! make --silent zcode "ZCODE_DST=$scratch/zcode/agents" "AGENTS_SRC=$scratch/src" >/dev/null 2>&1 ||
	! make --silent claude "CLAUDE_DST=$scratch/claude/agents" "AGENTS_SRC=$scratch/src" >/dev/null 2>&1; then
	echo "pre-commit: re-projecting .agents/agents/ failed — run: make init zcode claude (then retry the commit)" >&2
	exit 1
fi

status=0
while IFS= read -r f; do
	[ -n "$f" ] || continue
	n=$(basename "$f" .md)
	for pair in zcode claude; do
		case $pair in
		zcode) dst=".zcode/agents/$n.md" ;;
		claude) dst=".claude/agents/$n.md" ;;
		esac
		if [ ! -f "$dst" ]; then
			echo "pre-commit: projection missing: $dst (canonical $f) — run: make init zcode claude" >&2
			status=1
			continue
		fi
		# Frontmatter-anchored `color: ` strip: the Makefile injects the chip
		# only between the first two `---` lines, so lines starting with
		# `color: ` in the body are real content and compare literally.
		for side in fresh disk; do
			case $side in
			fresh) src="$scratch/$pair/agents/$n.md" ;;
			disk) src="$dst" ;;
			esac
			awk 'BEGIN{fm=0; cl=0} !cl && /^---[[:space:]]*$/{if(fm) cl=1; fm=1; print; next} !cl && fm && /^color: /{next} {print}' "$src" > "$scratch/$side.$n.$pair" || status=1
		done
		if ! diff -q "$scratch/fresh.$n.$pair" "$scratch/disk.$n.$pair" >/dev/null; then
			echo "pre-commit: projection out of sync: $dst (canonical $f) — run: make init zcode claude" >&2
			status=1
		fi
	done
done < "$scratch/staged"
if [ "$status" -ne 0 ]; then
	echo "pre-commit: agent projections are stale — run: make init zcode claude" >&2
	exit 1
fi
exit 0
