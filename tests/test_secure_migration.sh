#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
command -v jsonfilter >/dev/null 2>&1 || { echo "test_secure_migration: SKIP (jsonfilter unavailable)"; exit 0; }
TMP="${TMPDIR:-/tmp}/acmesh-migration.$$"; trap 'rm -rf "$TMP"' 0 HUP INT TERM
mkdir -p "$TMP/etc/acme/example.org_ecc" "$TMP/etc/acmesh-console/ssh" "$TMP/etc/ssl" "$TMP/etc/config" "$TMP/state" "$TMP/challenges" "$TMP/pending" "$TMP/tasks"
chmod 700 "$TMP" "$TMP/etc" "$TMP/etc/acme" "$TMP/etc/acmesh-console" "$TMP/etc/ssl" "$TMP/state" "$TMP/challenges" "$TMP/pending"
. "$ROOT/tests/lib/host_flock.sh"; acmesh_test_install_flock_shim "$TMP/flock"; acmesh_test_install_private_ls_shim "$TMP/private-ls" "$TMP"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"
export ACMESH_CONSOLE_CONFIG="$TMP/etc/acmesh-console/config.json" ACMESH_CONSOLE_UCI_CONFIG="$TMP/etc/config/acmesh-console"
export ACMESH_MIGRATION_ACME_ROOT="$TMP/etc/acme" ACMESH_MIGRATION_CONSOLE_ROOT="$TMP/etc/acmesh-console" ACMESH_MIGRATION_SSL_ROOT="$TMP/etc/ssl" ACMESH_MIGRATION_UCI_CONFIG="$TMP/etc/config/acmesh-console"
export ACMESH_PENDING_IMPORT_DIR="$TMP/pending" ACMESH_CONFIG_LOCK_FILE="$TMP/etc/acmesh-console/config.lock"
export ACMESH_AUTH_STATE_DIR="$TMP/state" ACMESH_AUTH_INSTANCE_FILE="$TMP/state/instance-id" ACMESH_AUTH_LEDGER_FILE="$TMP/state/authorizations.json" ACMESH_AUTH_LOCK_FILE="$TMP/state/authorization.lock" ACMESH_AUTH_CHALLENGE_DIR="$TMP/challenges"
export ACMESH_TASK_STATE_DIR="$TMP/tasks/state" ACMESH_TASK_LOG_DIR="$TMP/tasks/log" ACMESH_RUNTIME_DIR="$TMP/runtime"
CTL="$ROOT/root/usr/libexec/acmesh-console/acmeshctl"

cat > "$ACMESH_CONSOLE_CONFIG" <<'JSON'
{"schemaVersion":2,"global":{"defaultAccountEmail":"ops@example.org","coreTag":"v3.1.4","acmeHome":"/etc/acme"},"accountProfiles":[],"issueProfiles":[],"deployProfiles":[{"id":"local","name":"Local","type":"local","certSource":"managed-acme","domain":"example.org","keyType":"ec256","keyFile":"/etc/ssl/example.key","fullchainFile":"/etc/ssl/example.fullchain.pem","certFile":"","caFile":"","reloadcmd":"","owner":"","group":"","mode":""}]}
JSON
printf 'uci-home=/etc/acme\n' > "$ACMESH_CONSOLE_UCI_CONFIG"
printf 'account-state\n' > "$TMP/etc/acme/account.conf"
printf 'private-key\n' > "$TMP/etc/ssl/example.key"
printf 'fullchain\n' > "$TMP/etc/ssl/example.fullchain.pem"
printf 'unrelated\n' > "$TMP/etc/ssl/unrelated.pem"
printf 'do-not-migrate\n' > "$TMP/etc/acmesh-console/authorizations.json"
printf 'known-host\n' > "$TMP/etc/acmesh-console/ssh/known_hosts"
chmod 600 "$ACMESH_CONSOLE_CONFIG" "$TMP/etc/acme/account.conf" "$TMP/etc/ssl/example.key" "$TMP/etc/ssl/example.fullchain.pem"

printf '%s\n' '{"scope":"migration-archive"}' > "$TMP/export.json"
set +e; challenge="$(sh "$CTL" secret-export --request-file "$TMP/export.json")"; rc=$?; set -e
[ "$rc" = 3 ]
challenge_id="$(printf '%s' "$challenge" | jsonfilter -e '@.challengeId')"
printf '{"challengeId":"%s","decision":"once"}\n' "$challenge_id" > "$TMP/execute.json"
exported="$(sh "$CTL" authorization-execute --request-file "$TMP/execute.json")"
printf '%s' "$exported" | grep -F '"format":"acmesh-console-backup"' >/dev/null
printf '%s' "$exported" | jsonfilter -e '@.archiveBase64' | base64 -d > "$TMP/no-certs.tar.gz"
! tar -tzf "$TMP/no-certs.tar.gz" | grep -F 'etc/ssl/' >/dev/null
tar -tzf "$TMP/no-certs.tar.gz" | grep -F 'etc/acme/account.conf' >/dev/null
! tar -tzf "$TMP/no-certs.tar.gz" | grep -F 'authorizations.json' >/dev/null
! tar -tzf "$TMP/no-certs.tar.gz" | grep -F 'known_hosts' >/dev/null

printf '%s\n' '{"scope":"migration-archive-with-deployment-certs"}' > "$TMP/export-certs.json"
set +e; challenge="$(sh "$CTL" secret-export --request-file "$TMP/export-certs.json")"; rc=$?; set -e
[ "$rc" = 3 ]
challenge_id="$(printf '%s' "$challenge" | jsonfilter -e '@.challengeId')"
printf '{"challengeId":"%s","decision":"once"}\n' "$challenge_id" > "$TMP/execute.json"
exported="$(sh "$CTL" authorization-execute --request-file "$TMP/execute.json")"
printf '%s' "$exported" | jsonfilter -e '@.archiveBase64' | base64 -d > "$TMP/with-certs.tar.gz"
tar -tzf "$TMP/with-certs.tar.gz" | grep -F 'etc/ssl/example.key' >/dev/null
tar -tzf "$TMP/with-certs.tar.gz" | grep -F 'etc/ssl/example.fullchain.pem' >/dev/null
! tar -tzf "$TMP/with-certs.tar.gz" | grep -F 'etc/ssl/unrelated.pem' >/dev/null

archive_b64="$(base64 "$TMP/with-certs.tar.gz" | tr -d '\n')"
printf '{"archiveBase64":"%s"}\n' "$archive_b64" > "$TMP/import.json"
preview="$(sh "$CTL" import-preview --request-file "$TMP/import.json")"
preview_id="$(printf '%s' "$preview" | jsonfilter -e '@.previewId')"
[ -f "$TMP/pending/$preview_id.tar.gz" ]
printf '%s\n' '{"schemaVersion":2,"global":{"defaultAccountEmail":"changed@example.org","coreTag":"v3.1.4","acmeHome":"/etc/acme"},"accountProfiles":[],"issueProfiles":[],"deployProfiles":[]}' > "$ACMESH_CONSOLE_CONFIG"
printf 'changed-key\n' > "$TMP/etc/ssl/example.key"
printf '{"previewId":"%s"}\n' "$preview_id" > "$TMP/apply.json"
set +e; challenge="$(sh "$CTL" import-apply --request-file "$TMP/apply.json")"; rc=$?; set -e
[ "$rc" = 3 ]
challenge_id="$(printf '%s' "$challenge" | jsonfilter -e '@.challengeId')"
printf '{"challengeId":"%s","decision":"once"}\n' "$challenge_id" > "$TMP/execute.json"
applied="$(sh "$CTL" authorization-execute --request-file "$TMP/execute.json")"
printf '%s' "$applied" | grep -F '"applied":true' >/dev/null
grep -F 'ops@example.org' "$ACMESH_CONSOLE_CONFIG" >/dev/null
grep -F 'private-key' "$TMP/etc/ssl/example.key" >/dev/null
[ ! -e "$TMP/pending/$preview_id.tar.gz" ]

printf '{"archiveBase64":"%s"}\n' "$archive_b64" > "$TMP/failing-import.json"
failed_preview="$(sh "$CTL" import-preview --request-file "$TMP/failing-import.json")"
failed_preview_id="$(printf '%s' "$failed_preview" | jsonfilter -e '@.previewId')"
rm "$TMP/etc/ssl/example.key"
mkdir "$TMP/etc/ssl/example.key"
printf '{"previewId":"%s"}\n' "$failed_preview_id" > "$TMP/failing-apply.json"
set +e; failed_challenge="$(sh "$CTL" import-apply --request-file "$TMP/failing-apply.json")"; failed_apply_rc=$?; set -e
[ "$failed_apply_rc" = 3 ]
failed_challenge_id="$(printf '%s' "$failed_challenge" | jsonfilter -e '@.challengeId')"
printf '{"challengeId":"%s","decision":"once"}\n' "$failed_challenge_id" > "$TMP/failing-execute.json"
set +e; failed_output="$(sh "$CTL" authorization-execute --request-file "$TMP/failing-execute.json")"; failed_execute_rc=$?; set -e
[ "$failed_execute_rc" = 1 ]
case "$failed_output" in
	*'"ok":false'*'"error":"migration restore failed"'*) ;;
	*) echo "failed migration restore must return structured backend error"; echo "$failed_output"; exit 1 ;;
esac

printf '%s\n' '{"scope":"config-with-secrets"}' > "$TMP/legacy-export.json"
if sh "$CTL" secret-export --request-file "$TMP/legacy-export.json" >/dev/null 2>&1; then
	echo "legacy JSON export scope was accepted"
	exit 1
fi
echo "test_secure_migration: ok"
