#!/bin/sh
# Copyright (c) 2026 Rhythm Shahriar <me@rhy.io>
# SPDX-License-Identifier: MIT

# Fails when a tool pins the rhythm kit more than one minor release behind
# the latest rhythm tag, so kit security fixes can't silently stop reaching
# its users.
#
#   sh scripts/check-kit-pin.sh [path/to/go.mod]
#
# The pin is read from go.mod itself, never from go.work: the release builds
# with GOWORK=off, so go.mod is what users get. The latest tag comes from
# `git ls-remote --tags` unless RHYTHM_KIT_LATEST is set (tests and mirrors).
# A failed ls-remote is retried once after RHYTHM_KIT_RETRY_DELAY seconds
# (default 5).
#
# Exit codes: 0 up to date or no kit requirement, 1 stale pin, 2 usage or
# lookup error.
set -eu

module=github.com/RhythmShahriar/rhythm
remote=${RHYTHM_KIT_REMOTE:-https://github.com/RhythmShahriar/rhythm}
gomod=${1:-go.mod}

if [ ! -f "$gomod" ]; then
	echo "check-kit-pin: $gomod not found" >&2
	exit 2
fi

# Matches both "require <module> <version>" and a line inside a
# "require (...)" block. Only the exact module path counts: a different
# module that merely starts with the same path isn't the kit.
pin=$(awk -v m="$module" '
	/^[[:space:]]*\/\// { next }
	$1 == "require" && $2 == m { print $3; exit }
	$1 == "require" && $2 == "(" { block = 1; next }
	block && $1 == ")" { block = 0; next }
	block && $1 == m { print $2; exit }
' "$gomod")

if [ -z "$pin" ]; then
	echo "check-kit-pin: $gomod doesn't require $module; skipped"
	exit 0
fi

if [ -n "${RHYTHM_KIT_LATEST:-}" ]; then
	latest=$RHYTHM_KIT_LATEST
else
	# One retry, so a brief GitHub blip doesn't fail CI.
	if ! refs=$(git ls-remote --tags --refs "$remote" 'v*'); then
		echo "check-kit-pin: listing the tags at $remote failed; retrying once" >&2
		sleep "${RHYTHM_KIT_RETRY_DELAY:-5}"
		if ! refs=$(git ls-remote --tags --refs "$remote" 'v*'); then
			echo "check-kit-pin: couldn't list the tags at $remote" >&2
			exit 2
		fi
	fi
	# Release tags only: prereleases (v1.2.0-rc1) and peeled refs (^{}) are
	# dropped, then the highest version wins.
	latest=$(printf '%s\n' "$refs" |
		sed -n 's|.*refs/tags/\(v[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)$|\1|p' |
		sed 's/^v//' | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1)
	[ -z "$latest" ] || latest=v$latest
fi

if [ -z "$latest" ]; then
	echo "check-kit-pin: couldn't find the latest rhythm tag at $remote" >&2
	exit 2
fi

# major and minor of a version like v0.5.3 or v0.5.3-0.20260101-abcdef.
split() {
	printf '%s\n' "$1" | sed -n 's/^v\([0-9][0-9]*\)\.\([0-9][0-9]*\)\..*$/\1 \2/p'
}

# split prints two words; the unquoted expansion splits them on purpose.
# shellcheck disable=SC2046
set -- $(split "$pin")
pin_major=${1:-} pin_minor=${2:-}
# shellcheck disable=SC2046
set -- $(split "$latest")
latest_major=${1:-} latest_minor=${2:-}

if [ -z "$pin_major" ] || [ -z "$latest_major" ]; then
	echo "check-kit-pin: can't compare $pin with $latest" >&2
	exit 2
fi

# A newer major is always too far behind. Within one major, the pin may
# trail the latest minor by one release, so a tool has a release cycle to
# catch up.
if [ "$pin_major" -lt "$latest_major" ] ||
	{ [ "$pin_major" -eq "$latest_major" ] && [ $((latest_minor - pin_minor)) -gt 1 ]; }; then
	oldest=$latest_minor
	[ "$oldest" -eq 0 ] || oldest=$((oldest - 1))
	echo "check-kit-pin: $gomod pins $module $pin but the latest is $latest; move to v$latest_major.$oldest.0 or later" >&2
	exit 1
fi

echo "check-kit-pin: $module $pin is current enough (latest $latest)"
