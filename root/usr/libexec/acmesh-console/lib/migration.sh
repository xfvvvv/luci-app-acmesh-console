LIB_DIR="${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}"
. "$LIB_DIR/json.sh"
. "$LIB_DIR/io.sh"

if [ -z "${ACMESH_MIGRATION_MAX_ARCHIVE_BYTES-}" ]; then ACMESH_MIGRATION_MAX_ARCHIVE_BYTES=16777216; fi
if [ -z "${ACMESH_MIGRATION_MAX_FILE_BYTES-}" ]; then ACMESH_MIGRATION_MAX_FILE_BYTES=8388608; fi
if [ -z "${ACMESH_MIGRATION_ACME_ROOT-}" ]; then ACMESH_MIGRATION_ACME_ROOT=/etc/acme; fi
if [ -z "${ACMESH_MIGRATION_CONSOLE_ROOT-}" ]; then ACMESH_MIGRATION_CONSOLE_ROOT=/etc/acmesh-console; fi
if [ -z "${ACMESH_MIGRATION_SSL_ROOT-}" ]; then ACMESH_MIGRATION_SSL_ROOT=/etc/ssl; fi
if [ -z "${ACMESH_MIGRATION_UCI_CONFIG-}" ]; then ACMESH_MIGRATION_UCI_CONFIG=/etc/config/acmesh-console; fi

acmesh_migration_canonical_root() {
	case "$1" in
		/etc/acme|/etc/acme/*) printf '%s\n' acme ;;
		/etc/acmesh-console|/etc/acmesh-console/*) printf '%s\n' console ;;
		/etc/ssl|/etc/ssl/*) printf '%s\n' ssl ;;
		*) return 1 ;;
	esac
}

acmesh_migration_map_path() {
	case "$1" in
		/etc/acme) printf '%s\n' "$ACMESH_MIGRATION_ACME_ROOT" ;;
		/etc/acme/*) printf '%s/%s\n' "$ACMESH_MIGRATION_ACME_ROOT" "$(printf '%s' "$1" | sed 's#^/etc/acme/##')" ;;
		/etc/acmesh-console) printf '%s\n' "$ACMESH_MIGRATION_CONSOLE_ROOT" ;;
		/etc/acmesh-console/*) printf '%s/%s\n' "$ACMESH_MIGRATION_CONSOLE_ROOT" "$(printf '%s' "$1" | sed 's#^/etc/acmesh-console/##')" ;;
		/etc/ssl) printf '%s\n' "$ACMESH_MIGRATION_SSL_ROOT" ;;
		/etc/ssl/*) printf '%s/%s\n' "$ACMESH_MIGRATION_SSL_ROOT" "$(printf '%s' "$1" | sed 's#^/etc/ssl/##')" ;;
		/etc/config/acmesh-console) printf '%s\n' "$ACMESH_MIGRATION_UCI_CONFIG" ;;
		*) return 1 ;;
	esac
}

acmesh_migration_safe_relative() {
	safe_relative_path="$1"
	case "$safe_relative_path" in
		''|/*|*\\*) return 1 ;;
	esac
	while [ "${safe_relative_path%/}" != "$safe_relative_path" ]; do
		safe_relative_path=${safe_relative_path%/}
	done
	[ -n "$safe_relative_path" ] || return 1
	case "$safe_relative_path" in
		*/../*|../*|*/..|..) return 1 ;;
	esac
	return 0
}

acmesh_migration_safe_file() (
	safe_file_path="$1"
	[ -f "$safe_file_path" ] && [ ! -L "$safe_file_path" ] || return 1
	safe_file_size=$(wc -c < "$safe_file_path" | tr -d ' ')
	case "$safe_file_size" in ''|*[!0-9]*) return 1 ;; esac
	[ "$safe_file_size" -le "$ACMESH_MIGRATION_MAX_FILE_BYTES" ]
)

acmesh_migration_is_runtime_state() {
	case "$1" in
		etc/acmesh-console/instance-id|etc/acmesh-console/authorization.lock|etc/acmesh-console/authorizations.json|etc/acmesh-console/authorizations.json.*|etc/acmesh-console/config.lock|etc/acmesh-console/ssh/known_hosts|etc/acmesh-console/ssh/known_hosts.lock)
			return 0
			;;
		*) return 1 ;;
	esac
}

acmesh_migration_copy_tree() {
	source="$1" relroot="$2" stage="$3"
	[ -d "$source" ] && [ ! -L "$source" ] || return 0
	mkdir -p "$stage/$relroot" || return 1
	find "$source" -type d -print | while IFS= read -r path; do
		rel="${path#"$source"/}"
		[ "$rel" = "$path" ] && rel=
		[ -z "$rel" ] || mkdir -p "$stage/$relroot/$rel" || exit 1
	done || return 1
	find "$source" -type f -print | while IFS= read -r path; do
		rel="${path#"$source"/}"
		[ "$rel" != "$path" ] || exit 1
		acmesh_migration_safe_relative "$rel" || exit 1
		acmesh_migration_is_runtime_state "$relroot/$rel" && continue
		cp -p "$path" "$stage/$relroot/$rel" || exit 1
	done || return 1
}

acmesh_migration_collect_deploy_files() {
	config_path="$1" output="$2"
	: > "$output"
	for field in keyFile fullchainFile certFile caFile sourceKeyFile sourceFullchainFile; do
		jsonfilter -i "$config_path" -e "@.deployProfiles[*].$field" 2>/dev/null | while IFS= read -r path; do
			[ -n "$path" ] || continue
			if ! acmesh_migration_canonical_root "$path" >/dev/null 2>&1; then
				printf '%s\n' skipped >> "$output"
				continue
			fi
			mapped=$(acmesh_migration_map_path "$path") || { printf '%s\n' skipped >> "$output"; continue; }
			if ! acmesh_migration_safe_file "$mapped"; then
				printf '%s\n' skipped >> "$output"
				continue
			fi
			grep -Fx "$path" "$output" >/dev/null 2>&1 || printf '%s\n' "$path" >> "$output"
		done
	done
}

acmesh_migration_collect_deploy_paths() {
	config_path="$1" output="$2"
	: > "$output"
	for field in keyFile fullchainFile certFile caFile sourceKeyFile sourceFullchainFile; do
		jsonfilter -i "$config_path" -e "@.deployProfiles[*].$field" 2>/dev/null | while IFS= read -r path; do
			[ -n "$path" ] || continue
			acmesh_migration_canonical_root "$path" >/dev/null 2>&1 || continue
			grep -Fx "$path" "$output" >/dev/null 2>&1 || printf '%s\n' "$path" >> "$output"
		done
	done
}

acmesh_migration_write_manifest() {
	stage="$1" include_certs="$2" skipped="$3"
	files=$(find "$stage/etc" -type f 2>/dev/null | wc -l | tr -d ' ')
	printf '{"format":"acmesh-console-backup","version":1,"includeDeploymentCertificates":%s,"fileCount":%s,"skippedDeploymentFiles":%s}\n' "$include_certs" "$files" "$skipped" > "$stage/acmesh-console-backup.json"
}

acmesh_migration_build_archive() {
	include_certs="$1" archive="$2" persistent_config_path=$(acmesh_config_path)
	parent=$(dirname "$archive"); tmp="$parent/.migration-build.$$.$(date +%s)"; stage="$tmp/stage"
	trap 'rm -rf "$tmp"' HUP INT TERM EXIT
	config_path="$persistent_config_path"; default_config=
	if [ -s "$persistent_config_path" ]; then
		acmesh_config_validate_file "$persistent_config_path" || return 1
	else
		default_config="$tmp/default-config.json"; config_path="$default_config"
		(umask 077; mkdir -p "$tmp"; acmesh_config_get > "$default_config") || return 1
		acmesh_config_validate_file "$default_config" || return 1
	fi
	(umask 077
		mkdir -p "$stage/etc/acme" "$stage/etc/acmesh-console" "$stage/etc/config" || exit 1
		acmesh_migration_copy_tree "$ACMESH_MIGRATION_ACME_ROOT" etc/acme "$stage" || exit 1
		acmesh_migration_copy_tree "$ACMESH_MIGRATION_CONSOLE_ROOT" etc/acmesh-console "$stage" || exit 1
		if [ -n "$default_config" ]; then
			cp -p "$default_config" "$stage/etc/acmesh-console/config.json" || exit 1
		fi
		if [ -f "$ACMESH_MIGRATION_UCI_CONFIG" ] && [ ! -L "$ACMESH_MIGRATION_UCI_CONFIG" ]; then
			cp -p "$ACMESH_MIGRATION_UCI_CONFIG" "$stage/etc/config/acmesh-console" || exit 1
		fi
		skipped=0; files="$tmp/deploy-files"
		if [ "$include_certs" = true ]; then
			acmesh_migration_collect_deploy_files "$config_path" "$files" || exit 1
			while IFS= read -r path; do
				[ -n "$path" ] || continue
				if [ "$path" = skipped ]; then skipped=$((skipped + 1)); continue; fi
				mapped=$(acmesh_migration_map_path "$path") || exit 1
				rel=$(printf '%s' "$path" | sed 's#^/##')
				if [ ! -f "$stage/$rel" ]; then
					mkdir -p "$stage/$(dirname "$rel")" || exit 1
					cp -p "$mapped" "$stage/$rel" || exit 1
				fi
			done < "$files"
		fi
		acmesh_migration_write_manifest "$stage" "$include_certs" "$skipped" || exit 1
		chmod 755 "$stage/etc" "$stage/etc/config" || exit 1
		if [ -d "$stage/etc/ssl" ]; then
			chmod 755 "$stage/etc/ssl" || exit 1
		fi
		tar -czf "$archive" -C "$stage" acmesh-console-backup.json etc || exit 1
	) || return 1
	bytes=$(wc -c < "$archive" | tr -d ' ')
	case "$bytes" in ''|*[!0-9]*) return 1 ;; esac
	[ "$bytes" -le "$ACMESH_MIGRATION_MAX_ARCHIVE_BYTES" ] || return 1
	rm -rf "$tmp"; trap - HUP INT TERM EXIT
}

acmesh_migration_archive_response() {
	include_certs="$1" expected="$2" path=$(acmesh_config_path)
	[ -f "$path" ] && [ "$(sha256sum "$path" | awk '{print $1}')" = "$expected" ] || return 5
	root=${ACMESH_RUNTIME_DIR:-/var/run/acmesh-console}; acmesh_private_dir "$root" || return 1
	tmp="$root/.migration-export.$$.$(date +%s)"; archive="$tmp.tar.gz"
	trap 'rm -f "$archive"; rmdir "$tmp" 2>/dev/null || true' HUP INT TERM EXIT
	(umask 077; mkdir "$tmp") || return 1
	acmesh_migration_build_archive "$include_certs" "$archive" || return 1
	bytes=$(wc -c < "$archive" | tr -d ' '); digest=$(sha256sum "$archive" | awk '{print $1}'); encoded=$(base64 "$archive" | tr -d '\n')
	printf '{"ok":true,"format":"acmesh-console-backup","version":1,"filename":"acmesh-console-backup.tar.gz","bytes":%s,"sha256":"%s","includeDeploymentCertificates":%s,"archiveBase64":"%s"}\n' "$bytes" "$digest" "$include_certs" "$encoded"
	rm -f "$archive"; rmdir "$tmp" 2>/dev/null || true; trap - HUP INT TERM EXIT
}

acmesh_migration_archive_validate() {
	archive="$1" stage="$2"; list="$stage.list"
	[ -f "$archive" ] && [ ! -L "$archive" ] || return 1
	bytes=$(wc -c < "$archive" | tr -d ' '); case "$bytes" in ''|*[!0-9]*) return 1 ;; esac
	[ "$bytes" -le "$ACMESH_MIGRATION_MAX_ARCHIVE_BYTES" ] || return 1
	tar -tzf "$archive" > "$list" || return 1
	while IFS= read -r entry; do
		entry=$(printf '%s' "$entry" | sed 's#^\\./##')
		[ -n "$entry" ] || continue
		while [ "${entry%/}" != "$entry" ]; do
			entry=${entry%/}
		done
		[ -n "$entry" ] || return 1
		acmesh_migration_safe_relative "$entry" || return 1
		case "$entry" in
			acmesh-console-backup.json|etc|etc/|etc/acme|etc/acme/*|etc/acmesh-console|etc/acmesh-console/*|etc/config|etc/config/acmesh-console|etc/ssl|etc/ssl/*) ;;
			*) return 1 ;;
		esac
	done < "$list"
	tar -tvzf "$archive" > "$stage.types" || return 1
	while IFS= read -r line; do
		case "$(printf '%s' "$line" | cut -c1)" in -|d) ;; *) return 1 ;; esac
	done < "$stage.types"
	mkdir -p "$stage" || return 1
	tar -xzf "$archive" -C "$stage" || return 1
	[ -f "$stage/acmesh-console-backup.json" ] && [ ! -L "$stage/acmesh-console-backup.json" ] || return 1
	[ "$(jsonfilter -i "$stage/acmesh-console-backup.json" -e '@.format' 2>/dev/null || true)" = acmesh-console-backup ] || return 1
	[ "$(jsonfilter -i "$stage/acmesh-console-backup.json" -e '@.version' 2>/dev/null || true)" = 1 ] || return 1
	include_certs=$(jsonfilter -i "$stage/acmesh-console-backup.json" -e '@.includeDeploymentCertificates' 2>/dev/null || true)
	[ "$include_certs" = true ] || [ "$include_certs" = false ] || return 1
	if [ "$include_certs" != true ] && find "$stage/etc/ssl" \( -type f -o -type l \) -print 2>/dev/null | grep -q .; then return 1; fi
	if find "$stage" -type l -print 2>/dev/null | grep -q .; then return 1; fi
	[ -f "$stage/etc/acmesh-console/config.json" ] && [ ! -L "$stage/etc/acmesh-console/config.json" ] || return 1
	acmesh_config_validate_file "$stage/etc/acmesh-console/config.json" || return 1
	if [ "$include_certs" = true ]; then
		deploy_paths="$stage.deploy-paths"
		acmesh_migration_collect_deploy_paths "$stage/etc/acmesh-console/config.json" "$deploy_paths" || return 1
		find "$stage/etc/ssl" -type f -print 2>/dev/null | while IFS= read -r file; do
			rel="${file#"$stage"/}"
			grep -Fx "/$rel" "$deploy_paths" >/dev/null 2>&1 || exit 1
		done || return 1
	fi
}

acmesh_migration_archive_stage_cleanup() (
	stage="${1:-}"
	[ -n "$stage" ] || exit 0
	rm -rf "$stage" "$stage.list" "$stage.types" "$stage.deploy-paths"
)

acmesh_migration_prepare_destination_parent() {
	destination="$1"
	destination_parent_path=$(dirname "$destination")
	mkdir -p "$destination_parent_path" || return 1
	chmod 755 "$destination_parent_path" || return 1
}

acmesh_migration_prepare_destination_root() {
	rel="$1"
	case "$rel" in
		etc/acme/*)
			acmesh_migration_prepare_destination_parent "$ACMESH_MIGRATION_ACME_ROOT" || return 1
			mkdir -p -m 700 "$ACMESH_MIGRATION_ACME_ROOT" || return 1
			;;
		etc/acmesh-console/*)
			acmesh_migration_prepare_destination_parent "$ACMESH_MIGRATION_CONSOLE_ROOT" || return 1
			mkdir -p -m 700 "$ACMESH_MIGRATION_CONSOLE_ROOT" || return 1
			;;
		etc/config/*)
			acmesh_migration_prepare_destination_parent "$ACMESH_MIGRATION_ACME_ROOT" || return 1
			acmesh_migration_prepare_destination_parent "$ACMESH_MIGRATION_UCI_CONFIG" || return 1
			;;
		etc/ssl/*)
			acmesh_migration_prepare_destination_parent "$ACMESH_MIGRATION_ACME_ROOT" || return 1
			acmesh_migration_prepare_destination_parent "$ACMESH_MIGRATION_SSL_ROOT" || return 1
			mkdir -p -m 755 "$ACMESH_MIGRATION_SSL_ROOT" || return 1
			;;
		*) return 1 ;;
	esac
}

acmesh_migration_archive_candidate() {
	archive="$1" output="$2"; parent=$(dirname "$output"); tmp="$parent/.archive-candidate.$$.$(date +%s)"
	stage="$tmp/stage"
	trap 'rm -rf "$tmp"; acmesh_migration_archive_stage_cleanup "$stage" || true' HUP INT TERM EXIT
	mkdir "$tmp" || return 1
	chmod 700 "$tmp" || return 1
	mkdir "$tmp/stage" || return 1
	chmod 700 "$tmp/stage" || return 1
	acmesh_migration_archive_validate "$archive" "$tmp/stage" || return 1
	cat "$tmp/stage/etc/acmesh-console/config.json" | acmesh_atomic_write "$output" 600 || return 1
	rm -rf "$tmp"; acmesh_migration_archive_stage_cleanup "$stage"; trap - HUP INT TERM EXIT
}

acmesh_migration_import_preview() (
	set +u
	request_file="$1"; acmesh_private_dir "$ACMESH_PENDING_IMPORT_DIR" || return 1
	tmp="$ACMESH_PENDING_IMPORT_DIR/.archive-preview.$$.$(date +%s)"; archive="$tmp.tar.gz"; stage="$tmp.stage"; candidate="$tmp.config"
	trap 'rm -rf "$tmp" "$archive" "$candidate"; acmesh_migration_archive_stage_cleanup "$stage" || true' HUP INT TERM EXIT
	[ "$(jsonfilter -i "$request_file" -t '@.archiveBase64' 2>/dev/null || true)" = string ] || { printf '{"ok":false,"error":"archive payload required"}\n'; return 2; }
	jsonfilter -i "$request_file" -e '@.archiveBase64' | base64 -d > "$archive" || { printf '{"ok":false,"error":"invalid archive encoding"}\n'; return 2; }
	chmod 600 "$archive"; mkdir -p "$stage"
	acmesh_migration_archive_validate "$archive" "$stage" || { printf '{"ok":false,"error":"invalid migration archive"}\n'; return 2; }
	cat "$stage/etc/acmesh-console/config.json" | acmesh_atomic_write "$candidate" 600 || return 1
	digest=$(sha256sum "$archive" | awk '{print $1}'); pending="$ACMESH_PENDING_IMPORT_DIR/$digest.tar.gz"; mv -f "$archive" "$pending" && chmod 600 "$pending" || return 1
	accounts=$(jsonfilter -i "$candidate" -e '@.accountProfiles[*]' 2>/dev/null | wc -l | tr -d ' '); issues=$(jsonfilter -i "$candidate" -e '@.issueProfiles[*]' 2>/dev/null | wc -l | tr -d ' '); deploys=$(jsonfilter -i "$candidate" -e '@.deployProfiles[*]' 2>/dev/null | wc -l | tr -d ' ')
	include_certs=$(jsonfilter -i "$stage/acmesh-console-backup.json" -e '@.includeDeploymentCertificates'); files=$(find "$stage/etc" -type f 2>/dev/null | wc -l | tr -d ' ')
	rm -rf "$tmp" "$candidate"; acmesh_migration_archive_stage_cleanup "$stage"; trap - HUP INT TERM EXIT
	printf '{"ok":true,"previewId":"%s","configDigest":"%s","archive":true,"summary":{"accounts":%s,"issueProfiles":%s,"deployProfiles":%s,"files":%s,"deploymentCertificates":%s}}\n' "$digest" "$digest" "$accounts" "$issues" "$deploys" "$files" "$include_certs"
)

acmesh_migration_install_archive() {
	archive="$1"; parent="$ACMESH_PENDING_IMPORT_DIR/.archive-apply.$$.$(date +%s)"
	stage="$parent/stage"; rollback="$parent/rollback"; touched="$parent/touched"; existing="$parent/existing"
	trap 'rm -rf "$parent"; acmesh_migration_archive_stage_cleanup "$stage" || true' HUP INT TERM EXIT
	mkdir -p "$stage" "$rollback" || return 1
	acmesh_migration_archive_validate "$archive" "$stage" || return 1
	find "$stage/etc" -type f -print | sed "s#^$stage/##" | while IFS= read -r rel; do
		acmesh_migration_is_runtime_state "$rel" || printf '%s\n' "$rel"
	done > "$touched" || return 1
	: > "$existing"
	while IFS= read -r rel; do
		dest=$(acmesh_migration_map_path "/$rel") || return 1
		if [ -L "$dest" ] || [ -d "$dest" ]; then return 1; fi
		if [ -f "$dest" ]; then
			mkdir -p "$rollback/$(dirname "$rel")" || return 1
			cp -p "$dest" "$rollback/$rel" || return 1
			printf '%s\n' "$rel" >> "$existing"
		fi
	done < "$touched"
	while IFS= read -r rel; do
		dest=$(acmesh_migration_map_path "/$rel") || return 1
		acmesh_migration_prepare_destination_root "$rel" || return 1
		mkdir -p "$(dirname "$dest")" || return 1
		tmp="$dest.acmesh-import.$$"; rm -f "$tmp"
		if ! cp -p "$stage/$rel" "$tmp" || ! mv -f "$tmp" "$dest"; then
			rm -f "$tmp"
			while IFS= read -r old; do old_dest=$(acmesh_migration_map_path "/$old") || return 1; rm -f "$old_dest"; done < "$touched"
			while IFS= read -r old; do old_dest=$(acmesh_migration_map_path "/$old") || return 1; mkdir -p "$(dirname "$old_dest")"; cp -p "$rollback/$old" "$old_dest"; done < "$existing"
			return 1
		fi
	done < "$touched"
	rm -f "$archive"; rm -rf "$parent"; acmesh_migration_archive_stage_cleanup "$stage"; trap - HUP INT TERM EXIT
}
