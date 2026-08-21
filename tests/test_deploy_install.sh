#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"
. "$ACMESH_LIB_DIR/json.sh"
. "$ROOT/tests/lib/cli_request.sh"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"
export ACMESH_TASK_STATE_DIR="$ROOT/tests/.tmp/deploy-state"
export ACMESH_TASK_LOG_DIR="$ROOT/tests/.tmp/deploy-log"
export ACMESH_DEPLOY_LOCK_DIR="$ROOT/tests/.tmp/deploy-locks"
export ACMESH_SSH_DIR="$ROOT/tests/.tmp/deploy-ssh"
export ACMESH_TASK_WORKSPACE_DIR="$ROOT/tests/.tmp/deploy-workspaces"
rm -rf "$ACMESH_TASK_STATE_DIR" "$ACMESH_TASK_LOG_DIR" "$ACMESH_DEPLOY_LOCK_DIR" "$ACMESH_TASK_WORKSPACE_DIR"
mkdir -p "$ROOT/tests/.tmp"
mkdir -p "$ACMESH_TASK_WORKSPACE_DIR"
chmod 700 "$ROOT/tests/.tmp"
chmod 700 "$ACMESH_TASK_WORKSPACE_DIR"
. "$ROOT/tests/lib/host_flock.sh"
acmesh_test_install_flock_shim "$ROOT/tests/.tmp/deploy-flock"
printf '%s\n' '11111111-2222-3333-4444-555555555555' > "$ROOT/tests/.tmp/boot_id"
ACMESH_BOOT_ID_FILE="$ROOT/tests/.tmp/boot_id"
export ACMESH_BOOT_ID_FILE

if [ "$(LC_ALL=C ls -ld "$ROOT/tests/.tmp" | awk '{print $1}')" != drwx------ ]; then
	host_bin="$ROOT/tests/.tmp/deploy-host-bin"
	mkdir -p "$host_bin"
	export ACMESH_TEST_REAL_LS="$(command -v ls)"
	export ACMESH_TEST_PRIVATE_ROOT="$ROOT/tests/.tmp"
	cat > "$host_bin/ls" <<'EOF'
#!/bin/sh
case "${1:-}" in
	-ld|-nd)
		candidate="${2:-}"
		case "$candidate" in
			"$ACMESH_TEST_PRIVATE_ROOT"|"$ACMESH_TEST_PRIVATE_ROOT"/*)
				if [ -d "$candidate" ] && [ ! -L "$candidate" ]; then
					printf 'drwx------ 1 0 0 0 Jan 1 00:00 %s\n' "$candidate"
					exit 0
				fi
				if [ -f "$candidate" ] && [ ! -L "$candidate" ]; then
					printf '%s\n' "-rw------- 1 0 0 0 Jan 1 00:00 $candidate"
					exit 0
				fi
				;;
		esac
		;;
esac
exec "$ACMESH_TEST_REAL_LS" "$@"
EOF
	chmod +x "$host_bin/ls"
	PATH="$host_bin:$PATH"
	export PATH
	printf '%s\n' "test_deploy_install: SKIP POSIX mode observation (using isolated host metadata adapter)" >&2
fi

trust_bin="$ROOT/tests/.tmp/deploy-trust-bin"
rm -rf "$trust_bin" "$ACMESH_SSH_DIR"
mkdir -p "$trust_bin" "$ACMESH_SSH_DIR"
cat > "$trust_bin/ssh-keyscan" <<'EOF'
#!/bin/sh
host=""
while [ "$#" -gt 0 ]; do case "$1" in -p|-T|-t) shift 2;; *) host="$1"; shift;; esac; done
printf '%s ssh-ed25519 AAAAdeployfixture\n' "$host"
EOF
cat > "$trust_bin/ssh-keygen" <<'EOF'
#!/bin/sh
printf '256 SHA256:deploy-fixture fixture (ED25519)\n'
EOF
chmod +x "$trust_bin/ssh-keyscan" "$trust_bin/ssh-keygen"
PATH="$trust_bin:$PATH"
export PATH
for pinned_host in 192.0.2.30 192.0.2.31 192.0.2.32 192.0.2.33 192.0.2.40 192.0.2.41; do
	printf '%s ssh-ed25519 AAAAdeployfixture\n' "$pinned_host" >> "$ACMESH_SSH_DIR/known_hosts"
done
chmod 600 "$ACMESH_SSH_DIR/known_hosts"

preview="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" deploy-preview --domain example.com --key-file /etc/ssl/example.key --fullchain-file /etc/ssl/example.fullchain.pem --reloadcmd 'service nginx reload')"
case "$preview" in
	*"--install-cert"*"-d 'example.com'"*"--key-file '/etc/ssl/example.key'"*"&& service nginx reload"*) ;;
	*) echo "deploy preview is wrong"; echo "$preview"; exit 1 ;;
esac

managed_home="$ROOT/tests/.tmp/deploy-managed-home"
rm -rf "$managed_home"
mkdir -p "$managed_home"
printf '#!/bin/sh\n' > "$managed_home/acme.sh"
chmod +x "$managed_home/acme.sh"
managed_preview="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" deploy-preview --home "$managed_home" --domain managed.example.com --key-file /etc/ssl/managed.key --fullchain-file /etc/ssl/managed.fullchain.pem)"
case "$managed_preview" in
	*"'$managed_home/acme.sh'"*"--install-cert"*"-d 'managed.example.com'"*) ;;
	*) echo "managed acme deploy should use configured acme.sh home"; echo "$managed_preview"; exit 1 ;;
esac

rsa_managed_preview="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" deploy-preview \
	--type ssh \
	--cert-source managed-acme \
	--domain rsa.example.com \
	--key-type rsa \
	--host 192.0.2.10 \
	--key-file /etc/ssl/rsa.example.key \
	--fullchain-file /etc/ssl/rsa.example.fullchain.pem)"
case "$(printf '%s\n' "$rsa_managed_preview" | wc -l | tr -d ' ')" in
	1) ;;
	*) echo "deploy preview JSON should not contain literal newlines"; echo "$rsa_managed_preview"; exit 1 ;;
esac
if ssh -V 2>&1 | grep -qi dropbear; then
	case "$rsa_managed_preview" in
		*"HOME='[task-private-ssh-home]' ssh "*) ;;
		*) echo "Dropbear preview must use a private pinned-host home"; echo "$rsa_managed_preview"; exit 1 ;;
	esac
else
	case "$rsa_managed_preview" in
		*"StrictHostKeyChecking=yes"*"UserKnownHostsFile="*) ;;
		*) echo "OpenSSH preview must enforce the pinned host store"; echo "$rsa_managed_preview"; exit 1 ;;
	esac
fi
case "$rsa_managed_preview" in
	*"ssh -y"*|*"StrictHostKeyChecking=accept-new"*) echo "SSH preview must not auto-accept host keys"; echo "$rsa_managed_preview"; exit 1 ;;
esac
case "$rsa_managed_preview" in
	*"/etc/acme/rsa.example.com/fullchain.cer"*"/etc/acme/rsa.example.com/rsa.example.com.key"*) ;;
	*) echo "managed RSA deploy should use RSA source directory"; echo "$rsa_managed_preview"; exit 1 ;;
esac
case "$rsa_managed_preview" in
	*"/etc/acme/rsa.example.com_ecc/"*) echo "managed RSA deploy must not use ECC source directory"; echo "$rsa_managed_preview"; exit 1 ;;
esac

ecc_managed_preview="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" deploy-preview \
	--type ssh \
	--cert-source managed-acme \
	--domain ecc.example.com \
	--key-type ecc \
	--host 192.0.2.10 \
	--key-file /etc/ssl/ecc.example.key \
	--fullchain-file /etc/ssl/ecc.example.fullchain.pem)"
case "$ecc_managed_preview" in
	*"/etc/acme/ecc.example.com_ecc/fullchain.cer"*"/etc/acme/ecc.example.com_ecc/ecc.example.com.key"*) ;;
	*) echo "managed ECC deploy should use ECC source directory"; echo "$ecc_managed_preview"; exit 1 ;;
esac

out="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" deploy-test --domain example.com --key-file /etc/ssl/example.key --fullchain-file /etc/ssl/example.fullchain.pem --reloadcmd 'printf deploy-test-log-secret >/dev/null')"
case "$out" in
	*'"ok":true'*'"testMode":true'*) ;;
	*) echo "deploy test did not return preview"; echo "$out"; exit 1 ;;
esac
case "$out" in *'"taskId"'*) echo "deploy test mode created task"; exit 1;; esac
for forbidden in deploy-test-log-secret /etc/ssl/example.key --install-cert --reloadcmd; do
	case "$out" in
		*"$forbidden"*) echo "deploy preview exposed command data: $forbidden"; echo "$out"; exit 1 ;;
	esac
done

pem_out="$(acmesh_test_cli_request deploy-test \
	--type ssh \
	--cert-source paste-pem \
	--domain pem.example.com \
	--host 192.0.2.20 \
	--port 2222 \
	--user deploy \
	--key-file /etc/ssl/pem.example.key \
	--fullchain-file /etc/ssl/pem.example.fullchain.pem \
	--key-pem '-----BEGIN PRIVATE KEY-----
secret-private-key
-----END PRIVATE KEY-----' \
	--fullchain-pem '-----BEGIN CERTIFICATE-----
public-cert
-----END CERTIFICATE-----' \
	--reloadcmd 'systemctl reload nginx')"
case "$pem_out" in
	*'"ok":true'*'"testMode":true'*) ;;
	*) echo "deploy pem test did not return preview"; echo "$pem_out"; exit 1 ;;
esac
case "$pem_out" in *'"taskId"'*) echo "deploy pem test mode created task"; exit 1;; esac
for forbidden in secret-private-key /tmp/acmesh-console-deploy deploy@192.0.2.20 "ssh -y" "scp -o" "systemctl reload nginx"; do
	case "$pem_out" in
		*"$forbidden"*) echo "deploy pem preview exposed command data: $forbidden"; echo "$pem_out"; exit 1 ;;
	esac
done

pem_preview="$(acmesh_test_cli_request deploy-preview \
	--type ssh \
	--cert-source paste-pem \
	--domain preview-pem.example.com \
	--host 192.0.2.21 \
	--key-file /etc/ssl/preview-pem.key \
	--fullchain-file /etc/ssl/preview-pem.fullchain.pem \
	--key-pem '-----BEGIN PRIVATE KEY-----
preview-secret-private-key
-----END PRIVATE KEY-----' \
	--fullchain-pem '-----BEGIN CERTIFICATE-----
preview-public-cert
-----END CERTIFICATE-----')"
case "$pem_preview" in *'"ok":true'*'"command"'*'[task-private-pem-key]'*) ;; *) echo "deploy pem stdin preview failed"; echo "$pem_preview"; exit 1;; esac
case "$pem_preview" in *preview-secret-private-key*|*preview-public-cert*) echo "deploy pem stdin preview leaked PEM"; exit 1;; esac

if unsafe_preview="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" deploy-preview \
	--type ssh \
	--cert-source local-files \
	--domain unsafe.example.com \
	--host '192.0.2.20;touch /tmp/acmesh-pwned' \
	--user 'deploy;id' \
	--source-key-file /tmp/source.key \
	--source-fullchain-file /tmp/source.fullchain.pem \
	--key-file /etc/ssl/unsafe.key \
	--fullchain-file /etc/ssl/unsafe.fullchain.pem 2>&1)"; then
	echo "unsafe SSH target should be rejected"
	echo "$unsafe_preview"
	exit 1
fi

# Task 9 closes legacy argument-based real deployment. Transactional local,
# remote and conversion execution remains covered by the dedicated deploy,
# SSH-security and transaction tests; this CLI test now asserts the closed gate.
set +e
legacy_real="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" deploy-run --type local --domain blocked.example 2>&1)"; legacy_rc=$?
set -e
[ "$legacy_rc" = 2 ] && printf '%s' "$legacy_real" | grep -F 'real deploy requires profileId' >/dev/null
echo "test_deploy_install: ok"
exit 0

DEPLOY_TMP="$ROOT/tests/.tmp/deploy-run"
rm -rf "$DEPLOY_TMP"
mkdir -p "$DEPLOY_TMP"
printf 'source-key\n' > "$DEPLOY_TMP/source.key"
printf 'source-fullchain\n' > "$DEPLOY_TMP/source.fullchain.pem"
run_out="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" deploy-run \
	--type local \
	--cert-source local-files \
	--domain run.example.com \
	--source-key-file "$DEPLOY_TMP/source.key" \
	--source-fullchain-file "$DEPLOY_TMP/source.fullchain.pem" \
	--key-file "$DEPLOY_TMP/target.key" \
	--fullchain-file "$DEPLOY_TMP/target.fullchain.pem" \
	--reloadcmd 'printf deploy-run-log-secret >/dev/null')"
case "$run_out" in
	*'"ok":true'*'"taskId"'*) ;;
	*) echo "deploy run did not create task"; echo "$run_out"; exit 1 ;;
esac
run_task_id="$(printf '%s' "$run_out" | sed -n 's/.*"taskId":"\([^"]*\)".*/\1/p')"
sleep 1
run_status="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" task-status --task-id "$run_task_id")"
run_log="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" task-log --task-id "$run_task_id")"
case "$run_status" in
	*'"status":"success"'*) ;;
	*) echo "deploy run task should succeed"; echo "$run_status"; echo "$run_log"; exit 1 ;;
esac
case "$run_status" in
	*'"operation":"deploy-run"'*) ;;
	*) echo "deploy run task has wrong operation"; echo "$run_status"; echo "$run_log"; exit 1 ;;
esac
[ "$(cat "$DEPLOY_TMP/target.key")" = "source-key" ] || { echo "deploy run did not install key"; exit 1; }
[ "$(cat "$DEPLOY_TMP/target.fullchain.pem")" = "source-fullchain" ] || { echo "deploy run did not install fullchain"; exit 1; }
case "$run_log" in
	*"REAL MODE: executing deploy profile"*) ;;
	*) echo "deploy run log is wrong"; echo "$run_log"; exit 1 ;;
esac
for forbidden in deploy-run-log-secret "$DEPLOY_TMP/source.key" "$DEPLOY_TMP/target.key" "mkdir -p" "chmod 600"; do
	case "$run_log" in
		*"$forbidden"*) echo "deploy run task log exposed command data: $forbidden"; echo "$run_log"; exit 1 ;;
	esac
done

failbin="$ROOT/tests/.tmp/deploy-fail-bin"
rm -rf "$failbin"
mkdir -p "$failbin"
cat > "$failbin/scp" <<'EOF'
#!/bin/sh
printf 'unexpected scp %s\n' "$*" >> "$ACMESH_DEPLOY_FAIL_TRACE"
exit 42
EOF
cat > "$failbin/ssh" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "-V" ]; then
	printf 'Dropbear ssh client\n' >&2
	exit 0
fi
printf 'ssh %s\n' "$*" >> "$ACMESH_DEPLOY_FAIL_TRACE"
case "$*" in
	*'acmesh_action=prepare'*|*'acmesh_action=cancel'*) exit 0 ;;
	*) exit 42 ;;
esac
EOF
chmod +x "$failbin/scp" "$failbin/ssh"
fail_trace="$ROOT/tests/.tmp/deploy-fail.trace"
rm -f "$fail_trace"
fail_ssh_key="$ROOT/tests/.tmp/deploy-fail.key"
printf '%s\n' 'dropbear-test-key' > "$fail_ssh_key"
chmod 600 "$fail_ssh_key"
old_path="$PATH"
PATH="$failbin:$PATH"
export PATH
ACMESH_DEPLOY_FAIL_TRACE="$fail_trace"
export ACMESH_DEPLOY_FAIL_TRACE
fail_out="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" deploy-run \
	--type ssh \
	--cert-source local-files \
	--domain fail.example.com \
	--host 192.0.2.30 \
	--ssh-key "$fail_ssh_key" \
	--source-key-file "$DEPLOY_TMP/source.key" \
	--source-fullchain-file "$DEPLOY_TMP/source.fullchain.pem" \
	--key-file /etc/ssl/fail.key \
	--fullchain-file /etc/ssl/fail.fullchain.pem)"
PATH="$old_path"
export PATH
case "$fail_out" in
	*'"ok":true'*'"taskId"'*) ;;
	*) echo "deploy fail run did not create task"; echo "$fail_out"; exit 1 ;;
esac
fail_task_id="$(printf '%s' "$fail_out" | sed -n 's/.*"taskId":"\([^"]*\)".*/\1/p')"
sleep 1
fail_status="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" task-status --task-id "$fail_task_id")"
fail_log="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" task-log --task-id "$fail_task_id")"
case "$fail_status" in
	*'"status":"failed"'*'"exitCode":42'*) ;;
	*) echo "ssh deploy should fail when first copy fails"; echo "$fail_status"; echo "$fail_log"; exit 1 ;;
esac
case "$(grep -c '^ssh ' "$fail_trace" | tr -d ' ')" in
	3) ;;
	*) echo "ssh deploy should prepare, stop after first failed copy, and cancel once"; cat "$fail_trace"; exit 1 ;;
esac
case "$(grep -c "cat > '/etc/ssl/fail.key.acmesh-new-" "$fail_trace" | tr -d ' ')" in 1) ;; *) echo "ssh deploy should attempt only the key upload"; cat "$fail_trace"; exit 1;; esac
case "$(grep -c 'acmesh_action=cancel' "$fail_trace" | tr -d ' ')" in 1) ;; *) echo "ssh deploy should cancel the prepared target lock after upload failure"; cat "$fail_trace"; exit 1;; esac
if grep -q "unexpected scp" "$fail_trace"; then
	echo "dropbear deploy should not call scp"
	cat "$fail_trace"
	exit 1
fi

dropbear_bin="$ROOT/tests/.tmp/deploy-dropbear-bin"
rm -rf "$dropbear_bin"
mkdir -p "$dropbear_bin"
cat > "$dropbear_bin/ssh" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "-V" ]; then
	printf 'Dropbear ssh client\n' >&2
	exit 0
fi
printf 'ssh should not run before key preflight\n' >> "$ACMESH_DEPLOY_DROPBEAR_TRACE"
exit 0
EOF
cat > "$dropbear_bin/scp" <<'EOF'
#!/bin/sh
printf 'scp should not run before key preflight\n' >> "$ACMESH_DEPLOY_DROPBEAR_TRACE"
exit 0
EOF
chmod +x "$dropbear_bin/ssh" "$dropbear_bin/scp"
openssh_key="$ROOT/tests/.tmp/openssh-only.key"
cat > "$openssh_key" <<'EOF'
-----BEGIN OPENSSH PRIVATE KEY-----
not-a-real-key
-----END OPENSSH PRIVATE KEY-----
EOF
dropbear_trace="$ROOT/tests/.tmp/deploy-dropbear.trace"
rm -f "$dropbear_trace"
old_path="$PATH"
PATH="$dropbear_bin:$old_path"
export PATH
ACMESH_DEPLOY_DROPBEAR_TRACE="$dropbear_trace"
export ACMESH_DEPLOY_DROPBEAR_TRACE
dropbear_out="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" deploy-run \
	--type ssh \
	--cert-source local-files \
	--domain dropbear.example.com \
	--host 192.0.2.31 \
	--ssh-key "$openssh_key" \
	--source-key-file "$DEPLOY_TMP/source.key" \
	--source-fullchain-file "$DEPLOY_TMP/source.fullchain.pem" \
	--key-file /etc/ssl/dropbear.key \
	--fullchain-file /etc/ssl/dropbear.fullchain.pem)"
PATH="$old_path"
export PATH
case "$dropbear_out" in
	*'"ok":true'*'"taskId"'*) ;;
	*) echo "dropbear key preflight run did not create task"; echo "$dropbear_out"; exit 1 ;;
esac
dropbear_task_id="$(printf '%s' "$dropbear_out" | sed -n 's/.*"taskId":"\([^"]*\)".*/\1/p')"
sleep 1
dropbear_status="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" task-status --task-id "$dropbear_task_id")"
dropbear_log="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" task-log --task-id "$dropbear_task_id")"
case "$dropbear_status" in
	*'"status":"failed"'*) ;;
	*) echo "dropbear OpenSSH key preflight should fail"; echo "$dropbear_status"; echo "$dropbear_log"; exit 1 ;;
esac
case "$dropbear_log" in
	*"OpenSSH private key detected"*"Dropbear dbclient"*"ACMESH_DEPLOY_CONVERTIBLE_SSH_KEY=1"*"Confirm temporary key conversion in LuCI"*) ;;
	*) echo "dropbear key preflight should explain the incompatible key"; echo "$dropbear_log"; exit 1 ;;
esac
case "$dropbear_log" in
	*"not found"*) echo "dropbear key preflight should not depend on missing helper commands"; echo "$dropbear_log"; exit 1 ;;
esac
if [ -e "$dropbear_trace" ]; then
	echo "dropbear key preflight should fail before scp or ssh"
	cat "$dropbear_trace"
	exit 1
fi

missing_convert_key="$ROOT/tests/.tmp/missing-converter-user-private.key"
cp "$openssh_key" "$missing_convert_key"
PATH="$dropbear_bin:$old_path"
ACMESH_DROPBEARCONVERT_BIN="$ROOT/tests/.tmp/does-not-exist/dropbearconvert"
export PATH ACMESH_DROPBEARCONVERT_BIN
missing_convert_out="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" deploy-run \
	--type ssh \
	--cert-source local-files \
	--domain missing-converter.example.com \
	--host 192.0.2.33 \
	--ssh-key "$missing_convert_key" \
	--allow-key-convert \
	--source-key-file "$DEPLOY_TMP/source.key" \
	--source-fullchain-file "$DEPLOY_TMP/source.fullchain.pem" \
	--key-file /etc/ssl/missing-converter.key \
	--fullchain-file /etc/ssl/missing-converter.fullchain.pem)"
PATH="$old_path"
unset ACMESH_DROPBEARCONVERT_BIN
export PATH
case "$missing_convert_out" in
	*'"ok":true'*'"taskId"'*) ;;
	*) echo "missing-converter deploy did not create task"; echo "$missing_convert_out"; exit 1 ;;
esac
missing_convert_task_id="$(printf '%s' "$missing_convert_out" | sed -n 's/.*"taskId":"\([^"]*\)".*/\1/p')"
sleep 1
missing_convert_status="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" task-status --task-id "$missing_convert_task_id")"
missing_convert_log="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" task-log --task-id "$missing_convert_task_id")"
case "$missing_convert_status" in
	*'"status":"failed"'*) ;;
	*) echo "missing-converter deploy should fail"; echo "$missing_convert_status"; echo "$missing_convert_log"; exit 1 ;;
esac
case "$missing_convert_log" in
	*"OpenSSH private key conversion is unavailable on this system."*) ;;
	*) echo "missing-converter task log should contain only a generic conversion error"; echo "$missing_convert_log"; exit 1 ;;
esac
for forbidden in "Suggested conversion" "$missing_convert_key" /tmp/acmesh-console-deploy dropbearconvert; do
	case "$missing_convert_log" in
		*"$forbidden"*) echo "missing-converter task log exposed private conversion data: $forbidden"; echo "$missing_convert_log"; exit 1 ;;
	esac
done

convert_bin="$ROOT/tests/.tmp/deploy-convert-bin"
rm -rf "$convert_bin"
mkdir -p "$convert_bin"
cat > "$convert_bin/ssh" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "-V" ]; then
	printf 'Dropbear ssh client\n' >&2
	exit 0
fi
printf 'ssh %s\n' "$*" >> "$ACMESH_DEPLOY_CONVERT_TRACE"
exit 0
EOF
cat > "$convert_bin/scp" <<'EOF'
#!/bin/sh
printf 'unexpected scp %s\n' "$*" >> "$ACMESH_DEPLOY_CONVERT_TRACE"
exit 1
EOF
cat > "$convert_bin/dropbearconvert" <<'EOF'
#!/bin/sh
printf 'dropbearconvert %s\n' "$*" >> "$ACMESH_DEPLOY_CONVERT_TRACE"
printf 'converted-key\n' > "$4"
exit 0
EOF
chmod +x "$convert_bin/ssh" "$convert_bin/scp" "$convert_bin/dropbearconvert"
convert_key="$ROOT/tests/.tmp/openssh-convert.key"
cat > "$convert_key" <<'EOF'
-----BEGIN OPENSSH PRIVATE KEY-----
not-a-real-key
-----END OPENSSH PRIVATE KEY-----
EOF
convert_trace="$ROOT/tests/.tmp/deploy-convert.trace"
rm -f "$convert_trace"
secure_workspace="$ROOT/tests/.tmp/deploy-workspaces"
rm -rf "$secure_workspace"
mkdir -p "$secure_workspace"
chmod 700 "$secure_workspace"
ACMESH_TASK_WORKSPACE_DIR="$secure_workspace"
export ACMESH_TASK_WORKSPACE_DIR
old_path="$PATH"
PATH="$convert_bin:$old_path"
export PATH
ACMESH_DEPLOY_CONVERT_TRACE="$convert_trace"
export ACMESH_DEPLOY_CONVERT_TRACE
convert_out="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" deploy-run \
	--type ssh \
	--cert-source local-files \
	--domain convert.example.com \
	--host 192.0.2.32 \
	--ssh-key "$convert_key" \
	--allow-key-convert \
	--source-key-file "$DEPLOY_TMP/source.key" \
	--source-fullchain-file "$DEPLOY_TMP/source.fullchain.pem" \
	--key-file /etc/ssl/convert.key \
	--fullchain-file /etc/ssl/convert.fullchain.pem)"
PATH="$old_path"
export PATH
case "$convert_out" in
	*'"ok":true'*'"taskId"'*) ;;
	*) echo "authorized key conversion deploy did not create task"; echo "$convert_out"; exit 1 ;;
esac
convert_task_id="$(printf '%s' "$convert_out" | sed -n 's/.*"taskId":"\([^"]*\)".*/\1/p')"
sleep 1
convert_status="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" task-status --task-id "$convert_task_id")"
convert_log="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" task-log --task-id "$convert_task_id")"
case "$convert_status" in
	*'"status":"success"'*) ;;
	*) echo "authorized key conversion deploy should succeed"; echo "$convert_status"; echo "$convert_log"; exit 1 ;;
esac
case "$convert_log" in
	*"Converted OpenSSH private key to a temporary Dropbear key."*"Removed temporary converted SSH key."*) ;;
	*) echo "authorized key conversion should log conversion and cleanup"; echo "$convert_log"; exit 1 ;;
esac
case "$(grep -c '^dropbearconvert ' "$convert_trace" | tr -d ' ')" in
	1) ;;
	*) echo "authorized key conversion should run dropbearconvert once"; cat "$convert_trace"; exit 1 ;;
esac
converted_output_path="$(awk '/^dropbearconvert / { path=$NF } END { print path }' "$convert_trace")"
[ -n "$converted_output_path" ] || { echo "conversion trace should include the temporary output path"; exit 1; }
[ ! -e "$converted_output_path" ] || { echo "converted SSH key should be removed after deployment"; exit 1; }
if grep -q '^unexpected scp ' "$convert_trace"; then
	echo "dropbear deploy should copy via pinned ssh instead of scp"
	cat "$convert_trace"
	exit 1
fi
case "$(grep -c '^ssh ' "$convert_trace" | tr -d ' ')" in
	5) ;;
	*) echo "dropbear deploy should use prepare, two uploads, one remote transaction, and one state ACK"; cat "$convert_trace"; exit 1 ;;
esac
prepare_trace="$(awk '/^ssh / { count++ } count == 1 { print }' "$convert_trace")"
case "$prepare_trace" in *'acmesh_action=prepare'*) ;; *) echo "first SSH command is not target-lock preparation"; echo "$prepare_trace"; exit 1;; esac
ack_trace="$(awk '/^ssh / { count++ } count == 5 { print }' "$convert_trace")"
case "$ack_trace" in *'acmesh_action=ack'*'.acmesh-transaction.lock'*) ;; *) echo "fifth SSH command is not the target-lock state ACK"; echo "$ack_trace"; exit 1;; esac
case "$ack_trace" in *'.acmesh-backup-'*) echo "transaction ACK must never delete backup paths"; echo "$ack_trace"; exit 1;; esac
if grep -q -- ' -y ' "$convert_trace"; then
	echo "dropbear deploy must not bypass pinned host keys"
	cat "$convert_trace"
	exit 1
fi
for forbidden in "$convert_key" /etc/ssl/convert.key /tmp/acmesh-console-deploy "ssh -y" "cat >" source.fullchain.pem source.key; do
	case "$convert_log" in
		*"$forbidden"*) echo "dropbear deploy task log exposed command data: $forbidden"; echo "$convert_log"; exit 1 ;;
	esac
done
partial_bin="$ROOT/tests/.tmp/deploy-partial-convert-bin"
rm -rf "$partial_bin"
mkdir -p "$partial_bin"
cp "$convert_bin/ssh" "$partial_bin/ssh"
cp "$convert_bin/scp" "$partial_bin/scp"
cat > "$partial_bin/dropbearconvert" <<'EOF'
#!/bin/sh
printf 'partial-private-key\n' > "$4"
printf '%s\n' "$4" > "$ACMESH_DEPLOY_PARTIAL_PATH"
exit 23
EOF
chmod +x "$partial_bin/ssh" "$partial_bin/scp" "$partial_bin/dropbearconvert"
partial_path="$ROOT/tests/.tmp/deploy-partial.path"
rm -f "$partial_path"
. "$ACMESH_LIB_DIR/deploy.sh"

bad_mode='0640
; touch /tmp/acmesh-mode-injected'
rm -f /tmp/acmesh-mode-injected
if acmesh_build_profile_deploy_command local local-files '' /tmp/inject.key /tmp/inject.fullchain '' '' '' "$DEPLOY_TMP/source.key" "$DEPLOY_TMP/source.fullchain.pem" '' '' '' 22 root '' ecc '' root root "$bad_mode" >/dev/null 2>&1; then
	echo "multiline mode injection was accepted"; exit 1
fi
[ ! -e /tmp/acmesh-mode-injected ] || { echo "multiline mode executed"; exit 1; }

managed_meta="$(acmesh_build_profile_deploy_command local managed-acme meta.example /tmp/meta.key /tmp/meta.fullchain '' '' '' '' '' '' '' '' 22 root '' ecc never root root 0640)"
case "$managed_meta" in *"chmod '0640' '/tmp/meta.key' '/tmp/meta.fullchain'"*"chown 'root':'root' '/tmp/meta.key' '/tmp/meta.fullchain'"*) ;; *) echo "managed local metadata is incomplete"; echo "$managed_meta"; exit 1;; esac
local_meta="$(acmesh_build_profile_deploy_command local local-files '' /tmp/local.key /tmp/local.fullchain '' '' '' "$DEPLOY_TMP/source.key" "$DEPLOY_TMP/source.fullchain.pem" '' '' '' 22 root '' ecc never root root 0640)"
case "$local_meta" in *"chmod '0640' '/tmp/local.key' '/tmp/local.fullchain'"*"chown 'root':'root' '/tmp/local.key' '/tmp/local.fullchain'"*) ;; *) echo "ordinary local metadata is incomplete"; echo "$local_meta"; exit 1;; esac
ssh_meta="$(acmesh_build_profile_deploy_command ssh local-files '' /etc/ssl/remote.key /etc/ssl/remote.fullchain '' '' '' "$DEPLOY_TMP/source.key" "$DEPLOY_TMP/source.fullchain.pem" '' '' 192.0.2.20 22 root /root/.ssh/id ecc never root ssl-cert 0640)"
case "$ssh_meta" in *"chmod 0640"*remote.fullchain*"chown"*root*remote.fullchain*"chgrp"*ssl-cert*remote.fullchain*"chmod 0640"*remote.key*"chown"*root*remote.key*"chgrp"*ssl-cert*remote.key*) ;; *) echo "SSH key/fullchain metadata is incomplete"; echo "$ssh_meta"; exit 1;; esac
preserve_meta="$(acmesh_build_profile_deploy_command local local-files '' /tmp/preserve.key /tmp/preserve.fullchain '' '' '' "$DEPLOY_TMP/source.key" "$DEPLOY_TMP/source.fullchain.pem" '' '' '' 22 root '' ecc never root ssl-cert 0640 true)"
case "$preserve_meta" in *"preserve existing owner/group/mode"*) ;; *) echo "preserve metadata preview is incomplete"; echo "$preserve_meta"; exit 1;; esac

if [ "$(id -u)" = 0 ]; then
	managed_exec_home="$ROOT/tests/.tmp/managed-meta-home"
	managed_exec_target="$ROOT/tests/.tmp/managed-meta-target"
	rm -rf "$managed_exec_home" "$managed_exec_target"
	mkdir -p "$managed_exec_home/meta.example_ecc" "$managed_exec_target"
	printf 'managed-key\n' > "$managed_exec_home/meta.example_ecc/meta.example.key"
	printf 'managed-chain\n' > "$managed_exec_home/meta.example_ecc/fullchain.cer"
	cat > "$managed_exec_home/acme.sh" <<'EOF'
#!/bin/sh
key= chain=
while [ "$#" -gt 0 ]; do case "$1" in --key-file) key="$2"; shift 2;; --fullchain-file) chain="$2"; shift 2;; *) shift;; esac; done
printf 'managed-key\n' > "$key"
printf 'managed-chain\n' > "$chain"
EOF
	chmod +x "$managed_exec_home/acme.sh"
	ACMESH_ACME_HOME="$managed_exec_home" ACMESH_CURRENT_TASK_ID=20260101010108-784 \
		acmesh_execute_profile_deploy local managed-acme meta.example "$managed_exec_target/key.pem" "$managed_exec_target/fullchain.pem" '' '' '' '' '' '' '' '' 22 root '' ecc '' root root 0640 >/dev/null
	for installed in "$managed_exec_target/key.pem" "$managed_exec_target/fullchain.pem"; do
		set -- $(LC_ALL=C ls -ld "$installed")
		case "$installed" in
			*/key.pem) expected_mode=-rw-r----- ;;
			*) expected_mode=-rw-r----- ;;
		esac
		[ "$1" = "$expected_mode" ] && [ "$3:$4" = root:root ] || { echo "managed local metadata was not applied to $installed"; exit 1; }
	done
	preserve_exec_target="$ROOT/tests/.tmp/preserve-meta-target"
	rm -rf "$preserve_exec_target"
	mkdir -p "$preserve_exec_target"
	printf 'old-key\n' > "$preserve_exec_target/key.pem"
	printf 'old-chain\n' > "$preserve_exec_target/fullchain.pem"
	chmod 0640 "$preserve_exec_target/key.pem"
	chmod 0660 "$preserve_exec_target/fullchain.pem"
	ACMESH_CURRENT_TASK_ID=20260101010109-785 \
		acmesh_execute_profile_deploy local paste-pem preserve.example.com \
		"$preserve_exec_target/key.pem" "$preserve_exec_target/fullchain.pem" '' '' '' \
		'' '' 'preserve-private-key' 'preserve-fullchain' '' 22 root '' ecc '' '' '' '' true >/dev/null
	for installed in "$preserve_exec_target/key.pem" "$preserve_exec_target/fullchain.pem"; do
		set -- $(LC_ALL=C ls -ld "$installed")
		case "$installed" in
			*/key.pem) expected_mode=-rw-r----- ;;
			*) expected_mode=-rw-rw---- ;;
		esac
		[ "$1" = "$expected_mode" ] && [ "$3:$4" = root:root ] || { echo "preserved local metadata was not applied to $installed"; exit 1; }
	done
	preserve_missing_target="$ROOT/tests/.tmp/preserve-meta-missing-target"
	rm -rf "$preserve_missing_target"
	mkdir -p "$preserve_missing_target"
	ACMESH_CURRENT_TASK_ID=20260101010110-786 \
		acmesh_execute_profile_deploy local paste-pem preserve-missing.example.com \
		"$preserve_missing_target/key.pem" "$preserve_missing_target/fullchain.pem" '' '' '' \
		'' '' 'missing-private-key' 'missing-fullchain' '' 22 root '' ecc '' '' '' '' true >/dev/null
	set -- $(LC_ALL=C ls -ld "$preserve_missing_target/key.pem")
	[ "$1" = -rw------- ] || { echo "missing preserved key should use the default 0600 mode"; exit 1; }
	set -- $(LC_ALL=C ls -ld "$preserve_missing_target/fullchain.pem")
	[ "$1" = -rw-r--r-- ] || { echo "missing preserved fullchain should use the default 0644 mode"; exit 1; }
fi

same_lock_a="$(acmesh_deploy_target_lock_path local paste-pem shared.example.com /etc/ssl/shared.key /etc/ssl/shared.fullchain.pem '' '' '' '' '' '' '' '' 22 root '' ecc)"
same_lock_b="$(acmesh_deploy_target_lock_path local paste-pem another-domain.example /etc/ssl/shared.key /etc/ssl/shared.fullchain.pem '' '' '' '' '' '' '' '' 22 root '' ecc)"
[ "$same_lock_a" = "$same_lock_b" ] || { echo "deployments targeting the same certificate pair should share a lock"; exit 1; }
different_lock="$(acmesh_deploy_target_lock_path local paste-pem shared.example.com /etc/ssl/other.key /etc/ssl/other.fullchain.pem '' '' '' '' '' '' '' '' 22 root '' ecc)"
[ "$same_lock_a" != "$different_lock" ] || { echo "different deployment targets should not share the same lock identity"; exit 1; }

prepare_fail_workspace="$ROOT/tests/.tmp/paste-prepare-hostile"
prepare_fail_target="$ROOT/tests/.tmp/paste-prepare-target"
rm -rf "$prepare_fail_workspace" "$prepare_fail_target"
mkdir -p "$prepare_fail_target"
ln -s "$prepare_fail_target" "$prepare_fail_workspace"
if [ -L "$prepare_fail_workspace" ]; then
	ACMESH_TASK_WORKSPACE_DIR="$prepare_fail_workspace"
	ACMESH_CURRENT_TASK_ID=20260101010105-781
	export ACMESH_TASK_WORKSPACE_DIR ACMESH_CURRENT_TASK_ID
	if acmesh_execute_profile_deploy local paste-pem prepare-fail.example.com \
		"$prepare_fail_target/should-not-exist.key" "$prepare_fail_target/should-not-exist.fullchain" '' '' '' \
		'' '' 'prepare-fail-key' 'prepare-fail-fullchain' '' 22 root '' ecc >/dev/null 2>&1; then
		echo "unsafe PEM workspace should fail deployment immediately"
		exit 1
	fi
	[ ! -e "$prepare_fail_target/should-not-exist.key" ] || { echo "PEM preparation failure should not continue to target writes"; exit 1; }
	[ ! -e "$prepare_fail_target/should-not-exist.fullchain" ] || { echo "PEM preparation failure should not continue to target writes"; exit 1; }
fi
ACMESH_TASK_WORKSPACE_DIR="$secure_workspace"
unset ACMESH_CURRENT_TASK_ID
export ACMESH_TASK_WORKSPACE_DIR

paste_target="$ROOT/tests/.tmp/paste-target"
rm -rf "$paste_target"
mkdir -p "$paste_target"
(
	ACMESH_CURRENT_TASK_ID=20260101010103-779
	export ACMESH_CURRENT_TASK_ID
	acmesh_execute_profile_deploy local paste-pem shared.example.com \
		"$paste_target/first.key" "$paste_target/first.fullchain.pem" '' '' '' \
		'' '' 'first-private-key' 'first-fullchain' '' 22 root '' ecc >/dev/null
) &
paste_first_pid=$!
(
	ACMESH_CURRENT_TASK_ID=20260101010104-780
	export ACMESH_CURRENT_TASK_ID
	acmesh_execute_profile_deploy local paste-pem shared.example.com \
		"$paste_target/second.key" "$paste_target/second.fullchain.pem" '' '' '' \
		'' '' 'second-private-key' 'second-fullchain' '' 22 root '' ecc >/dev/null
) &
paste_second_pid=$!
wait "$paste_first_pid"
wait "$paste_second_pid"
grep -q '^first-private-key$' "$paste_target/first.key" || { echo "first concurrent PEM deployment used the wrong private key"; exit 1; }
grep -q '^first-fullchain$' "$paste_target/first.fullchain.pem" || { echo "first concurrent PEM deployment used the wrong fullchain"; exit 1; }
grep -q '^second-private-key$' "$paste_target/second.key" || { echo "second concurrent PEM deployment used the wrong private key"; exit 1; }
grep -q '^second-fullchain$' "$paste_target/second.fullchain.pem" || { echo "second concurrent PEM deployment used the wrong fullchain"; exit 1; }
if find "$secure_workspace/20260101010103-779" "$secure_workspace/20260101010104-780" -type f -print -quit 2>/dev/null | grep . >/dev/null; then
	echo "paste-pem task workspace should not retain temporary certificate material"
	exit 1
fi

PATH="$partial_bin:$old_path"
ACMESH_DEPLOY_PARTIAL_PATH="$partial_path"
ACMESH_CURRENT_TASK_ID=20260101010101-777
ACMESH_DEPLOY_ALLOW_KEY_CONVERT=1
export PATH ACMESH_DEPLOY_PARTIAL_PATH ACMESH_CURRENT_TASK_ID ACMESH_DEPLOY_ALLOW_KEY_CONVERT
partial_error="$ROOT/tests/.tmp/deploy-partial.error"
if acmesh_execute_profile_deploy ssh local-files partial.example.com \
	/etc/ssl/partial.key /etc/ssl/partial.fullchain.pem '' '' '' \
	"$DEPLOY_TMP/source.key" "$DEPLOY_TMP/source.fullchain.pem" '' '' \
	192.0.2.40 22 root "$convert_key" ecc >/dev/null 2>"$partial_error"; then
	echo "converter partial-write failure should fail deployment"
	exit 1
fi
PATH="$old_path"
export PATH
[ -s "$partial_path" ] || { echo "partial converter should report its output path"; cat "$partial_error"; exit 1; }
partial_output="$(cat "$partial_path")"
[ ! -e "$partial_output" ] || { echo "partial converted key should be removed after converter failure"; exit 1; }
case "$partial_output" in
	"$secure_workspace/20260101010101-777/"*) ;;
	*) echo "converted key should use the private task workspace"; echo "$partial_output"; exit 1 ;;
esac
case "$partial_output" in
	*.XXXXXX|*openssh-convert*) echo "converted key path should be unpredictable"; exit 1 ;;
esac

hostile_workspace="$ROOT/tests/.tmp/hostile-deploy-workspace"
hostile_target="$ROOT/tests/.tmp/hostile-target"
rm -rf "$hostile_workspace" "$hostile_target"
mkdir -p "$hostile_target"
ln -s "$hostile_target" "$hostile_workspace"
if [ -L "$hostile_workspace" ]; then
	ACMESH_TASK_WORKSPACE_DIR="$hostile_workspace"
	ACMESH_CURRENT_TASK_ID=20260101010102-778
	PATH="$convert_bin:$old_path"
	export ACMESH_TASK_WORKSPACE_DIR ACMESH_CURRENT_TASK_ID PATH ACMESH_DEPLOY_ALLOW_KEY_CONVERT
	if acmesh_execute_profile_deploy ssh local-files hostile.example.com \
		/etc/ssl/hostile.key /etc/ssl/hostile.fullchain.pem '' '' '' \
		"$DEPLOY_TMP/source.key" "$DEPLOY_TMP/source.fullchain.pem" '' '' \
		192.0.2.41 22 root "$convert_key" ecc >/dev/null 2>&1; then
		echo "symlinked deployment workspace should be rejected"
		exit 1
	fi
	[ -z "$(find "$hostile_target" -type f -print -quit 2>/dev/null)" ] || { echo "hostile workspace received converted key material"; exit 1; }
else
	printf '%s\n' "test_deploy_install: SKIP symlink attack assertion (host lacks POSIX directory symlinks)" >&2
fi
PATH="$old_path"
ACMESH_TASK_WORKSPACE_DIR="$secure_workspace"
unset ACMESH_CURRENT_TASK_ID
unset ACMESH_DEPLOY_ALLOW_KEY_CONVERT
export PATH ACMESH_TASK_WORKSPACE_DIR

echo "test_deploy_install: ok"
