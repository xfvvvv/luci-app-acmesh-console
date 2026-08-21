#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
command -v jsonfilter >/dev/null 2>&1 || { echo "test_operation_admission: SKIP (jsonfilter unavailable)"; exit 0; }
TMP="${TMPDIR:-/tmp}/acmesh-operation.$$"; trap 'rm -rf "$TMP"' 0 HUP INT TERM
mkdir -p "$TMP/state" "$TMP/challenges" "$TMP/tasks" "$TMP/config" "$TMP/acme/renew.example_ecc"; chmod 700 "$TMP" "$TMP/state" "$TMP/challenges" "$TMP/tasks" "$TMP/config" "$TMP/acme" "$TMP/acme/renew.example_ecc"
. "$ROOT/tests/lib/host_flock.sh"; acmesh_test_install_flock_shim "$TMP/flock"; acmesh_test_install_private_ls_shim "$TMP/private-ls" "$TMP"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib" ACMESH_AUTH_STATE_DIR="$TMP/state" ACMESH_AUTH_INSTANCE_FILE="$TMP/state/instance-id"
export ACMESH_AUTH_LEDGER_FILE="$TMP/state/authorizations.json" ACMESH_AUTH_LOCK_FILE="$TMP/state/authorization.lock" ACMESH_AUTH_CHALLENGE_DIR="$TMP/challenges"
export ACMESH_CONSOLE_CONFIG="$TMP/config/config.json" ACMESH_CONSOLE_UCI_CONFIG="$TMP/missing-uci" ACMESH_ACME_HOME="$TMP/acme"
. "$ACMESH_LIB_DIR/cert.sh"
. "$ACMESH_LIB_DIR/task.sh"
. "$ACMESH_LIB_DIR/command.sh"
. "$ACMESH_LIB_DIR/dns.sh"
. "$ACMESH_LIB_DIR/provider.sh"
. "$ACMESH_LIB_DIR/deploy.sh"
. "$ACMESH_LIB_DIR/ssh.sh"
. "$ACMESH_LIB_DIR/config.sh"
. "$ACMESH_LIB_DIR/request_payload.sh"
. "$ACMESH_LIB_DIR/operation.sh"

# Exercise every real Task 9 operation through its real recompute/admission
# router.  No authorization means challenge-only and no task creation.
ssh-keygen -q -t ed25519 -N '' -f "$TMP/id_ed25519"
cat > "$ACMESH_CONSOLE_CONFIG" <<JSON
{"schemaVersion":2,"global":{"defaultAccountEmail":"ops@example.org","coreTag":"v3.1.4","acmeHome":"$TMP/acme"},"accountProfiles":[{"id":"acc","name":"LE","ca":"letsencrypt","accountEmail":"ops@example.org"}],"issueProfiles":[{"id":"issue-real","name":"Issue","domain":"issue.example","accountProfileId":"acc","deployProfileId":"deploy-local","keyType":"ec256","validationMethod":"dns","testModeOverride":"force-real-mode","dnsApi":"dns_cf","credentialMode":"token","credentials":{"CF_Token":"secret"}},{"id":"renew-link","name":"Renew link","domain":"renew.example","accountProfileId":"acc","deployProfileId":"deploy-renew","keyType":"ec256","validationMethod":"standalone","testModeOverride":"force-real-mode"}],"deployProfiles":[{"id":"deploy-local","name":"Local","type":"local","certSource":"paste-pem","keyPem":"private","fullchainPem":"certificate","keyFile":"$TMP/out.key","fullchainFile":"$TMP/out.pem","owner":"root","group":"root","mode":"0600"},{"id":"deploy-renew","name":"Renew","type":"local","certSource":"managed-acme","domain":"renew.example","keyType":"ec256","keyFile":"$TMP/renew.key","fullchainFile":"$TMP/renew.pem","owner":"root","group":"root","mode":"0600"},{"id":"deploy-ssh","name":"SSH","type":"ssh","certSource":"local-files","sourceKeyFile":"$TMP/source.key","sourceFullchainFile":"$TMP/source.pem","host":"192.0.2.1","user":"root","port":"22","sshKey":"$TMP/id_ed25519","keyFile":"/etc/ssl/key.pem","fullchainFile":"/etc/ssl/fullchain.pem","sudoMode":"never","owner":"root","group":"root","mode":"0600"}]}
JSON
chmod 600 "$ACMESH_CONSOLE_CONFIG"; printf private > "$TMP/source.key"; printf certificate > "$TMP/source.pem"
# Real core operations use saved configuration as their only parameter source
# and reject effect-bearing request/CLI overrides instead of silently ignoring them.
set +e; core_mismatch="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" core-install --home "$TMP/other-acme" --email ops@example.org 2>/dev/null)"; core_mismatch_rc=$?; set -e
[ "$core_mismatch_rc" = 2 ]; printf '%s' "$core_mismatch" | grep -F 'must match saved configuration' >/dev/null
set +e; core_mismatch="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" core-upgrade --home "$TMP/other-acme" 2>/dev/null)"; core_mismatch_rc=$?; set -e
[ "$core_mismatch_rc" = 2 ]; printf '%s' "$core_mismatch" | grep -F 'must match saved configuration' >/dev/null
# Issue credential values remain secret; mode and key references are the
# authorization identity required by the design.
acmesh_operation_recompute issue issueProfile issue-real "$TMP/issue-credential-1" "$TMP/issue-credential-summary-1"
issue_credential_fp="$(acmesh_auth_fingerprint "$TMP/issue-credential-1")"
[ "$(acmesh_auth_snapshot_value "$TMP/issue-credential-1" subjectId)" = issue-real ]
[ "$(jsonfilter -i "$TMP/issue-credential-summary-1" -e '@.ca')" = letsencrypt ]
[ "$(jsonfilter -i "$TMP/issue-credential-summary-1" -e '@.domains[0]')" = issue.example ]
[ "$(jsonfilter -i "$TMP/issue-credential-summary-1" -e '@.keyType')" = ec256 ]
[ "$(jsonfilter -i "$TMP/issue-credential-summary-1" -e '@.deployProfileId')" = deploy-local ]
[ "$(jsonfilter -i "$ACMESH_OPERATION_RESOLVED_FILE" -e '@.id')" = issue-real ]
sed -i 's/"credentialMode":"token","credentials":{"CF_Token":"secret"}/"credentialMode":"global-key","credentials":{"CF_Email":"ops@example.org","CF_Key":"replacement"}/' "$ACMESH_CONSOLE_CONFIG"
acmesh_operation_recompute issue issueProfile issue-real "$TMP/issue-credential-2" "$TMP/issue-credential-summary-2"
[ "$issue_credential_fp" != "$(acmesh_auth_fingerprint "$TMP/issue-credential-2")" ]
! grep -F 'replacement' "$TMP/issue-credential-2" >/dev/null
cat > "$TMP/acme/renew.example_ecc/renew.example.conf" <<'CONF'
Le_Domain='renew.example'
Le_Alt='www.renew.example'
Le_Keylength='ec-256'
Le_Webroot='dns_cf'
Le_API='letsencrypt'
CONF
chmod 600 "$TMP/acme/renew.example_ecc/renew.example.conf"
matrix_start() {
	set +e; matrix_out="$(acmesh_operation_start "$1" "$2" "$3" '')"; matrix_rc=$?; set -e
	[ "$matrix_rc" = 3 ] || { echo "$1 did not require authorization: $matrix_rc $matrix_out"; exit 1; }
	printf '%s' "$matrix_out" | grep -F '"authorizationRequired":true' >/dev/null
}
matrix_start issue issueProfile issue-real
[ "$(printf '%s' "$matrix_out" | jsonfilter -e '@.riskSummary.ca')" = letsencrypt ]
[ "$(printf '%s' "$matrix_out" | jsonfilter -e '@.riskSummary.domains[0]')" = issue.example ]
[ "$(printf '%s' "$matrix_out" | jsonfilter -e '@.riskSummary.keyType')" = ec256 ]
matrix_start renew certificate ecc.renew.example
[ "$(printf '%s' "$matrix_out" | jsonfilter -e '@.riskSummary.deployProfileId')" = deploy-renew ]
matrix_start deploy-run deployProfile deploy-local
[ "$(printf '%s' "$matrix_out" | jsonfilter -e '@.riskSummary.keyFile')" = "$TMP/out.key" ]
matrix_start core-install global core
matrix_start core-upgrade global core
matrix_start ssh-key-convert sshKey deploy-ssh
[ ! -e "$TMP/tasks/state" ] && [ ! -e "$TMP/tasks/log" ]

# Preparation probes may return a structured prerequisite response while
# failing with a non-zero status.  The operation boundary must forward that
# response as the sole JSON document instead of appending a generic failure.
acmesh_ssh_verify_pinned_host() {
	printf '%s\n' '{"ok":false,"error":"hostKeyRequired","algorithm":"ssh-ed25519","fingerprint":"SHA256:fixture"}'
	return 4
}
set +e; host_key_response="$(acmesh_operation_start deploy-run deployProfile deploy-ssh '')"; host_key_rc=$?; set -e
[ "$host_key_rc" = 4 ]
[ "$(printf '%s' "$host_key_response" | jsonfilter -e '@.error')" = hostKeyRequired ]
[ "$(printf '%s' "$host_key_response" | jsonfilter -e '@.fingerprint')" = SHA256:fixture ]
[ "$(printf '%s\n' "$host_key_response" | awk 'NF { count++ } END { print count + 0 }')" = 1 ]
unset -f acmesh_ssh_verify_pinned_host

# Renew performs a final identity check while holding its certificate lock.
# A business-intent change after authorization must fail before acme.sh runs.
mkdir -p "$TMP/renew-final"; chmod 700 "$TMP/renew-final"
acmesh_operation_recompute renew certificate ecc.renew.example "$TMP/renew-authorized.snapshot" "$TMP/renew-authorized.summary"
renew_authorized_fp="$(acmesh_auth_fingerprint "$TMP/renew-authorized.snapshot")"
[ "$(acmesh_auth_snapshot_value "$TMP/renew-authorized.snapshot" subjectId)" = ecc.renew.example ]
[ "$(jsonfilter -i "$TMP/renew-authorized.summary" -e '@.domains[0]')" = renew.example ]
[ "$(jsonfilter -i "$TMP/renew-authorized.summary" -e '@.deployProfileId')" = deploy-renew ]
sed -i "s/Le_Webroot='dns_cf'/Le_Webroot='dns_route53'/" "$TMP/acme/renew.example_ecc/renew.example.conf"
acmesh_execute_renew() { printf executed > "$TMP/renew-executed"; }
set +e; acmesh_operation_run_renew_locked ecc.renew.example "$renew_authorized_fp" "$TMP/renew-final" >/dev/null 2>&1; renew_changed_rc=$?; set -e
[ "$renew_changed_rc" != 0 ] && [ ! -e "$TMP/renew-executed" ]
rm -rf "$TMP/state" "$TMP/challenges"; mkdir -p "$TMP/state" "$TMP/challenges"; chmod 700 "$TMP/state" "$TMP/challenges"

acmesh_operation_recompute() { op="$1" type="$2" id="$3"; ACMESH_AUTH_ACCOUNT_ID=a ACMESH_AUTH_CA=letsencrypt ACMESH_AUTH_PRIMARY_DOMAIN="$id" ACMESH_AUTH_DOMAINS="$id" ACMESH_AUTH_KEY_TYPE=ec256 ACMESH_AUTH_VALIDATION=renew ACMESH_AUTH_DNS_SLEEP=0 ACMESH_AUTH_TEST_MODE=false acmesh_auth_snapshot "$op" "$type" "$id" "$4"; acmesh_auth_summary "$4" "$5"; }
acmesh_operation_admit() { printf '%s:%s\n' "$1" "$4" >> "$TMP/admitted"; ACMESH_OPERATION_TASK_ID="task-$(wc -l < "$TMP/admitted" | tr -d ' ')"; export ACMESH_OPERATION_TASK_ID; }
set +e; first="$(acmesh_operation_start renew certificate example.com '')"; rc=$?; set -e
[ "$rc" = 3 ]; id="$(printf '%s' "$first" | jsonfilter -e '@.challengeId')"; [ ! -e "$TMP/admitted" ]
printf '{"challengeId":"%s","decision":"once"}\n' "$id" > "$TMP/execute.json"
acmesh_operation_execute_challenge "$TMP/execute.json" | grep -F '"taskId":"task-1"' >/dev/null
set +e; second="$(acmesh_operation_start renew certificate example.com '')"; rc=$?; set -e; [ "$rc" = 3 ]
id="$(printf '%s' "$second" | jsonfilter -e '@.challengeId')"; printf '{"challengeId":"%s","decision":"remember"}\n' "$id" > "$TMP/execute.json"
acmesh_operation_execute_challenge "$TMP/execute.json" | grep -F '"taskId":"task-2"' >/dev/null
acmesh_operation_start renew certificate example.com '' | grep -F '"taskId":"task-3"' >/dev/null
set +e; acmesh_operation_start arbitrary certificate example.com '' >/dev/null 2>&1; bad=$?; set -e; [ "$bad" = 2 ]
# A remembered-only caller (the automatic deploy hook) fails closed and never
# creates a challenge if authorization disappears between its check and start.
challenge_count="$(find "$TMP/challenges" -name '*.json' | wc -l | tr -d ' ')"
set +e; ACMESH_OPERATION_REQUIRE_REMEMBERED=1 acmesh_operation_start renew certificate changed.example '' >/dev/null; hook_rc=$?; set -e
[ "$hook_rc" = 4 ]; [ "$(find "$TMP/challenges" -name '*.json' | wc -l | tr -d ' ')" = "$challenge_count" ]

# A conversion Run-once grant is consumed exactly once under admission lock,
# even when two deploy admissions race for it.
grant="$(acmesh_operation_conversion_grant_path deploy-once)"; printf 'sha256:%064d\n%s\n' 0 $(( $(date +%s) + 300 )) > "$grant"; chmod 600 "$grant"
ACMESH_OPERATION_USES_ONCE_CONVERSION=1
ACMESH_OPERATION_CONVERSION_FINGERPRINT="sha256:$(printf '%064d' 0)"
export ACMESH_OPERATION_USES_ONCE_CONVERSION ACMESH_OPERATION_CONVERSION_FINGERPRINT
( set +e; acmesh_auth_lock_run acmesh_operation_consume_conversion_grant deploy-once; printf '%s\n' "$?" > "$TMP/consume-1" ) & p1=$!
( set +e; acmesh_auth_lock_run acmesh_operation_consume_conversion_grant deploy-once; printf '%s\n' "$?" > "$TMP/consume-2" ) & p2=$!
wait "$p1" "$p2"
[ "$(awk '$1 == 0 { n++ } END { print n + 0 }' "$TMP/consume-1" "$TMP/consume-2")" = 1 ]
[ ! -e "$grant" ]
if acmesh_operation_consume_conversion_grant deploy-once; then echo "conversion once grant was reused"; exit 1; fi
export ACMESH_TASK_STATE_DIR="$TMP/test-tasks" ACMESH_TASK_LOG_DIR="$TMP/test-logs"
preview="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" issue --domain test.example --test-mode)"; case "$preview" in *'"taskId"'*) exit 1;; esac
[ ! -e "$ACMESH_TASK_STATE_DIR" ] && [ ! -e "$ACMESH_TASK_LOG_DIR" ]
echo "test_operation_admission: ok"
