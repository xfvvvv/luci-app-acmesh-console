#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"; TMP="${TMPDIR:-/tmp}/acmesh-hook-auth.$$"; trap 'rm -rf "$TMP"' 0 HUP INT TERM
mkdir -p "$TMP/lib"
for lib in cert task command dns provider deploy ssh config request_payload authorization; do : > "$TMP/lib/$lib.sh"; done
mkdir -p "$TMP/bin"
cat > "$TMP/bin/jsonfilter" <<'SH'
#!/bin/sh
file="" expr=""
while [ "$#" -gt 0 ]; do
	case "$1" in
		-i) file="$2"; shift 2 ;;
		-e) expr="$2"; shift 2 ;;
		*) shift ;;
	esac
done
data="$(if [ -n "$file" ]; then cat "$file"; else cat; fi)"
case "$expr" in
	'@.taskId') printf '%s\n' "$data" | sed -n 's/.*"taskId"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' ;;
	'@.status') printf '%s\n' "$data" | sed -n 's/.*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' ;;
esac
SH
chmod 0755 "$TMP/bin/jsonfilter"
cat > "$TMP/lib/operation.sh" <<'SH'
acmesh_profile_validate_id() { return 0; }
acmesh_profile_find_linked_deploy() { printf '%s\n' deploy-1; }
acmesh_operation_is_remembered() { [ "${HOOK_AUTHORIZED:-0}" = 1 ]; }
acmesh_task_validate_id() { [ "$1" = hook-task ]; }
acmesh_operation_start() { [ "${ACMESH_OPERATION_REQUIRE_REMEMBERED:-0}" = 1 ] || return 99; printf '%s\n' "$*" >> "$HOOK_TRACE"; printf '{"ok":true,"taskId":"hook-task"}\n'; }
SH
mkdir -p "$TMP/tasks"; printf '{"status":"success"}\n' > "$TMP/tasks/hook-task.json"
export ACMESH_LIB_DIR="$TMP/lib" HOOK_TRACE="$TMP/trace" ACMESH_TASK_STATE_DIR="$TMP/tasks"
export PATH="$TMP/bin:$PATH"
set +e; denied="$(ACMESH_DEPLOY_PROFILE_ID=deploy-1 sh "$ROOT/root/usr/libexec/acmesh-console/hooks/acmesh-console-ssh.sh" 2>&1)"; rc=$?; set -e
[ "$rc" -ne 0 ]; case "$denied" in *'authorization required for deploy profile deploy-1'*) ;; *) echo "$denied"; exit 1;; esac
[ ! -s "$TMP/trace" ]
HOOK_AUTHORIZED=1 ACMESH_DEPLOY_PROFILE_ID=deploy-1 sh "$ROOT/root/usr/libexec/acmesh-console/hooks/acmesh-console-ssh.sh" | grep -F '"taskId":"hook-task"' >/dev/null
[ "$(tail -n 1 "$TMP/trace")" = 'deploy-run deployProfile deploy-1 ' ]
echo "test_deploy_hook_authorization: ok"
