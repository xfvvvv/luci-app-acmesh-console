. "${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}/json.sh"
. "${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}/io.sh"
. "${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}/dns.sh"

acmesh_profile_jshn() { command -v jsonfilter >/dev/null 2>&1 && [ -r /usr/share/libubox/jshn.sh ] || return 1; JSON_PREFIX=; JSON_UNSET=; JSON_SEQ=; JSON_CUR=; . /usr/share/libubox/jshn.sh; }
acmesh_profile_validate_id() { printf '%s\n' "${1:-}" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$'; }
acmesh_profile_allowed_keys() { allowed=" $1 "; shift; for candidate in "$@"; do case "$allowed" in *" $candidate "*) ;; *) return 1;; esac; done; }
acmesh_profile_type() { json_get_type _type "$1" 2>/dev/null || _type=; [ "$_type" = "$2" ]; }
acmesh_profile_string() { key="$1" required="${2:-0}"; json_get_type _type "$key" 2>/dev/null || _type=; [ -z "$_type" ] && [ "$required" = 0 ] && return 0; [ "$_type" = string ] || return 1; json_get_var _value "$key"; [ "$required" = 0 ] || [ -n "$_value" ]; }
acmesh_profile_key_type() { case "$1" in ec256|ec384|ec521|rsa2048|rsa3072|rsa4096|rsa8192) return 0;; *) return 1;; esac; }
acmesh_profile_abs_path() { case "$1" in /*) [ "$1" != / ];; *) return 1;; esac; }
acmesh_profile_single_line() { case "$1" in *"$(printf '\r')"*|*'
'*|*'\n'*|*'\r'*|*'\u0000'*) return 1;; esac; }
acmesh_profile_domain() { acmesh_profile_single_line "$1" && printf '%s\n' "$1" | grep -Eq '^\*?\.?[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$' && case "$1" in *..*|.*|*.) return 1;; esac; }
acmesh_profile_env_name() { printf '%s\n' "$1" | grep -Eq '^[A-Za-z_][A-Za-z0-9_]*$' || return 1; case "$1" in PATH|ENV|BASH_ENV|IFS|CDPATH|LD_*) return 1;; esac; }
acmesh_profile_port() { case "$1" in *[!0-9]*|'') return 1;; esac; [ "$1" -ge 1 ] && [ "$1" -le 65535 ]; }
acmesh_profile_identity() { [ -z "$1" ] || { acmesh_profile_single_line "$1" && printf '%s\n' "$1" | grep -Eq '^[A-Za-z_][A-Za-z0-9_.-]*$'; }; }
acmesh_profile_file_mode() { [ -z "$1" ] || { acmesh_profile_single_line "$1" || return 1; case "$1" in [0-7][0-7][0-7]|0[0-7][0-7][0-7]) return 0;; *) return 1;; esac; }; }

acmesh_profile_install_cleanup_traps() {
	ACMESH_RESOLVED_CLEANUP_FILE="$1"
	trap 'rm -f -- "$ACMESH_RESOLVED_CLEANUP_FILE"' EXIT
	# BusyBox ash does not reliably run the EXIT trap after exiting from a
	# signal trap, so remove the resolved secret snapshot in each signal path.
	trap 'rm -f -- "$ACMESH_RESOLVED_CLEANUP_FILE"; exit 129' HUP
	trap 'rm -f -- "$ACMESH_RESOLVED_CLEANUP_FILE"; exit 130' INT
	trap 'rm -f -- "$ACMESH_RESOLVED_CLEANUP_FILE"; exit 143' TERM
}

acmesh_profile_validate_global() {
	json_select global || return 1; json_get_keys keys
	# testMode is accepted only as a no-op migration field for existing schema-2 files.
	acmesh_profile_allowed_keys 'defaultAccountEmail testMode coreTag acmeHome' $keys || return 1
	acmesh_profile_string defaultAccountEmail || return 1; acmesh_profile_string coreTag 1 || return 1; acmesh_profile_string acmeHome 1 || return 1
	json_get_var home acmeHome; acmesh_profile_abs_path "$home" || return 1; json_get_type legacy_test_type testMode 2>/dev/null || legacy_test_type=; [ -z "$legacy_test_type" ] || [ "$legacy_test_type" = boolean ] || return 1; json_select ..
}

acmesh_profile_validate_accounts() {
	ids=' '; json_select accountProfiles || return 1; json_get_keys indexes
	for index in $indexes; do json_select "$index" || return 1; json_get_keys keys; acmesh_profile_allowed_keys 'id name ca accountEmail' $keys || return 1; acmesh_profile_string id 1 || return 1; json_get_var id id; acmesh_profile_validate_id "$id" || return 1; case "$ids" in *" $id "*) return 1;; esac; ids="$ids$id "; acmesh_profile_string name || return 1; acmesh_profile_string accountEmail || return 1; acmesh_profile_string ca 1 || return 1; json_get_var ca ca; case "$ca" in letsencrypt|letsencrypt_staging|zerossl|google) ;; *) return 1;; esac; json_select ..; done
	ACMESH_ACCOUNT_IDS="$ids"; json_select ..
}

acmesh_profile_dns_credentials_valid() {
	dns="$1"; mode="$2"; json_get_type ctype credentials 2>/dev/null || ctype=; [ "$ctype" = object ] || return 1; json_select credentials || return 1; json_get_keys credential_keys
	credentials=
	for key in $credential_keys; do
		acmesh_profile_env_name "$key" || return 1; acmesh_profile_string "$key" || return 1; json_get_var value "$key"
		case "$value" in *"$(printf '\r')"*|*'
'*|*'\n'*|*'\r'*|*'\u0000'*) return 1;; esac
		credentials="${credentials}${credentials:+
}$key=$value"
	done
	json_select ..
	acmesh_dns_credential_mode_valid "$dns" "$mode" || return 1
	acmesh_dns_validate_mode_credentials "$dns" "$mode" "$credentials"
}

acmesh_profile_validate_deploys() {
	ids=' '; json_select deployProfiles || return 1; json_get_keys indexes
	for index in $indexes; do
		json_select "$index" || return 1; json_get_keys keys; acmesh_profile_allowed_keys 'id name type certSource domain keyType host user port sshKey sourceKeyFile sourceFullchainFile keyPem fullchainPem keyFile fullchainFile certFile caFile reloadcmd sudoMode owner group mode preserveMetadata' $keys || return 1
		acmesh_profile_string id 1 || return 1; json_get_var id id; acmesh_profile_validate_id "$id" || return 1; case "$ids" in *" $id "*) return 1;; esac; ids="$ids$id "
		for key in name domain host user port sshKey sourceKeyFile sourceFullchainFile keyPem fullchainPem keyFile fullchainFile certFile caFile reloadcmd sudoMode owner group mode; do acmesh_profile_string "$key" || return 1; done
		acmesh_profile_string type 1 || return 1; json_get_var type type; case "$type" in local|ssh) ;; *) return 1;; esac
		acmesh_profile_string certSource 1 || return 1; json_get_var source certSource; case "$source" in managed-acme|local-files|paste-pem) ;; *) return 1;; esac
		json_get_var key_type keyType; [ -z "$key_type" ] || acmesh_profile_key_type "$key_type" || return 1
		json_get_var port port; [ -z "$port" ] && port=22; case "$port" in *[!0-9]*|'') return 1;; esac; [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || return 1
		json_get_var sudo_mode sudoMode; case "$sudo_mode" in ''|auto|always|never) ;; *) return 1;; esac
		json_get_var owner owner; json_get_var group group; json_get_var mode mode; acmesh_profile_identity "$owner" || return 1; acmesh_profile_identity "$group" || return 1; acmesh_profile_file_mode "$mode" || return 1
		json_get_type preserve_metadata_type preserveMetadata 2>/dev/null || preserve_metadata_type=; [ -z "$preserve_metadata_type" ] || [ "$preserve_metadata_type" = boolean ] || return 1
		for path_key in keyFile fullchainFile certFile caFile sshKey sourceKeyFile sourceFullchainFile; do json_get_var path "$path_key"; [ -z "$path" ] || acmesh_profile_abs_path "$path" || return 1; done
		json_get_var key_file keyFile; json_get_var chain_file fullchainFile; [ -n "$key_file" ] && [ -n "$chain_file" ] || return 1
		json_get_var domain domain; json_get_var sourceKeyFile sourceKeyFile; json_get_var sourceFullchainFile sourceFullchainFile; json_get_var keyPem keyPem; json_get_var fullchainPem fullchainPem; json_get_var host host; json_get_var user user; json_get_var ssh_key sshKey; json_get_var cert_file certFile; json_get_var ca_file caFile; json_select ..
		case "$source" in
			managed-acme) [ -n "$domain" ] && [ -z "$sourceKeyFile$sourceFullchainFile$keyPem$fullchainPem" ] || return 1 ;;
			local-files) [ -n "$sourceKeyFile" ] && [ -n "$sourceFullchainFile" ] && [ -z "$domain$key_type$keyPem$fullchainPem$cert_file$ca_file" ] || return 1 ;;
			paste-pem) [ -n "$keyPem" ] && [ -n "$fullchainPem" ] && [ -z "$domain$key_type$sourceKeyFile$sourceFullchainFile$cert_file$ca_file" ] || return 1 ;;
		esac
		case "$type" in local) [ -z "$host$user$ssh_key" ] && [ "$port" = 22 ] && [ -z "$sudo_mode" ] || return 1;; ssh) [ -n "$host" ] && [ -n "$ssh_key" ] && [ -z "$cert_file$ca_file" ] || return 1;; esac
	done
	ACMESH_DEPLOY_IDS="$ids"; json_select ..
}

acmesh_profile_validate_issues() {
	ids=' '; json_select issueProfiles || return 1; json_get_keys indexes
	for index in $indexes; do
		json_select "$index" || return 1; json_get_keys keys; acmesh_profile_allowed_keys 'id name domain domains accountProfileId deployProfileId keyType validationMethod testModeOverride dnsApi credentialMode credentials challengeAlias dnsSleep webroot listenPort' $keys || return 1
		acmesh_profile_string id 1 || return 1; json_get_var id id; acmesh_profile_validate_id "$id" || return 1; case "$ids" in *" $id "*) return 1;; esac; ids="$ids$id "
		for key in name deployProfileId dnsApi credentialMode challengeAlias webroot listenPort; do acmesh_profile_string "$key" || return 1; done
		acmesh_profile_string domain 1 || return 1; acmesh_profile_string accountProfileId 1 || return 1; json_get_var account accountProfileId; case "$ACMESH_ACCOUNT_IDS" in *" $account "*) ;; *) return 1;; esac
		json_get_var deploy deployProfileId; if [ -n "$deploy" ]; then case "$ACMESH_DEPLOY_IDS" in *" $deploy "*) ;; *) return 1;; esac; fi
		acmesh_profile_string keyType 1 || return 1; json_get_var key_type keyType; acmesh_profile_key_type "$key_type" || return 1
		acmesh_profile_string validationMethod 1 || return 1; json_get_var validation validationMethod; case "$validation" in dns|webroot|standalone|alpn) ;; *) return 1;; esac
		acmesh_profile_string testModeOverride 1 || return 1; json_get_var policy testModeOverride; case "$policy" in inherit-global-test-mode|force-test-mode|force-real-mode) ;; *) return 1;; esac
		json_get_var domain domain; acmesh_profile_domain "$domain" || return 1
		json_get_type domains_type domains 2>/dev/null || domains_type=; [ -z "$domains_type" ] || [ "$domains_type" = array ] || return 1
		if [ "$domains_type" = array ]; then json_select domains; json_get_keys domain_indexes; [ -n "$domain_indexes" ] || return 1; seen=' '; first=; for domain_index in $domain_indexes; do json_get_type item_type "$domain_index"; [ "$item_type" = string ] || return 1; json_get_var item "$domain_index"; [ -n "$first" ] || first="$item"; acmesh_profile_domain "$item" || return 1; case "$seen" in *" $item "*) return 1;; esac; seen="$seen$item "; done; [ "$first" = "$domain" ] || return 1; json_select ..; fi
		json_get_type sleep_type dnsSleep 2>/dev/null || sleep_type=; [ -z "$sleep_type" ] || [ "$sleep_type" = int ] || return 1; json_get_var sleep_value dnsSleep; [ -z "$sleep_value" ] || [ "$sleep_value" -ge 0 ] || return 1
		json_get_var dns dnsApi; json_get_var credential_mode credentialMode; json_get_var webroot webroot; json_get_var listen_port listenPort; json_get_var alias challengeAlias
		case "$validation" in
			dns) acmesh_profile_string dnsApi 1 || return 1; printf '%s\n' "$dns" | grep -Eq '^dns_[A-Za-z0-9_]+$' || return 1; acmesh_profile_string credentialMode 1 || return 1; [ -z "$webroot$listen_port" ] || return 1; acmesh_profile_dns_credentials_valid "$dns" "$credential_mode" || return 1 ;;
			webroot) [ -z "$dns$credential_mode$listen_port$alias$sleep_value" ] || return 1; acmesh_profile_abs_path "$webroot" || return 1; json_get_type ctype credentials 2>/dev/null && return 1 || : ;;
			standalone|alpn) [ -z "$dns$credential_mode$webroot$alias$sleep_value" ] || return 1; [ -z "$listen_port" ] || acmesh_profile_port "$listen_port" || return 1; json_get_type ctype credentials 2>/dev/null && return 1 || : ;;
		esac
		json_select ..
	done
	json_select ..
}

acmesh_config_validate_file() (
	set +u
	path="${1:-}"; [ -f "$path" ] && [ ! -L "$path" ] || return 1; acmesh_profile_jshn || return 1
	jsonfilter -i "$path" -e '@' >/dev/null 2>&1 || return 1
	[ "$(jsonfilter -i "$path" -t '@.global' 2>/dev/null)" = object ] || return 1; [ "$(jsonfilter -i "$path" -t '@.accountProfiles' 2>/dev/null)" = array ] || return 1; [ "$(jsonfilter -i "$path" -t '@.issueProfiles' 2>/dev/null)" = array ] || return 1; [ "$(jsonfilter -i "$path" -t '@.deployProfiles' 2>/dev/null)" = array ] || return 1
	json_load_file "$path" >/dev/null 2>&1 || return 1; json_get_keys keys; acmesh_profile_allowed_keys 'schemaVersion global accountProfiles issueProfiles deployProfiles' $keys || return 1
	json_get_type vtype schemaVersion 2>/dev/null || vtype=; case "$vtype" in '') ;; int) json_get_var version schemaVersion; [ "$version" = 2 ] || return 1;; *) return 1;; esac
	acmesh_profile_validate_global && acmesh_profile_validate_accounts && acmesh_profile_validate_deploys && acmesh_profile_validate_issues
)

acmesh_profile_extract() (
	set +u
	kind="$1" id="$2" output="$3"; acmesh_profile_validate_id "$id" || return 2; acmesh_config_validate_file "$ACMESH_CONSOLE_CONFIG" || return 1; acmesh_profile_jshn || return 1
	case "$kind" in account) array=accountProfiles;; issue) array=issueProfiles;; deploy) array=deployProfiles;; *) return 2;; esac
	json_load_file "$ACMESH_CONSOLE_CONFIG" || return 1; json_select "$array"; json_get_keys indexes; found=
	for index in $indexes; do json_select "$index"; json_get_var candidate id; if [ "$candidate" = "$id" ]; then [ -z "$found" ] || return 1; found="$index"; fi; json_select ..; done
	[ -n "$found" ] || return 1; json_index=$((found - 1)); jsonfilter -i "$ACMESH_CONSOLE_CONFIG" -e "@.$array[$json_index]" | acmesh_atomic_write "$output" 600
)

acmesh_profile_resolve_issue() (
	set +u
	id="$1" output="$2"; acmesh_profile_validate_id "$id" || return 2; acmesh_config_validate_file "$ACMESH_CONSOLE_CONFIG" || return 1; acmesh_profile_jshn || return 1; json_load_file "$ACMESH_CONSOLE_CONFIG" || return 1
	json_select global; json_get_var default_email defaultAccountEmail; json_select ..
	json_select issueProfiles; json_get_keys indexes; found=; for index in $indexes; do json_select "$index"; json_get_var candidate id; [ "$candidate" = "$id" ] && found="$index"; json_select ..; done; [ -n "$found" ] || return 1
	json_select "$found"; json_get_var account_id accountProfileId; json_get_var domain domain; json_get_var key_type keyType; json_get_var validation validationMethod; json_get_var dns dnsApi || dns=; json_get_var credential_mode credentialMode || credential_mode=; json_get_var alias challengeAlias || alias=; json_get_var sleep_value dnsSleep || sleep_value=; json_get_var webroot webroot || webroot=; json_get_var listen_port listenPort || listen_port=; json_get_var deploy_id deployProfileId || deploy_id=; json_get_var policy testModeOverride; json_select ..; json_select ..
	account_email="$default_email"; ca=letsencrypt; json_select accountProfiles; json_get_keys indexes; for index in $indexes; do json_select "$index"; json_get_var candidate id; if [ "$candidate" = "$account_id" ]; then json_get_var overlay accountEmail || overlay=; json_get_var ca ca; [ -z "$overlay" ] || account_email="$overlay"; fi; json_select ..; done
	case "$policy" in
		force-test-mode) test_mode=true ;;
		force-real-mode) test_mode=false ;;
		inherit-global-test-mode) test_mode=false ;;
		*) return 1 ;;
	esac
	[ -n "$sleep_value" ] || sleep_value=0
	json_index=$((found - 1)); cred_json="$(jsonfilter -i "$ACMESH_CONSOLE_CONFIG" -e "@.issueProfiles[$json_index].credentials" 2>/dev/null || true)"; [ -n "$cred_json" ] || cred_json='{}'
	domains_json="$(jsonfilter -i "$ACMESH_CONSOLE_CONFIG" -e "@.issueProfiles[$json_index].domains" 2>/dev/null || true)"; [ -n "$domains_json" ] || domains_json="[\"$(acmesh_json_escape "$domain")\"]"
	printf '{"id":"%s","accountId":"%s","accountEmail":"%s","ca":"%s","domains":%s,"keyType":"%s","validationMethod":"%s","dnsApi":"%s","credentialMode":"%s","challengeAlias":"%s","dnsSleep":%s,"webroot":"%s","listenPort":"%s","deployProfileId":"%s","testMode":%s,"credentials":%s}\n' "$(acmesh_json_escape "$id")" "$(acmesh_json_escape "$account_id")" "$(acmesh_json_escape "$account_email")" "$(acmesh_json_escape "$ca")" "$domains_json" "$(acmesh_json_escape "$key_type")" "$(acmesh_json_escape "$validation")" "$(acmesh_json_escape "$dns")" "$(acmesh_json_escape "$credential_mode")" "$(acmesh_json_escape "$alias")" "$sleep_value" "$(acmesh_json_escape "$webroot")" "$(acmesh_json_escape "$listen_port")" "$(acmesh_json_escape "$deploy_id")" "$test_mode" "$cred_json" | acmesh_atomic_write "$output" 600
)

acmesh_profile_resolve_deploy() (
	set +u
	id="$1" output="$2"; tmp="${output}.profile.$$"; trap 'rm -f "$tmp"' EXIT; trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM; acmesh_profile_extract deploy "$id" "$tmp" || return $?
	type="$(jsonfilter -i "$tmp" -e '@.type')"; source="$(jsonfilter -i "$tmp" -e '@.certSource')"
	domain="$(jsonfilter -i "$tmp" -e '@.domain' 2>/dev/null || true)"; key_type="$(jsonfilter -i "$tmp" -e '@.keyType' 2>/dev/null || true)"
	host="$(jsonfilter -i "$tmp" -e '@.host' 2>/dev/null || true)"; user="$(jsonfilter -i "$tmp" -e '@.user' 2>/dev/null || true)"; port="$(jsonfilter -i "$tmp" -e '@.port' 2>/dev/null || true)"; ssh_key="$(jsonfilter -i "$tmp" -e '@.sshKey' 2>/dev/null || true)"
	source_key="$(jsonfilter -i "$tmp" -e '@.sourceKeyFile' 2>/dev/null || true)"; source_chain="$(jsonfilter -i "$tmp" -e '@.sourceFullchainFile' 2>/dev/null || true)"
	key_pem="$(jsonfilter -i "$tmp" -e '@.keyPem' 2>/dev/null || true)"; chain_pem="$(jsonfilter -i "$tmp" -e '@.fullchainPem' 2>/dev/null || true)"
	key_file="$(jsonfilter -i "$tmp" -e '@.keyFile')"; chain_file="$(jsonfilter -i "$tmp" -e '@.fullchainFile')"
	cert_file="$(jsonfilter -i "$tmp" -e '@.certFile' 2>/dev/null || true)"; ca_file="$(jsonfilter -i "$tmp" -e '@.caFile' 2>/dev/null || true)"
	reload="$(jsonfilter -i "$tmp" -e '@.reloadcmd' 2>/dev/null || true)"; sudo_mode="$(jsonfilter -i "$tmp" -e '@.sudoMode' 2>/dev/null || true)"
	owner="$(jsonfilter -i "$tmp" -e '@.owner' 2>/dev/null || true)"; group="$(jsonfilter -i "$tmp" -e '@.group' 2>/dev/null || true)"; mode="$(jsonfilter -i "$tmp" -e '@.mode' 2>/dev/null || true)"; preserve_metadata="$(jsonfilter -i "$tmp" -e '@.preserveMetadata' 2>/dev/null || true)"
	[ "$preserve_metadata" = true ] || preserve_metadata=false
	digest="$(sha256sum "$ACMESH_CONSOLE_CONFIG" | awk '{print $1}')"; rm -f "$tmp"
	printf '{"id":"%s","source":{"config":"%s","digest":"%s","certSource":"%s","domain":"%s","keyType":"%s","keyFile":"%s","fullchainFile":"%s","keyPem":"%s","fullchainPem":"%s"},"target":{"type":"%s","host":"%s","port":%s,"user":"%s","sshKey":"%s","sudoMode":"%s"},"destinations":{"keyFile":"%s","fullchainFile":"%s","certFile":"%s","caFile":"%s","owner":"%s","group":"%s","mode":"%s","preserveMetadata":%s},"reloadCommand":"%s"}\n' \
		"$(acmesh_json_escape "$id")" "$(acmesh_json_escape "$ACMESH_CONSOLE_CONFIG")" "$digest" "$(acmesh_json_escape "$source")" "$(acmesh_json_escape "$domain")" "$(acmesh_json_escape "$key_type")" "$(acmesh_json_escape "$source_key")" "$(acmesh_json_escape "$source_chain")" "$(acmesh_json_escape "$key_pem")" "$(acmesh_json_escape "$chain_pem")" \
		"$(acmesh_json_escape "$type")" "$(acmesh_json_escape "$host")" "${port:-22}" "$(acmesh_json_escape "$user")" "$(acmesh_json_escape "$ssh_key")" "$(acmesh_json_escape "$sudo_mode")" \
		"$(acmesh_json_escape "$key_file")" "$(acmesh_json_escape "$chain_file")" "$(acmesh_json_escape "$cert_file")" "$(acmesh_json_escape "$ca_file")" "$(acmesh_json_escape "$owner")" "$(acmesh_json_escape "$group")" "$(acmesh_json_escape "$mode")" "$preserve_metadata" "$(acmesh_json_escape "$reload")" | acmesh_atomic_write "$output" 600
)

acmesh_profile_load_deploy_file() {
	path="$1"
	ACMESH_DEPLOY_TYPE="$(jsonfilter -i "$path" -e '@.target.type')" || return 1
	ACMESH_DEPLOY_CERT_SOURCE="$(jsonfilter -i "$path" -e '@.source.certSource')" || return 1
	ACMESH_DEPLOY_DOMAIN="$(jsonfilter -i "$path" -e '@.source.domain' 2>/dev/null || true)"
	ACMESH_DEPLOY_KEY_TYPE="$(jsonfilter -i "$path" -e '@.source.keyType' 2>/dev/null || true)"
	ACMESH_DEPLOY_SOURCE_KEY="$(jsonfilter -i "$path" -e '@.source.keyFile' 2>/dev/null || true)"
	ACMESH_DEPLOY_SOURCE_CHAIN="$(jsonfilter -i "$path" -e '@.source.fullchainFile' 2>/dev/null || true)"
	ACMESH_DEPLOY_KEY_PEM="$(jsonfilter -i "$path" -e '@.source.keyPem' 2>/dev/null || true)"
	ACMESH_DEPLOY_CHAIN_PEM="$(jsonfilter -i "$path" -e '@.source.fullchainPem' 2>/dev/null || true)"
	ACMESH_DEPLOY_HOST="$(jsonfilter -i "$path" -e '@.target.host' 2>/dev/null || true)"; ACMESH_DEPLOY_PORT="$(jsonfilter -i "$path" -e '@.target.port')"
	ACMESH_DEPLOY_USER="$(jsonfilter -i "$path" -e '@.target.user' 2>/dev/null || true)"; ACMESH_DEPLOY_SSH_KEY="$(jsonfilter -i "$path" -e '@.target.sshKey' 2>/dev/null || true)"
	ACMESH_DEPLOY_KEY_FILE="$(jsonfilter -i "$path" -e '@.destinations.keyFile')" || return 1; ACMESH_DEPLOY_CHAIN_FILE="$(jsonfilter -i "$path" -e '@.destinations.fullchainFile')" || return 1
	ACMESH_DEPLOY_CERT_FILE="$(jsonfilter -i "$path" -e '@.destinations.certFile' 2>/dev/null || true)"; ACMESH_DEPLOY_CA_FILE="$(jsonfilter -i "$path" -e '@.destinations.caFile' 2>/dev/null || true)"
	ACMESH_DEPLOY_RELOAD="$(jsonfilter -i "$path" -e '@.reloadCommand' 2>/dev/null || true)"
	ACMESH_DEPLOY_SUDO_MODE="$(jsonfilter -i "$path" -e '@.target.sudoMode' 2>/dev/null || true)"
	ACMESH_DEPLOY_OWNER="$(jsonfilter -i "$path" -e '@.destinations.owner' 2>/dev/null || true)"
	ACMESH_DEPLOY_GROUP="$(jsonfilter -i "$path" -e '@.destinations.group' 2>/dev/null || true)"
	ACMESH_DEPLOY_MODE="$(jsonfilter -i "$path" -e '@.destinations.mode' 2>/dev/null || true)"
	ACMESH_DEPLOY_PRESERVE_METADATA="$(jsonfilter -i "$path" -e '@.destinations.preserveMetadata' 2>/dev/null || true)"
	[ "$ACMESH_DEPLOY_PRESERVE_METADATA" = true ] || ACMESH_DEPLOY_PRESERVE_METADATA=false
}

acmesh_profile_load_issue_file() {
	set +u
	path="$1"; acmesh_profile_jshn || return 1; json_load_file "$path" || return 1
	json_get_var ACMESH_PROFILE_ACCOUNT_EMAIL accountEmail
	json_get_var ACMESH_PROFILE_CA ca
	json_get_var ACMESH_PROFILE_KEY_TYPE keyType
	json_get_var ACMESH_PROFILE_VALIDATION validationMethod
	json_get_var ACMESH_PROFILE_DNS_API dnsApi || ACMESH_PROFILE_DNS_API=
	json_get_var ACMESH_PROFILE_CREDENTIAL_MODE credentialMode || ACMESH_PROFILE_CREDENTIAL_MODE=
	json_get_var ACMESH_PROFILE_TEST_MODE testMode
	case "$ACMESH_PROFILE_TEST_MODE" in 1|true) ACMESH_PROFILE_TEST_MODE=true;; *) ACMESH_PROFILE_TEST_MODE=false;; esac
	json_get_var ACMESH_PROFILE_WEBROOT webroot || ACMESH_PROFILE_WEBROOT=
	json_get_var ACMESH_PROFILE_LISTEN_PORT listenPort || ACMESH_PROFILE_LISTEN_PORT=
	json_get_var ACMESH_PROFILE_CHALLENGE_ALIAS challengeAlias || ACMESH_PROFILE_CHALLENGE_ALIAS=
	json_get_var ACMESH_PROFILE_DNS_SLEEP dnsSleep || ACMESH_PROFILE_DNS_SLEEP=0
	ACMESH_PROFILE_DOMAINS=; json_select domains; json_get_keys domain_indexes; for domain_index in $domain_indexes; do json_get_var domain_value "$domain_index"; ACMESH_PROFILE_DOMAINS="${ACMESH_PROFILE_DOMAINS}${ACMESH_PROFILE_DOMAINS:+
}$domain_value"; done; json_select ..
	ACMESH_PROFILE_DOMAIN="$(printf '%s\n' "$ACMESH_PROFILE_DOMAINS" | sed -n '1p')"
	ACMESH_PROFILE_CREDENTIALS=
	json_select credentials; json_get_keys credential_keys
	for credential_key in $credential_keys; do
		json_get_var credential_value "$credential_key"
		ACMESH_PROFILE_CREDENTIALS="${ACMESH_PROFILE_CREDENTIALS}${ACMESH_PROFILE_CREDENTIALS:+
}$credential_key=$credential_value"
	done
	json_select ..
}

# Renewal is deliberately resolved from the certificate state first.  The
# issue-profile lookup below is only a fallback for certificates imported from
# another machine, where acme.sh has a domain config but the console profile
# was not present when the certificate was created.
acmesh_profile_renew_key_type_normalize() (
	set +u
	case "$(printf '%s' "${1:-}" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz')" in
		ecc) printf 'ecc\n' ;;
		ec256|ec-256) printf 'ec256\n' ;;
		ec384|ec-384) printf 'ec384\n' ;;
		ec521|ec-521) printf 'ec521\n' ;;
		rsa) printf 'rsa\n' ;;
		rsa2048|2048) printf 'rsa2048\n' ;;
		rsa3072|3072) printf 'rsa3072\n' ;;
		rsa4096|4096) printf 'rsa4096\n' ;;
		rsa8192|8192) printf 'rsa8192\n' ;;
		*) printf '%s\n' "${1:-}" ;;
	esac
)

acmesh_profile_renew_key_type_matches() {
	r_profile_key="$(acmesh_profile_renew_key_type_normalize "${1:-}")"
	r_certificate_key="$(acmesh_profile_renew_key_type_normalize "${2:-}")"
	[ -n "$r_profile_key" ] || return 1
	case "$r_certificate_key:$r_profile_key" in
		ecc:ec256|ecc:ec384|ecc:ec521|rsa:rsa2048|rsa:rsa3072|rsa:rsa4096|rsa:rsa8192) return 0 ;;
		*) [ "$r_profile_key" = "$r_certificate_key" ] ;;
	esac
}

acmesh_profile_find_issue_for_renew() (
	set +u
	r_renew_domain="${1:-}" r_renew_key_type="${2:-}" r_renew_dns_api="${3:-}"
	[ -n "$r_renew_domain" ] && [ -n "$r_renew_dns_api" ] || exit 1
	[ -n "${ACMESH_CONSOLE_CONFIG:-}" ] || exit 1
	acmesh_config_validate_file "$ACMESH_CONSOLE_CONFIG" >/dev/null 2>&1 || exit 1
	acmesh_profile_jshn || exit 1
	json_load_file "$ACMESH_CONSOLE_CONFIG" || exit 1
	json_select issueProfiles || exit 1
	json_get_keys r_issue_indexes
	r_renew_domain_lower="$(printf '%s' "$r_renew_domain" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz')"
	r_renew_dns_api_lower="$(printf '%s' "$r_renew_dns_api" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz')"
	r_match_count=0
	r_match_id=
	for r_issue_index in $r_issue_indexes; do
		json_select "$r_issue_index" || exit 1
		json_get_var r_candidate_domain domain
		json_get_var r_candidate_key_type keyType
		json_get_var r_candidate_validation validationMethod
		json_get_var r_candidate_dns_api dnsApi || r_candidate_dns_api=
		json_get_var r_candidate_id id
		r_candidate_domain_lower="$(printf '%s' "$r_candidate_domain" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz')"
		r_candidate_dns_api_lower="$(printf '%s' "$r_candidate_dns_api" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz')"
		if [ "$r_candidate_domain_lower" = "$r_renew_domain_lower" ] &&
			[ "$r_candidate_validation" = dns ] &&
			[ "$r_candidate_dns_api_lower" = "$r_renew_dns_api_lower" ] &&
			acmesh_profile_renew_key_type_matches "$r_candidate_key_type" "$r_renew_key_type"; then
			r_match_count=$((r_match_count + 1))
			r_match_id="$r_candidate_id"
		fi
		json_select .. || exit 1
	done
	json_select .. || exit 1
	case "$r_match_count" in
		0) exit 1 ;;
		1) printf '%s\n' "$r_match_id" ;;
		*) exit 2 ;;
	esac
)

acmesh_profile_load_issue_for_renew_impl() {
	ACMESH_RENEW_PROFILE_ID= ACMESH_RENEW_PROFILE_DOMAIN= ACMESH_RENEW_PROFILE_KEY_TYPE=
	ACMESH_RENEW_PROFILE_DNS_API= ACMESH_RENEW_PROFILE_CREDENTIAL_MODE= ACMESH_RENEW_PROFILE_CREDENTIALS=
	r_issue_id="${1:-}"
	acmesh_profile_validate_id "$r_issue_id" || return 2
	[ -n "${ACMESH_CONSOLE_CONFIG:-}" ] || return 1
	acmesh_config_validate_file "$ACMESH_CONSOLE_CONFIG" >/dev/null 2>&1 || return 1
	acmesh_profile_jshn || return 1
	json_load_file "$ACMESH_CONSOLE_CONFIG" || return 1
	json_select issueProfiles || return 1
	json_get_keys r_issue_indexes
	r_found_index=
	for r_issue_index in $r_issue_indexes; do
		json_select "$r_issue_index" || return 1
		json_get_var r_candidate_id id
		if [ "$r_candidate_id" = "$r_issue_id" ]; then
			[ -z "$r_found_index" ] || return 1
			r_found_index="$r_issue_index"
		fi
		json_select .. || return 1
	done
	[ -n "$r_found_index" ] || return 1
	json_select "$r_found_index" || return 1
	json_get_var ACMESH_RENEW_PROFILE_ID id
	json_get_var ACMESH_RENEW_PROFILE_DOMAIN domain
	json_get_var ACMESH_RENEW_PROFILE_KEY_TYPE keyType
	json_get_var ACMESH_RENEW_PROFILE_DNS_API dnsApi || ACMESH_RENEW_PROFILE_DNS_API=
	json_get_var ACMESH_RENEW_PROFILE_CREDENTIAL_MODE credentialMode || ACMESH_RENEW_PROFILE_CREDENTIAL_MODE=
	json_select credentials || return 1
	json_get_keys r_credential_keys
	for r_credential_key in $r_credential_keys; do
		acmesh_profile_env_name "$r_credential_key" || return 1
		json_get_var r_credential_value "$r_credential_key" || return 1
		acmesh_profile_single_line "$r_credential_value" || return 1
		ACMESH_RENEW_PROFILE_CREDENTIALS="${ACMESH_RENEW_PROFILE_CREDENTIALS}${ACMESH_RENEW_PROFILE_CREDENTIALS:+
}$r_credential_key=$r_credential_value"
	done
	json_select .. || return 1
	json_select .. || return 1
}

acmesh_profile_load_issue_for_renew() {
	r_load_had_nounset=0
	case "$-" in *u*) r_load_had_nounset=1; set +u ;; esac
	if acmesh_profile_load_issue_for_renew_impl "$@"; then
		r_load_rc=0
	else
		r_load_rc=$?
	fi
	[ "$r_load_had_nounset" = 1 ] && set -u
	return "$r_load_rc"
}

acmesh_profile_renew_credential_name() {
	case "${1:-}" in
		CF_Token|CF_Zone_ID|CF_Account_ID|CF_Email|CF_Key|Ali_Key|Ali_Secret|DP_Id|DP_Key|Tencent_SecretId|Tencent_SecretKey|DuckDNS_Token|DYNV6_TOKEN|KEY|GD_Key|GD_Secret|AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|AWS_DNS_SLOWRATE|Baidu_AK|Baidu_SK|Baidu_API_Preference|Baidu_View|Baidu_Line|AZUREDNS_SUBSCRIPTIONID|AZUREDNS_TENANTID|AZUREDNS_APPID|AZUREDNS_CLIENTSECRET|AZUREDNS_MANAGEDIDENTITY|AZUREDNS_BEARERTOKEN|CLOUDNS_AUTH_ID|CLOUDNS_SUB_AUTH_ID|CLOUDNS_AUTH_PASSWORD|HE_Username|HE_Password|HUAWEICLOUD_Username|HUAWEICLOUD_Password|HUAWEICLOUD_DomainName|HUAWEICLOUD_Region|GCORE_Key|NAMECHEAP_USERNAME|NAMECHEAP_API_KEY|NAMECHEAP_SOURCEIP|LA_Id|LA_Sk|LA_Token|Namecom_Username|Namecom_Token|Namesilo_Key|NS1_Key|PORKBUN_API_KEY|PORKBUN_SECRET_API_KEY|Volcengine_ACCESS_KEY_ID|Volcengine_SECRET_ACCESS_KEY|Volcengine_SESSION_TOKEN|SPACESHIP_API_KEY|SPACESHIP_API_SECRET|SPACESHIP_ROOT_DOMAIN|VERCEL_TOKEN|LINODE_V4_API_KEY|DO_API_KEY|CLOUDSDK_ACTIVE_CONFIG_NAME|ZM_Key)
			return 0
			;;
		*) return 1 ;;
	esac
}

acmesh_profile_renew_unquote() {
	r_value="${1:-}"
	case "$r_value" in
		\'*) case "$r_value" in *\') r_value="${r_value#\'}"; r_value="${r_value%\'}" ;; esac ;;
		\"*) case "$r_value" in *\") r_value="${r_value#\"}"; r_value="${r_value%\"}" ;; esac ;;
	esac
	printf '%s\n' "$r_value"
}

acmesh_profile_renew_credentials_normalize() (
	set +u
	r_credentials="${1:-}"
	[ -n "$r_credentials" ] || exit 0
	r_status=0
	while IFS= read -r r_credential || [ -n "$r_credential" ]; do
		[ -n "$r_credential" ] || continue
		case "$r_credential" in *=*) ;; *) r_status=1; break ;; esac
		r_name="${r_credential%%=*}" r_value="${r_credential#*=}"
		acmesh_profile_env_name "$r_name" || { r_status=1; break; }
		acmesh_profile_single_line "$r_value" || { r_status=1; break; }
		case "$r_value" in ''|-|none|null|NONE|NULL) continue ;; esac
		printf '%s=%s\n' "$r_name" "$r_value"
	done <<EOF
$r_credentials
EOF
	[ "$r_status" = 0 ] || exit "$r_status"
)

acmesh_profile_renew_conf_credentials() (
	set +u
	r_conf="${1:-}"
	[ -f "$r_conf" ] && [ ! -L "$r_conf" ] || exit 1
	r_credentials=
	r_status=0
	while IFS= read -r r_line || [ -n "$r_line" ]; do
		case "$r_line" in ''|'#'*) continue ;; esac
		case "$r_line" in *=*) ;; *) continue ;; esac
		r_name="${r_line%%=*}" r_value="${r_line#*=}"
		acmesh_profile_renew_credential_name "$r_name" || continue
		r_value="$(acmesh_profile_renew_unquote "$r_value")" || { r_status=1; break; }
		acmesh_profile_single_line "$r_value" || { r_status=1; break; }
		case "$r_value" in ''|-|none|null|NONE|NULL) continue ;; esac
		r_credentials="${r_credentials}${r_credentials:+
}$r_name=$r_value"
	done < "$r_conf"
	[ "$r_status" = 0 ] || exit "$r_status"
	printf '%s\n' "$r_credentials"
)

acmesh_profile_renew_credential_keys() (
	set +u
	r_credentials="${1:-}"
	[ -n "$r_credentials" ] || exit 0
	while IFS= read -r r_credential || [ -n "$r_credential" ]; do
		case "$r_credential" in *=*) printf '%s\n' "${r_credential%%=*}" ;; esac
	done <<EOF
$r_credentials
EOF
)

acmesh_profile_renew_shell_quote() {
	printf "'%s'" "$(printf '%s' "${1:-}" | sed "s/'/'\\\\''/g")"
}

acmesh_profile_renew_merge_conf() (
	set +u
	r_conf="$1" r_profile_credentials="$2" r_output="${3:-}"
	[ -f "$r_conf" ] && [ ! -L "$r_conf" ] || exit 1
	[ -n "$r_output" ] || exit 1
	r_profile_credentials="$(acmesh_profile_renew_credentials_normalize "$r_profile_credentials")" || exit 1
	[ -n "$r_profile_credentials" ] || exit 1
	r_existing_names=
	{
		while IFS= read -r r_line || [ -n "$r_line" ]; do
			r_emit=1
			case "$r_line" in
				*=*)
					r_name="${r_line%%=*}" r_value="${r_line#*=}"
					if acmesh_profile_renew_credential_name "$r_name"; then
						r_value="$(acmesh_profile_renew_unquote "$r_value")" || exit 1
						acmesh_profile_single_line "$r_value" || exit 1
						case "$r_value" in
							''|-|none|null|NONE|NULL) r_emit=0 ;;
							*) r_existing_names="${r_existing_names}${r_existing_names:+ }$r_name" ;;
						esac
					fi
					;;
			 esac
			[ "$r_emit" = 1 ] && printf '%s\n' "$r_line"
		done < "$r_conf"
		while IFS= read -r r_credential || [ -n "$r_credential" ]; do
			[ -n "$r_credential" ] || continue
			r_name="${r_credential%%=*}" r_value="${r_credential#*=}"
			case " $r_existing_names " in
				*" $r_name "*) ;;
				*) printf '%s=%s\n' "$r_name" "$(acmesh_profile_renew_shell_quote "$r_value")" ;;
			 esac
		done <<EOF
$r_profile_credentials
EOF
	} > "$r_output" || exit 1
	chmod 600 "$r_output"
)

acmesh_profile_renew_persist_conf() (
	set +u
	r_conf="$1" r_profile_credentials="$2" r_dns_api="$3" r_credential_mode="$4"
	[ -f "$r_conf" ] && [ ! -L "$r_conf" ] || exit 1
	acmesh_path_dir "$r_conf" || exit 1
	r_conf_dir="$dir" r_conf_base="${r_conf##*/}"
	acmesh_private_dir "$r_conf_dir" || exit 1
	r_candidate="$(umask 077; mktemp "$r_conf_dir/.${r_conf_base}.acmesh-renew.XXXXXX")" || exit 1
	trap 'rm -f -- "$r_candidate"' EXIT
	trap 'rm -f -- "$r_candidate"; exit 129' HUP
	trap 'rm -f -- "$r_candidate"; exit 130' INT
	trap 'rm -f -- "$r_candidate"; exit 143' TERM
	chmod 600 "$r_candidate" || exit 1
	acmesh_profile_renew_merge_conf "$r_conf" "$r_profile_credentials" "$r_candidate" || exit 1
	acmesh_private_file_is_secure "$r_candidate" || exit 1
	r_effective_credentials="$(acmesh_profile_renew_conf_credentials "$r_candidate" 2>/dev/null)" || exit 1
	[ -n "$r_effective_credentials" ] || exit 1
	acmesh_dns_validate_credentials "$r_dns_api" "$r_effective_credentials" >/dev/null 2>&1 || exit 1
	acmesh_dns_validate_mode_credentials "$r_dns_api" "$r_credential_mode" "$r_effective_credentials" >/dev/null 2>&1 || exit 1
	acmesh_private_file_is_secure "$r_conf" || exit 1
	acmesh_atomic_write "$r_conf" 600 < "$r_candidate" || exit 1
	printf '%s\n' "$r_effective_credentials"
)

acmesh_profile_resolve_renew_credentials() {
	r_conf="$1" r_renew_domain="$2" r_renew_key_type="$3" r_renew_dns_api="${4:-}" r_persist="${5:-0}"
	ACMESH_RENEW_CREDENTIALS= ACMESH_RENEW_CREDENTIAL_SOURCE= ACMESH_RENEW_CREDENTIAL_MODE= ACMESH_RENEW_PROFILE_ID= ACMESH_RENEW_CREDENTIAL_KEYS=
	case "$r_renew_dns_api" in dns_*) ;; *) return 0 ;; esac
	acmesh_private_file_is_secure "$r_conf" >/dev/null 2>&1 || {
		echo "renewal certificate config is not a secure private file: $r_conf" >&2
		return 1
	}
	r_conf_credentials="$(acmesh_profile_renew_conf_credentials "$r_conf" 2>/dev/null || true)"
	if [ -n "$r_conf_credentials" ] && acmesh_dns_validate_credentials "$r_renew_dns_api" "$r_conf_credentials" >/dev/null 2>&1; then
		ACMESH_RENEW_CREDENTIALS="$r_conf_credentials"
		ACMESH_RENEW_CREDENTIAL_SOURCE=certificate-config
		ACMESH_RENEW_CREDENTIAL_MODE=certificate-config
		ACMESH_RENEW_CREDENTIAL_KEYS="$(acmesh_profile_renew_credential_keys "$r_conf_credentials")"
		return 0
	fi
	r_profile_id=
	if r_profile_id="$(acmesh_profile_find_issue_for_renew "$r_renew_domain" "$r_renew_key_type" "$r_renew_dns_api" 2>/dev/null)"; then
		:
	else
		r_profile_rc=$?
		[ "$r_profile_rc" = 2 ] || return 0
		echo "multiple issue profiles match renewal certificate $r_renew_domain" >&2
		return 1
	fi
	[ -n "$r_profile_id" ] || return 0
	acmesh_profile_load_issue_for_renew "$r_profile_id" || {
		echo "unable to load issue profile for renewal certificate $r_renew_domain" >&2
		return 1
	}
	[ "$ACMESH_RENEW_PROFILE_DNS_API" = "$r_renew_dns_api" ] || return 1
	r_profile_credentials="$(acmesh_profile_renew_credentials_normalize "$ACMESH_RENEW_PROFILE_CREDENTIALS")" || {
		echo "issue profile for renewal certificate $r_renew_domain has invalid DNS credentials" >&2
		return 1
	}
	[ -n "$r_profile_credentials" ] || return 1
	acmesh_dns_validate_mode_credentials "$r_renew_dns_api" "$ACMESH_RENEW_PROFILE_CREDENTIAL_MODE" "$r_profile_credentials" >/dev/null 2>&1 || {
		echo "issue profile for renewal certificate $r_renew_domain has unusable DNS credentials" >&2
		return 1
	}
	if [ "$r_persist" = 1 ]; then
		r_effective_credentials="$(acmesh_profile_renew_persist_conf "$r_conf" "$r_profile_credentials" "$r_renew_dns_api" "$ACMESH_RENEW_PROFILE_CREDENTIAL_MODE")" || {
			echo "unable to persist DNS credentials to renewal certificate config $r_conf" >&2
			return 1
		}
		ACMESH_RENEW_CREDENTIALS="$r_effective_credentials"
	else
		ACMESH_RENEW_CREDENTIALS="$r_profile_credentials"
	fi
	ACMESH_RENEW_PROFILE_ID="$r_profile_id"
	ACMESH_RENEW_CREDENTIAL_SOURCE="issue-profile:$r_profile_id"
	ACMESH_RENEW_CREDENTIAL_MODE="$ACMESH_RENEW_PROFILE_CREDENTIAL_MODE"
	ACMESH_RENEW_CREDENTIAL_KEYS="$(acmesh_profile_renew_credential_keys "$ACMESH_RENEW_CREDENTIALS")"
}

acmesh_profile_find_linked_deploy() (
	domain="$1" key_type="${2:-}"
	acmesh_config_validate_file "$ACMESH_CONSOLE_CONFIG" || return 1
	acmesh_profile_jshn || return 1; json_load_file "$ACMESH_CONSOLE_CONFIG" || return 1
	json_select issueProfiles; json_get_keys indexes; found=
	for index in $indexes; do
		json_select "$index"; json_get_var candidate domain; json_get_var variant keyType; json_get_var deploy deployProfileId || deploy=
		if [ "$candidate" = "$domain" ] && { [ -z "$key_type" ] || [ "$variant" = "$key_type" ] || { acmesh_key_type_is_ecc "$variant" && acmesh_key_type_is_ecc "$key_type"; }; }; then
			[ -z "$found" ] || return 1; found="$deploy"
		fi
		json_select ..
	done
	[ -n "$found" ] || return 1; printf '%s\n' "$found"
)
