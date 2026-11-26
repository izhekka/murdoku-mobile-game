#!/usr/bin/env bash
# run_with_timeout.sh <seconds> <log-file> <command…> — pure-bash process
# watchdog (issue #85). The host has no `timeout`/`gtimeout` binaries, so the
# bound is enforced in bash: the child runs in the background leading its own
# process group (`set -m`), a watchdog subshell sleeps the bound and kills the
# child's process group on expiry (SIGTERM, 2s grace, then SIGKILL) so the
# whole child tree dies — `flutter test`'s hung `flutter_tester` grandkids
# included (#83's 38-minute idle).
#
# stdout+stderr of <command…> are teed into <log-file> AND shown; the last
# output line is `exit=<code>`. `exit=124` is printed if and only if the
# watchdog delivered SIGTERM to the child's process group within the bound —
# whatever the child then exits with (a graceful TERM handler cannot turn a
# hung harness into a PASS). A nonzero child exit without a fired watchdog is
# reported verbatim. The log is truncated explicitly at start — never append
# into a stale log. Missing or invalid arguments exit nonzero (64 usage,
# 65 unwritable/mktemp/log failures).
#
# There is one µs-scale boundary race, as in any watchdog: a child finishing
# naturally at the same instant the bound fires may be classified either way.
#
# bash-3.2 compatible (macOS system bash): no `wait -n`, no `$!` on process
# substitutions, no math on floats.
set -u

die() { printf 'run_with_timeout: %s\n' "$1" >&2; }

if [ "$#" -lt 3 ]; then
	die "usage: run_with_timeout.sh <seconds> <log-file> <command…>"
	exit 64
fi
seconds="$1"
case "$seconds" in
'' | *[!0-9]*)
	die "<seconds> must be a positive integer, got: '$seconds'"
	exit 64
	;;
esac
if [ "${#seconds}" -gt 9 ]; then
	die "<seconds> is out of range (max 999999999), got: '$seconds'"
	exit 64
fi
if [ "$seconds" -lt 1 ]; then
	die "<seconds> must be a positive integer, got: '$seconds'"
	exit 64
fi
log="$2"
shift 2
if ! : >"$log" 2>/dev/null; then
	die "cannot write log file: $log"
	exit 65
fi

bound="$seconds"
marker=$(mktemp "${TMPDIR:-/tmp}/run_with_timeout.XXXXXX") || {
	die "cannot create a marker file"
	exit 65
}

(
	# Monitor mode: backgrounded jobs get their own process group, so the
	# watcher's group-kill reaches everything under the child.
	set -m

	"$@" &
	pid=$!

	# Watchdog. stdio detached so it never holds the tee'd pipe open and
	# cannot delay EOF on the consumer after an expiry. The marker records
	# a DELIVERED TERM (kill returned 0) only, so an already-dead child is
	# never mislabeled.
	(
		sleep "$bound" 2>/dev/null
		if kill -TERM -- "-$pid" >/dev/null 2>&1; then
			printf 1 >"$marker"
		fi
		sleep 2 2>/dev/null
		kill -KILL -- "-$pid" 2>/dev/null
	) >/dev/null 2>&1 &
	watcher=$!

	wait "$pid"
	rc=$?

	if [ -s "$marker" ]; then
		# The bound expired and the TERM was delivered: never a success.
		# Leave the watcher alive to finish its TERM→KILL escalation, but
		# do not wait for it (keeps expiry ≈ the bound).
		rc=124
	else
		# Child finished inside the bound: stop the pending watchdog.
		kill -- "-$watcher" 2>/dev/null || kill "$watcher" 2>/dev/null
		wait "$watcher" 2>/dev/null
	fi
	rm -f "$marker"

	printf 'exit=%s\n' "$rc"
	exit "$rc"
) > >(tee "$log") 2>&1
exit $?
