#!/bin/sh
# TDD harness for the projection-drift guard, .githooks/check-projections.sh
# (issue #78). Builds a disposable git repo per case (real Makefile copied in,
# synthetic agent fixtures), stages a canonical .agents/agents/*.md file and
# runs the guard the way the pre-commit hook does. Exits non-zero on any
# failing case.
#
# Fixture shape mirrors the real agents: frontmatter with name/description and
# a `tools: [Read, Edit]` array (the claude projection rewrites it to the
# comma form), plus a body. The zcode projection carries a `color:` chip the
# comparison must ignore (a Makefile injection the guard must never treat as
# drift).
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
guard="$root/.githooks/check-projections.sh"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/proj-guard-test.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT INT TERM
case_n=0
fails=0

[ -f "$guard" ] || { echo "FAIL: $guard missing (implement the guard first)"; exit 1; }

report() { # report <ok|fail-word> <case description> [message]
	[ "$1" = ok ] && { echo "PASS: $2"; return 0; }
	echo "FAIL: $2${3:+ — $3}"; fails=$((fails + 1)); return 1
}

run_guard() { # run_guard <repo-dir>: sets rc; combined output lands in $out
	(cd "$1" && sh "$guard" >"$tmp/out" 2>&1)
	rc=$?
	out=$(cat "$tmp/out")
}

new_repo() { # new_repo: fresh repo with canonical + both projections staged
	case_n=$((case_n + 1))
	r="$tmp/repo$case_n"
	git init -q "$r" || exit 1
	cp "$root/Makefile" "$r/Makefile" || exit 1
	mkdir -p "$r/.agents/agents" "$r/.zcode/agents" "$r/.claude/agents"

	cat > "$r/.agents/agents/demo.md" <<'EOF'
---
name: "demo"
description: "demo agent"
tools: [Read, Edit]
---
Body line one.
EOF

	cat > "$r/.zcode/agents/demo.md" <<'EOF'
---
name: "demo"
description: "demo agent"
tools: [Read, Edit]
color: green
---
Body line one.
EOF

	cat > "$r/.claude/agents/demo.md" <<'EOF'
---
name: "demo"
description: "demo agent"
tools: Read, Edit
---
Body line one.
EOF
	git -C "$r" add .agents/agents/demo.md
	# ship the hook files like a real checkout would have them
	mkdir -p "$r/.githooks"
	cp "$root/.githooks/pre-commit" "$r/.githooks/pre-commit" || exit 1
	cp "$root/.githooks/check-projections.sh" "$r/.githooks/check-projections.sh" || exit 1
}

regen() { (cd "$r" && make --silent zcode claude >/dev/null 2>&1); }

# Case 1: canonical + in-sync projections staged -> guard exits 0.
new_repo
run_guard "$r"
[ "$rc" -eq 0 ] && report ok "case 1: in-sync staged canonical exits 0" \
	|| report fail "case 1: in-sync staged canonical exits 0" "exit $rc: $out"

# Case 2: canonical body edited and staged, projections stale -> exit 1,
# naming .zcode and .claude paths + the make init remedy.
new_repo
printf 'Body line two.\n' >> "$r/.agents/agents/demo.md"
git -C "$r" add .agents/agents/demo.md
run_guard "$r"
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -Fq ".zcode/agents/demo.md" \
	&& printf '%s' "$out" | grep -Fq ".claude/agents/demo.md" \
	&& printf '%s' "$out" | grep -Fq "make init zcode claude"; then
	report ok "case 2: stale projections block, named + remedy"
else
	report fail "case 2: stale projections block, named + remedy" "exit $rc: $out"
fi

# Case 3: after `make --silent zcode claude` in the same repo -> exit 0.
new_repo
printf 'Body line two.\n' >> "$r/.agents/agents/demo.md"
git -C "$r" add .agents/agents/demo.md
run_guard "$r"
[ "$rc" -eq 1 ] || report fail "case 3 precheck: drift must block before regen" "exit $rc"
regen
run_guard "$r"
[ "$rc" -eq 0 ] && report ok "case 3: regen clears the drift block" \
	|| report fail "case 3: regen clears the drift block" "exit $rc: $out"

# Case 4: color-chip-only difference on disk -> exit 0 (injected line ignored).
new_repo
sed 's/color: green/color: red/' "$r/.zcode/agents/demo.md" > "$r/z.tmp" \
	&& mv "$r/z.tmp" "$r/.zcode/agents/demo.md"
run_guard "$r"
[ "$rc" -eq 0 ] && report ok "case 4: color-chip-only difference ignored" \
	|| report fail "case 4: color-chip-only difference ignored" "exit $rc: $out"

# Case 5: missing claude projection -> exit 1 naming the .claude path.
new_repo
rm "$r/.claude/agents/demo.md"
run_guard "$r"
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -Fq "missing: .claude/agents/demo.md"; then
	report ok "case 5: missing projection blocks, named"
else
	report fail "case 5: missing projection blocks, named" "exit $rc: $out"
fi

# Case 6: claude-only body drift -> exit 1 naming only `.claude/...`;
# regen clears it.
new_repo
printf 'Drifted claude body.\n' >> "$r/.claude/agents/demo.md"
run_guard "$r"
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -Fq "out of sync: .claude/agents/demo.md" \
	&& ! printf '%s' "$out" | grep -Fq "out of sync: .zcode/agents/demo.md"; then
	report ok "case 6: claude-only body drift named (zcode not blamed)"
else
	report fail "case 6: claude-only body drift named (zcode not blamed)" "exit $rc: $out"
fi
regen
run_guard "$r"
[ "$rc" -eq 0 ] && report ok "case 6b: regen clears claude-only drift" \
	|| report fail "case 6b: regen clears claude-only drift" "exit $rc: $out"

# Case 7: the pre-commit wrapper propagates a failing guard (the guard runs
# first, before the dart gates, so a temp repo needs no Flutter project).
new_repo
printf 'Body line two.\n' >> "$r/.agents/agents/demo.md"
git -C "$r" add .agents/agents/demo.md
run_wrap() { (cd "$1" && sh .githooks/pre-commit >"$tmp/out" 2>&1); rc=$?; out=$(cat "$tmp/out"); }
run_wrap "$r"
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -Fq "out of sync: .zcode/agents/demo.md"; then
	report ok "case 7: wrapper propagates the failing guard"
else
	report fail "case 7: wrapper propagates the failing guard" "exit $rc: $out"
fi

# Case 8: wrapper with the guard script missing -> FAILS CLOSED (exits 1 with
# the missing-script message, never the old warn-and-skip path).
new_repo
rm "$r/.githooks/check-projections.sh"
run_wrap "$r"
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -Fq "check-projections.sh missing" \
	&& ! printf '%s' "$out" | grep -Fq "guard skipped"; then
	report ok "case 8: missing guard fails closed"
else
	report fail "case 8: missing guard fails closed" "exit $rc: $out"
fi

# Case 9: the guard projects STAGED (index) content, not the working tree —
# the index holds version A (staged by new_repo), the worktree holds A+extra,
# and the on-disk projections were regenerated from the worktree; the commit
# would land A, which was never projected, so the guard must block.
new_repo
printf 'Body line two.\n' >> "$r/.agents/agents/demo.md"   # worktree = B
regen                                                       # projections from B
run_guard "$r"
[ "$rc" -eq 1 ] && report ok "case 9: partially staged blob (never projected) blocks" \
	|| report fail "case 9: partially staged blob (never projected) blocks" "exit $rc: $out"

# Case 10: the `color: ` strip must be anchored to the frontmatter — a body
# line starting with `color: ` is REAL content; drift on it must block.
new_repo
printf 'Color-line body line.\ncolor: red-body\n' >> "$r/.agents/agents/demo.md"
git -C "$r" add .agents/agents/demo.md
regen
# now drift ONLY the projected body's color-prefixed line (stale copy)
sed 's/color: red-body/color: blue-body/' "$r/.zcode/agents/demo.md" \
	> "$r/z.tmp" && mv "$r/z.tmp" "$r/.zcode/agents/demo.md"
run_guard "$r"
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -Fq "out of sync: .zcode/agents/demo.md"; then
	report ok "case 10: body color-prefixed line drift is not masked"
else
	report fail "case 10: body color-prefixed line drift is not masked" "exit $rc: $out"
fi
regen
run_guard "$r"
[ "$rc" -eq 0 ] && report ok "case 10b: body color lines compare literally once fresh" \
	|| report fail "case 10b: body color lines compare literally once fresh" "exit $rc: $out"

echo "cases: $case_n group(s), failures: $fails"
[ "$fails" -eq 0 ] || exit 1
