. "${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}/json.sh"
. "${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}/io.sh"
. "${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}/profile.sh"

: "${ACMESH_CONSOLE_CONFIG:=/etc/acmesh-console/config.json}"
: "${ACMESH_CONSOLE_UCI_CONFIG:=/etc/config/acmesh-console}"
: "${ACMESH_PENDING_IMPORT_DIR:=/var/run/acmesh-console/pending-import}"
: "${ACMESH_CONFIG_LOCK_FILE:=${ACMESH_CONSOLE_CONFIG%/*}/config.lock}"
: "${ACMESH_CONFIG_SECRET_PLACEHOLDER:=********}"

acmesh_config_uci_option() {
	key="$1"
	[ -r "$ACMESH_CONSOLE_UCI_CONFIG" ] || return 1
	sed -n "s/^[	 ]*option[	 ][	 ]*$key[	 ][	 ]*['\"]\\([^'\"]*\\)['\"].*/\\1/p" "$ACMESH_CONSOLE_UCI_CONFIG" | head -n 1
}

acmesh_config_default_json() {
	home="$(acmesh_config_uci_option home || true)"
	email="$(acmesh_config_uci_option default_account_email || true)"
	core_tag="$(acmesh_config_uci_option core_tag || true)"
	[ -n "$home" ] || home="/etc/acme"
	[ -n "$core_tag" ] || core_tag="v3.1.4"
	printf '{"schemaVersion":2,"global":{"defaultAccountEmail":"%s","coreTag":"%s","acmeHome":"%s"},"accountProfiles":[],"issueProfiles":[],"deployProfiles":[]}\n' \
		"$(acmesh_json_escape "$email")" \
		"$(acmesh_json_escape "$core_tag")" \
		"$(acmesh_json_escape "$home")"
}

acmesh_config_path() {
	printf '%s\n' "$ACMESH_CONSOLE_CONFIG"
}

acmesh_config_find_profile_index() {
	path="$1" array="$2" wanted_id="$3" index=0
	jsonfilter -i "$path" -e "@.$array[*].id" 2>/dev/null | while IFS= read -r candidate; do
		if [ "$candidate" = "$wanted_id" ]; then printf '%s\n' "$index"; exit 0; fi
		index=$((index + 1))
	done
}

acmesh_config_redact_file() (
	set +u
	path="$1"; acmesh_profile_jshn || return 1; json_load_file "$path" || return 1
	json_select issueProfiles || return 1; json_get_keys indexes
	for index in $indexes; do
		json_select "$index" || return 1
		json_get_type credentials_type credentials 2>/dev/null || credentials_type=
		if [ "$credentials_type" = object ]; then
			json_select credentials || return 1; json_get_keys credential_keys
			for credential_key in $credential_keys; do json_add_string "$credential_key" "$ACMESH_CONFIG_SECRET_PLACEHOLDER"; done
			json_select ..
		fi
		json_select ..
	done
	json_select ..
	json_select deployProfiles || return 1; json_get_keys indexes
	for index in $indexes; do
		json_select "$index" || return 1
		for pem_key in keyPem fullchainPem; do
			json_get_var pem_value "$pem_key" 2>/dev/null || pem_value=
			[ -z "$pem_value" ] || json_add_string "$pem_key" "$ACMESH_CONFIG_SECRET_PLACEHOLDER"
		done
		json_select ..
	done
	json_select ..
	json_dump
)

acmesh_config_get() {
	path="$(acmesh_config_path)"
	if [ -s "$path" ]; then
		acmesh_config_validate_file "$path" || return 1
		acmesh_config_redact_file "$path"
	else
		acmesh_config_default_json
	fi
}

acmesh_config_materialize_secrets() (
	set +u
	request_file="$1" output="$2" current="$(acmesh_config_path)"
	acmesh_profile_jshn || return 1; json_load_file "$request_file" || return 2
	json_select issueProfiles || return 2; json_get_keys indexes
	for index in $indexes; do
		json_select "$index" || return 2; json_get_var profile_id id; json_get_var new_dns_api dnsApi; json_get_var new_credential_mode credentialMode
		acmesh_profile_validate_id "$profile_id" || return 2
		old_index="$(acmesh_config_find_profile_index "$current" issueProfiles "$profile_id")"
		json_get_type credentials_type credentials 2>/dev/null || credentials_type=
		if [ "$credentials_type" = object ]; then
			json_select credentials || return 2; json_get_keys credential_keys
			for credential_key in $credential_keys; do
				acmesh_profile_env_name "$credential_key" || return 2
				json_get_var credential_value "$credential_key"
				[ "$credential_value" = "$ACMESH_CONFIG_SECRET_PLACEHOLDER" ] || continue
				[ -n "$old_index" ] || return 2
				[ "$(jsonfilter -i "$current" -e "@.issueProfiles[$old_index].dnsApi" 2>/dev/null || true)" = "$new_dns_api" ] || return 2
				[ "$(jsonfilter -i "$current" -e "@.issueProfiles[$old_index].credentialMode" 2>/dev/null || true)" = "$new_credential_mode" ] || return 2
				[ "$(jsonfilter -i "$current" -t "@.issueProfiles[$old_index].credentials.$credential_key" 2>/dev/null || true)" = string ] || return 2
				old_value="$(jsonfilter -i "$current" -e "@.issueProfiles[$old_index].credentials.$credential_key")" || return 2
				json_add_string "$credential_key" "$old_value"
			done
			json_select ..
		fi
		json_select ..
	done
	json_select ..
	json_select deployProfiles || return 2; json_get_keys indexes
	for index in $indexes; do
		json_select "$index" || return 2; json_get_var profile_id id; json_get_var new_cert_source certSource
		acmesh_profile_validate_id "$profile_id" || return 2
		old_index="$(acmesh_config_find_profile_index "$current" deployProfiles "$profile_id")"
		for pem_key in keyPem fullchainPem; do
			json_get_var pem_value "$pem_key" 2>/dev/null || pem_value=
			[ "$pem_value" = "$ACMESH_CONFIG_SECRET_PLACEHOLDER" ] || continue
			[ -n "$old_index" ] || return 2
			[ "$new_cert_source" = paste-pem ] || return 2
			[ "$(jsonfilter -i "$current" -e "@.deployProfiles[$old_index].certSource" 2>/dev/null || true)" = paste-pem ] || return 2
			[ "$(jsonfilter -i "$current" -t "@.deployProfiles[$old_index].$pem_key" 2>/dev/null || true)" = string ] || return 2
			old_value="$(jsonfilter -i "$current" -e "@.deployProfiles[$old_index].$pem_key")" || return 2
			[ -n "$old_value" ] || return 2
			json_add_string "$pem_key" "$old_value"
		done
		json_select ..
	done
	json_select ..
	json_dump | acmesh_atomic_write "$output" 600
)

acmesh_config_save_file_locked() (
	set +u
	request_file="$1"; materialized="${request_file}.materialized.$$"
	trap 'rm -f "$materialized"' HUP INT TERM EXIT
	if ! acmesh_config_materialize_secrets "$request_file" "$materialized" || ! acmesh_config_validate_file "$materialized"; then
		printf '{"ok":false,"error":"configuration schema validation failed"}\n'
		return 2
	fi
	request_file="$materialized"
	path="$(acmesh_config_path)"
	if [ -f "$path" ] && acmesh_config_validate_file "$path"; then
		for array in accountProfiles issueProfiles deployProfiles; do
			for existing_id in $(jsonfilter -i "$path" -e "@.$array[*].id" 2>/dev/null || true); do
				jsonfilter -i "$request_file" -e "@.$array[*].id" 2>/dev/null | grep -Fx "$existing_id" >/dev/null || {
					printf '{"ok":false,"error":"profile deletion requires profile-delete authorization","profileId":"%s"}\n' "$(acmesh_json_escape "$existing_id")"
					return 4
				}
			done
		done
	fi
	acmesh_profile_jshn || return 1
	json_load_file "$request_file" || return 1
	json_get_type version_type schemaVersion 2>/dev/null || version_type=
	[ -n "$version_type" ] || json_add_int schemaVersion 2
	json_dump | acmesh_atomic_write "$path" 600 || {
		printf '{"ok":false,"error":"configuration save failed"}\n'
		return 1
	}
	printf '{"ok":true,"path":"%s"}\n' "$(acmesh_json_escape "$path")"
	rm -f "$materialized"; trap - HUP INT TERM EXIT
)

acmesh_config_save_file() ( acmesh_lock_run "$ACMESH_CONFIG_LOCK_FILE" acmesh_config_save_file_locked "$1"; )

acmesh_config_import_preview() {
	request_file="$1"
	[ "$(jsonfilter -i "$request_file" -t '@.archiveBase64' 2>/dev/null || true)" = string ] || {
		printf '{"ok":false,"error":"migration archive required"}\n'
		return 2
	}
	acmesh_migration_import_preview "$request_file"
}

acmesh_config_pending_candidate() {
	digest="$1" output="$2"; [ "${#digest}" = 64 ] || return 2; case "$digest" in *[!0-9a-f]*) return 2;; esac
	if [ -f "$ACMESH_PENDING_IMPORT_DIR/$digest.tar.gz" ]; then
		pending="$ACMESH_PENDING_IMPORT_DIR/$digest.tar.gz"
		[ ! -L "$pending" ] && acmesh_private_file_is_secure "$pending" || return 1
		[ "$(sha256sum "$pending" | awk '{print $1}')" = "$digest" ] || return 1
		acmesh_migration_archive_candidate "$pending" "$output"
		return $?
	fi
	return 1
}

acmesh_config_apply_pending_locked() (
	digest="$1"; tmp="$ACMESH_PENDING_IMPORT_DIR/.apply.$$.config"
	trap 'rm -f "$tmp"' HUP INT TERM EXIT
	if [ -f "$ACMESH_PENDING_IMPORT_DIR/$digest.tar.gz" ]; then
		acmesh_migration_install_archive "$ACMESH_PENDING_IMPORT_DIR/$digest.tar.gz" || return 1
		return 0
	fi
	return 1
)

acmesh_config_apply_pending() ( acmesh_lock_run "$ACMESH_CONFIG_LOCK_FILE" acmesh_config_apply_pending_locked "$1"; )

acmesh_config_profile_dependencies() (
	set +u
	kind="$1" id="$2" path="$(acmesh_config_path)"; deps=; acmesh_profile_jshn || return 1; json_load_file "$path" || return 1
	case "$kind" in account) reference_field=accountProfileId;; deploy) reference_field=deployProfileId;; issue) reference_field=;; *) return 2;; esac
	if [ -n "$reference_field" ]; then
		json_select issueProfiles; json_get_keys indexes
		for index in $indexes; do
			json_select "$index"; json_get_var reference "$reference_field"; json_get_var dependent_id id
			[ "$reference" != "$id" ] || deps="${deps}${deps:+,}\"issueProfile:$(acmesh_json_escape "$dependent_id")\""
			json_select ..
		done
	fi
	printf '[%s]\n' "$deps"
)

acmesh_config_profile_exists() {
	kind="$1" id="$2" path="$(acmesh_config_path)"
	case "$kind" in account) array=accountProfiles;; issue) array=issueProfiles;; deploy) array=deployProfiles;; *) return 2;; esac
	jsonfilter -i "$path" -e "@.$array[*].id" 2>/dev/null | grep -Fx "$id" >/dev/null
}

acmesh_config_delete_profile_locked() (
	set +u
	kind="$1" id="$2" expected="$3" path="$(acmesh_config_path)"; [ "$(sha256sum "$path" | awk '{print $1}')" = "$expected" ] || return 5; acmesh_config_validate_file "$path" || return 1; acmesh_config_profile_exists "$kind" "$id" || return 2
	dependencies="$(acmesh_config_profile_dependencies "$kind" "$id")"; [ "$dependencies" = '[]' ] || { printf '{"ok":false,"error":"profileReferenced","dependencies":%s}\n' "$dependencies"; return 4; }
	case "$kind" in account) target=accountProfiles;; issue) target=issueProfiles;; deploy) target=deployProfiles;; esac
	tmpdir="${path%/*}/.profile-delete.$$"; acmesh_private_dir "$tmpdir" || return 1; trap 'rm -rf "$tmpdir"' HUP INT TERM EXIT
	global="$(jsonfilter -i "$path" -e '@.global')" || return 1
	for array in accountProfiles issueProfiles deployProfiles; do
		: > "$tmpdir/$array"; first=1
		jsonfilter -i "$path" -e "@.$array[*]" 2>/dev/null | while IFS= read -r object; do
			[ -n "$object" ] || continue
			printf '%s\n' "$object" > "$tmpdir/object"; object_id="$(jsonfilter -i "$tmpdir/object" -e '@.id')"
			if [ "$array" = "$target" ] && [ "$object_id" = "$id" ]; then continue; fi
			[ "$first" = 1 ] || printf ',' >> "$tmpdir/$array"; printf '%s' "$object" >> "$tmpdir/$array"; first=0
		done
	done
	printf '{"schemaVersion":2,"global":%s,"accountProfiles":[' "$global" > "$tmpdir/config"
	cat "$tmpdir/accountProfiles" >> "$tmpdir/config"; printf '],"issueProfiles":[' >> "$tmpdir/config"; cat "$tmpdir/issueProfiles" >> "$tmpdir/config"
	printf '],"deployProfiles":[' >> "$tmpdir/config"; cat "$tmpdir/deployProfiles" >> "$tmpdir/config"; printf ']}\n' >> "$tmpdir/config"
	acmesh_config_validate_file "$tmpdir/config" || return 1
	cat "$tmpdir/config" | acmesh_atomic_write "$path" 600 || return 1
	rm -rf "$tmpdir"; trap - HUP INT TERM EXIT
	printf '{"ok":true,"deleted":true,"profileType":"%s","profileId":"%s"}\n' "$kind" "$(acmesh_json_escape "$id")"
)

acmesh_config_delete_profile() ( acmesh_lock_run "$ACMESH_CONFIG_LOCK_FILE" acmesh_config_delete_profile_locked "$1" "$2" "$3"; )

acmesh_config_bool() {
	key="$1"
	default="$2"
	value="$(acmesh_config_get | jsonfilter -e "@.global.$key" 2>/dev/null || true)"
	[ -n "$value" ] && printf '%s\n' "$value" || printf '%s\n' "$default"
}

acmesh_config_string() {
	key="$1"
	default="$2"
	value="$(acmesh_config_get | jsonfilter -e "@.global.$key" 2>/dev/null || true)"
	[ -n "$value" ] && printf '%s\n' "$value" || printf '%s\n' "$default"
}
