#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"
TMP="${TMPDIR:-/tmp}/acmesh-sudo-password.$$"
trap 'rm -rf "$TMP"' 0 HUP INT TERM
mkdir -p "$TMP"
chmod 700 "$TMP"

. "$ACMESH_LIB_DIR/authorization.sh"
. "$ACMESH_LIB_DIR/deploy.sh"
. "$ACMESH_LIB_DIR/operation.sh"
. "$ACMESH_LIB_DIR/task.sh"

export ACMESH_AUTH_STATE_DIR="$TMP/auth-state"
export ACMESH_AUTH_INSTANCE_FILE="$TMP/auth-state/instance-id"
export ACMESH_AUTH_CHALLENGE_DIR="$TMP/challenges"
mkdir -p "$ACMESH_AUTH_STATE_DIR" "$ACMESH_AUTH_CHALLENGE_DIR"
chmod 700 "$ACMESH_AUTH_STATE_DIR" "$ACMESH_AUTH_CHALLENGE_DIR"
# The host test runner may execute as an unprivileged WSL user.  Keep this
# focused protocol test independent of the host UID while retaining private
# directory semantics.
acmesh_private_dir() { mkdir -p "$1" && chmod 700 "$1"; }

ACMESH_AUTH_DEPLOY_TYPE=ssh
ACMESH_AUTH_SOURCE_TYPE=local-files
ACMESH_AUTH_HOST=router.example
ACMESH_AUTH_PORT=22
ACMESH_AUTH_USER=deploy
ACMESH_AUTH_SUDO_MODE=auto
ACMESH_AUTH_KEY_FILE=/etc/ssl/key.pem
ACMESH_AUTH_FULLCHAIN_FILE=/etc/ssl/fullchain.pem
ACMESH_AUTH_SUDO_PASSWORD_REQUIRED=true
snapshot="$TMP/deploy.snapshot"
acmesh_auth_snapshot deploy-run deployProfile deploy-1 "$snapshot"
grep -F 'b:sudoPasswordRequired:true' "$snapshot" >/dev/null
! grep -E 'password|secret' "$snapshot" >/dev/null

password_file="$TMP/sudo-password"
printf '%s' 'one-time-secret' > "$password_file"
chmod 600 "$password_file"
acmesh_private_file_is_secure() { [ "${1:-}" = "$password_file" ]; }
ACMESH_DEPLOY_SUDO_PASSWORD_FILE="$password_file"
export ACMESH_DEPLOY_SUDO_PASSWORD_FILE
remote_command="$(acmesh_deploy_remote_write_command 'cat > /tmp/target' 1)"
case "$remote_command" in
	*"sudo -S -p '' sh -c"*) ;;
	*) echo "sudo password mode should use sudo -S"; echo "$remote_command"; exit 1 ;;
esac
case "$remote_command" in *one-time-secret*|*sudo-password*) echo "sudo password leaked into remote command"; exit 1 ;; esac

ssh_bin="$TMP/bin"
mkdir -p "$ssh_bin"
cat > "$ssh_bin/ssh" <<'EOF'
#!/bin/sh
cat > "$ACMESH_SUDO_TEST_STDIN"
printf '%s\n' "$*" > "$ACMESH_SUDO_TEST_ARGS"
EOF
chmod +x "$ssh_bin/ssh"
source_file="$TMP/source.pem"
printf '%s' 'certificate-payload' > "$source_file"
stdin_capture="$TMP/stdin"
args_capture="$TMP/args"
old_path="$PATH"
PATH="$ssh_bin:$PATH"
export PATH ACMESH_SUDO_TEST_STDIN="$stdin_capture" ACMESH_SUDO_TEST_ARGS="$args_capture"
acmesh_ssh_client_is_dropbear() { return 1; }
acmesh_ssh_known_hosts_file() { printf '%s\n' "$TMP/known_hosts"; }
acmesh_deploy_ssh_copy "$source_file" deploy@router.example /tmp/target /tmp/key 22 1 "$TMP/target.tmp" 600
PATH="$old_path"
export PATH
expected_stdin="$TMP/expected"
printf 'one-time-secret\ncertificate-payload' > "$expected_stdin"
cmp "$expected_stdin" "$stdin_capture"
! grep -F 'one-time-secret' "$args_capture" >/dev/null

staged_dir="$TMP/staged"
mkdir -p "$staged_dir"
ACMESH_OPERATION_SUDO_PASSWORD_FILE="$password_file"
export ACMESH_OPERATION_SUDO_PASSWORD_FILE
acmesh_operation_stage_sudo_password "$staged_dir/sudo-password"
[ "$(cat "$staged_dir/sudo-password")" = 'one-time-secret' ]
ACMESH_DEPLOY_SUDO_PASSWORD_FILE="$staged_dir/sudo-password"
export ACMESH_DEPLOY_SUDO_PASSWORD_FILE
acmesh_deploy_cleanup_sudo_password
[ ! -e "$staged_dir/sudo-password" ]

task_id=20260822000000-123
task_workspace="$TMP/tasks/$task_id"
mkdir -p "$task_workspace"
printf '%s' 'stale-one-time-secret' > "$task_workspace/sudo-password"
ACMESH_TASK_WORKSPACE_DIR="$TMP/tasks"
export ACMESH_TASK_WORKSPACE_DIR
acmesh_task_cleanup_one_time_sudo_password "$task_id"
[ ! -e "$task_workspace/sudo-password" ]

acmesh_deploy_cleanup_sudo_password
[ ! -e "$password_file" ]
echo "test_sudo_password_flow: ok"
