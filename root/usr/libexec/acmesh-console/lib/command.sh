. "${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}/json.sh"

acmesh_shell_quote() {
	printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

acmesh_mask_secret() {
	printf '%s' "$1" | sed -E \
		-e "s/(([A-Za-z0-9_]*(Token|TOKEN|token|Key|KEY|key|Secret|SECRET|secret|Password|PASSWORD|password|Authorization|AUTHORIZATION|authorization|Credential|CREDENTIAL|credential)[A-Za-z0-9_]*|[A-Za-z0-9_]*_(SK|Sk|sk))=)'[^']*'/\1'***'/g" \
		-e "s/(([A-Za-z0-9_]*(Token|TOKEN|token|Key|KEY|key|Secret|SECRET|secret|Password|PASSWORD|password|Authorization|AUTHORIZATION|authorization|Credential|CREDENTIAL|credential)[A-Za-z0-9_]*|[A-Za-z0-9_]*_(SK|Sk|sk))=)[^ ]+/\1'***'/g"
}

acmesh_credential_prefix() {
	credentials="${1:-}"
	[ -n "$credentials" ] || return 0
	printf '%s\n' "$credentials" | while IFS= read -r cred; do
		[ -n "$cred" ] || continue
		case "$cred" in *"$(printf '\r')"*|*'\r'*|*'\n'*|*'\u0000'*) return 1;; esac
		case "$cred" in *=*) name=${cred%%=*};; *) return 1;; esac
		printf '%s\n' "$name" | grep -Eq '^[A-Za-z_][A-Za-z0-9_]*$' || return 1
		case "$name" in PATH|ENV|BASH_ENV|IFS|CDPATH|LD_*) return 1;; esac
		case "$cred" in
			*=*)
				name=${cred%%=*}
				value=${cred#*=}
				case "$name" in
					*[!A-Za-z0-9_]*|'') continue ;;
				esac
				printf '%s=%s ' "$name" "$(acmesh_shell_quote "$value")"
				;;
		esac
	done
}

acmesh_redact_credentials() {
	credentials="${1:-}"
	[ -n "$credentials" ] || return 0
	printf '%s\n' "$credentials" | while IFS= read -r cred; do
		case "$cred" in *=*) name=${cred%%=*}; printf '%s=***\n' "$name";; esac
	done
}

acmesh_sanitize_credentials() {
	credentials="${1:-}"
	[ -n "$credentials" ] || return 0
	old_ifs=$IFS
	IFS='
'
	for cred in $credentials; do
		[ -n "$cred" ] || continue
		case "$cred" in *"$(printf '\r')"*|*'\r'*|*'\n'*|*'\u0000'*) IFS=$old_ifs; return 1;; esac
		case "$cred" in *=*) name=${cred%%=*};; *) IFS=$old_ifs; return 1;; esac
		printf '%s\n' "$name" | grep -Eq '^[A-Za-z_][A-Za-z0-9_]*$' || { IFS=$old_ifs; return 1; }
		case "$name" in PATH|ENV|BASH_ENV|IFS|CDPATH|LD_*) IFS=$old_ifs; return 1;; esac
		case "$cred" in
			CF_Zone_ID=|CF_Account_ID=|CF_Zone_ID=-|CF_Account_ID=-|CF_Zone_ID=none|CF_Account_ID=none|CF_Zone_ID=null|CF_Account_ID=null) continue ;;
		esac
		printf '%s\n' "$cred"
	done
	IFS=$old_ifs
}

acmesh_ca_server_value() {
	case "${1:-letsencrypt}" in
		''|letsencrypt|production)
			printf '%s\n' letsencrypt
			;;
		letsencrypt_staging|staging)
			printf '%s\n' letsencrypt_test
			;;
		zerossl|google)
			printf '%s\n' "$1"
			;;
		https://*|http://*)
			printf '%s\n' "$1"
			;;
		*)
			echo "unsupported ca: $1" >&2
			return 1
			;;
	esac
}

acmesh_build_issue_command() {
	home="$1"
	main_domain="$2"
	key_type="$3"
	validation_method="${4:-dns}"
	dns_api="${5:-}"
	webroot="${6:-}"
	listen_port="${7:-}"
	credentials="$(acmesh_sanitize_credentials "${8:-}")"
	ca="${9:-letsencrypt}"
	account_email="${10:-}"
	domains="${11:-$main_domain}"
	challenge_alias="${12:-}"
	dns_sleep="${13:-}"

	[ -n "$main_domain" ] || { echo "main domain is required" >&2; return 1; }
	[ -n "$key_type" ] || key_type="ecc"

	case "$validation_method" in
		dns|webroot|standalone|alpn) ;;
		*)
			dns_api="$validation_method"
			validation_method="dns"
			;;
	esac

	[ -n "$dns_api" ] || dns_api="dns_cf"

	keylength="$(acmesh_keylength_value "$key_type")" || return 1
	server_value="$(acmesh_ca_server_value "$ca")" || return 1
	server_args=""
	[ -n "$server_value" ] && server_args="--server $(acmesh_shell_quote "$server_value")"

	case "$validation_method" in
		dns)
			validation_args="--dns $(acmesh_shell_quote "$dns_api")"
			;;
		webroot)
			[ -n "$webroot" ] || webroot="/www"
			validation_args="--webroot $(acmesh_shell_quote "$webroot")"
			;;
		standalone)
			validation_args="--standalone"
			[ -n "$listen_port" ] && validation_args="$validation_args --httpport $listen_port"
			;;
		alpn)
			validation_args="--alpn"
			[ -n "$listen_port" ] && validation_args="$validation_args --tlsport $listen_port"
			;;
	esac

	account_prefix=""
	account_args=""
	if [ -n "$account_email" ]; then
		account_prefix="ACCOUNT_EMAIL=$(acmesh_shell_quote "$account_email") "
		account_args="--accountemail $(acmesh_shell_quote "$account_email")"
	fi

	domain_args=""
	while IFS= read -r issue_domain; do [ -n "$issue_domain" ] && domain_args="$domain_args -d $(acmesh_shell_quote "$issue_domain")"; done <<EOF
$domains
EOF
	[ -n "$domain_args" ] || domain_args=" -d $(acmesh_shell_quote "$main_domain")"
	extra_args=""
	[ -n "$challenge_alias" ] && extra_args="$extra_args --challenge-alias $(acmesh_shell_quote "$challenge_alias")"
	[ -n "$dns_sleep" ] && [ "$dns_sleep" != 0 ] && extra_args="$extra_args --dnssleep $(acmesh_shell_quote "$dns_sleep")"
	printf '%s%sacme.sh --home %s --issue %s %s %s%s%s %s\n' \
		"$account_prefix" \
		"$(acmesh_credential_prefix "$credentials")" \
		"$(acmesh_shell_quote "$home")" \
		"$server_args" \
		"$account_args" \
		"$validation_args" \
		"$domain_args" \
		"$extra_args" \
		"--keylength $keylength"
}

acmesh_issue_preview_json() {
	home="$1"
	main_domain="$2"
	key_type="$3"
	validation_method="$4"
	dns_api="$5"
	webroot="$6"
	listen_port="$7"
	credentials="$(acmesh_sanitize_credentials "${8:-}")"
	ca="${9:-letsencrypt}"
	account_email="${10:-}"
	domains="${11:-$main_domain}"
	challenge_alias="${12:-}"
	dns_sleep="${13:-}"
	command="$(acmesh_build_issue_command "$home" "$main_domain" "$key_type" "$validation_method" "$dns_api" "$webroot" "$listen_port" "$credentials" "$ca" "$account_email" "$domains" "$challenge_alias" "$dns_sleep")"
	printf '{"ok":true,"command":"%s"}\n' "$(acmesh_json_escape "$(acmesh_mask_secret "$command")")"
}

acmesh_keylength_value() {
	case "$1" in
		ecc|ec256|ec-256) printf 'ec-256' ;;
		ec384|ec-384) printf 'ec-384' ;;
		ec521|ec-521) printf 'ec-521' ;;
		rsa|rsa2048|2048) printf '2048' ;;
		rsa3072|3072) printf '3072' ;;
		rsa4096|4096) printf '4096' ;;
		rsa8192|8192) printf '8192' ;;
		*) echo "unsupported key type: $1" >&2; return 1 ;;
	esac
}

acmesh_key_type_is_ecc() {
	case "${1:-}" in
		ecc|ec256|ec-256|ec384|ec-384|ec521|ec-521) return 0 ;;
		*) return 1 ;;
	esac
}

acmesh_find_script() {
	home="$1"
	if [ -x "$home/acme.sh" ]; then
		printf '%s/acme.sh\n' "$home"
	elif command -v acme.sh >/dev/null 2>&1; then
		command -v acme.sh
	else
		return 1
	fi
}

acmesh_reconcile_account_email() {
	home="$1"
	account_email="$2"
	[ -n "$account_email" ] || return 0
	mkdir -p "$home"
	account_conf="$home/account.conf"
	tmp="$account_conf.tmp.$$"
	escaped="$(printf '%s' "$account_email" | sed "s/'/'\\\\''/g")"
	if [ -f "$account_conf" ]; then
		if grep -q '^[[:space:]]*ACCOUNT_EMAIL=' "$account_conf"; then
			sed "s/^[[:space:]]*ACCOUNT_EMAIL=.*/ACCOUNT_EMAIL='$escaped'/" "$account_conf" > "$tmp"
		else
			cat "$account_conf" > "$tmp"
			printf "ACCOUNT_EMAIL='%s'\n" "$escaped" >> "$tmp"
		fi
	else
		printf "ACCOUNT_EMAIL='%s'\n" "$escaped" > "$tmp"
	fi
	mv "$tmp" "$account_conf"
}

acmesh_execute_issue() {
	home="$1"
	main_domain="$2"
	key_type="$3"
	validation_method="$4"
	dns_api="$5"
	webroot="$6"
	listen_port="$7"
	credentials="$(acmesh_sanitize_credentials "${8:-}")"
	ca="${9:-letsencrypt}"
	account_email="${10:-}"
	domains="${11:-$main_domain}"
	challenge_alias="${12:-}"
	dns_sleep="${13:-}"
	[ -n "$account_email" ] || { echo "account email is required for real mode" >&2; return 1; }
	log_credentials="$(acmesh_redact_credentials "$credentials")"
	command="$(acmesh_build_issue_command "$home" "$main_domain" "$key_type" "$validation_method" "$dns_api" "$webroot" "$listen_port" "$log_credentials" "$ca" "$account_email" "$domains" "$challenge_alias" "$dns_sleep")"
	script="$(acmesh_find_script "$home")" || {
		printf 'acme.sh not found in %s or PATH\n' "$home" >&2
		return 127
	}
	keylength="$(acmesh_keylength_value "$key_type")"
	server_value="$(acmesh_ca_server_value "$ca")" || return 1

	printf 'REAL MODE: executing acme.sh command\n'
	printf '%s\n' "$(acmesh_mask_secret "$command")"
	if [ -n "$credentials" ]; then
		while IFS= read -r cred; do
			[ -n "$cred" ] || continue
			case "$cred" in
				*=*)
					name=${cred%%=*}
					value=${cred#*=}
					case "$name" in
						*[!A-Za-z0-9_]*|'') continue ;;
					esac
					export "$name=$value"
					;;
			esac
		done <<EOF
$credentials
EOF
	fi
	if [ -n "$account_email" ]; then
		acmesh_reconcile_account_email "$home" "$account_email"
		printf 'Using account email: %s\n' "$account_email"
		export ACCOUNT_EMAIL="$account_email"
	fi
	case "$validation_method" in
		dns)
			set -- "$script" --home "$home" --issue
			[ -n "$server_value" ] && set -- "$@" --server "$server_value"
			[ -n "$account_email" ] && set -- "$@" --accountemail "$account_email"
			set -- "$@" --dns "$dns_api"
			while IFS= read -r issue_domain; do [ -n "$issue_domain" ] && set -- "$@" -d "$issue_domain"; done <<EOF
$domains
EOF
			[ -n "$challenge_alias" ] && set -- "$@" --challenge-alias "$challenge_alias"
			[ -n "$dns_sleep" ] && [ "$dns_sleep" != 0 ] && set -- "$@" --dnssleep "$dns_sleep"
			"$@" --keylength "$keylength"
			;;
		webroot)
			[ -n "$webroot" ] || webroot="/www"
			set -- "$script" --home "$home" --issue
			[ -n "$server_value" ] && set -- "$@" --server "$server_value"
			[ -n "$account_email" ] && set -- "$@" --accountemail "$account_email"
			set -- "$@" --webroot "$webroot"; while IFS= read -r issue_domain; do [ -n "$issue_domain" ] && set -- "$@" -d "$issue_domain"; done <<EOF
$domains
EOF
			"$@" --keylength "$keylength"
			;;
		standalone)
			set -- "$script" --home "$home" --issue
			[ -n "$server_value" ] && set -- "$@" --server "$server_value"
			[ -n "$account_email" ] && set -- "$@" --accountemail "$account_email"
			if [ -n "$listen_port" ]; then
				set -- "$@" --standalone --httpport "$listen_port"
			else
				set -- "$@" --standalone
			fi
			while IFS= read -r issue_domain; do [ -n "$issue_domain" ] && set -- "$@" -d "$issue_domain"; done <<EOF
$domains
EOF
			"$@" --keylength "$keylength"
			;;
		alpn)
			set -- "$script" --home "$home" --issue
			[ -n "$server_value" ] && set -- "$@" --server "$server_value"
			[ -n "$account_email" ] && set -- "$@" --accountemail "$account_email"
			if [ -n "$listen_port" ]; then
				set -- "$@" --alpn --tlsport "$listen_port"
			else
				set -- "$@" --alpn
			fi
			while IFS= read -r issue_domain; do [ -n "$issue_domain" ] && set -- "$@" -d "$issue_domain"; done <<EOF
$domains
EOF
			"$@" --keylength "$keylength"
			;;
		*)
			echo "unsupported validation method: $validation_method" >&2
			return 1
			;;
	esac
}

acmesh_build_renew_command() {
	home="$1"
	main_domain="$2"
	key_type="${3:-}"
	[ -n "$main_domain" ] || { echo "domain is required" >&2; return 1; }
	printf 'acme.sh --home %s --renew -d %s' \
		"$(acmesh_shell_quote "$home")" \
		"$(acmesh_shell_quote "$main_domain")"
	if [ -n "$key_type" ] && acmesh_key_type_is_ecc "$key_type"; then
		printf ' --ecc'
	fi
	printf '\n'
}

acmesh_execute_renew() {
	home="$1"
	main_domain="$2"
	key_type="${3:-}"
	credentials="$(acmesh_sanitize_credentials "${4:-}")"
	[ -n "$main_domain" ] || { echo "domain is required" >&2; return 1; }
	script="$(acmesh_find_script "$home")" || {
		printf 'acme.sh not found in %s or PATH\n' "$home" >&2
		return 127
	}
	deploy_id="$(acmesh_profile_find_linked_deploy "$main_domain" "$key_type" 2>/dev/null || true)"
	if [ -n "$deploy_id" ]; then
		acmesh_deploy_install_acme_hooks "$home" || { echo "unable to install acme.sh deploy hook" >&2; return 1; }
	fi
	command="$(acmesh_build_renew_command "$home" "$main_domain" "$key_type")"
	printf 'REAL MODE: executing acme.sh renew\n'
	printf '%s\n' "$command"
	set -- "$script" --home "$home" --renew -d "$main_domain"
	if [ -n "$key_type" ] && acmesh_key_type_is_ecc "$key_type"; then
		set -- "$@" --ecc
	fi
	if [ -n "$credentials" ]; then
		while IFS= read -r cred; do
			[ -n "$cred" ] || continue
			case "$cred" in
				*=*)
					name=${cred%%=*}
					value=${cred#*=}
					export "$name=$value"
					;;
				esac
		done <<EOF
$credentials
EOF
	fi
	"$@"
}

acmesh_build_certificate_destructive_command() {
	home="$1" action="$2" domain="$3" key_type="${4:-}"
	case "$action" in revoke|remove) ;; *) return 2;; esac
	command="$(acmesh_shell_quote "$(acmesh_find_script "$home" 2>/dev/null || printf '%s/acme.sh' "$home")") --home $(acmesh_shell_quote "$home") --$action -d $(acmesh_shell_quote "$domain")"
	[ -z "$key_type" ] || ! acmesh_key_type_is_ecc "$key_type" || command="$command --ecc"
	printf '%s\n' "$command"
}

acmesh_execute_certificate_destructive() {
	home="$1" action="$2" domain="$3" key_type="${4:-}"
	case "$action" in revoke|remove) ;; *) return 2;; esac
	script="$(acmesh_find_script "$home")" || { printf 'acme.sh not found in %s or PATH\n' "$home" >&2; return 127; }
	printf 'REAL MODE: executing acme.sh certificate %s\n' "$action"
	acmesh_build_certificate_destructive_command "$home" "$action" "$domain" "$key_type"
	set -- "$script" --home "$home" "--$action" -d "$domain"
	[ -z "$key_type" ] || ! acmesh_key_type_is_ecc "$key_type" || set -- "$@" --ecc
	"$@"
}

acmesh_import_history() {
	home="$1"
	status="$(acmesh_scan_home "$home")"
	count="$(printf '%s' "$status" | grep -o '"mainDomain"' | wc -l | tr -d ' ')"
	printf 'Importing acme.sh history from %s\n' "$home"
	printf 'Imported certificate variants: %s\n' "$count"
	printf '%s\n' "$status" | sed 's/[{}]/\n/g' | grep -E '"mainDomain"|"keyType"' || true
}

acmesh_core_status_json() {
	home="$1"
	script=""
	version=""
	version_raw=""
	installed=false
	openssl_bin="${ACME_OPENSSL_BIN:-openssl}"
	openssl_available=false
	curl_available=false
	wget_available=false
	package_manager="none"

	if script="$(acmesh_find_script "$home" 2>/dev/null)"; then
		installed=true
		version_raw="$("$script" --version 2>&1 | head -n 2 || true)"
		version="$(printf '%s\n' "$version_raw" | sed -n 's/.*\(v[0-9][0-9A-Za-z._-]*\).*/\1/p' | head -n 1)"
		[ -n "$version" ] || version="$(printf '%s\n' "$version_raw" | head -n 1)"
	fi
	command -v "$openssl_bin" >/dev/null 2>&1 && openssl_available=true
	command -v curl >/dev/null 2>&1 && curl_available=true
	command -v wget >/dev/null 2>&1 && wget_available=true
	if command -v apk >/dev/null 2>&1; then
		package_manager="apk"
	elif command -v opkg >/dev/null 2>&1; then
		package_manager="opkg"
	fi

	printf '{"ok":true,"home":"%s","homeExists":%s,"installed":%s,"script":"%s","version":"%s","accountConf":%s,"dependencies":{"openssl":%s,"opensslBin":"%s","curl":%s,"wget":%s,"packageManager":"%s"}}\n' \
		"$(acmesh_json_escape "$home")" \
		"$([ -d "$home" ] && printf true || printf false)" \
		"$installed" \
		"$(acmesh_json_escape "$script")" \
		"$(acmesh_json_escape "$version")" \
		"$([ -f "$home/account.conf" ] && printf true || printf false)" \
		"$openssl_available" \
		"$(acmesh_json_escape "$openssl_bin")" \
		"$curl_available" \
		"$wget_available" \
		"$(acmesh_json_escape "$package_manager")"
}

acmesh_core_install_command() {
	home="$1"
	email="$2"
	tag="${3:-${ACMESH_CORE_TAG:-v3.1.4}}"
	tag="$(acmesh_core_tag_value "$tag")" || return 1
	email_args=""
	[ -n "$email" ] && email_args=" --accountemail $(acmesh_shell_quote "$email")"
	printf 'curl -fsSL %s | tar -xz -C /tmp && cd %s && LE_WORKING_DIR=%s LE_CONFIG_HOME=%s ./acme.sh --install --home %s --config-home %s%s --no-profile\n' \
		"$(acmesh_shell_quote "$(acmesh_core_tag_url "$tag")")" \
		"$(acmesh_shell_quote "/tmp/acme.sh-${tag#v}")" \
		"$(acmesh_shell_quote "$home")" \
		"$(acmesh_shell_quote "$home")" \
		"$(acmesh_shell_quote "$home")" \
		"$(acmesh_shell_quote "$home")" \
		"$email_args"
	printf '# target home requested by console: %s\n' "$(acmesh_shell_quote "$home")"
	printf '# acme.sh tag: %s\n' "$(acmesh_shell_quote "$tag")"
}

acmesh_core_tag_value() {
	tag="${1:-${ACMESH_CORE_TAG:-v3.1.4}}"
	case "$tag" in
		v[0-9]*.[0-9]*.[0-9]*|[0-9]*.[0-9]*.[0-9]*)
			case "$tag" in
				v*) printf '%s\n' "$tag" ;;
				*) printf 'v%s\n' "$tag" ;;
			esac
			;;
		*)
			echo "unsupported acme.sh tag: $tag" >&2
			return 1
			;;
	esac
}

acmesh_core_tag_url() {
	tag="$(acmesh_core_tag_value "$1")" || return 1
	printf 'https://codeload.github.com/acmesh-official/acme.sh/tar.gz/refs/tags/%s\n' "${tag#v}"
}

acmesh_core_require_openssl() {
	openssl_bin="${ACME_OPENSSL_BIN:-openssl}"
	if command -v "$openssl_bin" >/dev/null 2>&1; then
		return 0
	fi

	printf 'openssl is required before installing acme.sh. ACME_OPENSSL_BIN=%s\n' "$openssl_bin" >&2
	printf 'Install it first, then retry core install:\n' >&2
	printf '  apk add openssl-util\n' >&2
	printf '  opkg update && opkg install openssl-util\n' >&2
	return 127
}

acmesh_execute_core_install() {
	home="$1"
	email="$2"
	tag="${3:-${ACMESH_CORE_TAG:-v3.1.4}}"
	tag="$(acmesh_core_tag_value "$tag")" || return 1
	mkdir -p "$home"
	backup_dir="${ACMESH_CORE_BACKUP_DIR:-$home/.acmesh-console-backup.$$}"
	old_script="$home/acme.sh" old_sha= absent=0
	if [ -f "$old_script" ] && [ ! -L "$old_script" ]; then
		(umask 077; mkdir -p "$backup_dir" && chmod 700 "$backup_dir" && cp -p "$old_script" "$backup_dir/acme.sh") || return 1
		old_sha="$(sha256sum "$old_script" | awk '{print $1}')"
		(umask 077; "$old_script" --version > "$backup_dir/version.txt" 2>&1) || { rm -rf "$backup_dir"; return 1; }
	else absent=1; fi
	rollback_core() {
		if [ -f "$backup_dir/acme.sh" ]; then cp -p "$backup_dir/acme.sh" "$old_script.rollback.$$" && mv -f "$old_script.rollback.$$" "$old_script" && printf 'Rollback restored previous acme.sh (%s).\n' "$old_sha" >&2
		elif [ "$absent" = 1 ]; then rm -f "$old_script"; printf 'Rollback removed incomplete install.\n' >&2; fi
	}
	workdir="${ACMESH_CORE_TMPDIR:-/tmp/acmesh-console-core-$$}"
	archive="$workdir/acme.sh-$tag.tar.gz"
	printf 'REAL MODE: installing acme.sh from official tag %s\n' "$tag"
	acmesh_core_install_command "$home" "$email" "$tag"
	acmesh_core_require_openssl || { rc=$?; rollback_core; rm -rf "$backup_dir"; return "$rc"; }
	rm -rf "$workdir"
	mkdir -p "$workdir"
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL "$(acmesh_core_tag_url "$tag")" -o "$archive" || { rollback_core; rm -rf "$workdir" "$backup_dir"; return 1; }
	elif command -v wget >/dev/null 2>&1; then
		wget -O "$archive" "$(acmesh_core_tag_url "$tag")" || { rollback_core; rm -rf "$workdir" "$backup_dir"; return 1; }
	else
		echo "curl or wget is required to install acme.sh" >&2
		rm -rf "$workdir"
		rollback_core; rm -rf "$backup_dir"; return 127
	fi
	if ! tar -xzf "$archive" -C "$workdir"; then rollback_core; rm -rf "$workdir" "$backup_dir"; return 1; fi
	src="$workdir/acme.sh-${tag#v}"
	if [ ! -d "$src" ]; then
		src=""
		for dir in "$workdir"/acme.sh-*; do
			[ -d "$dir" ] || continue
			src="$dir"
			break
		done
	fi
	[ -n "$src" ] && [ -x "$src/acme.sh" ] && "$src/acme.sh" --version >/dev/null 2>&1 || { echo "unusable official tag archive" >&2; rollback_core; rm -rf "$workdir" "$backup_dir"; return 1; }
	(
		cd "$src"
		if [ -n "$email" ]; then
			LE_WORKING_DIR="$home" LE_CONFIG_HOME="$home" ./acme.sh --install --home "$home" --config-home "$home" --accountemail "$email" --no-profile
		else
			LE_WORKING_DIR="$home" LE_CONFIG_HOME="$home" ./acme.sh --install --home "$home" --config-home "$home" --no-profile
		fi
	)
	rc=$?
	if [ "$rc" = 0 ]; then [ -x "$old_script" ] && "$old_script" --version >/dev/null 2>&1 || rc=1; fi
	[ "$rc" = 0 ] || rollback_core
	rm -rf "$workdir"
	rm -rf "$backup_dir"
	return "$rc"
}

acmesh_core_upgrade_command() {
	home="$1"
	tag="${2:-${ACMESH_CORE_TAG:-v3.1.4}}"
	acmesh_core_install_command "$home" "" "$tag"
}

acmesh_core_upgrade_test_log() {
	home="$1"
	tag="${2:-${ACMESH_CORE_TAG:-v3.1.4}}"
	script="$(acmesh_find_script "$home")" || { echo "acme.sh not found" >&2; return 1; }
	version="$("$script" --version 2>&1 | head -n 2 | tr '\n' ' ' || true)"
	printf 'TEST MODE: generated tag-pinned acme.sh upgrade command, but did not download or replace anything.\n'
	printf 'Current: %s\n' "$version"
	acmesh_core_upgrade_command "$home" "$tag"
}

acmesh_execute_core_upgrade() {
	home="$1"
	tag="${2:-${ACMESH_CORE_TAG:-v3.1.4}}"
	acmesh_find_script "$home" >/dev/null || { echo "acme.sh not found" >&2; return 1; }
	printf 'REAL MODE: upgrading acme.sh by installing official tag %s\n' "$(acmesh_core_tag_value "$tag")"
	acmesh_execute_core_install "$home" "" "$tag"
}
