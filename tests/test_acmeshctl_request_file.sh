#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$ROOT/tests/.tmp/acmeshctl-request-file"
BIN="$TMP/bin"
CTL="$ROOT/root/usr/libexec/acmesh-console/acmeshctl"

rm -rf "$TMP"
mkdir -p "$BIN" "$TMP/tasks"
chmod 700 "$TMP"
chmod 700 "$TMP/tasks"
. "$ROOT/tests/lib/host_flock.sh"
acmesh_test_install_flock_shim "$TMP/host-flock"
acmesh_test_install_private_ls_shim "$TMP/host-private-ls" "$TMP/tasks"

JSONFILTER_ARG_LOG=""
if command -v node >/dev/null 2>&1; then
	cat > "$BIN/jsonfilter" <<'JS'
#!/usr/bin/env node
const fs = require('fs');
const args = process.argv.slice(2);
const inputIndex = args.indexOf('-i');
const input = inputIndex >= 0 ? args[inputIndex + 1] : '';
const typeIndex = args.indexOf('-t');
const valueIndex = args.indexOf('-e');
const expr = args[(typeIndex >= 0 ? typeIndex : valueIndex) + 1];
fs.appendFileSync(process.env.JSONFILTER_ARG_LOG, args.join(' ') + '\n');
const raw = input ? fs.readFileSync(input, 'utf8') : fs.readFileSync(0, 'utf8');
const data = JSON.parse(raw);
const jsonType = (value) => {
	if (value === null) return 'null';
	if (Array.isArray(value)) return 'array';
	if (Number.isInteger(value)) return 'int';
	if (typeof value === 'number') return 'double';
	return typeof value;
};
const tokens = [];
let offset = 0;
if (expr !== '@') {
	if (!expr || expr[0] !== '@') process.exit(2);
	offset = 1;
	while (offset < expr.length) {
		if (expr[offset] === '.') {
			const match = expr.slice(offset + 1).match(/^[A-Za-z0-9_:-]+/);
			if (!match) process.exit(2);
			tokens.push({ kind: 'key', value: match[0] });
			offset += match[0].length + 1;
		} else if (expr[offset] === '[') {
			const rest = expr.slice(offset);
			const wildcard = rest.match(/^\[\*\]/);
			const index = rest.match(/^\[([0-9]+)\]/);
			if (wildcard) {
				tokens.push({ kind: 'wildcard' });
				offset += wildcard[0].length;
			} else if (index) {
				tokens.push({ kind: 'index', value: Number(index[1]) });
				offset += index[0].length;
			} else {
				process.exit(2);
			}
		} else {
			process.exit(2);
		}
	}
}
let values = [data];
for (const token of tokens) {
	const next = [];
	for (const value of values) {
		if (token.kind === 'key' && value !== null && typeof value === 'object' && !Array.isArray(value) && Object.prototype.hasOwnProperty.call(value, token.value)) {
			next.push(value[token.value]);
		} else if (token.kind === 'index' && Array.isArray(value) && token.value < value.length) {
			next.push(value[token.value]);
		} else if (token.kind === 'wildcard' && Array.isArray(value)) {
			next.push(...value);
		}
	}
	values = next;
}
if (typeIndex >= 0) {
	if (values.length > 0) process.stdout.write(jsonType(values[0]) + '\n');
} else if (values.length > 0) {
	process.stdout.write(values.map((value) => typeof value === 'object' ? JSON.stringify(value) : String(value)).join('\n'));
}
JS
	chmod +x "$BIN/jsonfilter"
	PATH="$BIN:$PATH"
	JSONFILTER_ARG_LOG="$TMP/jsonfilter-argv.log"
fi

export PATH JSONFILTER_ARG_LOG
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"
export ACMESH_CONSOLE_CONFIG="$TMP/config/config.json"
export ACMESH_CONSOLE_UCI_CONFIG="$TMP/missing-uci"
export ACMESH_TASK_STATE_DIR="$TMP/tasks/state"
export ACMESH_TASK_LOG_DIR="$TMP/tasks/log"
export ACMESH_PENDING_IMPORT_DIR="$TMP/pending-imports"
export ACMESH_CONFIG_LOCK_FILE="$TMP/config/config.lock"

task_artifact_count() {
	count=0
	for dir in "$ACMESH_TASK_STATE_DIR" "$ACMESH_TASK_LOG_DIR"; do
		[ ! -d "$dir" ] || count=$((count + $(find "$dir" -type f | wc -l)))
	done
	printf '%s\n' "$count"
}

expect_invalid_request() {
	label="$1"
	command="$2"
	payload="$3"
	expected_error="$4"
	request="$TMP/invalid-$label.json"
	printf '%s\n' "$payload" > "$request"
	before="$(task_artifact_count)"
	set +e
	out="$(sh "$CTL" "$command" --request-file "$request")"
	rc=$?
	set -e
	[ "$rc" = 2 ] || { echo "$label request should exit 2"; echo "$out"; exit 1; }
	case "$out" in
		*'"ok":false'*"$expected_error"*) ;;
		*) echo "$label request returned the wrong structured error"; echo "$out"; exit 1 ;;
	esac
	after="$(task_artifact_count)"
	[ "$before" = "$after" ] || { echo "$label request started a task"; exit 1; }
}

expect_invalid_request top-level-array issue '[]' 'request payload must be a JSON object'
expect_invalid_request string-true issue '{"domain":"invalid-string.example","accountEmail":"ops@example.org","testMode":"true"}' 'request testMode must be a JSON boolean'
expect_invalid_request object-mode renew '{"domain":"invalid-object.example","testMode":{}}' 'request testMode must be a JSON boolean'
expect_invalid_request numeric-one core-install '{"home":"/tmp/invalid-core-install","email":"ops@example.org","testMode":1}' 'request testMode must be a JSON boolean'
expect_invalid_request numeric-zero core-upgrade '{"home":"/tmp/invalid-core-upgrade","testMode":0}' 'request testMode must be a JSON boolean'
expect_invalid_request array-mode dns-test '{"domain":"invalid-array.example","dnsApi":"dns_cf","testMode":[]}' 'request testMode must be a JSON boolean'
expect_invalid_request null-mode renew '{"domain":"invalid-null.example","testMode":null}' 'request testMode must be a JSON boolean'

config_request="$TMP/config-request.json"
cat > "$config_request" <<EOF
{"schemaVersion":2,"global":{"defaultAccountEmail":"request@example.org","coreTag":"v3.1.4","acmeHome":"$TMP/acme-home"},"accountProfiles":[{"id":"request-account","name":"Request","ca":"letsencrypt_staging","accountEmail":""}],"issueProfiles":[{"id":"request-profile","name":"Request","domain":"request.example.org","accountProfileId":"request-account","deployProfileId":"","keyType":"ec256","validationMethod":"dns","testModeOverride":"force-test-mode","dnsApi":"dns_cf","credentialMode":"token","credentials":{"CF_Token":"config-secret-token"}}],"deployProfiles":[]}
EOF
set +e
config_out="$(sh "$CTL" config-save --request-file "$config_request")"
config_rc=$?
set -e
[ "$config_rc" = 0 ] || { echo "request-file config-save command failed"; echo "$config_out"; exit 1; }
case "$config_out" in *'"ok":true'*) ;; *) echo "request-file config-save failed"; echo "$config_out"; exit 1 ;; esac
[ "$(jsonfilter -i "$ACMESH_CONSOLE_CONFIG" -e '@.issueProfiles[0].credentials.CF_Token')" = config-secret-token ] || { echo "request-file config payload was not saved"; exit 1; }

renew_request="$TMP/renew-request.json"
printf '%s\n' '{"domain":"request-renew.example","keyType":"rsa","testMode":true}' > "$renew_request"
renew_out="$(sh "$CTL" renew --request-file "$renew_request")"
case "$renew_out" in *'"ok":true'*'"testMode":true'*'"command"'*) ;; *) echo "request-file renew failed"; echo "$renew_out"; exit 1 ;; esac
case "$renew_out" in *"-d 'request-renew.example'"*'--ecc'*) echo "request-file renew ignored rsa key type"; exit 1 ;; *"-d 'request-renew.example'"*) ;; *) echo "request-file renew ignored domain"; echo "$renew_out"; exit 1 ;; esac
case "$renew_out" in *'taskId'*) echo "renew test mode created a task"; exit 1 ;; esac

issue_request="$TMP/issue-request.json"
printf '%s\n' '{"domain":"request-issue.example","keyType":"rsa2048","validationMethod":"dns","dnsApi":"dns_cf","ca":"letsencrypt_staging","accountEmail":"request@example.org","credentials":["CF_Token=issue-secret-token"],"testMode":true}' > "$issue_request"
issue_out="$(sh "$CTL" issue --request-file "$issue_request")"
case "$issue_out" in *'"ok":true'*'"testMode":true'*'"command"'*) ;; *) echo "request-file issue failed"; echo "$issue_out"; exit 1 ;; esac
case "$issue_out" in *"letsencrypt_test"*"request-issue.example"*"--keylength 2048"*) ;; *) echo "request-file issue ignored fields"; echo "$issue_out"; exit 1 ;; esac
case "$issue_out" in *'issue-secret-token'*|*'taskId'*) echo "request-file issue leaked a secret or created a task"; exit 1 ;; esac

core_request="$TMP/core-request.json"
cat > "$core_request" <<EOF
{"home":"$TMP/core-home","email":"core-request@example.org","tag":"v3.1.3","testMode":true}
EOF
core_out="$(sh "$CTL" core-install --request-file "$core_request")"
case "$core_out" in *'"ok":true'*'"testMode":true'*'"command"'*) ;; *) echo "request-file core-install failed"; echo "$core_out"; exit 1 ;; esac
for needle in "$TMP/core-home" 'codeload.github.com/acmesh-official/acme.sh/tar.gz/refs/tags/3.1.3' 'core-request@example.org'; do
	printf '%s' "$core_out" | grep -F "$needle" >/dev/null || { echo "request-file core-install ignored $needle"; echo "$core_out"; exit 1; }
done
case "$core_out" in *'taskId'*) echo "core test mode created a task"; exit 1 ;; esac

deploy_request="$TMP/deploy-request.json"
printf '%s\n' '{"type":"local","certSource":"paste-pem","domain":"request-deploy.example","keyFile":"/etc/ssl/request.key","fullchainFile":"/etc/ssl/request.fullchain.pem","reloadcmd":"service nginx reload","keyPem":"deploy-private-secret","fullchainPem":"deploy-fullchain-secret"}' > "$deploy_request"
deploy_out="$(sh "$CTL" deploy-test --request-file "$deploy_request")"
case "$deploy_out" in *'"ok":true'*'"testMode":true'*) ;; *) echo "request-file deploy-test failed"; echo "$deploy_out"; exit 1 ;; esac
case "$deploy_out" in *'"preview":"validated; no task or external mutation created"'*) ;; *) echo "request-file deploy did not return safe preview"; exit 1 ;; esac
case "$deploy_out" in *'/etc/ssl/request.key'*|*'/etc/ssl/request.fullchain.pem'*|*'service nginx reload'*|*'deploy-private-secret'*|*'deploy-fullchain-secret'*|*'taskId'*) echo "request-file deploy leaked command material or created task"; exit 1 ;; esac

dns_request="$TMP/dns-request.json"
printf '%s\n' '{"domain":"request-dns.example","dnsApi":"dns_cf","credentials":["CF_Token=dns-secret-token"],"testMode":true}' > "$dns_request"
dns_out="$(sh "$CTL" dns-test --request-file "$dns_request")"
case "$dns_out" in *'"ok":true'*'"testMode":true'*'"taskId"'*) ;; *) echo "request-file dns-test failed"; echo "$dns_out"; exit 1 ;; esac
dns_id="$(printf '%s' "$dns_out" | sed -n 's/.*"taskId":"\([^"]*\)".*/\1/p')"
dns_log=""
for _dns_wait in 1 2 3 4 5 6 7 8 9 10; do
	dns_log="$(sh "$CTL" task-log --task-id "$dns_id")"
	case "$dns_log" in *'Domain: request-dns.example'*'Provider: dns_cf'*'CF_Token=***'*) break ;; esac
	sleep 1
done
case "$dns_log" in *'Domain: request-dns.example'*'Provider: dns_cf'*'CF_Token=***'*) ;; *) echo "request-file dns-test ignored fields"; echo "$dns_log"; exit 1 ;; esac
case "$dns_log" in *'dns-secret-token'*) echo "request-file dns-test leaked credential"; exit 1 ;; esac

import_request="$TMP/import-request.json"
printf '%s\n' '{"payload":"{\"format\":\"acmesh-console-config\",\"version\":1,\"config\":{}}"}' > "$import_request"
set +e
preview_out="$(sh "$CTL" import-preview --request-file "$import_request")"
preview_rc=$?
set -e
[ "$preview_rc" = 2 ] || { echo "legacy JSON import should be rejected"; echo "$preview_out"; exit 1; }
printf '%s' "$preview_out" | grep -F 'migration archive required' >/dev/null

set +e
not_implemented="$(sh "$CTL" authorization-execute --request-file "$issue_request")"
not_implemented_rc=$?
set -e
[ "$not_implemented_rc" = 2 ] || { echo "invalid authorization command should exit 2"; exit 1; }
printf '%s' "$not_implemented" | grep -F '"ok":false' >/dev/null
printf '%s' "$not_implemented" | grep -F 'invalid authorization challenge' >/dev/null

if [ -n "$JSONFILTER_ARG_LOG" ] && [ -f "$JSONFILTER_ARG_LOG" ]; then
	! grep -F 'config-secret-token' "$JSONFILTER_ARG_LOG" >/dev/null || { echo "config secret entered jsonfilter argv"; exit 1; }
	! grep -F 'issue-secret-token' "$JSONFILTER_ARG_LOG" >/dev/null || { echo "issue secret entered jsonfilter argv"; exit 1; }
	! grep -F 'deploy-private-secret' "$JSONFILTER_ARG_LOG" >/dev/null || { echo "deploy secret entered jsonfilter argv"; exit 1; }
	! grep -F 'dns-secret-token' "$JSONFILTER_ARG_LOG" >/dev/null || { echo "dns secret entered jsonfilter argv"; exit 1; }
fi

echo "test_acmeshctl_request_file: ok"
