#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CTL="$ROOT/root/usr/libexec/acmesh-console/acmeshctl"
ISSUE_BLOCK="$(sed -n '/^acmesh_run_issue_profile() (/,/^)/p' "$CTL")"

printf '%s\n' "$ISSUE_BLOCK" | grep -F 'acmesh_deploy_install_acme_hooks' >/dev/null
printf '%s\n' "$ISSUE_BLOCK" | grep -F 'acmesh_execute_issue' >/dev/null
if printf '%s\n' "$ISSUE_BLOCK" | grep -F -- '--deploy-hook' >/dev/null; then
	echo "issue worker must not run a second deploy hook"
	exit 1
fi

echo "test_issue_deploy_separation: ok"
