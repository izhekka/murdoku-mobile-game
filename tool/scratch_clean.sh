#!/usr/bin/env bash
# scratch_clean.sh <dir> — the ONLY sanctioned scratch-cleanup path in
# visual-reviewer context (issue #85). Fail closed:
#
#   - resolves <dir> with realpath (symlinks expanded, repo-internal
#     traversals land back in the tree where they are caught);
#   - refuses (nonzero, message, NOTHING deleted) any path inside the repo
#     tree, any path not strictly under a sanctioned temp root (/tmp and
#     $TMPDIR — canonicalized with realpath too, because /tmp is really
#     /private/tmp on macOS), the temp roots themselves, and non-directories;
#   - otherwise prints exactly what it is about to delete, removes it, and
#     verifies it is gone.
#
# Raw `rm`/`pkill`/`killall` are banned for the reviewer (stall risk on
# permission prompts, no fail-closed checks); route every cleanup through
# this script.
#
# bash-3.2 compatible (macOS system bash).
set -u

die() { printf 'scratch_clean: %s\n' "$1" >&2; exit 1; }

if [ "$#" -ne 1 ]; then
	die "usage: scratch_clean.sh <dir>"
fi
if ! command -v realpath >/dev/null 2>&1; then
	die "realpath is required but not available on this host"
fi

script_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P) ||
	die "cannot locate the script directory"
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd -P) ||
	die "cannot locate the repo root"

target=$(realpath "$1" 2>/dev/null) ||
	die "cannot resolve '$1' (missing path or broken symlink); nothing deleted"
[ -d "$target" ] || die "not a directory: $target; nothing deleted"

case "$target" in
"$repo_root"|"$repo_root"/*)
	die "refusing: '$target' is inside the repo tree ($repo_root); nothing deleted"
	;;
esac

# Sanctioned temp roots, canonicalized the same way the target is.
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
		# A bare temp root itself is never a scratch dir.
		continue
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
if [ -z "$under" ]; then
	die "refusing: '$target' is not a scratch dir under a sanctioned temp root (/tmp, \$TMPDIR); nothing deleted"
fi

printf 'scratch_clean: deleting %s (under %s)\n' "$target" "$under"
find "$target" -print | sed 's/^/  /'
rm -rf -- "$target" || die "rm -rf failed on '$target'"
[ -e "$target" ] && die "target still present after rm -rf: $target"
printf 'scratch_clean: removed %s\n' "$target"
