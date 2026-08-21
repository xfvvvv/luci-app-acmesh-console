. "${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}/authorization.sh"

# Closed, backend-owned operation router.  Parameters supplied by an RPC are
# used only to select an existing backend object; they are never persisted in a
# challenge and are never trusted by authorization_execute.
acmesh_operation_subject_type() {
	case "$1" in
		issue|issue-deploy) printf '%s\n' issueProfile ;;
		renew) printf '%s\n' certificate ;;
		deploy-run) printf '%s\n' deployProfile ;;
		core-install|core-upgrade) printf '%s\n' global ;;
		ssh-key-convert) printf '%s\n' sshKey ;;
		import-apply) printf '%s\n' pendingImport ;;
		secret-export) printf '%s\n' config ;;
		certificate-revoke|certificate-remove) printf '%s\n' certificate ;;
		profile-delete) printf '%s\n' profile ;;
		*) return 2 ;;
	esac
}

acmesh_operation_snapshot_reset() {
	unset ACMESH_AUTH_ACCOUNT_ID ACMESH_AUTH_ACCOUNT_EMAIL ACMESH_AUTH_CA ACMESH_AUTH_PRIMARY_DOMAIN ACMESH_AUTH_DOMAINS
	unset ACMESH_AUTH_KEY_TYPE ACMESH_AUTH_VALIDATION ACMESH_AUTH_DNS_API ACMESH_AUTH_CREDENTIAL_MODE ACMESH_AUTH_CREDENTIAL_KEYS ACMESH_AUTH_CHALLENGE_ALIAS
	unset ACMESH_AUTH_DNS_SLEEP ACMESH_AUTH_WEBROOT ACMESH_AUTH_LISTEN_PORT ACMESH_AUTH_DEPLOY_PROFILE_ID ACMESH_AUTH_DEPLOY_FINGERPRINT
	unset ACMESH_AUTH_CERT_IDENTITY_DIGEST ACMESH_AUTH_TEST_MODE ACMESH_AUTH_DEPLOY_TYPE ACMESH_AUTH_SOURCE_TYPE ACMESH_AUTH_SOURCE_IDENTITY
	unset ACMESH_AUTH_SOURCE_DIGEST ACMESH_AUTH_KEY_VARIANT ACMESH_AUTH_SOURCE_KEY_FILE ACMESH_AUTH_SOURCE_FULLCHAIN_FILE ACMESH_AUTH_KEY_PEM
	unset ACMESH_AUTH_FULLCHAIN_PEM ACMESH_AUTH_HOST ACMESH_AUTH_PORT ACMESH_AUTH_USER ACMESH_AUTH_SSH_CLIENT ACMESH_AUTH_HOSTKEY_ALGORITHM
	unset ACMESH_AUTH_HOSTKEY_FINGERPRINT ACMESH_AUTH_KEY_FILE ACMESH_AUTH_FULLCHAIN_FILE ACMESH_AUTH_CERT_FILE ACMESH_AUTH_CA_FILE
	unset ACMESH_AUTH_RELOAD ACMESH_AUTH_SUDO_MODE ACMESH_AUTH_OWNER ACMESH_AUTH_GROUP ACMESH_AUTH_MODE ACMESH_AUTH_PRESERVE_METADATA ACMESH_AUTH_ACME_HOME ACMESH_AUTH_CORE_TAG ACMESH_AUTH_CORE_EMAIL
	unset ACMESH_AUTH_PUBLIC_IDENTITY_DIGEST ACMESH_AUTH_SOURCE_FORMAT ACMESH_AUTH_TARGET_CLIENT ACMESH_AUTH_TARGET_FORMAT
	unset ACMESH_AUTH_CONFIG_DIGEST ACMESH_AUTH_OVERWRITE_MODE ACMESH_AUTH_EXPORT_SCOPE ACMESH_AUTH_EXPORT_CERTS
	unset ACMESH_AUTH_OBJECT_IDENTITY ACMESH_AUTH_OBJECT_DIGEST ACMESH_AUTH_VARIANT
	unset ACMESH_OPERATION_USES_ONCE_CONVERSION ACMESH_OPERATION_CONVERSION_FINGERPRINT ACMESH_OPERATION_RESOLVED_FILE
	unset ACMESH_RENEW_CERT_CONF ACMESH_RENEW_DOMAIN ACMESH_RENEW_KEY_TYPE ACMESH_RENEW_DNS_API ACMESH_RENEW_CREDENTIALS
	unset ACMESH_RENEW_CREDENTIAL_SOURCE ACMESH_RENEW_CREDENTIAL_MODE ACMESH_RENEW_CREDENTIAL_KEYS ACMESH_RENEW_PROFILE_ID
}

acmesh_operation_snapshot_issue() {
	local issue_profile_id="$1" issue_out="$2" issue_summary="$3" issue_resolved="$4" issue_operation="${5:-issue}"
	local issue_deploy_id issue_deploy_fingerprint deploy_snapshot deploy_summary deploy_resolved
	acmesh_operation_snapshot_reset
	acmesh_profile_resolve_issue "$issue_profile_id" "$issue_resolved" || return 1
	acmesh_profile_load_issue_file "$issue_resolved" || return 1
	ACMESH_AUTH_ACCOUNT_ID="$(jsonfilter -i "$issue_resolved" -e '@.accountId')"
	ACMESH_AUTH_ACCOUNT_EMAIL="$ACMESH_PROFILE_ACCOUNT_EMAIL" ACMESH_AUTH_CA="$ACMESH_PROFILE_CA"
	ACMESH_AUTH_PRIMARY_DOMAIN="$ACMESH_PROFILE_DOMAIN" ACMESH_AUTH_DOMAINS="$ACMESH_PROFILE_DOMAINS"
	ACMESH_AUTH_KEY_TYPE="$ACMESH_PROFILE_KEY_TYPE" ACMESH_AUTH_VALIDATION="$ACMESH_PROFILE_VALIDATION"
	ACMESH_AUTH_DNS_API="$ACMESH_PROFILE_DNS_API" ACMESH_AUTH_CREDENTIAL_MODE="$ACMESH_PROFILE_CREDENTIAL_MODE" ACMESH_AUTH_CHALLENGE_ALIAS="$ACMESH_PROFILE_CHALLENGE_ALIAS"
	ACMESH_AUTH_DNS_SLEEP="$ACMESH_PROFILE_DNS_SLEEP" ACMESH_AUTH_WEBROOT="$ACMESH_PROFILE_WEBROOT"
	ACMESH_AUTH_LISTEN_PORT="$ACMESH_PROFILE_LISTEN_PORT" ACMESH_AUTH_DEPLOY_PROFILE_ID="$(jsonfilter -i "$issue_resolved" -e '@.deployProfileId' 2>/dev/null || true)"
	ACMESH_AUTH_TEST_MODE=false
	issue_deploy_id="$ACMESH_AUTH_DEPLOY_PROFILE_ID" issue_deploy_fingerprint=
	if [ "$issue_operation" = issue-deploy ] && [ -n "$ACMESH_AUTH_DEPLOY_PROFILE_ID" ]; then
		deploy_snapshot="${issue_out}.linked-deploy" deploy_summary="${issue_out}.linked-summary" deploy_resolved="${issue_out}.linked-resolved"
		acmesh_operation_snapshot_deploy "$ACMESH_AUTH_DEPLOY_PROFILE_ID" "$deploy_snapshot" "$deploy_summary" "$deploy_resolved" || return 1
		issue_deploy_fingerprint="$(acmesh_auth_fingerprint "$deploy_snapshot")"
		# Restore issue fields overwritten while resolving linked deployment.
		acmesh_profile_load_issue_file "$issue_resolved" || return 1
	fi
	[ "$issue_operation" != issue-deploy ] || [ -n "$issue_deploy_id" ] || return 1
	ACMESH_AUTH_ACCOUNT_ID="$(jsonfilter -i "$issue_resolved" -e '@.accountId')"
	ACMESH_AUTH_ACCOUNT_EMAIL="$ACMESH_PROFILE_ACCOUNT_EMAIL" ACMESH_AUTH_CA="$ACMESH_PROFILE_CA"
	ACMESH_AUTH_PRIMARY_DOMAIN="$ACMESH_PROFILE_DOMAIN" ACMESH_AUTH_DOMAINS="$ACMESH_PROFILE_DOMAINS"
	ACMESH_AUTH_KEY_TYPE="$ACMESH_PROFILE_KEY_TYPE" ACMESH_AUTH_VALIDATION="$ACMESH_PROFILE_VALIDATION"
	ACMESH_AUTH_DNS_API="$ACMESH_PROFILE_DNS_API" ACMESH_AUTH_CREDENTIAL_MODE="$ACMESH_PROFILE_CREDENTIAL_MODE" ACMESH_AUTH_CHALLENGE_ALIAS="$ACMESH_PROFILE_CHALLENGE_ALIAS"
	ACMESH_AUTH_CREDENTIAL_KEYS="$(printf '%s\n' "$ACMESH_PROFILE_CREDENTIALS" | sed -n 's/=.*//p' | LC_ALL=C sort)"
	ACMESH_AUTH_DNS_SLEEP="$ACMESH_PROFILE_DNS_SLEEP" ACMESH_AUTH_WEBROOT="$ACMESH_PROFILE_WEBROOT"
	ACMESH_AUTH_LISTEN_PORT="$ACMESH_PROFILE_LISTEN_PORT" ACMESH_AUTH_DEPLOY_PROFILE_ID="$issue_deploy_id" ACMESH_AUTH_DEPLOY_FINGERPRINT="$issue_deploy_fingerprint" ACMESH_AUTH_TEST_MODE=false
	export ACMESH_AUTH_ACCOUNT_ID ACMESH_AUTH_ACCOUNT_EMAIL ACMESH_AUTH_CA ACMESH_AUTH_PRIMARY_DOMAIN ACMESH_AUTH_DOMAINS ACMESH_AUTH_KEY_TYPE ACMESH_AUTH_VALIDATION ACMESH_AUTH_DNS_API ACMESH_AUTH_CREDENTIAL_MODE ACMESH_AUTH_CREDENTIAL_KEYS ACMESH_AUTH_CHALLENGE_ALIAS ACMESH_AUTH_DNS_SLEEP ACMESH_AUTH_WEBROOT ACMESH_AUTH_LISTEN_PORT ACMESH_AUTH_DEPLOY_PROFILE_ID ACMESH_AUTH_TEST_MODE
	export ACMESH_AUTH_DEPLOY_FINGERPRINT
	ACMESH_OPERATION_RESOLVED_FILE="$issue_resolved"; export ACMESH_OPERATION_RESOLVED_FILE
	acmesh_auth_snapshot "$issue_operation" issueProfile "$issue_profile_id" "$issue_out" && acmesh_auth_summary "$issue_out" "$issue_summary"
}

acmesh_operation_snapshot_deploy() {
	local deploy_profile_id="$1" deploy_out="$2" deploy_summary="$3" deploy_resolved="$4"
	local hostkey_file deploy_hostkey_algorithm deploy_hostkey_fingerprint conversion_snapshot conversion_summary conversion_fp
	acmesh_operation_snapshot_reset
	acmesh_profile_resolve_deploy "$deploy_profile_id" "$deploy_resolved" || return 1
	acmesh_profile_load_deploy_file "$deploy_resolved" || return 1
	if [ "$ACMESH_DEPLOY_TYPE" = ssh ]; then
		hostkey_file="${deploy_out}.hostkey"
		if ! acmesh_ssh_verify_pinned_host "$ACMESH_DEPLOY_HOST" "$ACMESH_DEPLOY_PORT" > "$hostkey_file"; then cat "$hostkey_file"; return 4; fi
		ACMESH_AUTH_HOSTKEY_ALGORITHM="$(jsonfilter -i "$hostkey_file" -e '@.algorithm')"
		ACMESH_AUTH_HOSTKEY_FINGERPRINT="$(jsonfilter -i "$hostkey_file" -e '@.fingerprint')"
		deploy_hostkey_algorithm="$ACMESH_AUTH_HOSTKEY_ALGORITHM" deploy_hostkey_fingerprint="$ACMESH_AUTH_HOSTKEY_FINGERPRINT"
		if acmesh_ssh_key_is_openssh_private "$ACMESH_DEPLOY_SSH_KEY" && acmesh_ssh_client_is_dropbear; then
			conversion_snapshot="${deploy_out}.conversion" conversion_summary="${deploy_out}.conversion-summary"
			acmesh_operation_snapshot_conversion "$deploy_profile_id" "$conversion_snapshot" "$conversion_summary" "$deploy_resolved" || return 1
			conversion_fp="$(acmesh_auth_fingerprint "$conversion_snapshot")"
			if acmesh_auth_is_remembered ssh-key-convert "$conversion_fp"; then :
			elif acmesh_operation_conversion_grant_valid "$deploy_profile_id" "$conversion_fp"; then
				ACMESH_OPERATION_USES_ONCE_CONVERSION=1 ACMESH_OPERATION_CONVERSION_FINGERPRINT="$conversion_fp"; export ACMESH_OPERATION_USES_ONCE_CONVERSION ACMESH_OPERATION_CONVERSION_FINGERPRINT
			else ACMESH_OPERATION_CONVERSION_SUBJECT="$deploy_profile_id"; export ACMESH_OPERATION_CONVERSION_SUBJECT; return 6; fi
		fi
		ACMESH_AUTH_HOSTKEY_ALGORITHM="$deploy_hostkey_algorithm" ACMESH_AUTH_HOSTKEY_FINGERPRINT="$deploy_hostkey_fingerprint"
	fi
	ACMESH_AUTH_DEPLOY_TYPE="$ACMESH_DEPLOY_TYPE" ACMESH_AUTH_SOURCE_TYPE="$ACMESH_DEPLOY_CERT_SOURCE"
	ACMESH_AUTH_SOURCE_IDENTITY="$ACMESH_DEPLOY_DOMAIN" ACMESH_AUTH_KEY_VARIANT="$ACMESH_DEPLOY_KEY_TYPE"
	ACMESH_AUTH_SOURCE_KEY_FILE="$ACMESH_DEPLOY_SOURCE_KEY" ACMESH_AUTH_SOURCE_FULLCHAIN_FILE="$ACMESH_DEPLOY_SOURCE_CHAIN"
	ACMESH_AUTH_KEY_PEM="$ACMESH_DEPLOY_KEY_PEM" ACMESH_AUTH_FULLCHAIN_PEM="$ACMESH_DEPLOY_CHAIN_PEM"
	ACMESH_AUTH_HOST="$ACMESH_DEPLOY_HOST" ACMESH_AUTH_PORT="$ACMESH_DEPLOY_PORT" ACMESH_AUTH_USER="$ACMESH_DEPLOY_USER"
	ACMESH_AUTH_SSH_CLIENT="$(acmesh_ssh_client_type 2>/dev/null || printf unknown)" ACMESH_AUTH_KEY_FILE="$ACMESH_DEPLOY_KEY_FILE" ACMESH_AUTH_FULLCHAIN_FILE="$ACMESH_DEPLOY_CHAIN_FILE"
	ACMESH_AUTH_CERT_FILE="$ACMESH_DEPLOY_CERT_FILE" ACMESH_AUTH_CA_FILE="$ACMESH_DEPLOY_CA_FILE" ACMESH_AUTH_RELOAD="$ACMESH_DEPLOY_RELOAD"
	ACMESH_AUTH_SUDO_MODE="$ACMESH_DEPLOY_SUDO_MODE" ACMESH_AUTH_OWNER="$ACMESH_DEPLOY_OWNER" ACMESH_AUTH_GROUP="$ACMESH_DEPLOY_GROUP" ACMESH_AUTH_MODE="$ACMESH_DEPLOY_MODE" ACMESH_AUTH_PRESERVE_METADATA="$ACMESH_DEPLOY_PRESERVE_METADATA"
	export ACMESH_AUTH_DEPLOY_TYPE ACMESH_AUTH_SOURCE_TYPE ACMESH_AUTH_SOURCE_IDENTITY ACMESH_AUTH_KEY_VARIANT ACMESH_AUTH_SOURCE_KEY_FILE ACMESH_AUTH_SOURCE_FULLCHAIN_FILE ACMESH_AUTH_KEY_PEM ACMESH_AUTH_FULLCHAIN_PEM ACMESH_AUTH_HOST ACMESH_AUTH_PORT ACMESH_AUTH_USER ACMESH_AUTH_SSH_CLIENT ACMESH_AUTH_HOSTKEY_ALGORITHM ACMESH_AUTH_HOSTKEY_FINGERPRINT ACMESH_AUTH_KEY_FILE ACMESH_AUTH_FULLCHAIN_FILE ACMESH_AUTH_CERT_FILE ACMESH_AUTH_CA_FILE ACMESH_AUTH_RELOAD ACMESH_AUTH_SUDO_MODE ACMESH_AUTH_OWNER ACMESH_AUTH_GROUP ACMESH_AUTH_MODE ACMESH_AUTH_PRESERVE_METADATA
	ACMESH_OPERATION_RESOLVED_FILE="$deploy_resolved"; export ACMESH_OPERATION_RESOLVED_FILE
	acmesh_auth_snapshot deploy-run deployProfile "$deploy_profile_id" "$deploy_out" && acmesh_auth_summary "$deploy_out" "$deploy_summary"
}

acmesh_operation_snapshot_conversion() {
	local conversion_profile_id="$1" conversion_out="$2" conversion_summary="$3" conversion_resolved="$4"
	local ssh_keygen public_identity
	acmesh_operation_snapshot_reset
	[ -f "$conversion_resolved" ] || acmesh_profile_resolve_deploy "$conversion_profile_id" "$conversion_resolved" || return 1
	acmesh_profile_load_deploy_file "$conversion_resolved" || return 1
	[ -r "$ACMESH_DEPLOY_SSH_KEY" ] || return 1
	ssh_keygen="${ACMESH_SSH_KEYGEN_BIN:-ssh-keygen}"
	command -v "$ssh_keygen" >/dev/null 2>&1 || { echo "ssh-keygen is required to derive the SSH public identity" >&2; return 127; }
	public_identity="$($ssh_keygen -y -f "$ACMESH_DEPLOY_SSH_KEY" 2>/dev/null)" || return 1
	[ -n "$public_identity" ] || return 1
	ACMESH_AUTH_PUBLIC_IDENTITY_DIGEST="$(printf '%s\n' "$public_identity" | sha256sum | awk '{print $1}')"
	ACMESH_AUTH_SOURCE_FORMAT=openssh-private ACMESH_AUTH_TARGET_CLIENT=dropbear ACMESH_AUTH_TARGET_FORMAT=dropbear-private
	export ACMESH_AUTH_PUBLIC_IDENTITY_DIGEST ACMESH_AUTH_SOURCE_FORMAT ACMESH_AUTH_TARGET_CLIENT ACMESH_AUTH_TARGET_FORMAT
	acmesh_auth_snapshot ssh-key-convert sshKey "$conversion_profile_id" "$conversion_out" && acmesh_auth_summary "$conversion_out" "$conversion_summary"
}

acmesh_operation_conversion_grant_path() { printf '%s/.conversion-once.%s\n' "$ACMESH_AUTH_CHALLENGE_DIR" "$1"; }
acmesh_operation_conversion_continuation_path() {
	parent_operation="$1" conversion_subject="$2"
	acmesh_auth_valid_id "$conversion_subject" || return 2
	printf '%s/.conversion-continuation.%s.%s\n' "$ACMESH_AUTH_CHALLENGE_DIR" "$conversion_subject" "$parent_operation"
}
acmesh_operation_save_conversion_continuation() {
	parent_operation="$1" parent_subject_id="$2" conversion_subject="$3"
	path="$(acmesh_operation_conversion_continuation_path "$parent_operation" "$conversion_subject")" || return 1
	acmesh_private_dir "${path%/*}" || return 1
	acmesh_auth_valid_id "$parent_subject_id" || return 2
	printf '%s\n%s\n' "$parent_operation" "$parent_subject_id" | acmesh_atomic_write "$path" 600
}
acmesh_operation_take_conversion_continuation() {
	conversion_subject="$1"
	for parent_operation in issue-deploy deploy-run; do
		path="$(acmesh_operation_conversion_continuation_path "$parent_operation" "$conversion_subject")" || continue
		[ -f "$path" ] && [ ! -L "$path" ] && acmesh_private_file_is_secure "$path" || continue
		parent_subject_id="$(sed -n '2p' "$path")"
		acmesh_auth_valid_id "$parent_subject_id" || { rm -f -- "$path"; continue; }
		rm -f -- "$path"
		printf '%s\n%s\n' "$parent_operation" "$parent_subject_id"
		return 0
	done
	return 1
}
acmesh_operation_conversion_grant_valid() {
	profile_id="$1" fingerprint="$2" now="$(acmesh_auth_now)" grant="$(acmesh_operation_conversion_grant_path "$profile_id")"
	[ -f "$grant" ] && [ ! -L "$grant" ] && acmesh_private_file_is_secure "$grant" || return 1
	grant_fp="$(sed -n '1p' "$grant")" grant_expiry="$(sed -n '2p' "$grant")"
	case "$grant_expiry" in ''|*[!0-9]*) return 1 ;; esac
	[ "$grant_fp" = "$fingerprint" ] && [ "$now" -lt "$grant_expiry" ]
}
acmesh_operation_consume_conversion_grant() {
	[ "${ACMESH_OPERATION_USES_ONCE_CONVERSION:-0}" = 1 ] || return 0
	grant="$(acmesh_operation_conversion_grant_path "$1")"
	acmesh_operation_conversion_grant_valid "$1" "${ACMESH_OPERATION_CONVERSION_FINGERPRINT:-}" || return 1
	rm -f "$grant"
}

acmesh_operation_convert_key_task() {
	profile_id="$1" resolved="$2"; acmesh_profile_resolve_deploy "$profile_id" "$resolved" || return 1
	acmesh_profile_load_deploy_file "$resolved" || return 1
	ACMESH_DEPLOY_ALLOW_KEY_CONVERT=1 acmesh_deploy_resolve_ssh_key "$ACMESH_DEPLOY_SSH_KEY" 1 || return 1
	acmesh_deploy_cleanup_temp_key
	printf 'Temporary SSH key conversion verified and deleted.\n'
}

acmesh_operation_recompute() {
	local recompute_operation="$1" recompute_subject_type="$2" recompute_subject_id="$3" recompute_snapshot="$4" recompute_summary="$5"
	local recompute_resolved="${4}.resolved"
	local renew_snapshot renew_summary renew_domain renew_variant cert_dir cert_conf renew_ca renew_alt renew_key renew_webroot renew_validation renew_dns_api renew_domains renew_deploy_id renew_deploy_fingerprint renew_auth_credential_mode deploy_snapshot candidate config_path destructive_domain destructive_variant destructive_dir destructive_conf profile_kind profile_id
	case "$recompute_operation:$recompute_subject_type" in
		issue:issueProfile) acmesh_operation_snapshot_issue "$recompute_subject_id" "$recompute_snapshot" "$recompute_summary" "$recompute_resolved" issue ;;
		issue-deploy:issueProfile) acmesh_operation_snapshot_issue "$recompute_subject_id" "$recompute_snapshot" "$recompute_summary" "$recompute_resolved" issue-deploy ;;
		deploy-run:deployProfile) acmesh_operation_snapshot_deploy "$recompute_subject_id" "$recompute_snapshot" "$recompute_summary" "$recompute_resolved" ;;
		ssh-key-convert:sshKey) acmesh_operation_snapshot_conversion "$recompute_subject_id" "$recompute_snapshot" "$recompute_summary" "$recompute_resolved" ;;
		renew:certificate)
			acmesh_operation_snapshot_reset
			renew_snapshot="$recompute_snapshot" renew_summary="$recompute_summary"
			case "$recompute_subject_id" in ecc.*) renew_domain="${recompute_subject_id#ecc.}"; renew_variant=ecc;; rsa.*) renew_domain="${recompute_subject_id#rsa.}"; renew_variant=rsa;; *) renew_domain="$recompute_subject_id"; renew_variant=rsa;; esac
			acmesh_profile_domain "$renew_domain" || { echo "invalid renewal certificate domain" >&2; return 1; }
			cert_dir="$ACMESH_ACME_HOME/$renew_domain"; [ "$renew_variant" = ecc ] && cert_dir="${cert_dir}_ecc"
			cert_conf="$cert_dir/$renew_domain.conf"; [ -f "$cert_conf" ] && [ ! -L "$cert_conf" ] || return 1
			renew_ca="$(sed -n "s/^Le_API='\([^']*\)'.*/\1/p" "$cert_conf" | head -n 1)"; [ -n "$renew_ca" ] || renew_ca=letsencrypt
			renew_alt="$(sed -n "s/^Le_Alt='\([^']*\)'.*/\1/p" "$cert_conf" | head -n 1 | tr ',' '\n')"
			renew_key="$(sed -n "s/^Le_Keylength='\([^']*\)'.*/\1/p" "$cert_conf" | head -n 1)"; [ -n "$renew_key" ] || renew_key="$renew_variant"
			renew_webroot="$(sed -n "s/^Le_Webroot='\([^']*\)'.*/\1/p" "$cert_conf" | head -n 1)"
			case "$renew_webroot" in dns_*) renew_validation=dns; renew_dns_api="$renew_webroot" ;; no|standalone) renew_validation=standalone; renew_dns_api= ;; tls_alpn_01) renew_validation=alpn; renew_dns_api= ;; *) renew_validation=webroot; renew_dns_api= ;; esac
			renew_domains="$(printf '%s\n%s\n' "$renew_domain" "$renew_alt")"
			acmesh_profile_resolve_renew_credentials "$cert_conf" "$renew_domain" "$renew_key" "$renew_dns_api" 0 || return 1
			ACMESH_RENEW_CERT_CONF="$cert_conf" ACMESH_RENEW_DOMAIN="$renew_domain" ACMESH_RENEW_KEY_TYPE="$renew_key" ACMESH_RENEW_DNS_API="$renew_dns_api"
			renew_auth_credential_mode="${ACMESH_RENEW_CREDENTIAL_MODE:-}"
			case "${ACMESH_RENEW_CREDENTIAL_SOURCE:-}" in
				certificate-config) renew_auth_credential_mode=certificate-config ;;
				issue-profile:*) renew_auth_credential_mode="${ACMESH_RENEW_CREDENTIAL_SOURCE}:${ACMESH_RENEW_CREDENTIAL_MODE}" ;;
			esac
			# Certificate bytes and acme.sh renewal timestamps are expected to change
			# after every successful renew and therefore are not authorization identity.
			renew_deploy_id="$(acmesh_profile_find_linked_deploy "$renew_domain" "$renew_key" 2>/dev/null || true)" renew_deploy_fingerprint=
			if [ -n "$renew_deploy_id" ]; then deploy_snapshot="${renew_snapshot}.linked-deploy"; acmesh_operation_snapshot_deploy "$renew_deploy_id" "$deploy_snapshot" "${renew_summary}.linked" "${renew_snapshot}.linked-resolved" || return 1; renew_deploy_fingerprint="$(acmesh_auth_fingerprint "$deploy_snapshot")"; fi
			ACMESH_AUTH_ACCOUNT_ID=certificate ACMESH_AUTH_CA="$renew_ca" ACMESH_AUTH_PRIMARY_DOMAIN="$renew_domain" ACMESH_AUTH_DOMAINS="$renew_domains" ACMESH_AUTH_KEY_TYPE="$renew_key" ACMESH_AUTH_VALIDATION="$renew_validation" ACMESH_AUTH_DNS_API="$renew_dns_api" ACMESH_AUTH_CREDENTIAL_MODE="$renew_auth_credential_mode" ACMESH_AUTH_CREDENTIAL_KEYS="${ACMESH_RENEW_CREDENTIAL_KEYS:-}" ACMESH_AUTH_WEBROOT="$renew_webroot" ACMESH_AUTH_DNS_SLEEP=0 ACMESH_AUTH_TEST_MODE=false ACMESH_AUTH_CERT_IDENTITY_DIGEST= ACMESH_AUTH_DEPLOY_PROFILE_ID="$renew_deploy_id" ACMESH_AUTH_DEPLOY_FINGERPRINT="$renew_deploy_fingerprint"
			export ACMESH_AUTH_ACCOUNT_ID ACMESH_AUTH_CA ACMESH_AUTH_PRIMARY_DOMAIN ACMESH_AUTH_DOMAINS ACMESH_AUTH_KEY_TYPE ACMESH_AUTH_VALIDATION ACMESH_AUTH_DNS_API ACMESH_AUTH_CREDENTIAL_MODE ACMESH_AUTH_CREDENTIAL_KEYS ACMESH_AUTH_WEBROOT ACMESH_AUTH_DNS_SLEEP ACMESH_AUTH_TEST_MODE ACMESH_AUTH_CERT_IDENTITY_DIGEST ACMESH_AUTH_DEPLOY_PROFILE_ID ACMESH_AUTH_DEPLOY_FINGERPRINT
			acmesh_auth_snapshot renew certificate "$recompute_subject_id" "$renew_snapshot" && acmesh_auth_summary "$renew_snapshot" "$renew_summary" ;;
		core-install:global|core-upgrade:global)
			acmesh_operation_snapshot_reset
			ACMESH_AUTH_ACME_HOME="$(acmesh_config_string acmeHome /etc/acme)" ACMESH_AUTH_CORE_TAG="$(acmesh_config_string coreTag "${ACMESH_CORE_TAG:-v3.1.4}")" ACMESH_AUTH_CORE_EMAIL="$(acmesh_config_string defaultAccountEmail '')"
			export ACMESH_AUTH_ACME_HOME ACMESH_AUTH_CORE_TAG ACMESH_AUTH_CORE_EMAIL
			acmesh_auth_snapshot "$recompute_operation" global "$recompute_subject_id" "$recompute_snapshot" && acmesh_auth_summary "$recompute_snapshot" "$recompute_summary" ;;
		import-apply:pendingImport)
			acmesh_operation_snapshot_reset
			candidate="${recompute_snapshot}.candidate"; acmesh_config_pending_candidate "$recompute_subject_id" "$candidate" || return 1
			ACMESH_AUTH_CONFIG_DIGEST="$recompute_subject_id" ACMESH_AUTH_OVERWRITE_MODE=replace
			export ACMESH_AUTH_CONFIG_DIGEST ACMESH_AUTH_OVERWRITE_MODE
			acmesh_auth_snapshot import-apply pendingImport "$recompute_subject_id" "$recompute_snapshot" && acmesh_auth_summary "$recompute_snapshot" "$recompute_summary" ;;
		secret-export:config)
			acmesh_operation_snapshot_reset
			config_path="$(acmesh_config_path)"; [ -f "$config_path" ] && [ ! -L "$config_path" ] && acmesh_config_validate_file "$config_path" || return 1
			case "$recompute_subject_id" in
				migration-archive) ACMESH_AUTH_EXPORT_SCOPE=migration-archive; ACMESH_AUTH_EXPORT_CERTS=false ;;
				migration-archive-with-deployment-certs) ACMESH_AUTH_EXPORT_SCOPE=migration-archive-with-deployment-certs; ACMESH_AUTH_EXPORT_CERTS=true ;;
				*) return 2 ;;
			esac
			ACMESH_AUTH_CONFIG_DIGEST="$(sha256sum "$config_path" | awk '{print $1}')"
			export ACMESH_AUTH_CONFIG_DIGEST ACMESH_AUTH_EXPORT_SCOPE ACMESH_AUTH_EXPORT_CERTS
			acmesh_auth_snapshot secret-export config "$recompute_subject_id" "$recompute_snapshot" && acmesh_auth_summary "$recompute_snapshot" "$recompute_summary" ;;
		certificate-revoke:certificate|certificate-remove:certificate)
			acmesh_operation_snapshot_reset
			case "$recompute_subject_id" in ecc.*) destructive_domain="${recompute_subject_id#ecc.}"; destructive_variant=ecc;; rsa.*) destructive_domain="${recompute_subject_id#rsa.}"; destructive_variant=rsa;; *) return 2;; esac
			destructive_dir="$ACMESH_ACME_HOME/$destructive_domain"; [ "$destructive_variant" = ecc ] && destructive_dir="${destructive_dir}_ecc"
			destructive_conf="$destructive_dir/$destructive_domain.conf"; [ -f "$destructive_conf" ] && [ ! -L "$destructive_conf" ] || return 1
			ACMESH_AUTH_OBJECT_IDENTITY="$destructive_domain" ACMESH_AUTH_VARIANT="$destructive_variant" ACMESH_AUTH_OBJECT_DIGEST="$(sha256sum "$destructive_conf" | awk '{print $1}')"
			export ACMESH_AUTH_OBJECT_IDENTITY ACMESH_AUTH_VARIANT ACMESH_AUTH_OBJECT_DIGEST
			acmesh_auth_snapshot "$recompute_operation" certificate "$recompute_subject_id" "$recompute_snapshot" && acmesh_auth_summary "$recompute_snapshot" "$recompute_summary" ;;
		profile-delete:profile)
			acmesh_operation_snapshot_reset
			case "$recompute_subject_id" in account.*) profile_kind=account; profile_id="${recompute_subject_id#account.}";; issue.*) profile_kind=issue; profile_id="${recompute_subject_id#issue.}";; deploy.*) profile_kind=deploy; profile_id="${recompute_subject_id#deploy.}";; *) return 2;; esac
			acmesh_profile_validate_id "$profile_id" && acmesh_config_profile_exists "$profile_kind" "$profile_id" || return 1
			ACMESH_AUTH_OBJECT_IDENTITY="$profile_id" ACMESH_AUTH_VARIANT="$profile_kind" ACMESH_AUTH_CONFIG_DIGEST="$(sha256sum "$(acmesh_config_path)" | awk '{print $1}')"
			export ACMESH_AUTH_OBJECT_IDENTITY ACMESH_AUTH_VARIANT ACMESH_AUTH_CONFIG_DIGEST
			acmesh_auth_snapshot profile-delete profile "$recompute_subject_id" "$recompute_snapshot" && acmesh_auth_summary "$recompute_snapshot" "$recompute_summary" ;;
		*) return 2 ;;
	esac
}

acmesh_operation_admit() {
	operation="$1" subject_type="$2" subject_id="$3" decision="$4"
	case "$operation:$subject_type" in
		issue:issueProfile)
			task_id="$(acmesh_task_create issue-profile)"; workspace="$(acmesh_task_workspace "$task_id")"; task_resolved="$workspace/issue-profile.json"
			[ -f "$ACMESH_OPERATION_RESOLVED_FILE" ] && [ ! -L "$ACMESH_OPERATION_RESOLVED_FILE" ] || return 1
			cp "$ACMESH_OPERATION_RESOLVED_FILE" "$task_resolved" && chmod 600 "$task_resolved" || return 1
			ACMESH_OPERATION_USE_RESOLVED=1; export ACMESH_OPERATION_USE_RESOLVED
			acmesh_task_spawn "$task_id" issue acme-sh acmesh_run_issue_profile "$subject_id" "$task_resolved" "$ACMESH_ACME_HOME" || return 1 ;;
		issue-deploy:issueProfile)
			task_id="$(acmesh_task_create issue-deploy)"; workspace="$(acmesh_task_workspace "$task_id")"; task_resolved="$workspace/issue-profile.json"; deploy_resolved="$workspace/deploy-profile.json"
			[ -f "$ACMESH_OPERATION_RESOLVED_FILE" ] && [ ! -L "$ACMESH_OPERATION_RESOLVED_FILE" ] || return 1
			cp "$ACMESH_OPERATION_RESOLVED_FILE" "$task_resolved" && chmod 600 "$task_resolved" || return 1
			deploy_id="$(jsonfilter -i "$task_resolved" -e '@.deployProfileId' 2>/dev/null || true)"
			[ -n "$deploy_id" ] || return 1
			acmesh_operation_consume_conversion_grant "$deploy_id" || return 1
			acmesh_profile_resolve_deploy "$deploy_id" "$deploy_resolved" || return 1
			chmod 600 "$deploy_resolved" || return 1
			ACMESH_DEPLOY_ALLOW_KEY_CONVERT=1 ACMESH_OPERATION_USE_RESOLVED=1
			export ACMESH_DEPLOY_ALLOW_KEY_CONVERT ACMESH_OPERATION_USE_RESOLVED
			acmesh_task_spawn "$task_id" issue-deploy acme-sh acmesh_run_issue_deploy_profile "$subject_id" "$task_resolved" "$deploy_resolved" "$ACMESH_ACME_HOME" || return 1 ;;
		deploy-run:deployProfile)
			acmesh_operation_consume_conversion_grant "$subject_id" || return 1
			task_id="$(acmesh_task_create deploy-profile)"; workspace="$(acmesh_task_workspace "$task_id")"; task_resolved="$workspace/deploy-profile.json"
			[ -f "$ACMESH_OPERATION_RESOLVED_FILE" ] && [ ! -L "$ACMESH_OPERATION_RESOLVED_FILE" ] || return 1
			cp "$ACMESH_OPERATION_RESOLVED_FILE" "$task_resolved" && chmod 600 "$task_resolved" || return 1
			ACMESH_DEPLOY_ALLOW_KEY_CONVERT=1 ACMESH_OPERATION_USE_RESOLVED=1
			export ACMESH_DEPLOY_ALLOW_KEY_CONVERT ACMESH_OPERATION_USE_RESOLVED
			acmesh_task_spawn "$task_id" deploy-run deploy acmesh_run_deploy_profile "$subject_id" "$task_resolved" || return 1 ;;
		ssh-key-convert:sshKey)
			if [ "$decision" = once ]; then
				tmp="$(acmesh_operation_conversion_grant_path "$subject_id")"; acmesh_private_dir "${tmp%/*}" || return 1
				snapshot="${tmp}.snapshot" summary="${tmp}.summary" resolved="${tmp}.resolved"
				acmesh_operation_snapshot_conversion "$subject_id" "$snapshot" "$summary" "$resolved" || return 1
				fp="$(acmesh_auth_fingerprint "$snapshot")"; expires=$(( $(acmesh_auth_now) + 300 ))
				printf '%s\n%s\n' "$fp" "$expires" | acmesh_atomic_write "$tmp" 600 || return 1
				rm -f "$snapshot" "$summary" "$resolved"
			fi
			ACMESH_OPERATION_TASK_ID=; export ACMESH_OPERATION_TASK_ID; return 0 ;;
		renew:certificate)
			task_id="$(acmesh_task_create renew)"; workspace="$(acmesh_task_workspace "$task_id")"
			acmesh_task_spawn "$task_id" renew acme-sh acmesh_operation_run_renew "$subject_id" "$ACMESH_OPERATION_FINGERPRINT" "$workspace" || return 1 ;;
		core-install:global) task_id="$(acmesh_task_create core-install)"; acmesh_task_spawn "$task_id" core-install install acmesh_execute_core_install "$ACMESH_AUTH_ACME_HOME" "$ACMESH_AUTH_CORE_EMAIL" "$ACMESH_AUTH_CORE_TAG" || return 1 ;;
		core-upgrade:global) task_id="$(acmesh_task_create core-upgrade)"; acmesh_task_spawn "$task_id" core-upgrade upgrade acmesh_execute_core_upgrade "$ACMESH_AUTH_ACME_HOME" "$ACMESH_AUTH_CORE_TAG" || return 1 ;;
		import-apply:pendingImport)
			[ "$decision" = once ] || return 2
			ACMESH_OPERATION_TASK_ID=; export ACMESH_OPERATION_TASK_ID; return 0 ;;
		secret-export:config)
			ACMESH_OPERATION_TASK_ID=; export ACMESH_OPERATION_TASK_ID; return 0 ;;
		certificate-revoke:certificate|certificate-remove:certificate)
			task_id="$(acmesh_task_create "$operation")"; workspace="$(acmesh_task_workspace "$task_id")"
			acmesh_task_spawn "$task_id" "$operation" acme-sh acmesh_operation_run_certificate_destructive "$operation" "$subject_id" "$ACMESH_OPERATION_FINGERPRINT" "$workspace" || return 1 ;;
		profile-delete:profile)
			[ "$decision" = once ] || return 2
			ACMESH_OPERATION_TASK_ID=; export ACMESH_OPERATION_TASK_ID; return 0 ;;
		*) return 2 ;;
	esac
	ACMESH_OPERATION_TASK_ID="$task_id"
	export ACMESH_OPERATION_TASK_ID
}

acmesh_operation_direct_dispatch() {
	operation="$1" subject_id="$2"
	case "$operation" in
		import-apply)
			acmesh_config_apply_pending "$subject_id" || {
				operation_rc=$?
				acmesh_operation_emit_failure "$operation" "$operation_rc" 'migration restore failed'
				return "$operation_rc"
			}
			printf '{"ok":true,"authorized":true,"applied":true,"configDigest":"%s"}\n' "$subject_id"
			;;
		secret-export) acmesh_migration_archive_response "$ACMESH_AUTH_EXPORT_CERTS" "$ACMESH_AUTH_CONFIG_DIGEST" ;;
		profile-delete)
			case "$subject_id" in account.*) profile_kind=account; profile_id="${subject_id#account.}";; issue.*) profile_kind=issue; profile_id="${subject_id#issue.}";; deploy.*) profile_kind=deploy; profile_id="${subject_id#deploy.}";; *) return 2;; esac
			acmesh_config_delete_profile "$profile_kind" "$profile_id" "$ACMESH_AUTH_CONFIG_DIGEST"
			;;
		*) return 2;;
	esac
}

acmesh_operation_emit_failure() {
	operation_name="$1" operation_rc="$2" error_message="${3:-operation execution failed}"
	printf '{"ok":false,"error":"%s","operation":"%s","exitCode":%s}\n' \
		"$(acmesh_json_escape "$error_message")" "$(acmesh_json_escape "$operation_name")" "$operation_rc"
}

acmesh_operation_run_renew() {
	subject_id="$1" expected="$2" workspace="$3"
	lock_id="$(printf '%s\n' "$ACMESH_ACME_HOME:$subject_id" | sha256sum | awk '{print $1}')"
	acmesh_lock_run "${ACMESH_RUNTIME_DIR:-/var/run/acmesh-console}/renew-locks/$lock_id.lock" acmesh_operation_run_renew_locked "$subject_id" "$expected" "$workspace"
}

acmesh_operation_run_renew_locked() {
	subject_id="$1" expected="$2" workspace="$3"
	snapshot="$workspace/renew-final.snapshot" summary="$workspace/renew-final-summary.json"
	acmesh_operation_recompute renew certificate "$subject_id" "$snapshot" "$summary" || return 1
	[ "$(acmesh_auth_fingerprint "$snapshot")" = "$expected" ] || { echo "renew authorization identity changed before execution" >&2; return 1; }
	acmesh_profile_resolve_renew_credentials "$ACMESH_RENEW_CERT_CONF" "$ACMESH_RENEW_DOMAIN" "$ACMESH_RENEW_KEY_TYPE" "$ACMESH_RENEW_DNS_API" 1 || return 1
	acmesh_execute_renew "$ACMESH_ACME_HOME" "$ACMESH_RENEW_DOMAIN" "$ACMESH_RENEW_KEY_TYPE" "${ACMESH_RENEW_CREDENTIALS:-}"
}

acmesh_operation_run_certificate_destructive() {
	operation="$1" subject_id="$2" expected="$3" workspace="$4"
	lock_id="$(printf '%s\n' "$ACMESH_ACME_HOME:$subject_id" | sha256sum | awk '{print $1}')"
	acmesh_lock_run "${ACMESH_RUNTIME_DIR:-/var/run/acmesh-console}/certificate-locks/$lock_id.lock" acmesh_operation_run_certificate_destructive_locked "$operation" "$subject_id" "$expected" "$workspace"
}

acmesh_operation_run_certificate_destructive_locked() {
	operation="$1" subject_id="$2" expected="$3" workspace="$4"; snapshot="$workspace/final.snapshot" summary="$workspace/final-summary.json"
	acmesh_operation_recompute "$operation" certificate "$subject_id" "$snapshot" "$summary" || return 1
	[ "$(acmesh_auth_fingerprint "$snapshot")" = "$expected" ] || { echo "certificate identity changed before destructive execution" >&2; return 1; }
	case "$subject_id" in ecc.*) domain="${subject_id#ecc.}"; key_type=ecc;; rsa.*) domain="${subject_id#rsa.}"; key_type=rsa;; *) return 2;; esac
	case "$operation" in certificate-revoke) action=revoke;; certificate-remove) action=remove;; *) return 2;; esac
	acmesh_execute_certificate_destructive "$ACMESH_ACME_HOME" "$action" "$domain" "$key_type"
}

acmesh_operation_is_remembered() {
	operation="$1" subject_type="$2" subject_id="$3"
	[ "$(acmesh_operation_subject_type "$operation")" = "$subject_type" ] || return 2
	tmp="${ACMESH_AUTH_CHALLENGE_DIR}/.check.$$.$(date +%s)"; acmesh_private_dir "$tmp" || return 1
	rc=0; acmesh_operation_recompute "$operation" "$subject_type" "$subject_id" "$tmp/snapshot" "$tmp/summary" || rc=$?
	if [ "$rc" = 0 ]; then fingerprint="$(acmesh_auth_fingerprint "$tmp/snapshot")" || rc=$?; fi
	if [ "$rc" = 0 ]; then acmesh_auth_is_remembered "$operation" "$fingerprint" || rc=$?; fi
	rm -rf "$tmp"
	return "$rc"
}

acmesh_operation_start() {
	op_start_operation="$1" op_start_subject_type="$2" op_start_subject_id="$3" op_start_parameters_file="${4:-}"
	[ "$(acmesh_operation_subject_type "$op_start_operation")" = "$op_start_subject_type" ] || return 2
	op_start_tmp="${ACMESH_AUTH_CHALLENGE_DIR}/.prepare.$$.$(date +%s)"; acmesh_private_dir "$op_start_tmp" || return 1
	trap 'rm -rf "$op_start_tmp"' HUP INT TERM EXIT
	ACMESH_OPERATION_RESPONSE_FILE="$op_start_tmp/result"; export ACMESH_OPERATION_RESPONSE_FILE
	ACMESH_AUTH_RECOMPUTE_CALLBACK=acmesh_operation_recompute ACMESH_AUTH_ADMIT_CALLBACK=acmesh_operation_admit
	ACMESH_AUTH_REQUIRE_REMEMBERED="${ACMESH_OPERATION_REQUIRE_REMEMBERED:-0}"
	export ACMESH_AUTH_RECOMPUTE_CALLBACK ACMESH_AUTH_ADMIT_CALLBACK ACMESH_AUTH_REQUIRE_REMEMBERED
	recompute_response="$op_start_tmp/recompute-response"
	recompute_rc=0
	# Some preparation probes (notably SSH host-key verification) return a
	# structured response on stdout while also using a non-zero status to stop
	# the operation.  Capture that response so the RPC emits exactly one JSON
	# document instead of appending the generic preparation failure to it.
	acmesh_operation_recompute "$op_start_operation" "$op_start_subject_type" "$op_start_subject_id" "$op_start_tmp/snapshot" "$op_start_tmp/summary" > "$recompute_response" || recompute_rc=$?
	if [ "$recompute_rc" = 6 ]; then
		conversion_subject="${ACMESH_OPERATION_CONVERSION_SUBJECT:-$op_start_subject_id}"
		acmesh_operation_save_conversion_continuation "$op_start_operation" "$op_start_subject_id" "$conversion_subject" || { rm -rf "$op_start_tmp"; trap - HUP INT TERM EXIT; return 1; }
		rm -rf "$op_start_tmp"; trap - HUP INT TERM EXIT
		acmesh_operation_start ssh-key-convert sshKey "${ACMESH_OPERATION_CONVERSION_SUBJECT:-$op_start_subject_id}" "$op_start_parameters_file"; return $?
	fi
	if [ "$recompute_rc" != 0 ]; then
		recompute_response_lines="$(awk 'NF { count++ } END { print count + 0 }' "$recompute_response")"
		if [ "$recompute_response_lines" = 1 ] && [ "$(jsonfilter -i "$recompute_response" -t '@' 2>/dev/null || true)" = object ]; then
			cat "$recompute_response"
		else
			case "$op_start_operation" in
				import-apply) op_start_error='migration restore preparation failed' ;;
				*) op_start_error='operation preparation failed' ;;
			esac
			acmesh_operation_emit_failure "$op_start_operation" "$recompute_rc" "$op_start_error"
		fi
		rm -rf "$op_start_tmp"; trap - HUP INT TERM EXIT
		return "$recompute_rc"
	fi
	rc=0; umask 077; acmesh_auth_prepare "$op_start_operation" "$op_start_subject_type" "$op_start_subject_id" "$op_start_tmp/snapshot" "$op_start_tmp/summary" > "$op_start_tmp/response" || rc=$?; chmod 600 "$op_start_tmp/response" 2>/dev/null || true
	if [ "$rc" = 0 ]; then case "$op_start_operation" in import-apply|secret-export|profile-delete) acmesh_operation_direct_dispatch "$op_start_operation" "$op_start_subject_id" > "$op_start_tmp/response" || rc=$?;; esac; fi
	if [ ! -s "$op_start_tmp/response" ] && [ ! -s "$op_start_tmp/result" ]; then
		acmesh_operation_emit_failure "$op_start_operation" "$rc" > "$op_start_tmp/response"
	fi
	if [ "$rc" = 0 ] && [ -f "$op_start_tmp/result" ]; then cat "$op_start_tmp/result"; else cat "$op_start_tmp/response"; fi
	rm -rf "$op_start_tmp"; trap - HUP INT TERM EXIT
	return "$rc"
}

acmesh_operation_execute_challenge() {
	request_file="$1"
	challenge_id="$(acmesh_request_value "$request_file" challengeId '')" decision="$(acmesh_request_value "$request_file" decision '')"
	acmesh_auth_valid_id "$challenge_id" || { printf '{"ok":false,"error":"invalid authorization challenge"}\n'; return 2; }
	case "$decision" in once|remember) ;; *) printf '{"ok":false,"error":"invalid authorization decision"}\n'; return 2 ;; esac
	op_execute_tmp="${ACMESH_AUTH_CHALLENGE_DIR}/.execute.$$.$(date +%s)"; acmesh_private_dir "$op_execute_tmp" || return 1
	ACMESH_OPERATION_RESPONSE_FILE="$op_execute_tmp/result"; export ACMESH_OPERATION_RESPONSE_FILE
	ACMESH_AUTH_RECOMPUTE_CALLBACK=acmesh_operation_recompute ACMESH_AUTH_ADMIT_CALLBACK=acmesh_operation_admit
	export ACMESH_AUTH_RECOMPUTE_CALLBACK ACMESH_AUTH_ADMIT_CALLBACK
	rc=0; umask 077; acmesh_auth_execute "$challenge_id" "$decision" > "$op_execute_tmp/response" || rc=$?; chmod 600 "$op_execute_tmp/response" 2>/dev/null || true
	if [ "$rc" = 0 ]; then case "${ACMESH_AUTH_EXECUTED_OPERATION:-}" in import-apply|secret-export|profile-delete) acmesh_operation_direct_dispatch "$ACMESH_AUTH_EXECUTED_OPERATION" "$ACMESH_AUTH_EXECUTED_SUBJECT_ID" > "$op_execute_tmp/response" || rc=$?;; esac; fi
	if [ ! -s "$op_execute_tmp/response" ] && [ ! -s "$op_execute_tmp/result" ]; then
		acmesh_operation_emit_failure "${ACMESH_AUTH_EXECUTED_OPERATION:-authorization-execute}" "$rc" > "$op_execute_tmp/response"
	fi
	if [ "$rc" = 0 ] && [ "${ACMESH_AUTH_EXECUTED_OPERATION:-}" = ssh-key-convert ]; then
		continuation="$(acmesh_operation_take_conversion_continuation "$ACMESH_AUTH_EXECUTED_SUBJECT_ID" 2>/dev/null || true)"
		if [ -n "$continuation" ]; then
			parent_operation="$(printf '%s\n' "$continuation" | sed -n '1p')"
			parent_subject_id="$(printf '%s\n' "$continuation" | sed -n '2p')"
			rm -rf "$op_execute_tmp"
			acmesh_operation_start "$parent_operation" "$(acmesh_operation_subject_type "$parent_operation")" "$parent_subject_id" "$request_file"
			return $?
		fi
		rm -rf "$op_execute_tmp"; acmesh_operation_start deploy-run deployProfile "$ACMESH_AUTH_EXECUTED_SUBJECT_ID" "$request_file"; return $?
	elif [ "$rc" = 0 ] && [ -f "$op_execute_tmp/result" ]; then cat "$op_execute_tmp/result"; else cat "$op_execute_tmp/response"; fi
	rm -rf "$op_execute_tmp"
	return "$rc"
}
