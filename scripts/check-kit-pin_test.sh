#!/bin/sh
# Copyright (c) 2026 Rhythm Shahriar <me@rhy.io>
# SPDX-License-Identifier: MIT

# Tests for check-kit-pin.sh against temporary go.mod files. Offline: the
# latest tag comes from RHYTHM_KIT_LATEST. RHYTHM_KIT_REMOTE points at a
# local repository with a few tags for the ls-remote path.
#
#   sh scripts/check-kit-pin_test.sh
set -eu

here=$(cd "$(dirname "$0")" && pwd)
check="$here/check-kit-pin.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

failures=0
fail() {
	echo "FAIL: $*"
	failures=$((failures + 1))
}

# block <version> writes a go.mod that requires the kit inside a block.
block() {
	cat >"$tmp/go.mod" <<EOF
module github.com/RhythmShahriar/tool

go 1.27

require (
	github.com/charmbracelet/lipgloss v1.1.0
	github.com/RhythmShahriar/rhythm $1
)
EOF
}

# expect <want exit> <grep pattern> runs the checker on $tmp/go.mod.
expect() {
	want=$1 pattern=$2
	set +e
	out=$(sh "$check" "$tmp/go.mod" 2>&1)
	got=$?
	set -e
	[ "$got" -eq "$want" ] || fail "$(sed -n '/RhythmShahriar\/rhythm/p' "$tmp/go.mod" | tr -s '\t ' ' '): exit $got, want $want: $out"
	printf '%s\n' "$out" | grep -q -- "$pattern" || fail "output doesn't match '$pattern': $out"
}

export RHYTHM_KIT_LATEST=v0.6.0

block v0.6.0
expect 0 "v0.6.0 is current enough"

block v0.5.3
expect 0 "v0.5.3 is current enough (latest v0.6.0)"

block v0.4.9
expect 1 "pins github.com/RhythmShahriar/rhythm v0.4.9 but the latest is v0.6.0"

block v0.1.0
expect 1 "pins github.com/RhythmShahriar/rhythm v0.1.0 but the latest is v0.6.0; move to v0.5.0 or later"

# A pseudo-version compares by its major and minor.
block v0.5.4-0.20261001000000-abcdefabcdef
expect 0 "is current enough"

# A single-line require counts too.
cat >"$tmp/go.mod" <<'EOF'
module github.com/RhythmShahriar/tool

require github.com/RhythmShahriar/rhythm v0.3.0
EOF
expect 1 "v0.3.0 but the latest is v0.6.0"

# No kit requirement: skipped. A module that only shares the prefix isn't
# the kit. Neither is a commented-out line.
cat >"$tmp/go.mod" <<'EOF'
module github.com/RhythmShahriar/tool

require (
	github.com/RhythmShahriar/rhythm-extra v0.1.0
	// github.com/RhythmShahriar/rhythm v0.1.0
)
EOF
expect 0 "doesn't require github.com/RhythmShahriar/rhythm; skipped"

# go.work is ignored: only go.mod decides.
block v0.1.0
printf 'go 1.27\n\nuse .\n' >"$tmp/go.work"
expect 1 "v0.1.0 but the latest is v0.6.0"
rm "$tmp/go.work"

# A newer major is always too far behind.
RHYTHM_KIT_LATEST=v1.0.0
block v0.9.0
expect 1 "v0.9.0 but the latest is v1.0.0; move to v1.0.0 or later"

# Without the override, the latest release tag comes from ls-remote;
# prereleases are ignored.
unset RHYTHM_KIT_LATEST
git init -q "$tmp/remote"
git -C "$tmp/remote" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m init
for t in v0.4.0 v0.10.1 v0.9.0 v0.11.0-rc1; do
	git -C "$tmp/remote" tag "$t"
done
export RHYTHM_KIT_REMOTE="$tmp/remote"
block v0.9.0
expect 0 "latest v0.10.1"
block v0.8.2
expect 1 "v0.8.2 but the latest is v0.10.1"

# A failed ls-remote is retried once. The git stub fails the first
# $GIT_FAILS calls, then runs the real git.
mkdir "$tmp/bin"
real_git=$(command -v git)
cat >"$tmp/bin/git" <<EOF
#!/bin/sh
n=\$(cat "$tmp/git.calls" 2>/dev/null || echo 0)
n=\$((n + 1))
echo "\$n" >"$tmp/git.calls"
[ "\$n" -gt "\$GIT_FAILS" ] || { echo "fatal: unable to access" >&2; exit 128; }
exec "$real_git" "\$@"
EOF
chmod +x "$tmp/bin/git"
export RHYTHM_KIT_RETRY_DELAY=0
block v0.9.0
rm -f "$tmp/git.calls"
PATH="$tmp/bin:$PATH" GIT_FAILS=1 expect 0 "latest v0.10.1"
[ "$(cat "$tmp/git.calls")" -eq 2 ] || fail "ls-remote ran $(cat "$tmp/git.calls") times after one failure, want 2"
rm -f "$tmp/git.calls"
PATH="$tmp/bin:$PATH" GIT_FAILS=2 expect 2 "couldn't list the tags"
[ "$(cat "$tmp/git.calls")" -eq 2 ] || fail "ls-remote ran $(cat "$tmp/git.calls") times after two failures, want 2"
unset RHYTHM_KIT_RETRY_DELAY

# A missing go.mod is a usage error.
rm "$tmp/go.mod"
expect 2 "not found"

if [ "$failures" -gt 0 ]; then
	echo "$failures check-kit-pin test(s) failed"
	exit 1
fi
echo "check-kit-pin: all tests passed"
