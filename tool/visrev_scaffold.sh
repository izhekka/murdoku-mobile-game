#!/usr/bin/env bash
# visrev_scaffold.sh <scratch-dir> <issue-number> — deterministic scratch
# prep for the visual-reviewer (issue #85). Produces the self-contained
# `pixrev<issue>` review environment, OUTSIDE the repo tree, with every
# process step wrapped by tool/run_with_timeout.sh so prep can never hang:
#
#   - pubspec template: path dependency on this repo (package name and
#     environment.sdk constraint are PARSED from the repo's own
#     pubspec.yaml — never hardcoded), `flutter` + `flutter_test` dev deps,
#     and the repo's assets/items/ declared (the only assets board painters
#     need — copied verbatim);
#   - `flutter pub get` first with --offline (deps are already in the pub
#     cache from the repo), plain fallback under its own bound only if
#     offline fails;
#   - environment.log: flutter version, repo HEAD, UTC timestamp, issue.
#
# Fail closed on: invalid issue number, existing target, bare basename not
# starting with "pixrev" (the pixrev<issue> convention), paths inside the
# repo tree or not strictly under /tmp / $TMPDIR.
#
# bash-3.2 compatible (macOS system bash).
set -u

die() { printf 'visrev_scaffold: %s\n' "$1" >&2; exit 1; }

if [ "$#" -ne 2 ]; then
	die "usage: visrev_scaffold.sh <scratch-dir> <issue-number>"
fi
scratch_arg="$1"
issue="$2"
case "$issue" in
'' | *[!0-9]*) die "issue number must be a non-negative integer, got: '$issue'" ;;
esac
if ! command -v realpath >/dev/null 2>&1; then
	die "realpath is required but not available on this host"
fi

script_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P) ||
	die "cannot locate the script directory"
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd -P) ||
	die "cannot locate the repo root"
wrapper="$script_dir/run_with_timeout.sh"
[ -x "$wrapper" ] || die "missing/unexecutable wrapper: $wrapper"
command -v flutter >/dev/null 2>&1 || die "flutter is not on PATH"
[ -f "$repo_root/pubspec.yaml" ] || die "no pubspec.yaml in $repo_root"

# Canonical target: the parent must exist (the script creates only the last
# component), so guards below see the real path the dir will live at.
parent_arg=$(dirname -- "$scratch_arg")
base_arg=$(basename -- "$scratch_arg")
parent=$(realpath "$parent_arg" 2>/dev/null) ||
	die "cannot resolve parent directory: $parent_arg"
target="$parent/$base_arg"

case "$base_arg" in
pixrev*) ;;
*) die "scratch dir basename must follow the pixrev<issue> convention (got '$base_arg')" ;;
esac
if [ -e "$target" ] || [ -L "$target" ]; then
	die "refusing: '$target' already exists — scaffold into a fresh dir (clean stale ones with tool/scratch_clean.sh)"
fi
case "$target" in
"$repo_root"|"$repo_root"/*)
	die "refusing: '$target' is inside the repo tree ($repo_root)"
	;;
esac
roots="/tmp"
if [ -n "${TMPDIR:-}" ] && [ -d "$TMPDIR" ]; then
	roots="$roots
$TMPDIR"
fi
under=""
while IFS= read -r root; do
	[ -n "$root" ] || continue
	can=$(realpath "$root" 2>/dev/null) || continue
	[ -n "$can" ] || continue
	if [ "$target" = "$can" ]; then
		continue # a temp root itself is never a scratch dir
	fi
	case "$target" in
	"$can"/*)
		under="$can"
		break
		;;
	esac
done <<EOF
$roots
EOF
[ -n "$under" ] ||
	die "refusing: '$target' is not under a sanctioned temp root (/tmp, \$TMPDIR)"

# Deterministic inputs from the repo's own pubspec.yaml (never hardcoded).
repo_pkg_name=$(awk '
	/^name:[[:space:]]*/ { sub(/^name:[[:space:]]*/, ""); print; exit }
' "$repo_root/pubspec.yaml")
sdk_constraint=$(awk '
	{ if (inenv && /^[^[:space:]#]/) exit } # left the environment block
	/^[[:space:]]*environment:/ { inenv=1; next }
	inenv && /^[[:space:]]*sdk:/ { sub(/^[[:space:]]*sdk:[[:space:]]*/, ""); print; exit }
' "$repo_root/pubspec.yaml")
[ -n "$repo_pkg_name" ] || die "could not parse name: from $repo_root/pubspec.yaml"
[ -n "$sdk_constraint" ] || die "could not parse environment.sdk from $repo_root/pubspec.yaml"
# The constraint is written VERBATIM (quotes preserved): a quoted `>=`-style
# constraint must stay quoted — an unquoted `>=3.5.0 <4.0.0` is a YAML parse
# error that breaks every flutter command in the scratch.

# Every process step runs under the wrapper; its log also records exit=<c>.
step() {
	secs="$1"
	logf="$2"
	shift 2
	( cd "$target" && "$wrapper" "$secs" "$target/scaffold/$logf" "$@" ) ||
		die "step '$*' failed (exit=$?, log: $target/scaffold/$logf)"
}

mkdir -p "$target/scaffold" "$target/assets" ||
	die "cannot create $target"

cat >"$target/pubspec.yaml" <<EOF
name: pixrev$issue
description: "Visual-reviewer scratch harness for murdoku issue #$issue"
publish_to: 'none'
environment:
  sdk: $sdk_constraint
dependencies:
  $repo_pkg_name:
    path: $repo_root
  flutter:
    sdk: flutter
dev_dependencies:
  flutter_test:
    sdk: flutter
flutter:
  uses-material-design: true
  assets:
    - assets/items/
EOF

step 120 flutter_version.log flutter --version
step 60 asset_copy.log cp -R "$repo_root/assets/items" "$target/assets"

# Offline pub get first (deps already cached from the repo); bounded plain
# fallback only if offline fails.
pub_get_mode="offline"
pub_get_log="pub_offline.log"
( cd "$target" && "$wrapper" 300 "$target/scaffold/pub_offline.log" flutter pub get --offline )
if [ $? -ne 0 ]; then
	printf 'visrev_scaffold: offline pub get failed; falling back (bounded)\n'
	pub_get_mode="plain fallback (bounded, after offline failure)"
	pub_get_log="pub_online.log"
	( cd "$target" && "$wrapper" 300 "$target/scaffold/pub_online.log" flutter pub get ) ||
		die "flutter pub get failed (offline and bounded fallback); see scaffold/pub_*.log"
fi
[ -f "$target/.dart_tool/package_config.json" ] ||
	die "pub get produced no package_config.json — environment incomplete"

head=$(git -C "$repo_root" rev-parse HEAD 2>/dev/null) ||
	die "cannot resolve repo HEAD"
utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
{
	printf '# Environment provenance (tool/visrev_scaffold.sh, issue #85 rails)\n'
	printf 'issue: %s\n' "$issue"
	printf 'repo: %s\n' "$repo_root"
	printf 'head: %s\n' "$head"
	printf 'created_utc: %s\n' "$utc"
	printf 'sdk_constraint: %s (parsed from repo pubspec.yaml)\n' "$sdk_constraint"
	printf 'pub_get: %s (log: scaffold/%s)\n' "$pub_get_mode" "$pub_get_log"
	printf 'flutter_version:\n'
	sed 's/^/  /' "$target/scaffold/flutter_version.log"
} >"$target/environment.log"

printf 'visrev_scaffold: ready %s\n' "$target"
printf 'visrev_scaffold: sdk=%s package=%s head=%s\n' "$sdk_constraint" "$repo_pkg_name" "$head"
