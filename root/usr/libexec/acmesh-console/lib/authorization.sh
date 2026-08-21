#!/bin/sh

# Canonical material snapshots.  Callers must populate ACMESH_AUTH_* only from
# validated, resolved backend values; browser supplied fingerprints are never
# accepted.
LC_ALL=C
export LC_ALL

if ! command -v acmesh_private_dir >/dev/null 2>&1; then
	. "${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}/io.sh"
fi
if ! command -v acmesh_json_escape >/dev/null 2>&1; then
	. "${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}/json.sh"
fi

: "${ACMESH_AUTH_CANON_VERSION:=1}"
: "${ACMESH_AUTH_ACK_VERSION:=1}"
: "${ACMESH_AUTH_STATE_DIR:=/etc/acmesh-console}"
: "${ACMESH_AUTH_INSTANCE_FILE:=$ACMESH_AUTH_STATE_DIR/instance-id}"
: "${ACMESH_AUTH_LEDGER_FILE:=$ACMESH_AUTH_STATE_DIR/authorizations.json}"
: "${ACMESH_AUTH_CHALLENGE_DIR:=/var/run/acmesh-console/authorization-challenges}"
: "${ACMESH_AUTH_LOCK_FILE:=$ACMESH_AUTH_STATE_DIR/authorization.lock}"
: "${ACMESH_AUTH_LEDGER_SCHEMA:=1}"

acmesh_canon_safe() {
	! printf '%s' "${1-}" | LC_ALL=C grep -q '[[:cntrl:]]'
}

acmesh_canon_string() {
	key="$1" value="${2-}"
	acmesh_canon_safe "$key$value" || return 2
	printf 's:%s:%s:%s:%s\n' "${#key}" "$key" "${#value}" "$value"
}

acmesh_canon_bool() {
	key="$1" value="$2"
	acmesh_canon_safe "$key" || return 2
	case "$value" in true|1) value=true ;; false|0) value=false ;; *) return 2 ;; esac
	printf 'b:%s:%s\n' "$key" "$value"
}

acmesh_canon_null() {
	acmesh_canon_safe "$1" || return 2
	printf 'n:%s\n' "$1"
}

acmesh_canon_array() {
	key="$1" values="${2-}"
	acmesh_canon_safe "$key" || return 2
	index=0
	printf '%s\n' "$values" | sed '/^$/d' | LC_ALL=C sort -u | while IFS= read -r value; do
		acmesh_canon_safe "$value" || exit 2
		printf 'a:%s:%s:%s:%s\n' "$key" "$index" "${#value}" "$value"
		index=$((index + 1))
	done
}

acmesh_auth_random_id() {
	if [ -r /dev/urandom ]; then
		hexdump -n 16 -v -e '16/1 "%02x" "\n"' /dev/urandom
	else
		printf '%s:%s:%s\n' "$$" "$(date +%s)" "${RANDOM:-0}" | sha256sum | awk '{print substr($1,1,32)}'
	fi
}

acmesh_auth_instance_id() {
	file="$ACMESH_AUTH_INSTANCE_FILE"
	[ ! -L "$file" ] || return 1
	if [ ! -f "$file" ]; then
		dir="${file%/*}"
		acmesh_private_dir "$dir" || return 1
		id="$(acmesh_auth_random_id)" || return 1
		if ! (umask 077; set -C; printf '%s\n' "$id" > "$file") 2>/dev/null; then
			attempt=0
			while [ ! -s "$file" ] && [ "$attempt" -lt 3 ]; do
				attempt=$((attempt + 1))
				sleep 1
			done
		fi
	fi
	[ -f "$file" ] && [ ! -L "$file" ] || return 1
	chmod 600 "$file" || return 1
	id="$(sed -n '1p' "$file")"
	printf '%s\n' "$id" | grep -Eq '^[a-f0-9]{32}$' || return 1
	printf '%s\n' "$id"
}

acmesh_auth_emit_optional() {
	key="$1" value="${2-}"
	if [ -n "$value" ]; then acmesh_canon_string "$key" "$value"; else acmesh_canon_null "$key"; fi
}

acmesh_auth_digest_text() {
	printf '%s' "${1-}" | sha256sum | awk '{print $1}'
}

acmesh_auth_emit_issue() {
	acmesh_canon_string accountId "${ACMESH_AUTH_ACCOUNT_ID-}" || return $?
	acmesh_auth_emit_optional accountEmail "${ACMESH_AUTH_ACCOUNT_EMAIL-}" || return $?
	acmesh_canon_string ca "${ACMESH_AUTH_CA-}" || return $?
	acmesh_canon_string primaryDomain "$(printf '%s' "${ACMESH_AUTH_PRIMARY_DOMAIN-}" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz')" || return $?
	acmesh_canon_array domains "$(printf '%s\n' "${ACMESH_AUTH_DOMAINS-}" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz')" || return $?
	acmesh_canon_string keyType "${ACMESH_AUTH_KEY_TYPE-}" || return $?
	acmesh_canon_string validationMethod "${ACMESH_AUTH_VALIDATION-}" || return $?
	acmesh_auth_emit_optional dnsApi "${ACMESH_AUTH_DNS_API-}" || return $?
	acmesh_auth_emit_optional credentialMode "${ACMESH_AUTH_CREDENTIAL_MODE-}" || return $?
	acmesh_canon_array credentialKeys "${ACMESH_AUTH_CREDENTIAL_KEYS-}" || return $?
	acmesh_auth_emit_optional challengeAlias "${ACMESH_AUTH_CHALLENGE_ALIAS-}" || return $?
	acmesh_canon_string dnsSleep "${ACMESH_AUTH_DNS_SLEEP:-0}" || return $?
	acmesh_auth_emit_optional webroot "${ACMESH_AUTH_WEBROOT-}" || return $?
	acmesh_auth_emit_optional listenPort "${ACMESH_AUTH_LISTEN_PORT-}" || return $?
	acmesh_auth_emit_optional deployProfileId "${ACMESH_AUTH_DEPLOY_PROFILE_ID-}" || return $?
	acmesh_auth_emit_optional deployFingerprint "${ACMESH_AUTH_DEPLOY_FINGERPRINT-}" || return $?
	acmesh_canon_bool testMode "${ACMESH_AUTH_TEST_MODE:-false}" || return $?
}

acmesh_auth_emit_deploy() {
	acmesh_canon_string deployType "${ACMESH_AUTH_DEPLOY_TYPE-}" || return $?
	acmesh_canon_string sourceType "${ACMESH_AUTH_SOURCE_TYPE-}" || return $?
	acmesh_auth_emit_optional sourceIdentity "${ACMESH_AUTH_SOURCE_IDENTITY-}" || return $?
	acmesh_auth_emit_optional sourceDigest "${ACMESH_AUTH_SOURCE_DIGEST-}" || return $?
	acmesh_auth_emit_optional keyVariant "${ACMESH_AUTH_KEY_VARIANT-}" || return $?
	if [ "${ACMESH_AUTH_SOURCE_TYPE-}" = paste-pem ]; then
		acmesh_canon_string keyPemDigest "$(acmesh_auth_digest_text "${ACMESH_AUTH_KEY_PEM-}")" || return $?
		acmesh_canon_string fullchainPemDigest "$(acmesh_auth_digest_text "${ACMESH_AUTH_FULLCHAIN_PEM-}")" || return $?
	else
		acmesh_auth_emit_optional sourceKeyFile "${ACMESH_AUTH_SOURCE_KEY_FILE-}" || return $?
		acmesh_auth_emit_optional sourceFullchainFile "${ACMESH_AUTH_SOURCE_FULLCHAIN_FILE-}" || return $?
	fi
	acmesh_auth_emit_optional host "$(printf '%s' "${ACMESH_AUTH_HOST-}" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz')" || return $?
	acmesh_canon_string port "${ACMESH_AUTH_PORT:-22}" || return $?
	acmesh_auth_emit_optional user "${ACMESH_AUTH_USER-}" || return $?
	acmesh_auth_emit_optional sshClient "${ACMESH_AUTH_SSH_CLIENT-}" || return $?
	acmesh_auth_emit_optional hostKeyAlgorithm "${ACMESH_AUTH_HOSTKEY_ALGORITHM-}" || return $?
	acmesh_auth_emit_optional hostKeyFingerprint "${ACMESH_AUTH_HOSTKEY_FINGERPRINT-}" || return $?
	acmesh_canon_string keyFile "${ACMESH_AUTH_KEY_FILE-}" || return $?
	acmesh_canon_string fullchainFile "${ACMESH_AUTH_FULLCHAIN_FILE-}" || return $?
	acmesh_auth_emit_optional certFile "${ACMESH_AUTH_CERT_FILE-}" || return $?
	acmesh_auth_emit_optional caFile "${ACMESH_AUTH_CA_FILE-}" || return $?
	acmesh_auth_emit_optional reloadCommand "${ACMESH_AUTH_RELOAD-}" || return $?
	acmesh_auth_emit_optional sudoMode "${ACMESH_AUTH_SUDO_MODE-}" || return $?
	acmesh_auth_emit_optional owner "${ACMESH_AUTH_OWNER-}" || return $?
	acmesh_auth_emit_optional group "${ACMESH_AUTH_GROUP-}" || return $?
	acmesh_auth_emit_optional mode "${ACMESH_AUTH_MODE-}" || return $?
	preserve_metadata="${ACMESH_AUTH_PRESERVE_METADATA-${ACMESH_DEPLOY_PRESERVE_METADATA-}}"
	if [ -n "$preserve_metadata" ]; then
		acmesh_canon_bool preserveMetadata "$preserve_metadata" || return $?
	fi
	acmesh_canon_string transactionStrategy "${ACMESH_AUTH_TRANSACTION_STRATEGY:-pair-rollback-v1}" || return $?
}

acmesh_auth_emit_core() {
	acmesh_canon_string sourceRepository "${ACMESH_AUTH_SOURCE_REPOSITORY:-acmesh-official/acme.sh}" || return $?
	acmesh_canon_string acmeHome "${ACMESH_AUTH_ACME_HOME-}" || return $?
	acmesh_canon_string tag "${ACMESH_AUTH_CORE_TAG-}" || return $?
	case "${operation-}" in core-install) acmesh_auth_emit_optional accountEmail "${ACMESH_AUTH_CORE_EMAIL-}" || return $?;; esac
	acmesh_canon_string backupPolicy "${ACMESH_AUTH_BACKUP_POLICY:-rollback-v1}" || return $?
}

acmesh_auth_snapshot() (
	operation="${1:-}" subject_type="${2:-}" subject_id="${3:-}" output="${4:-}"
	[ -n "$operation" ] && [ -n "$subject_type" ] && [ -n "$subject_id" ] && [ -n "$output" ] || return 2
	instance_id="$(acmesh_auth_instance_id)" || return 1
	dir="${output%/*}"; acmesh_private_dir "$dir" || return 1
	tmp="$dir/.${output##*/}.$$.$(date +%s).tmp"
	trap 'rm -f "$tmp"' HUP INT TERM EXIT
	( umask 077
	set -e
	{
		acmesh_canon_string canonicalVersion "$ACMESH_AUTH_CANON_VERSION" || exit $?
		acmesh_canon_string ackVersion "$ACMESH_AUTH_ACK_VERSION" || exit $?
		acmesh_canon_string instanceId "$instance_id" || exit $?
		acmesh_canon_string operation "$operation" || exit $?
		acmesh_canon_string subjectType "$subject_type" || exit $?
		acmesh_canon_string subjectId "$subject_id" || exit $?
		case "$operation" in
			issue|renew) acmesh_auth_emit_issue || exit $? ;;
			issue-deploy) acmesh_auth_emit_issue || exit $?; acmesh_auth_emit_deploy || exit $? ;;
			deploy|deploy-run) acmesh_auth_emit_deploy || exit $? ;;
			core-install|core-upgrade) acmesh_auth_emit_core || exit $? ;;
			import|import-apply) acmesh_canon_string configDigest "${ACMESH_AUTH_CONFIG_DIGEST-}" && acmesh_canon_string overwriteMode "${ACMESH_AUTH_OVERWRITE_MODE-}" || exit $? ;;
			export|secret-export) acmesh_canon_string configDigest "${ACMESH_AUTH_CONFIG_DIGEST-}" && acmesh_canon_string exportScope "${ACMESH_AUTH_EXPORT_SCOPE-}" || exit $? ;;
			ssh-key-convert) acmesh_canon_string publicIdentityDigest "${ACMESH_AUTH_PUBLIC_IDENTITY_DIGEST-}" && acmesh_canon_string sourceFormat "${ACMESH_AUTH_SOURCE_FORMAT-}" && acmesh_canon_string targetClient "${ACMESH_AUTH_TARGET_CLIENT-}" && acmesh_canon_string targetFormat "${ACMESH_AUTH_TARGET_FORMAT-}" || exit $? ;;
			certificate-revoke|certificate-remove|profile-delete|authorization-revoke) acmesh_canon_string objectIdentity "${ACMESH_AUTH_OBJECT_IDENTITY-}" && acmesh_canon_string variant "${ACMESH_AUTH_VARIANT-}" && acmesh_auth_emit_optional objectDigest "${ACMESH_AUTH_OBJECT_DIGEST-}" && acmesh_auth_emit_optional configDigest "${ACMESH_AUTH_CONFIG_DIGEST-}" || exit $? ;;
			*) return 2 ;;
		esac
	} > "$tmp"
	) || { rm -f "$tmp"; trap - HUP INT TERM EXIT; return 1; }
	chmod 600 "$tmp" && mv -f "$tmp" "$output" && chmod 600 "$output" || return 1
	trap - HUP INT TERM EXIT
)

acmesh_auth_fingerprint() {
	snapshot="${1:-}"
	[ -f "$snapshot" ] && [ ! -L "$snapshot" ] || return 2
	printf 'sha256:%s\n' "$(sha256sum "$snapshot" | awk '{print $1}')"
}

acmesh_auth_summary_array() {
	snapshot="$1" wanted="$2" first=1
	while IFS= read -r line; do
		case "$line" in
			a:"$wanted":*)
				rest="${line#a:}"; key="${rest%%:*}"; rest="${rest#*:}"
				index="${rest%%:*}"; rest="${rest#*:}"; length="${rest%%:*}"; value="${rest#*:}"
				case "$index:$length" in *[!0-9:]*|:*) return 2;; esac
				[ "${#value}" = "$length" ] || return 2
				[ "$first" = 1 ] || printf ','
				printf '"%s"' "$(acmesh_json_escape "$value")"; first=0
				;;
		esac
	done < "$snapshot"
}

acmesh_auth_summary() (
	snapshot="${1:-}" output="${2:-}"
	[ -f "$snapshot" ] && [ ! -L "$snapshot" ] && [ -n "$output" ] || return 2
	dir="${output%/*}"; acmesh_private_dir "$dir" || return 1
	operation="$(acmesh_auth_snapshot_value "$snapshot" operation)"
	subject_type="$(acmesh_auth_snapshot_value "$snapshot" subjectType)"
	subject_id="$(acmesh_auth_snapshot_value "$snapshot" subjectId)"
	canonical_version="$(acmesh_auth_snapshot_value "$snapshot" canonicalVersion)"
	ack_version="$(acmesh_auth_snapshot_value "$snapshot" ackVersion)"
	printf '%s\n' "$canonical_version" | grep -Eq '^[1-9][0-9]*$' || return 2
	printf '%s\n' "$ack_version" | grep -Eq '^[1-9][0-9]*$' || return 2
	fingerprint="$(acmesh_auth_fingerprint "$snapshot")" || return 1
	tmp="$dir/.${output##*/}.$$.$(date +%s).tmp"
	trap 'rm -f "$tmp"' HUP INT TERM EXIT
	(umask 077
		printf '{"operation":"%s","subjectType":"%s","subjectId":"%s","fingerprint":"%s","canonicalVersion":%s,"ackVersion":%s' \
			"$(acmesh_json_escape "$operation")" "$(acmesh_json_escape "$subject_type")" \
			"$(acmesh_json_escape "$subject_id")" "$(acmesh_json_escape "$fingerprint")" \
			"$canonical_version" "$ack_version"
		while IFS= read -r line; do
			case "$line" in
				s:*)
					rest="${line#s:}"; key_length="${rest%%:*}"; rest="${rest#*:}"
					key="${rest%%:*}"; rest="${rest#*:}"; value_length="${rest%%:*}"; value="${rest#*:}"
					case "$key_length:$value_length" in *[!0-9:]*|:*) exit 2;; esac
					[ "${#key}" = "$key_length" ] && [ "${#value}" = "$value_length" ] || exit 2
					case "$key" in canonicalVersion|ackVersion|instanceId|operation|subjectType|subjectId) continue;; esac
					printf ',"%s":"%s"' "$(acmesh_json_escape "$key")" "$(acmesh_json_escape "$value")"
					;;
				b:*) key="${line#b:}"; value="${key#*:}"; key="${key%%:*}"; case "$value" in true|false) ;; *) exit 2;; esac; printf ',"%s":%s' "$(acmesh_json_escape "$key")" "$value" ;;
				n:*) key="${line#n:}"; printf ',"%s":null' "$(acmesh_json_escape "$key")" ;;
				a:*) key="${line#a:}"; key="${key%%:*}"; case "$key" in domains|credentialKeys) ;; *) exit 2;; esac ;;
				*) exit 2 ;;
			esac
		done < "$snapshot"
		for array_key in domains credentialKeys; do
			if grep -F "a:$array_key:" "$snapshot" >/dev/null; then
				printf ',"%s":[' "$array_key"; acmesh_auth_summary_array "$snapshot" "$array_key" || exit $?; printf ']'
			fi
		done
		printf '}\n'
	) > "$tmp" || return 1
	chmod 600 "$tmp" && mv -f "$tmp" "$output" && chmod 600 "$output" || return 1
	trap - HUP INT TERM EXIT
)

acmesh_auth_now() { date +%s; }
acmesh_auth_valid_id() { printf '%s\n' "${1-}" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$'; }
acmesh_auth_json_type() { jsonfilter -i "$1" -t "$2" 2>/dev/null || true; }
acmesh_auth_json_get() { jsonfilter -i "$1" -e "$2" 2>/dev/null || true; }
acmesh_auth_snapshot_value() { sed -n "s/^s:[0-9][0-9]*:$2:[0-9][0-9]*://p" "$1"; }
acmesh_auth_snapshot_identity_matches() {
	[ "$(acmesh_auth_snapshot_value "$1" operation)" = "$2" ] &&
		[ "$(acmesh_auth_snapshot_value "$1" subjectType)" = "$3" ] &&
		[ "$(acmesh_auth_snapshot_value "$1" subjectId)" = "$4" ]
}
acmesh_auth_operation_supported() {
	case "$1" in
		issue|issue-deploy|renew|deploy|deploy-run|core-install|core-upgrade|import|import-apply|export|secret-export|ssh-key-convert|certificate-revoke|certificate-remove|profile-delete|authorization-revoke) return 0 ;;
		*) return 1 ;;
	esac
}
acmesh_auth_lock_run() {
	acmesh_path_dir "$ACMESH_AUTH_LOCK_FILE"
	acmesh_private_dir "$dir" || return 1
	acmesh_lock_file_prepare "$ACMESH_AUTH_LOCK_FILE" || return 1
	flock_bin="${ACMESH_FLOCK_BIN:-flock}"
	command -v "$flock_bin" >/dev/null 2>&1 || return 127
	exec 9<> "$ACMESH_AUTH_LOCK_FILE" || return 1
	attempt=0
	while ! "$flock_bin" -n 9; do
		attempt=$((attempt + 1))
		[ "$attempt" -lt 10 ] || { exec 9>&-; return 75; }
		sleep 1
	done
	acmesh_auth_lock_held=1
	if "$@"; then status=0; else status=$?; fi
	acmesh_auth_lock_release
	return "$status"
}
acmesh_auth_lock_release() {
	[ "${acmesh_auth_lock_held:-0}" = 1 ] || return 0
	"${flock_bin:-flock}" -u 9 2>/dev/null || true
	exec 9>&-
	acmesh_auth_lock_held=0
}

acmesh_auth_empty_ledger() {
	instance_id="$(acmesh_auth_instance_id)" || return 1
	printf '{"schemaVersion":%s,"instanceId":"%s","ackVersion":%s,"records":[]}\n' \
		"$ACMESH_AUTH_LEDGER_SCHEMA" "$(acmesh_json_escape "$instance_id")" "$ACMESH_AUTH_ACK_VERSION"
}

acmesh_auth_ledger_exact_fields_valid() (
	set +u
	path="$1"
	jshn_path="${ACMESH_JSHN_PATH:-/usr/share/libubox/jshn.sh}"
	[ -r "$jshn_path" ] || exit 1
	JSON_PREFIX= JSON_UNSET= JSON_SEQ= JSON_CUR=
	. "$jshn_path" || exit 1
	json_load_file "$path" || exit 1
	json_get_keys envelope_fields
	normalized_envelope_fields="$(printf '%s\n' $envelope_fields | LC_ALL=C sort | tr '\n' ' ')"
	[ "$normalized_envelope_fields" = 'ackVersion instanceId records schemaVersion ' ] || exit 1
	json_select records || exit 1
	json_get_keys record_indexes
	expected_fields='ackVersion fingerprint grantedAt id lastUsedAt operation subjectId subjectType useCount '
	for record_index in $record_indexes; do
		json_select "$record_index" || exit 1
		json_get_keys record_fields
		normalized_fields="$(printf '%s\n' $record_fields | LC_ALL=C sort | tr '\n' ' ')"
		[ "$normalized_fields" = "$expected_fields" ] || exit 1
		json_select .. || exit 1
	done
)

acmesh_auth_ledger_valid() {
	path="$1" instance_id="$(acmesh_auth_instance_id)" || return 1
	command -v jsonfilter >/dev/null 2>&1 || return 1
	[ "$(acmesh_auth_json_type "$path" '@')" = object ] || return 1
	[ "$(acmesh_auth_json_type "$path" '@.schemaVersion')" = int ] || return 1
	[ "$(acmesh_auth_json_get "$path" '@.schemaVersion')" = "$ACMESH_AUTH_LEDGER_SCHEMA" ] || return 1
	[ "$(acmesh_auth_json_type "$path" '@.instanceId')" = string ] || return 1
	[ "$(acmesh_auth_json_get "$path" '@.instanceId')" = "$instance_id" ] || return 1
	[ "$(acmesh_auth_json_type "$path" '@.ackVersion')" = int ] || return 1
	[ "$(acmesh_auth_json_get "$path" '@.ackVersion')" = "$ACMESH_AUTH_ACK_VERSION" ] || return 1
	[ "$(acmesh_auth_json_type "$path" '@.records')" = array ] || return 1
	acmesh_auth_ledger_exact_fields_valid "$path" 2>/dev/null || return 1
	i=0
	while [ "$(acmesh_auth_json_type "$path" "@.records[$i]")" = object ]; do
		for field in id operation subjectType subjectId fingerprint grantedAt lastUsedAt; do
			[ "$(acmesh_auth_json_type "$path" "@.records[$i].$field")" = string ] || return 1
		done
		[ "$(acmesh_auth_json_type "$path" "@.records[$i].useCount")" = int ] || return 1
		[ "$(acmesh_auth_json_type "$path" "@.records[$i].ackVersion")" = int ] || return 1
		acmesh_auth_valid_id "$(acmesh_auth_json_get "$path" "@.records[$i].id")" || return 1
		printf '%s\n' "$(acmesh_auth_json_get "$path" "@.records[$i].fingerprint")" | grep -Eq '^sha256:[a-f0-9]{64}$' || return 1
		[ "$(acmesh_auth_json_get "$path" "@.records[$i].ackVersion")" = "$ACMESH_AUTH_ACK_VERSION" ] || return 1
		i=$((i + 1))
	done
}

acmesh_auth_ledger_load_locked() {
	acmesh_private_dir "$ACMESH_AUTH_STATE_DIR" || return 1
	if [ ! -e "$ACMESH_AUTH_LEDGER_FILE" ]; then
		acmesh_auth_empty_ledger | acmesh_atomic_write "$ACMESH_AUTH_LEDGER_FILE" 600 || return 1
	elif ! acmesh_private_file_is_secure "$ACMESH_AUTH_LEDGER_FILE" || ! acmesh_auth_ledger_valid "$ACMESH_AUTH_LEDGER_FILE"; then
		stamp="$(acmesh_auth_now)"; corrupt="$ACMESH_AUTH_LEDGER_FILE.corrupt.$stamp"
		n=0; while [ -e "$corrupt" ]; do n=$((n + 1)); corrupt="$ACMESH_AUTH_LEDGER_FILE.corrupt.$stamp.$n"; done
		[ ! -L "$ACMESH_AUTH_LEDGER_FILE" ] || return 1
		mv "$ACMESH_AUTH_LEDGER_FILE" "$corrupt" || return 1
		chmod 600 "$corrupt" || return 1
		acmesh_auth_empty_ledger | acmesh_atomic_write "$ACMESH_AUTH_LEDGER_FILE" 600 || return 1
		return 2
	fi
	acmesh_auth_ledger_valid "$ACMESH_AUTH_LEDGER_FILE"
}

acmesh_auth_emit_record() {
	path="$1" i="$2"
	printf '{"id":"%s","operation":"%s","subjectType":"%s","subjectId":"%s","fingerprint":"%s","grantedAt":"%s","lastUsedAt":"%s","useCount":%s,"ackVersion":%s}' \
		"$(acmesh_json_escape "$(acmesh_auth_json_get "$path" "@.records[$i].id")")" \
		"$(acmesh_json_escape "$(acmesh_auth_json_get "$path" "@.records[$i].operation")")" \
		"$(acmesh_json_escape "$(acmesh_auth_json_get "$path" "@.records[$i].subjectType")")" \
		"$(acmesh_json_escape "$(acmesh_auth_json_get "$path" "@.records[$i].subjectId")")" \
		"$(acmesh_json_escape "$(acmesh_auth_json_get "$path" "@.records[$i].fingerprint")")" \
		"$(acmesh_json_escape "$(acmesh_auth_json_get "$path" "@.records[$i].grantedAt")")" \
		"$(acmesh_json_escape "$(acmesh_auth_json_get "$path" "@.records[$i].lastUsedAt")")" \
		"$(acmesh_auth_json_get "$path" "@.records[$i].useCount")" "$ACMESH_AUTH_ACK_VERSION"
}

acmesh_auth_rewrite_locked() {
	auth_rewrite_mode="$1" auth_rewrite_needle="${2-}" auth_rewrite_operation="${3-}" auth_rewrite_subject_type="${4-}" auth_rewrite_subject_id="${5-}" auth_rewrite_fingerprint="${6-}" auth_rewrite_now="${7-}"
	auth_rewrite_instance_id="$(acmesh_auth_instance_id)" || return 1
	{
		printf '{"schemaVersion":%s,"instanceId":"%s","ackVersion":%s,"records":[' "$ACMESH_AUTH_LEDGER_SCHEMA" "$(acmesh_json_escape "$auth_rewrite_instance_id")" "$ACMESH_AUTH_ACK_VERSION"
		auth_rewrite_i=0 auth_rewrite_first=1 auth_rewrite_found=0
		while [ "$(acmesh_auth_json_type "$ACMESH_AUTH_LEDGER_FILE" "@.records[$auth_rewrite_i]")" = object ]; do
			auth_rewrite_id="$(acmesh_auth_json_get "$ACMESH_AUTH_LEDGER_FILE" "@.records[$auth_rewrite_i].id")"; auth_rewrite_record_fingerprint="$(acmesh_auth_json_get "$ACMESH_AUTH_LEDGER_FILE" "@.records[$auth_rewrite_i].fingerprint")"
			auth_rewrite_keep=1; [ "$auth_rewrite_mode" = all ] && auth_rewrite_keep=0; [ "$auth_rewrite_mode" = revoke ] && [ "$auth_rewrite_id" = "$auth_rewrite_needle" ] && auth_rewrite_keep=0
			if [ "$auth_rewrite_mode" = upsert ] && [ "$auth_rewrite_record_fingerprint" = "$auth_rewrite_fingerprint" ]; then auth_rewrite_keep=0; auth_rewrite_found=1; fi
			if [ "$auth_rewrite_mode" = reuse ] && [ "$auth_rewrite_record_fingerprint" = "$auth_rewrite_fingerprint" ]; then
				[ "$auth_rewrite_first" = 1 ] || printf ','; auth_rewrite_first=0
				auth_rewrite_count="$(acmesh_auth_json_get "$ACMESH_AUTH_LEDGER_FILE" "@.records[$auth_rewrite_i].useCount")"; auth_rewrite_count=$((auth_rewrite_count + 1))
				printf '{"id":"%s","operation":"%s","subjectType":"%s","subjectId":"%s","fingerprint":"%s","grantedAt":"%s","lastUsedAt":"%s","useCount":%s,"ackVersion":%s}' \
					"$(acmesh_json_escape "$auth_rewrite_id")" "$(acmesh_json_escape "$(acmesh_auth_json_get "$ACMESH_AUTH_LEDGER_FILE" "@.records[$auth_rewrite_i].operation")")" "$(acmesh_json_escape "$(acmesh_auth_json_get "$ACMESH_AUTH_LEDGER_FILE" "@.records[$auth_rewrite_i].subjectType")")" "$(acmesh_json_escape "$(acmesh_auth_json_get "$ACMESH_AUTH_LEDGER_FILE" "@.records[$auth_rewrite_i].subjectId")")" "$(acmesh_json_escape "$auth_rewrite_record_fingerprint")" "$(acmesh_json_escape "$(acmesh_auth_json_get "$ACMESH_AUTH_LEDGER_FILE" "@.records[$auth_rewrite_i].grantedAt")")" "$auth_rewrite_now" "$auth_rewrite_count" "$ACMESH_AUTH_ACK_VERSION"
				auth_rewrite_found=1; auth_rewrite_keep=0
			fi
			if [ "$auth_rewrite_keep" = 1 ]; then [ "$auth_rewrite_first" = 1 ] || printf ','; auth_rewrite_first=0; acmesh_auth_emit_record "$ACMESH_AUTH_LEDGER_FILE" "$auth_rewrite_i"; fi
			auth_rewrite_i=$((auth_rewrite_i + 1))
		done
		if [ "$auth_rewrite_mode" = upsert ]; then [ "$auth_rewrite_first" = 1 ] || printf ','; auth_rewrite_id="$(acmesh_auth_random_id)"; printf '{"id":"%s","operation":"%s","subjectType":"%s","subjectId":"%s","fingerprint":"%s","grantedAt":"%s","lastUsedAt":"%s","useCount":1,"ackVersion":%s}' "$auth_rewrite_id" "$(acmesh_json_escape "$auth_rewrite_operation")" "$(acmesh_json_escape "$auth_rewrite_subject_type")" "$(acmesh_json_escape "$auth_rewrite_subject_id")" "$auth_rewrite_fingerprint" "$auth_rewrite_now" "$auth_rewrite_now" "$ACMESH_AUTH_ACK_VERSION"; auth_rewrite_found=1; fi
		printf ']}\n'
		[ "$auth_rewrite_mode" != reuse ] || [ "$auth_rewrite_found" = 1 ]
	} | acmesh_atomic_write "$ACMESH_AUTH_LEDGER_FILE" 600
}

acmesh_auth_call_recompute() {
	callback="${ACMESH_AUTH_RECOMPUTE_CALLBACK:-}"
	[ -n "$callback" ] && command -v "$callback" >/dev/null 2>&1 || return 1
	"$callback" "$1" "$2" "$3" "$4" "$5"
}

acmesh_auth_admit() {
	callback="${ACMESH_AUTH_ADMIT_CALLBACK:-:}"
	command -v "$callback" >/dev/null 2>&1 || return 1
	"$callback" "$@"
}

acmesh_auth_prepare_locked() {
	operation="$1" subject_type="$2" subject_id="$3" snapshot="$4" summary="$5" now="$6"
	load_rc=0; acmesh_auth_ledger_load_locked || load_rc=$?
	# Corruption is retained and deliberately cannot authorize this attempt.
	[ "$load_rc" = 0 ] || { [ "$load_rc" = 2 ] && acmesh_auth_create_challenge_locked "$operation" "$subject_type" "$subject_id" "$snapshot" "$summary" "$now"; return $?; }
	fingerprint="$(acmesh_auth_fingerprint "$snapshot")" || return 1
	i=0
	while [ "$(acmesh_auth_json_type "$ACMESH_AUTH_LEDGER_FILE" "@.records[$i]")" = object ]; do
		if [ "$(acmesh_auth_json_get "$ACMESH_AUTH_LEDGER_FILE" "@.records[$i].fingerprint")" = "$fingerprint" ] && [ "$(acmesh_auth_json_get "$ACMESH_AUTH_LEDGER_FILE" "@.records[$i].operation")" = "$operation" ]; then
			acmesh_auth_rewrite_locked reuse '' '' '' '' "$fingerprint" "$now" || return 1
			ACMESH_OPERATION_FINGERPRINT="$fingerprint"; export ACMESH_OPERATION_FINGERPRINT
			acmesh_auth_admit "$operation" "$subject_type" "$subject_id" remembered || return 1
			[ "${ACMESH_OPERATION_DIRECT_RESPONSE:-0}" = 1 ] || printf '{"ok":true,"authorized":true,"remembered":true,"taskId":"%s"}\n' "$(acmesh_json_escape "${ACMESH_OPERATION_TASK_ID:-}")"; return 0
		fi
		i=$((i + 1))
	done
	if [ "${ACMESH_AUTH_REQUIRE_REMEMBERED:-0}" = 1 ]; then
		printf '{"ok":false,"error":"rememberedAuthorizationRequired"}\n'
		return 4
	fi
	acmesh_auth_create_challenge_locked "$operation" "$subject_type" "$subject_id" "$snapshot" "$summary" "$now"
}

acmesh_auth_create_challenge_locked() {
	operation="$1" subject_type="$2" subject_id="$3" snapshot="$4" summary="$5" now="$6" changed="${7:-false}"
	acmesh_auth_prune_challenges_locked "$now" || return 1
	id="$(acmesh_auth_random_id)"; expires=$((now + 300)); fingerprint="$(acmesh_auth_fingerprint "$snapshot")" || return 1
	acmesh_private_dir "$ACMESH_AUTH_CHALLENGE_DIR" || return 1
	path="$ACMESH_AUTH_CHALLENGE_DIR/$id.json"
	instance_id="$(acmesh_auth_instance_id)" || return 1
	[ "$(acmesh_auth_json_type "$summary" '@')" = object ] || return 2
	printf '{"schemaVersion":%s,"instanceId":"%s","challengeId":"%s","operation":"%s","subjectType":"%s","subjectId":"%s","fingerprint":"%s","createdAt":%s,"expiresAt":%s,"ackVersion":%s,"summary":%s}\n' "$ACMESH_AUTH_LEDGER_SCHEMA" "$(acmesh_json_escape "$instance_id")" "$id" "$(acmesh_json_escape "$operation")" "$(acmesh_json_escape "$subject_type")" "$(acmesh_json_escape "$subject_id")" "$fingerprint" "$now" "$expires" "$ACMESH_AUTH_ACK_VERSION" "$(cat "$summary")" | acmesh_atomic_write "$path" 600 || return 1
	if [ "$changed" = true ]; then error='"error":"authorizationChanged",'; else error=; fi
	printf '{"ok":false,%s"authorizationRequired":true,"challengeId":"%s","expiresAt":%s,"fingerprint":"%s","operation":"%s","subject":{"type":"%s","id":"%s"},"riskSummary":%s}\n' "$error" "$id" "$expires" "$fingerprint" "$(acmesh_json_escape "$operation")" "$(acmesh_json_escape "$subject_type")" "$(acmesh_json_escape "$subject_id")" "$(cat "$summary")"
	return 3
}

acmesh_auth_prepare() {
	[ "$#" = 5 ] || return 2
	acmesh_auth_valid_id "$2" && acmesh_auth_valid_id "$3" || return 2
	acmesh_private_file_is_secure "$4" && acmesh_private_file_is_secure "$5" || return 2
	acmesh_auth_snapshot_identity_matches "$4" "$1" "$2" "$3" || return 2
	now="$(acmesh_auth_now)"
	acmesh_auth_lock_run acmesh_auth_prepare_locked "$1" "$2" "$3" "$4" "$5" "$now"
}

acmesh_auth_is_remembered_locked() {
	operation="$1" fingerprint="$2"; acmesh_auth_ledger_load_locked || return 1
	i=0
	while [ "$(acmesh_auth_json_type "$ACMESH_AUTH_LEDGER_FILE" "@.records[$i]")" = object ]; do
		[ "$(acmesh_auth_json_get "$ACMESH_AUTH_LEDGER_FILE" "@.records[$i].operation")" != "$operation" ] || \
			[ "$(acmesh_auth_json_get "$ACMESH_AUTH_LEDGER_FILE" "@.records[$i].fingerprint")" != "$fingerprint" ] || return 0
		i=$((i + 1))
	done
	return 1
}
acmesh_auth_is_remembered() {
	[ "$#" = 2 ] || return 2
	if [ "${acmesh_auth_lock_held:-0}" = 1 ]; then acmesh_auth_is_remembered_locked "$@"; else acmesh_auth_lock_run acmesh_auth_is_remembered_locked "$@"; fi
}

acmesh_auth_execute_locked() {
	id="$1" decision="$2" now="$3"; path="$ACMESH_AUTH_CHALLENGE_DIR/$id.json"; consuming="$path.consuming"
	[ -f "$path" ] && [ ! -L "$path" ] && acmesh_private_file_is_secure "$path" || { printf '{"ok":false,"error":"authorizationConsumedOrMissing"}\n'; return 4; }
	mv "$path" "$consuming" || return 1
	cleanup_consuming() { [ -z "${tmpdir:-}" ] || rm -rf "$tmpdir"; rm -f "$consuming"; acmesh_auth_lock_release; trap - HUP INT TERM EXIT; }
	trap 'cleanup_consuming' EXIT
	trap 'cleanup_consuming; exit 129' HUP
	trap 'cleanup_consuming; exit 130' INT
	trap 'cleanup_consuming; exit 143' TERM
	instance_id="$(acmesh_auth_instance_id)" || { cleanup_consuming; return 1; }
	[ "$(acmesh_auth_json_type "$consuming" '@')" = object ] && [ "$(acmesh_auth_json_get "$consuming" '@.schemaVersion')" = "$ACMESH_AUTH_LEDGER_SCHEMA" ] && [ "$(acmesh_auth_json_get "$consuming" '@.instanceId')" = "$instance_id" ] && [ "$(acmesh_auth_json_get "$consuming" '@.ackVersion')" = "$ACMESH_AUTH_ACK_VERSION" ] && [ "$(acmesh_auth_json_get "$consuming" '@.challengeId')" = "$id" ] || { cleanup_consuming; return 4; }
	expires="$(acmesh_auth_json_get "$consuming" '@.expiresAt')"; case "$expires" in ''|*[!0-9]*) cleanup_consuming; return 4 ;; esac
	[ "$now" -lt "$expires" ] || { rm -f "$consuming"; trap - HUP INT TERM EXIT; printf '{"ok":false,"error":"authorizationExpired"}\n'; return 4; }
	operation="$(acmesh_auth_json_get "$consuming" '@.operation')"; subject_type="$(acmesh_auth_json_get "$consuming" '@.subjectType')"; subject_id="$(acmesh_auth_json_get "$consuming" '@.subjectId')"
	case "$operation:$decision" in import-apply:remember|certificate-revoke:remember|certificate-remove:remember|profile-delete:remember) rm -f "$consuming"; trap - HUP INT TERM EXIT; printf '{"ok":false,"error":"rememberNotAllowed"}\n'; return 2;; esac
	ACMESH_AUTH_EXECUTED_OPERATION="$operation" ACMESH_AUTH_EXECUTED_SUBJECT_TYPE="$subject_type" ACMESH_AUTH_EXECUTED_SUBJECT_ID="$subject_id"
	export ACMESH_AUTH_EXECUTED_OPERATION ACMESH_AUTH_EXECUTED_SUBJECT_TYPE ACMESH_AUTH_EXECUTED_SUBJECT_ID
	tmpdir="$ACMESH_AUTH_CHALLENGE_DIR/.recompute.$id"; acmesh_private_dir "$tmpdir" || return 1
	snapshot="$tmpdir/snapshot"; summary="$tmpdir/summary"
	if ! acmesh_auth_call_recompute "$operation" "$subject_type" "$subject_id" "$snapshot" "$summary"; then cleanup_consuming; return 1; fi
	acmesh_private_file_is_secure "$snapshot" && acmesh_private_file_is_secure "$summary" && [ "$(acmesh_auth_json_type "$summary" '@')" = object ] || { cleanup_consuming; return 1; }
	acmesh_auth_snapshot_identity_matches "$snapshot" "$operation" "$subject_type" "$subject_id" || { cleanup_consuming; return 1; }
	current="$(acmesh_auth_fingerprint "$snapshot")"; expected="$(acmesh_auth_json_get "$consuming" '@.fingerprint')"
	if [ "$current" != "$expected" ]; then
		rm -f "$consuming"; trap - HUP INT TERM EXIT
		rc=0
		acmesh_auth_create_challenge_locked "$operation" "$subject_type" "$subject_id" "$snapshot" "$summary" "$now" true || rc=$?
		rm -rf "$tmpdir"; [ "$rc" = 3 ]; return 5
	fi
	load_rc=0; acmesh_auth_ledger_load_locked || load_rc=$?; [ "$load_rc" = 0 ] || { cleanup_consuming; return 1; }
	if [ "$decision" = remember ] && ! acmesh_auth_rewrite_locked upsert '' "$operation" "$subject_type" "$subject_id" "$current" "$now"; then cleanup_consuming; return 1; fi
	ACMESH_OPERATION_FINGERPRINT="$current"; export ACMESH_OPERATION_FINGERPRINT
	acmesh_auth_admit "$operation" "$subject_type" "$subject_id" "$decision" || { cleanup_consuming; return 1; }
	cleanup_consuming
	[ "${ACMESH_OPERATION_DIRECT_RESPONSE:-0}" = 1 ] || printf '{"ok":true,"authorized":true,"remembered":%s,"taskId":"%s"}\n' "$([ "$decision" = remember ] && printf true || printf false)" "$(acmesh_json_escape "${ACMESH_OPERATION_TASK_ID:-}")"
}

acmesh_auth_execute() {
	[ "$#" = 2 ] && acmesh_auth_valid_id "$1" || return 2
	case "$2" in once|remember) ;; *) return 2 ;; esac
	acmesh_auth_lock_run acmesh_auth_execute_locked "$1" "$2" "$(acmesh_auth_now)"
}

acmesh_auth_list_locked() {
	load_rc=0; acmesh_auth_ledger_load_locked || load_rc=$?
	[ "$load_rc" = 0 ] || { printf '{"ok":true,"records":[]}\n'; return 0; }
	printf '{"ok":true,"records":['; i=0 first=1
	while [ "$(acmesh_auth_json_type "$ACMESH_AUTH_LEDGER_FILE" "@.records[$i]")" = object ]; do
		operation="$(acmesh_auth_json_get "$ACMESH_AUTH_LEDGER_FILE" "@.records[$i].operation")"; subject_type="$(acmesh_auth_json_get "$ACMESH_AUTH_LEDGER_FILE" "@.records[$i].subjectType")"; subject_id="$(acmesh_auth_json_get "$ACMESH_AUTH_LEDGER_FILE" "@.records[$i].subjectId")"; expected="$(acmesh_auth_json_get "$ACMESH_AUTH_LEDGER_FILE" "@.records[$i].fingerprint")"
		status=Unsupported; tmp="$ACMESH_AUTH_CHALLENGE_DIR/.list.$$.$i"; acmesh_private_dir "$tmp" || return 1
		if acmesh_auth_operation_supported "$operation"; then
			status=Stale
			if { acmesh_auth_call_recompute "$operation" "$subject_type" "$subject_id" "$tmp/snapshot" "$tmp/summary" && acmesh_auth_snapshot_identity_matches "$tmp/snapshot" "$operation" "$subject_type" "$subject_id"; } 2>/dev/null; then current="$(acmesh_auth_fingerprint "$tmp/snapshot" 2>/dev/null || true)"; [ "$current" != "$expected" ] || status=Active; fi
		fi
		rm -rf "$tmp"; [ "$first" = 1 ] || printf ','; first=0
		record="$(acmesh_auth_emit_record "$ACMESH_AUTH_LEDGER_FILE" "$i")"; printf '%s,"status":"%s"}' "${record%\}}" "$status"
		i=$((i + 1))
	done
	printf ']}\n'
}
acmesh_auth_list() { acmesh_auth_lock_run acmesh_auth_list_locked; }
acmesh_auth_revoke_locked() { acmesh_auth_ledger_load_locked || return 1; acmesh_auth_rewrite_locked revoke "$1"; }
acmesh_auth_revoke() { [ "$#" = 1 ] && acmesh_auth_valid_id "$1" || return 2; acmesh_auth_lock_run acmesh_auth_revoke_locked "$1"; }
acmesh_auth_revoke_all_locked() { acmesh_auth_ledger_load_locked || return 1; acmesh_auth_rewrite_locked all; }
acmesh_auth_revoke_all() { acmesh_auth_lock_run acmesh_auth_revoke_all_locked; }

acmesh_auth_prune_challenges_locked() {
	now="$1"; acmesh_private_dir "$ACMESH_AUTH_CHALLENGE_DIR" || return 1
	for path in "$ACMESH_AUTH_CHALLENGE_DIR"/*.json "$ACMESH_AUTH_CHALLENGE_DIR"/*.json.consuming; do
		[ -f "$path" ] && [ ! -L "$path" ] || continue
		base="${path##*/}"; printf '%s\n' "$base" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}\.json(\.consuming)?$' || continue
		case "$base" in *.consuming) created="$(acmesh_auth_json_get "$path" '@.createdAt')"; case "$created" in ''|*[!0-9]*) continue ;; esac; [ $((created + 600)) -gt "$now" ] || rm -f "$path" ;; *) expires="$(acmesh_auth_json_get "$path" '@.expiresAt')"; case "$expires" in ''|*[!0-9]*) continue ;; esac; [ "$expires" -gt "$now" ] || rm -f "$path" ;; esac
	done
}
acmesh_auth_prune_challenges() { now="${1:-$(acmesh_auth_now)}"; case "$now" in ''|*[!0-9]*) return 2 ;; esac; acmesh_auth_lock_run acmesh_auth_prune_challenges_locked "$now"; }
