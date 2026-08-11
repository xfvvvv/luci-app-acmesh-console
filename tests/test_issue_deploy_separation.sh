#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CTL="$ROOT/root/usr/libexec/acmesh-console/acmeshctl"
OPERATION="$ROOT/root/usr/libexec/acmesh-console/lib/operation.sh"
AUTH="$ROOT/root/usr/libexec/acmesh-console/lib/authorization.sh"
RPC="$ROOT/root/usr/libexec/acmesh-console/rpc-write"
ISSUE_BLOCK="$(sed -n '/^acmesh_run_issue_profile() (/,/^)/p' "$CTL")"

printf '%s\n' "$ISSUE_BLOCK" | grep -F 'acmesh_deploy_install_acme_hooks' >/dev/null
printf '%s\n' "$ISSUE_BLOCK" | grep -F 'acmesh_execute_issue' >/dev/null
if printf '%s\n' "$ISSUE_BLOCK" | grep -F -- '--deploy-hook' >/dev/null; then
	echo "issue worker must not run a second deploy hook"
	exit 1
fi

grep -F 'acmesh_run_issue_deploy_profile() (' "$CTL" >/dev/null
grep -F 'acmesh_execute_profile_deploy' "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" >/dev/null
grep -F 'issue|issue-deploy) printf' "$OPERATION" >/dev/null
grep -F 'if [ "$issue_operation" = issue-deploy ] && [ -n "$ACMESH_AUTH_DEPLOY_PROFILE_ID" ]' "$OPERATION" >/dev/null
grep -F 'issue-deploy:issueProfile' "$OPERATION" >/dev/null
grep -F 'acmesh_operation_save_conversion_continuation' "$OPERATION" >/dev/null
grep -F 'acmesh_operation_take_conversion_continuation' "$OPERATION" >/dev/null
grep -F 'issue-deploy) acmesh_auth_emit_issue' "$AUTH" >/dev/null
grep -F 'issue|issue-deploy|renew' "$AUTH" >/dev/null
grep -F 'issue_deploy) command=issue-deploy' "$RPC" >/dev/null

echo "test_issue_deploy_separation: ok"
