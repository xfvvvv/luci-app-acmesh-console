#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
API="$ROOT/htdocs/luci-static/resources/acmesh/api_v2.js"

if grep -F "], 'json', false, true);" "$API" >/dev/null 2>&1; then
	echo "API transport must not merge stderr into JSON output"
	exit 1
fi
[ "$(grep -F "'json', false, false);" "$API" | wc -l | tr -d ' ')" = 2 ] || {
	echo "both API calls must disable stderr merging"
	exit 1
}

echo "test_api_transport: ok"
