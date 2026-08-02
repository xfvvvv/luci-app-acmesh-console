. "${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}/json.sh"
. "${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}/command.sh"
. "${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}/ssh.sh"

if ! command -v acmesh_task_workspace >/dev/null 2>&1; then
	. "${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}/io.sh"
fi

: "${ACMESH_CONSOLE_DEPLOY_HOOK_NAME:=acmesh-console-ssh}"
: "${ACMESH_CONSOLE_DEPLOY_HOOK_CANONICAL_NAME:=acmesh_console_ssh}"

acmesh_deploy_hook_source_path() {
	printf '%s\n' "${ACMESH_CONSOLE_HOOK_SOURCE:-/usr/libexec/acmesh-console/hooks/acmesh-console-ssh.sh}"
}

acmesh_deploy_install_acme_hook() (
	home="$1" hook_name="$2" legacy="$3"
	source_path="$(acmesh_deploy_hook_source_path)"
	case "$home" in /*) ;; *) return 2 ;; esac
	case "$hook_name" in [A-Za-z0-9_-]*) ;; *) return 2 ;; esac
	[ -r "$source_path" ] && [ ! -L "$source_path" ] || return 1
	hook_dir="$home/deploy"
	[ ! -L "$hook_dir" ] || return 1
	mkdir -p "$hook_dir" || return 1
	[ ! -L "$hook_dir" ] || return 1
	hook_path="$hook_dir/$hook_name.sh"
	[ ! -L "$hook_path" ] || return 1
	[ ! -e "$hook_path" ] || [ -f "$hook_path" ] || return 1
	tmp_path="$hook_path.tmp.$$"
	[ ! -e "$tmp_path" ] || return 1
	umask 077
	{
		printf '%s\n' '#!/bin/sh' 'set -eu'
		printf '%s\n' 'ACMESH_CONSOLE_HOOK_SOURCED=1' 'export ACMESH_CONSOLE_HOOK_SOURCED'
		if [ "$legacy" = 1 ]; then
			printf '%s\n' 'ACMESH_CONSOLE_HOOK_LEGACY=1' 'export ACMESH_CONSOLE_HOOK_LEGACY'
		fi
		printf '. %s\n' "$(acmesh_shell_quote "$source_path")"
	} > "$tmp_path" || { rm -f "$tmp_path"; return 1; }
	chmod 0755 "$tmp_path" || { rm -f "$tmp_path"; return 1; }
	mv -f "$tmp_path" "$hook_path" || { rm -f "$tmp_path"; return 1; }
)

acmesh_deploy_install_acme_hooks() (
	home="$1"
	acmesh_deploy_install_acme_hook "$home" "$ACMESH_CONSOLE_DEPLOY_HOOK_CANONICAL_NAME" 0 || return 1
	acmesh_deploy_install_acme_hook "$home" "$ACMESH_CONSOLE_DEPLOY_HOOK_NAME" 1 || return 1
)

acmesh_build_install_cert_command() {
	domain="$1"
	key_file="$2"
	fullchain_file="$3"
	cert_file="${4:-}"
	ca_file="${5:-}"
	reloadcmd="${6:-}"
	key_type="${7:-}"
	home="${ACMESH_ACME_HOME:-/etc/acme}"

	[ -n "$domain" ] || { echo "domain is required" >&2; return 1; }
	[ -n "$key_file" ] || { echo "key file is required" >&2; return 1; }
	[ -n "$fullchain_file" ] || { echo "fullchain file is required" >&2; return 1; }

	if [ -x "$home/acme.sh" ]; then
		script="$home/acme.sh"
	else
		script="acme.sh"
	fi

	printf '%s --install-cert -d %s --key-file %s --fullchain-file %s' \
		"$(acmesh_shell_quote "$script")" \
		"$(acmesh_shell_quote "$domain")" \
		"$(acmesh_shell_quote "$key_file")" \
		"$(acmesh_shell_quote "$fullchain_file")"
	[ -n "$cert_file" ] && printf ' --cert-file %s' "$(acmesh_shell_quote "$cert_file")"
	[ -n "$ca_file" ] && printf ' --ca-file %s' "$(acmesh_shell_quote "$ca_file")"
	[ -n "$reloadcmd" ] && printf ' --reloadcmd %s' "$(acmesh_shell_quote "$reloadcmd")"
	if [ -n "$key_type" ] && acmesh_key_type_is_ecc "$key_type"; then
		printf ' --ecc'
	fi
	printf '\n'
}

acmesh_deploy_safe_name() {
	printf '%s' "${1:-certificate}" | sed 's/[^A-Za-z0-9_.-]/_/g'
}

acmesh_deploy_metadata_valid() {
	owner="$1" group="$2" mode="$3"
	for identity in "$owner" "$group"; do
		[ -z "$identity" ] && continue
		case "$identity" in *"$(printf '\r')"*|*'
'*) return 1;; esac
		printf '%s\n' "$identity" | grep -Eq '^[A-Za-z_][A-Za-z0-9_.-]*$' || return 1
	done
	[ -z "$mode" ] && return 0
	case "$mode" in *"$(printf '\r')"*|*'
'*) return 1;; [0-7][0-7][0-7]|0[0-7][0-7][0-7]) return 0;; *) return 1;; esac
}

acmesh_deploy_metadata_command() {
	key_file="$1" fullchain_file="$2" owner="$3" group="$4" mode="$5"
	acmesh_deploy_metadata_valid "$owner" "$group" "$mode" || return 1
	[ -n "$mode" ] && printf ' && chmod %s %s %s' "$(acmesh_shell_quote "$mode")" "$(acmesh_shell_quote "$key_file")" "$(acmesh_shell_quote "$fullchain_file")"
	if [ -n "$owner" ] && [ -n "$group" ]; then
		printf ' && chown %s:%s %s %s' "$(acmesh_shell_quote "$owner")" "$(acmesh_shell_quote "$group")" "$(acmesh_shell_quote "$key_file")" "$(acmesh_shell_quote "$fullchain_file")"
	elif [ -n "$owner" ]; then
		printf ' && chown %s %s %s' "$(acmesh_shell_quote "$owner")" "$(acmesh_shell_quote "$key_file")" "$(acmesh_shell_quote "$fullchain_file")"
	elif [ -n "$group" ]; then
		printf ' && chgrp %s %s %s' "$(acmesh_shell_quote "$group")" "$(acmesh_shell_quote "$key_file")" "$(acmesh_shell_quote "$fullchain_file")"
	fi
}

acmesh_ssh_key_is_openssh_private() {
	key="$1"
	[ -r "$key" ] || return 1
	first_line="$(sed -n '1p' "$key" 2>/dev/null || true)"
	case "$first_line" in
		*"BEGIN OPENSSH PRIVATE KEY"*) return 0 ;;
	esac
	return 1
}

acmesh_deploy_cleanup_temp_key() {
	for temp_path in \
		"${ACMESH_DEPLOY_TEMP_KEY:-}" \
		"${ACMESH_DEPLOY_TEMP_PEM_KEY:-}" \
		"${ACMESH_DEPLOY_TEMP_PEM_FULLCHAIN:-}"; do
		[ -n "$temp_path" ] && rm -f -- "$temp_path"
	done
	ACMESH_DEPLOY_TEMP_KEY=""
	ACMESH_DEPLOY_TEMP_PEM_KEY=""
	ACMESH_DEPLOY_TEMP_PEM_FULLCHAIN=""
}

acmesh_deploy_stage() {
	stage="$1"
	printf '%s\n' "$stage"
	if [ -n "${ACMESH_DEPLOY_STAGE_LOG:-}" ]; then
		printf '%s\n' "$stage" >> "$ACMESH_DEPLOY_STAGE_LOG"
	fi
}

acmesh_deploy_lexical_absolute_target() {
	lexical_input="$1"
	case "$lexical_input" in /*) ;; *) return 73 ;; esac
	case "$lexical_input" in *'
'*) return 73 ;; esac
	if printf '%s' "$lexical_input" | LC_ALL=C grep -q '[[:cntrl:]]'; then return 73; fi
	lexical_rest=${lexical_input#/}
	lexical_result=""
	while :; do
		case "$lexical_rest" in
			*/*) lexical_segment=${lexical_rest%%/*}; lexical_rest=${lexical_rest#*/}; lexical_more=1 ;;
			*) lexical_segment=$lexical_rest; lexical_more=0 ;;
		esac
		case "$lexical_segment" in
			''|.) ;;
			..) case "$lexical_result" in */*) lexical_result=${lexical_result%/*};; *) lexical_result="";; esac ;;
			*) if [ -n "$lexical_result" ]; then lexical_result="$lexical_result/$lexical_segment"; else lexical_result=$lexical_segment; fi ;;
		esac
		[ "$lexical_more" = 1 ] || break
	done
	if [ -n "$lexical_result" ]; then printf '/%s\n' "$lexical_result"; else printf '/\n'; fi
}

acmesh_deploy_canonical_target() {
	canonical_input="$1"
	case "$canonical_input" in /*) ;; *) return 73 ;; esac
	case "$canonical_input" in *'
'*) return 73 ;; esac
	if printf '%s' "$canonical_input" | LC_ALL=C grep -q '[[:cntrl:]]'; then return 73; fi
	canonical_probe=$canonical_input
	canonical_suffix=""
	while :; do
		if [ -e "$canonical_probe" ] || [ -L "$canonical_probe" ]; then
			canonical_prefix="$(readlink -f "$canonical_probe" 2>/dev/null || true)"
			[ -n "$canonical_prefix" ] || return 73
			break
		fi
		[ "$canonical_probe" != / ] || { canonical_prefix=/; break; }
		canonical_segment=${canonical_probe##*/}
		canonical_parent=${canonical_probe%/*}
		[ "$canonical_parent" != "$canonical_probe" ] || return 73
		[ -n "$canonical_parent" ] || canonical_parent=/
		if [ -n "$canonical_segment" ]; then
			if [ -n "$canonical_suffix" ]; then canonical_suffix="$canonical_segment/$canonical_suffix"; else canonical_suffix=$canonical_segment; fi
		fi
		canonical_probe=$canonical_parent
	done
	if [ "$canonical_prefix" = / ]; then
		canonical_joined="/$canonical_suffix"
	elif [ -n "$canonical_suffix" ]; then
		canonical_joined="$canonical_prefix/$canonical_suffix"
	else
		canonical_joined=$canonical_prefix
	fi
	canonical_result="$(acmesh_deploy_lexical_absolute_target "$canonical_joined")" || return 73
	[ "$canonical_result" != / ] || return 73
	printf '%s\n' "$canonical_result"
}

acmesh_deploy_destination_preflight() {
	preflight_type="$1"
	case "$preflight_type" in
		local)
			ACMESH_DEPLOY_NORMALIZED_KEY_TARGET="$(acmesh_deploy_canonical_target "$2")" || return 73
			ACMESH_DEPLOY_NORMALIZED_CERT_TARGET="$(acmesh_deploy_canonical_target "$3")" || return 73
			;;
		ssh)
			# The router's filesystem cannot resolve symlinks for a remote target.
			# Normalize only lexical aliases here; the remote transaction resolves
			# symlinks and checks target identity on the destination host.
			ACMESH_DEPLOY_NORMALIZED_KEY_TARGET="$(acmesh_deploy_lexical_absolute_target "$2")" || return 73
			ACMESH_DEPLOY_NORMALIZED_CERT_TARGET="$(acmesh_deploy_lexical_absolute_target "$3")" || return 73
			;;
		*) return 2 ;;
	esac
	[ "$ACMESH_DEPLOY_NORMALIZED_KEY_TARGET" != / ] || return 73
	[ "$ACMESH_DEPLOY_NORMALIZED_CERT_TARGET" != / ] || return 73
	if [ "$ACMESH_DEPLOY_NORMALIZED_KEY_TARGET" = "$ACMESH_DEPLOY_NORMALIZED_CERT_TARGET" ]; then
		echo "key and fullchain targets must be different" >&2
		return 74
	fi
}

acmesh_deploy_transaction() (
	source_key="$1"
	source_fullchain="$2"
	key_target="$3"
	cert_target="$4"
	reload_command="${5:-}"
	owner="${6:-}"
	group="${7:-}"
	cert_mode="${8:-644}"
	task_id="${ACMESH_CURRENT_TASK_ID:-}"
	printf '%s\n' "$task_id" | grep -Eq '^[0-9]{14}-[0-9]+$' || exit 2
	[ -f "$source_key" ] && [ -f "$source_fullchain" ] || exit 1
	acmesh_ssh_validate_remote_path "$key_target" || exit 2
	acmesh_ssh_validate_remote_path "$cert_target" || exit 2
	acmesh_deploy_metadata_valid "$owner" "$group" "$cert_mode" || exit 2
	acmesh_deploy_destination_preflight local "$key_target" "$cert_target" || exit $?
	key_target="$ACMESH_DEPLOY_NORMALIZED_KEY_TARGET"
	cert_target="$ACMESH_DEPLOY_NORMALIZED_CERT_TARGET"
	mkdir -p "$(dirname "$key_target")" "$(dirname "$cert_target")"

	key_new="$key_target.acmesh-new-$task_id"
	cert_new="$cert_target.acmesh-new-$task_id"
	key_backup="$key_target.acmesh-backup-$task_id"
	cert_backup="$cert_target.acmesh-backup-$task_id"
	key_absent=0
	cert_absent=0

	cleanup_new() {
		rm -f "$key_new" "$cert_new"
	}
	rollback() {
		acmesh_deploy_stage rollback
		rollback_status=0
		if [ -e "$key_backup" ]; then
			mv -f "$key_backup" "$key_target" || rollback_status=1
		elif [ "$key_absent" = 1 ]; then
			rm -f "$key_target" || rollback_status=1
		fi
		if [ -e "$cert_backup" ]; then
			mv -f "$cert_backup" "$cert_target" || rollback_status=1
		elif [ "$cert_absent" = 1 ]; then
			rm -f "$cert_target" || rollback_status=1
		fi
		cleanup_new
		return "$rollback_status"
	}
	signal_rollback() {
		signal_status="$1"
		trap - HUP INT TERM
		rollback || true
		exit "$signal_status"
	}
	trap 'cleanup_new' EXIT
	trap 'signal_rollback 129' HUP
	trap 'signal_rollback 130' INT
	trap 'signal_rollback 143' TERM

	cleanup_new
	if [ -e "$key_backup" ] || [ -e "$cert_backup" ]; then
		echo "unresolved deployment backup exists" >&2
		exit 1
	fi
	[ -e "$key_target" ] || key_absent=1
	[ -e "$cert_target" ] || cert_absent=1
	acmesh_deploy_stage upload
	(umask 077; cp "$source_key" "$key_new") || exit 1
	chmod 600 "$key_new" || exit 1
	(umask 077; cp "$source_fullchain" "$cert_new") || exit 1
	chmod "$cert_mode" "$cert_new" || exit 1
	if [ -n "$owner" ] && [ -n "$group" ]; then
		chown "$owner:$group" "$key_new" "$cert_new" || exit 1
	elif [ -n "$owner" ]; then
		chown "$owner" "$key_new" "$cert_new" || exit 1
	elif [ -n "$group" ]; then
		chgrp "$group" "$key_new" "$cert_new" || exit 1
	fi

	acmesh_deploy_stage backup
	if [ "$key_absent" = 0 ]; then mv -f "$key_target" "$key_backup" || exit 1; fi
	if [ "$cert_absent" = 0 ]; then mv -f "$cert_target" "$cert_backup" || { rollback || true; exit 1; }; fi

	acmesh_deploy_stage replace
	if ! mv -f "$key_new" "$key_target"; then rollback || true; exit 1; fi
	if ! mv -f "$cert_new" "$cert_target"; then rollback || true; exit 1; fi
	chmod 600 "$key_target" || { rollback || true; exit 1; }
	chmod "$cert_mode" "$cert_target" || { rollback || true; exit 1; }

	acmesh_deploy_stage reload
	if [ -n "$reload_command" ] && ! sh -c "$reload_command"; then
		rollback || true
		exit 70
	fi
	trap '' HUP INT TERM
	rm -f "$key_backup" "$cert_backup" || exit 1
	trap - HUP INT TERM
)

acmesh_deploy_process_identity() {
	pid="${1:-}"
	case "$pid" in ''|0|*[!0-9]*) return 1 ;; esac
	stat_line="$(cat "/proc/$pid/stat" 2>/dev/null)" || return 1
	case "$stat_line" in "$pid ("*') '*) ;; *) return 1 ;; esac
	stat_rest=${stat_line##*) }
	set -- $stat_rest
	[ "$#" -ge 20 ] || return 1
	printf '%s %s %s\n' "$1" "$3" "${20}"
}

acmesh_deploy_worker_identity_matches() {
	worker_pid="${acmesh_deploy_worker_pid:-}"
	expected_starttime="${acmesh_deploy_worker_starttime:-}"
	[ -n "$worker_pid" ] && [ -n "$expected_starttime" ] || return 1
	identity="$(acmesh_deploy_process_identity "$worker_pid")" || return 1
	set -- $identity
	[ "$1" != Z ] && [ "$2" = "$worker_pid" ] && [ "$3" = "$expected_starttime" ]
}

acmesh_deploy_capture_worker_identity() {
	attempt=0
	while [ "$attempt" -lt 100 ]; do
		identity="$(acmesh_deploy_process_identity "$acmesh_deploy_worker_pid" 2>/dev/null || true)"
		if [ -n "$identity" ]; then
			set -- $identity
			if [ "$1" != Z ] && [ "$2" = "$acmesh_deploy_worker_pid" ]; then
				acmesh_deploy_worker_starttime="$3"
				return 0
			fi
		fi
		attempt=$((attempt + 1))
	done
	return 1
}

acmesh_deploy_stop_worker() {
	signal_name="${1:-TERM}"
	worker_pid="${acmesh_deploy_worker_pid:-}"
	case "$worker_pid" in ''|0|*[!0-9]*) return 0 ;; esac
	if acmesh_deploy_worker_identity_matches; then
		kill -"$signal_name" "-$worker_pid" 2>/dev/null || true
	fi
	attempt=0
	while acmesh_deploy_worker_identity_matches; do
		attempt=$((attempt + 1))
		[ "$attempt" -lt 5 ] || break
		sleep 1
	done
	if acmesh_deploy_worker_identity_matches; then
		kill -KILL "-$worker_pid" 2>/dev/null || true
	fi
	wait "$worker_pid" 2>/dev/null || true
	acmesh_deploy_worker_pid=""
	acmesh_deploy_worker_starttime=""
}

acmesh_deploy_run_worker() {
	workspace="${1:-}"
	shift
	[ "$#" -gt 0 ] || exit 2
	case "$workspace" in ''|/) exit 2 ;; esac
	runner_script="$1"
	shift
	[ -f "$runner_script" ] && [ ! -L "$runner_script" ] || exit 2
	timeout_seconds="${ACMESH_DEPLOY_TIMEOUT:-300}"
	case "$timeout_seconds" in ''|*[!0-9]*) exit 2 ;; esac
	setsid_bin="${ACMESH_SETSID_BIN:-setsid}"
	acmesh_deploy_worker_pid=""
	acmesh_deploy_worker_starttime=""
	cleanup_workspace() {
		[ -n "$workspace" ] && [ "$workspace" != / ] && rm -rf "$workspace"
	}
	forward_signal() {
		signal_name="$1" signal_status="$2"
		trap - HUP INT TERM
		worker_signal="$signal_name"
		[ "$signal_name" != INT ] || worker_signal=TERM
		acmesh_deploy_stop_worker "$worker_signal"
		cleanup_workspace
		exit "$signal_status"
	}
	trap 'cleanup_workspace' EXIT
	trap 'forward_signal HUP 129' HUP
	trap 'forward_signal INT 130' INT
	trap 'forward_signal TERM 143' TERM
	command -v "$setsid_bin" >/dev/null 2>&1 || exit 127
	"$setsid_bin" sh "$runner_script" "$@" &
	acmesh_deploy_worker_pid=$!
	if ! acmesh_deploy_capture_worker_identity; then
		set +e
		wait "$acmesh_deploy_worker_pid"
		worker_status=$?
		set -e
		acmesh_deploy_worker_pid=""
		return "$worker_status"
	fi
	elapsed=0
	while acmesh_deploy_worker_identity_matches; do
		if [ "$timeout_seconds" -gt 0 ] && [ "$elapsed" -ge "$timeout_seconds" ]; then
			acmesh_deploy_stop_worker TERM
			exit 124
		fi
		sleep 1
		elapsed=$((elapsed + 1))
	done
	set +e
	wait "$acmesh_deploy_worker_pid"
	worker_status=$?
	set -e
	acmesh_deploy_worker_pid=""
	acmesh_deploy_worker_starttime=""
	return "$worker_status"
}

acmesh_deploy_resolve_ssh_key() {
	key="$1"
	allow_convert="${2:-0}"
	ACMESH_DEPLOY_RESOLVED_SSH_KEY=""
	[ -n "$key" ] || { echo "SSH private key is required" >&2; return 1; }
	[ -r "$key" ] || { echo "SSH private key is not readable: $key" >&2; return 1; }
	if ! acmesh_ssh_key_is_openssh_private "$key" || ! acmesh_ssh_client_is_dropbear; then
		ACMESH_DEPLOY_RESOLVED_SSH_KEY="$key"
		return 0
	fi

	if [ "$allow_convert" != 1 ] && [ "$allow_convert" != true ]; then
		echo "OpenSSH private key detected, but the current SSH client is Dropbear dbclient." >&2
		echo "Dropbear cannot use this key format directly; this often appears as: /usr/bin/dbclient: Exited: String too long" >&2
		echo "ACMESH_DEPLOY_CONVERTIBLE_SSH_KEY=1" >&2
		echo "Confirm temporary key conversion in LuCI to retry this deployment." >&2
		return 1
	fi

	converter="${ACMESH_DROPBEARCONVERT_BIN:-dropbearconvert}"
	if ! command -v "$converter" >/dev/null 2>&1; then
		echo "OpenSSH private key conversion is unavailable on this system." >&2
		return 1
	fi
	[ -n "${ACMESH_CURRENT_TASK_ID:-}" ] || {
		echo "Temporary key conversion requires a task workspace." >&2
		return 1
	}
	workspace="$(acmesh_task_workspace "$ACMESH_CURRENT_TASK_ID")" || {
		echo "Unable to create a private task workspace for key conversion." >&2
		return 1
	}
	command -v mktemp >/dev/null 2>&1 || {
		echo "Secure temporary file creation is unavailable on this system." >&2
		return 1
	}
	umask 077
	converted="$(mktemp "$workspace/ssh-key.XXXXXX")" || return 1
	ACMESH_DEPLOY_TEMP_KEY="$converted"
	rc=0
	"$converter" openssh dropbear "$key" "$converted" >/dev/null || rc=$?
	if [ "$rc" -ne 0 ]; then
		acmesh_deploy_cleanup_temp_key
		return "$rc"
	fi
	chmod 600 "$converted" || {
		acmesh_deploy_cleanup_temp_key
		return 1
	}
	printf 'Converted OpenSSH private key to a temporary Dropbear key.\n' >&2
	ACMESH_DEPLOY_RESOLVED_SSH_KEY="$converted"
}

acmesh_deploy_remote_write_command() {
	remote_command="$1"
	use_sudo="${2:-0}"
	if [ "$use_sudo" = 1 ] || [ "$use_sudo" = true ]; then
		printf 'sudo -n sh -c %s' "$(acmesh_shell_quote "$remote_command")"
	else
		printf '%s' "$remote_command"
	fi
}

acmesh_deploy_dropbear_home() {
	printf '%s\n' "${ACMESH_DEPLOY_DROPBEAR_HOME:-[task-private-ssh-home]}"
}

acmesh_deploy_ssh_copy_command() {
	source_file="$1"
	target="$2"
	target_file="$3"
	ssh_key="$4"
	port="$5"
	use_sudo="${6:-0}"
	upload_mode="${7:-600}"
	case "$upload_mode" in ''|*[!0-7]*) return 2 ;; esac
	tmp_file="$target_file.tmp"
	remote_command="$(acmesh_deploy_remote_write_command "umask 077; cat > $(acmesh_shell_quote "$tmp_file"); chmod $upload_mode $(acmesh_shell_quote "$tmp_file")" "$use_sudo")"
	if acmesh_ssh_client_is_dropbear; then
		printf 'HOME=%s ssh -i %s -p %s %s %s < %s\n' \
			"$(acmesh_shell_quote "$(acmesh_deploy_dropbear_home)")" \
			"$(acmesh_shell_quote "$ssh_key")" \
			"$(acmesh_shell_quote "$port")" \
			"$(acmesh_shell_quote "$target")" \
			"$(acmesh_shell_quote "$remote_command")" \
			"$(acmesh_shell_quote "$source_file")"
	else
		printf 'ssh -o StrictHostKeyChecking=yes -o UserKnownHostsFile=%s -i %s -p %s %s %s < %s\n' \
			"$(acmesh_shell_quote "$(acmesh_ssh_known_hosts_file)")" \
			"$(acmesh_shell_quote "$ssh_key")" \
			"$(acmesh_shell_quote "$port")" \
			"$(acmesh_shell_quote "$target")" \
			"$(acmesh_shell_quote "$remote_command")" \
			"$(acmesh_shell_quote "$source_file")"
	fi
}

acmesh_deploy_ssh_exec_command() {
	target="$1"
	ssh_key="$2"
	port="$3"
	remote_command="$4"
	use_sudo="${5:-0}"
	remote_command="$(acmesh_deploy_remote_write_command "$remote_command" "$use_sudo")"
	if acmesh_ssh_client_is_dropbear; then
		printf 'HOME=%s ssh -i %s -p %s %s %s\n' \
			"$(acmesh_shell_quote "$(acmesh_deploy_dropbear_home)")" \
			"$(acmesh_shell_quote "$ssh_key")" \
			"$(acmesh_shell_quote "$port")" \
			"$(acmesh_shell_quote "$target")" \
			"$(acmesh_shell_quote "$remote_command")"
	else
		printf 'ssh -o StrictHostKeyChecking=yes -o UserKnownHostsFile=%s -i %s -p %s %s %s\n' \
			"$(acmesh_shell_quote "$(acmesh_ssh_known_hosts_file)")" \
			"$(acmesh_shell_quote "$ssh_key")" \
			"$(acmesh_shell_quote "$port")" \
			"$(acmesh_shell_quote "$target")" \
			"$(acmesh_shell_quote "$remote_command")"
	fi
}

acmesh_deploy_ssh_copy() {
	source_file="$1"
	target="$2"
	target_file="$3"
	ssh_key="$4"
	port="$5"
	use_sudo="${6:-0}"
	tmp_file="${7:-$target_file.tmp}"
	upload_mode="${8:-600}"
	case "$upload_mode" in ''|*[!0-7]*) return 2 ;; esac
	remote_command="$(acmesh_deploy_remote_write_command "umask 077; cat > $(acmesh_shell_quote "$tmp_file"); chmod $upload_mode $(acmesh_shell_quote "$tmp_file")" "$use_sudo")"
	if acmesh_ssh_client_is_dropbear; then
		HOME="$(acmesh_deploy_dropbear_home)" ssh -i "$ssh_key" -p "$port" "$target" "$remote_command" < "$source_file"
	else
		ssh -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$(acmesh_ssh_known_hosts_file)" -i "$ssh_key" -p "$port" "$target" "$remote_command" < "$source_file"
	fi
}

acmesh_deploy_ssh_exec() {
	target="$1"
	ssh_key="$2"
	port="$3"
	remote_command="$4"
	use_sudo="${5:-0}"
	remote_command="$(acmesh_deploy_remote_write_command "$remote_command" "$use_sudo")"
	if acmesh_ssh_client_is_dropbear; then
		HOME="$(acmesh_deploy_dropbear_home)" ssh -i "$ssh_key" -p "$port" "$target" "$remote_command"
	else
		ssh -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$(acmesh_ssh_known_hosts_file)" -i "$ssh_key" -p "$port" "$target" "$remote_command"
	fi
}

acmesh_deploy_prepare_ssh_trust() {
	host="$1" port="$2"
	acmesh_ssh_verify_pinned_host "$host" "$port" || return $?
	ACMESH_DEPLOY_DROPBEAR_HOME=""
	if acmesh_ssh_client_is_dropbear; then
		[ -n "${ACMESH_CURRENT_TASK_ID:-}" ] || return 2
		workspace="$(acmesh_task_workspace "$ACMESH_CURRENT_TASK_ID")" || return 1
		ACMESH_DEPLOY_DROPBEAR_HOME="$workspace/dropbear-home"
		acmesh_ssh_prepare_dropbear_home "$ACMESH_DEPLOY_DROPBEAR_HOME" || return 1
		export ACMESH_DEPLOY_DROPBEAR_HOME
	fi
}

acmesh_deploy_generation() {
	workspace="$1"
	command -v dd >/dev/null 2>&1 || return 127
	command -v sha256sum >/dev/null 2>&1 || return 127
	command -v awk >/dev/null 2>&1 || return 127
	random_file="$workspace/deploy-generation-random.$$"
	(umask 077; dd if=/dev/urandom of="$random_file" bs=32 count=1 2>/dev/null) || { rm -f "$random_file"; return 1; }
	[ "$(wc -c < "$random_file" | tr -d ' ')" = 32 ] || { rm -f "$random_file"; return 1; }
	generation="$(sha256sum "$random_file" | awk '{print $1}')" || { rm -f "$random_file"; return 1; }
	rm -f "$random_file"
	printf '%s\n' "$generation" | grep -Eq '^[0-9a-f]{64}$' || return 1
	printf '%s\n' "$generation"
}

acmesh_deploy_remote_lock_setup() {
	key_target="$1" cert_target="$2" generation="$3"
	printf '%s\n' "lexical_target() {
  lexical_input=\"\$1\"; case \"\$lexical_input\" in /*) ;; *) return 73 ;; esac
  printf '%s' \"\$lexical_input\" | LC_ALL=C grep -q '[[:cntrl:]]' && return 73
  lexical_rest=\${lexical_input#/}; lexical_result=
  while :; do
    case \"\$lexical_rest\" in */*) lexical_segment=\${lexical_rest%%/*}; lexical_rest=\${lexical_rest#*/}; lexical_more=1 ;; *) lexical_segment=\$lexical_rest; lexical_more=0 ;; esac
    case \"\$lexical_segment\" in ''|.) ;; ..) case \"\$lexical_result\" in */*) lexical_result=\${lexical_result%/*} ;; *) lexical_result= ;; esac ;; *) if [ -n \"\$lexical_result\" ]; then lexical_result=\"\$lexical_result/\$lexical_segment\"; else lexical_result=\$lexical_segment; fi ;; esac
    [ \"\$lexical_more\" = 1 ] || break
  done
  if [ -n \"\$lexical_result\" ]; then printf '/%s\\n' \"\$lexical_result\"; else printf '/\\n'; fi
}
canonical_target() {
  canonical_input=\"\$1\"; case \"\$canonical_input\" in /*) ;; *) return 73 ;; esac
  printf '%s' \"\$canonical_input\" | LC_ALL=C grep -q '[[:cntrl:]]' && return 73
  canonical_probe=\$canonical_input; canonical_suffix=
  while :; do
    if [ -e \"\$canonical_probe\" ] || [ -L \"\$canonical_probe\" ]; then canonical_prefix=\$(readlink -f \"\$canonical_probe\" 2>/dev/null || true); [ -n \"\$canonical_prefix\" ] || return 73; break; fi
    [ \"\$canonical_probe\" != / ] || { canonical_prefix=/; break; }
    canonical_segment=\${canonical_probe##*/}; canonical_parent=\${canonical_probe%/*}; [ \"\$canonical_parent\" != \"\$canonical_probe\" ] || return 73; [ -n \"\$canonical_parent\" ] || canonical_parent=/
    if [ -n \"\$canonical_segment\" ]; then if [ -n \"\$canonical_suffix\" ]; then canonical_suffix=\"\$canonical_segment/\$canonical_suffix\"; else canonical_suffix=\$canonical_segment; fi; fi
    canonical_probe=\$canonical_parent
  done
  if [ \"\$canonical_prefix\" = / ]; then canonical_joined=\"/\$canonical_suffix\"; elif [ -n \"\$canonical_suffix\" ]; then canonical_joined=\"\$canonical_prefix/\$canonical_suffix\"; else canonical_joined=\$canonical_prefix; fi
  canonical_result=\$(lexical_target \"\$canonical_joined\") || return 73
  [ \"\$canonical_result\" != / ] || return 73
  printf '%s\\n' \"\$canonical_result\"
}
key_target_input=$(acmesh_shell_quote "$key_target")
cert_target_input=$(acmesh_shell_quote "$cert_target")
generation=$(acmesh_shell_quote "$generation")
key_target=\$(canonical_target \"\$key_target_input\") || exit 73
cert_target=\$(canonical_target \"\$cert_target_input\") || exit 73
[ \"\$key_target\" != \"\$cert_target\" ] || { echo 'key and fullchain targets must be different' >&2; exit 74; }
key_lock=\"\$key_target.acmesh-transaction.lock\"; cert_lock=\"\$cert_target.acmesh-transaction.lock\"
lock_first=\$(printf '%s\\n%s\\n' \"\$key_lock\" \"\$cert_lock\" | LC_ALL=C sort | sed -n '1p')
if [ \"\$lock_first\" = \"\$key_lock\" ]; then lock_second=\"\$cert_lock\"; else lock_second=\"\$key_lock\"; fi
coordinator=\"\$lock_first\""
}

acmesh_deploy_remote_ack_transaction() {
	key_target="$1" cert_target="$2" target="$3" ssh_key="$4" port="$5" use_sudo="$6" generation="$7"
	lock_setup="$(acmesh_deploy_remote_lock_setup "$key_target" "$cert_target" "$generation")" || return 1
	ack_command="set -eu
acmesh_action=ack
$lock_setup
verify_lock() { lock=\"\$1\"; expected=\"\$2\"; [ \"\$(cat \"\$lock/generation\" 2>/dev/null || true)\" = \"\$generation\" ] && [ \"\$(cat \"\$lock/state\" 2>/dev/null || true)\" = \"\$expected\" ] && [ ! -e \"\$lock/active-\$generation\" ]; }
state=\$(cat \"\$coordinator/state\" 2>/dev/null || true)
case \"\$state\" in committed:\$generation|rolled-back:*:\$generation) ;; *) exit 75 ;; esac
verify_lock \"\$lock_first\" \"\$state\" || exit 76
[ -z \"\$lock_second\" ] || verify_lock \"\$lock_second\" \"\$state\" || exit 76
release_lock() { lock=\"\$1\"; [ \"\$(cat \"\$lock/generation\" 2>/dev/null || true)\" = \"\$generation\" ] || return 76; rm -f \"\$lock/state\" \"\$lock/state.tmp-\$generation\" \"\$lock/generation\" \"\$lock/generation.tmp-\$generation\" \"\$lock/active.tmp-\$generation\" \"\$lock/key-absent-\$generation\" \"\$lock/cert-absent-\$generation\"; rmdir \"\$lock\"; }
[ -z \"\$lock_second\" ] || release_lock \"\$lock_second\"
release_lock \"\$lock_first\""
	acmesh_deploy_ssh_exec "$target" "$ssh_key" "$port" "$ack_command" "$use_sudo"
}

acmesh_deploy_remote_transaction() {
	source_key="$1" source_fullchain="$2" key_target="$3" cert_target="$4"
	target="$5" ssh_key="$6" port="$7" use_sudo="$8" reload_command="${9:-}"
	owner="${10:-}" group="${11:-}" cert_mode="${12:-644}"
	task_id="${ACMESH_CURRENT_TASK_ID:-}"
	printf '%s\n' "$task_id" | grep -Eq '^[0-9]{14}-[0-9]+$' || return 2
	acmesh_deploy_destination_preflight ssh "$key_target" "$cert_target" || return $?
	key_target="$ACMESH_DEPLOY_NORMALIZED_KEY_TARGET"
	cert_target="$ACMESH_DEPLOY_NORMALIZED_CERT_TARGET"
	workspace="$(acmesh_task_workspace "$task_id")" || return 1
	generation="$(acmesh_deploy_generation "$workspace")" || return $?
	key_new="$key_target.acmesh-new-$generation"; cert_new="$cert_target.acmesh-new-$generation"
	key_backup="$key_target.acmesh-backup-$generation"; cert_backup="$cert_target.acmesh-backup-$generation"
	recovery_wait="${ACMESH_DEPLOY_REMOTE_RECOVERY_WAIT:-30}"
	case "$recovery_wait" in ''|*[!0-9]*) return 2 ;; esac
	state_result="$workspace/remote-transaction-state-$generation"
	rm -f "$state_result"
	lock_setup="$(acmesh_deploy_remote_lock_setup "$key_target" "$cert_target" "$generation")" || return 1

	prepare_command="set -eu
acmesh_action=prepare
$lock_setup
umask 077; made_first=0; made_second=0
cleanup_one() { lock=\"\$1\"; made=\"\$2\"; [ \"\$made\" = 1 ] || return 0; owner=\$(cat \"\$lock/generation\" 2>/dev/null || true); [ -z \"\$owner\" ] || [ \"\$owner\" = \"\$generation\" ] || return 0; rm -f \"\$lock/state\" \"\$lock/state.tmp-\$generation\" \"\$lock/generation\" \"\$lock/generation.tmp-\$generation\" \"\$lock/active.tmp-\$generation\"; rmdir \"\$lock\" 2>/dev/null || true; }
cleanup_prepare() { rc=\$?; trap - EXIT HUP INT TERM; [ -z \"\$lock_second\" ] || cleanup_one \"\$lock_second\" \"\$made_second\"; cleanup_one \"\$lock_first\" \"\$made_first\"; exit \"\$rc\"; }
trap cleanup_prepare EXIT; trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM
init_lock() { lock=\"\$1\"; printf '%s\n' \"\$generation\" > \"\$lock/generation.tmp-\$generation\"; chmod 600 \"\$lock/generation.tmp-\$generation\"; mv -f \"\$lock/generation.tmp-\$generation\" \"\$lock/generation\"; printf 'prepared:%s\n' \"\$generation\" > \"\$lock/state.tmp-\$generation\"; chmod 600 \"\$lock/state.tmp-\$generation\"; mv -f \"\$lock/state.tmp-\$generation\" \"\$lock/state\"; }
mkdir \"\$lock_first\" 2>/dev/null || exit 76; made_first=1; init_lock \"\$lock_first\"
if [ -n \"\$lock_second\" ]; then mkdir \"\$lock_second\" 2>/dev/null || exit 76; made_second=1; init_lock \"\$lock_second\"; fi
trap - EXIT HUP INT TERM"
	inspect_command="set -eu
acmesh_action=inspect
$lock_setup
if [ ! -d \"\$lock_first\" ] && { [ -z \"\$lock_second\" ] || [ ! -d \"\$lock_second\" ]; }; then printf 'absent\n'; exit 0; fi
verify_prepared() { lock=\"\$1\"; [ \"\$(cat \"\$lock/generation\" 2>/dev/null || true)\" = \"\$generation\" ] && [ \"\$(cat \"\$lock/state\" 2>/dev/null || true)\" = \"prepared:\$generation\" ]; }
verify_prepared \"\$lock_first\" && { [ -z \"\$lock_second\" ] || verify_prepared \"\$lock_second\"; } || { printf 'busy\n'; exit 0; }
printf 'prepared:%s\n' \"\$generation\""
	cancel_command="set -eu
acmesh_action=cancel
$lock_setup
key_new=$(acmesh_shell_quote "$key_new"); cert_new=$(acmesh_shell_quote "$cert_new")
verify_prepared() { lock=\"\$1\"; [ \"\$(cat \"\$lock/generation\" 2>/dev/null || true)\" = \"\$generation\" ] && [ \"\$(cat \"\$lock/state\" 2>/dev/null || true)\" = \"prepared:\$generation\" ] && [ ! -e \"\$lock/active-\$generation\" ]; }
verify_prepared \"\$lock_first\" || exit 76; [ -z \"\$lock_second\" ] || verify_prepared \"\$lock_second\" || exit 76
rm -f \"\$key_new\" \"\$cert_new\"
release_lock() { lock=\"\$1\"; verify_prepared \"\$lock\" || return 76; rm -f \"\$lock/state\" \"\$lock/state.tmp-\$generation\" \"\$lock/generation\" \"\$lock/generation.tmp-\$generation\" \"\$lock/active.tmp-\$generation\"; rmdir \"\$lock\"; }
[ -z \"\$lock_second\" ] || release_lock \"\$lock_second\"; release_lock \"\$lock_first\""

	prepare_status=0
	acmesh_deploy_ssh_exec "$target" "$ssh_key" "$port" "$prepare_command" "$use_sudo" >/dev/null 2>&1 || prepare_status=$?
	if [ "$prepare_status" -ne 0 ]; then
		if ! acmesh_deploy_ssh_exec "$target" "$ssh_key" "$port" "$inspect_command" "$use_sudo" > "$state_result"; then rm -f "$state_result"; return "$prepare_status"; fi
		prepared_state="$(sed -n '$p' "$state_result")"; rm -f "$state_result"
		case "$prepared_state" in "prepared:$generation") ;; absent) return "$prepare_status" ;; *) return 76 ;; esac
	fi

	acmesh_deploy_stage upload
	if acmesh_deploy_ssh_copy "$source_key" "$target" "$key_target" "$ssh_key" "$port" "$use_sudo" "$key_new" 600; then :; else status=$?; acmesh_deploy_ssh_exec "$target" "$ssh_key" "$port" "$cancel_command" "$use_sudo" >/dev/null 2>&1 || true; return "$status"; fi
	if acmesh_deploy_ssh_copy "$source_fullchain" "$target" "$cert_target" "$ssh_key" "$port" "$use_sudo" "$cert_new" "$cert_mode"; then :; else status=$?; acmesh_deploy_ssh_exec "$target" "$ssh_key" "$port" "$cancel_command" "$use_sudo" >/dev/null 2>&1 || true; return "$status"; fi

	remote_script="set -eu
acmesh_action=transaction
$lock_setup
key_new=$(acmesh_shell_quote "$key_new"); cert_new=$(acmesh_shell_quote "$cert_new"); key_backup=$(acmesh_shell_quote "$key_backup"); cert_backup=$(acmesh_shell_quote "$cert_backup")
reload_command=$(acmesh_shell_quote "$reload_command")
phase=prepare; key_absent=\"\$coordinator/key-absent-\$generation\"; cert_absent=\"\$coordinator/cert-absent-\$generation\"
verify_lock() { lock=\"\$1\"; expected=\"\$2\"; [ \"\$(cat \"\$lock/generation\" 2>/dev/null || true)\" = \"\$generation\" ] && [ \"\$(cat \"\$lock/state\" 2>/dev/null || true)\" = \"\$expected\" ]; }
verify_all() { verify_lock \"\$lock_first\" \"\$1\" && { [ -z \"\$lock_second\" ] || verify_lock \"\$lock_second\" \"\$1\"; }; }
write_one() { lock=\"\$1\"; value=\"\$2\"; printf '%s\n' \"\$value\" > \"\$lock/state.tmp-\$generation\"; chmod 600 \"\$lock/state.tmp-\$generation\"; mv -f \"\$lock/state.tmp-\$generation\" \"\$lock/state\"; }
cas_state() { expected=\"\$1:\$generation\"; replacement=\"\$2:\$generation\"; verify_all \"\$expected\" || return 76; write_one \"\$lock_first\" \"\$replacement\"; [ -z \"\$lock_second\" ] || write_one \"\$lock_second\" \"\$replacement\"; }
cleanup_new() { rm -f \"\$key_new\" \"\$cert_new\" \"\$lock_first/state.tmp-\$generation\"; [ -z \"\$lock_second\" ] || rm -f \"\$lock_second/state.tmp-\$generation\"; }
remove_active() { lock=\"\$1\"; active=\"\$lock/active-\$generation\"; [ \"\$(cat \"\$active\" 2>/dev/null || true)\" = \"\$generation\" ] && rm -f \"\$active\"; rm -f \"\$lock/active.tmp-\$generation\"; }
rollback() { rollback_phase=\"\$1\"; rollback_status=0; if [ -e \"\$key_backup\" ]; then mv -f \"\$key_backup\" \"\$key_target\" || rollback_status=1; elif [ -e \"\$key_absent\" ]; then rm -f \"\$key_target\" || rollback_status=1; fi; if [ -e \"\$cert_backup\" ]; then mv -f \"\$cert_backup\" \"\$cert_target\" || rollback_status=1; elif [ -e \"\$cert_absent\" ]; then rm -f \"\$cert_target\" || rollback_status=1; fi; cleanup_new; if [ \"\$rollback_status\" = 0 ]; then cas_state \"running:\$rollback_phase\" \"rolled-back:\$rollback_phase\"; rm -f \"\$key_absent\" \"\$cert_absent\"; else cas_state \"running:\$rollback_phase\" \"recovery-required:\$rollback_phase\" || true; fi; return \"\$rollback_status\"; }
cleanup_committed() { rm -f \"\$key_backup\" \"\$cert_backup\" \"\$key_absent\" \"\$cert_absent\" \"\$key_new\" \"\$cert_new\"; cleanup_new; }
finish() { rc=\$?; trap - EXIT HUP INT TERM; current_state=\$(cat \"\$coordinator/state\" 2>/dev/null || true); if [ \"\$current_state\" = \"committed:\$generation\" ]; then cleanup_committed; elif [ \"\$rc\" -ne 0 ]; then case \"\$current_state\" in prepared:\$generation) cleanup_new; cas_state prepared rolled-back:prepare || true ;; running:*:\$generation) rollback \"\$phase\" || true ;; esac; else cleanup_new; fi; [ -z \"\$lock_second\" ] || remove_active \"\$lock_second\"; remove_active \"\$lock_first\"; exit \"\$rc\"; }
verify_all \"prepared:\$generation\" || exit 76
trap finish EXIT; trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM
create_active() { lock=\"\$1\"; printf '%s\n' \"\$generation\" > \"\$lock/active.tmp-\$generation\"; chmod 600 \"\$lock/active.tmp-\$generation\"; mv -f \"\$lock/active.tmp-\$generation\" \"\$lock/active-\$generation\"; }
create_active \"\$lock_first\"; [ -z \"\$lock_second\" ] || create_active \"\$lock_second\"
cas_state prepared \"running:\$phase\"
chmod 600 \"\$key_new\"; chmod $(acmesh_shell_quote "$cert_mode") \"\$cert_new\"
cas_state \"running:\$phase\" running:backup; phase=backup
if [ -e \"\$key_target\" ]; then mv -f \"\$key_target\" \"\$key_backup\"; else : > \"\$key_absent\"; fi
if [ -e \"\$cert_target\" ]; then mv -f \"\$cert_target\" \"\$cert_backup\"; else : > \"\$cert_absent\"; fi
cas_state running:backup running:replace; phase=replace
mv -f \"\$key_new\" \"\$key_target\"; mv -f \"\$cert_new\" \"\$cert_target\"
cas_state running:replace running:metadata; phase=metadata
chmod 600 \"\$key_target\"; chmod $(acmesh_shell_quote "$cert_mode") \"\$cert_target\""
	if [ -n "$owner" ] && [ -n "$group" ]; then remote_script="$remote_script
chown $(acmesh_shell_quote "$owner:$group") \"\$key_target\" \"\$cert_target\""
	elif [ -n "$owner" ]; then remote_script="$remote_script
chown $(acmesh_shell_quote "$owner") \"\$key_target\" \"\$cert_target\""
	elif [ -n "$group" ]; then remote_script="$remote_script
chgrp $(acmesh_shell_quote "$group") \"\$key_target\" \"\$cert_target\""
	fi
	remote_script="$remote_script
cas_state running:metadata running:reload; phase=reload
if [ -n \"\$reload_command\" ] && ! sh -c \"\$reload_command\"; then exit 70; fi
cas_state running:reload committed
cleanup_committed"

	recovery_script="set -eu
acmesh_action=recover
$lock_setup
verify_lock() { lock=\"\$1\"; [ \"\$(cat \"\$lock/generation\" 2>/dev/null || true)\" = \"\$generation\" ]; }
verify_lock \"\$lock_first\" || exit 76; [ -z \"\$lock_second\" ] || verify_lock \"\$lock_second\" || exit 76
attempt=0
while [ -e \"\$lock_first/active-\$generation\" ] || { [ -n \"\$lock_second\" ] && [ -e \"\$lock_second/active-\$generation\" ]; }; do [ \"\$attempt\" -lt $(acmesh_shell_quote "$recovery_wait") ] || exit 75; attempt=\$((attempt + 1)); sleep 1; done
state=\$(cat \"\$coordinator/state\" 2>/dev/null || true)
[ \"\$(cat \"\$lock_first/state\" 2>/dev/null || true)\" = \"\$state\" ] || exit 76; [ -z \"\$lock_second\" ] || [ \"\$(cat \"\$lock_second/state\" 2>/dev/null || true)\" = \"\$state\" ] || exit 76
case \"\$state\" in committed:\$generation|rolled-back:*:\$generation|prepared:\$generation) printf '%s\n' \"\$state\" ;; running:*:\$generation|recovery-required:*:\$generation) exit 75 ;; *) exit 76 ;; esac"

	if acmesh_deploy_ssh_exec "$target" "$ssh_key" "$port" "$remote_script" "$use_sudo"; then
		acmesh_deploy_stage backup; acmesh_deploy_stage replace; acmesh_deploy_stage reload
		acmesh_deploy_remote_ack_transaction "$key_target" "$cert_target" "$target" "$ssh_key" "$port" "$use_sudo" "$generation" >/dev/null 2>&1 || return 75
		return 0
	else status=$?; fi
	if ! acmesh_deploy_ssh_exec "$target" "$ssh_key" "$port" "$recovery_script" "$use_sudo" > "$state_result"; then rm -f "$state_result"; return "$status"; fi
	remote_state="$(sed -n '$p' "$state_result")"; rm -f "$state_result"
	case "$remote_state" in
		"committed:$generation") acmesh_deploy_stage backup; acmesh_deploy_stage replace; acmesh_deploy_stage reload; acmesh_deploy_remote_ack_transaction "$key_target" "$cert_target" "$target" "$ssh_key" "$port" "$use_sudo" "$generation" >/dev/null 2>&1 || return 75; return 0 ;;
		rolled-back:*:"$generation") phase=${remote_state#rolled-back:}; phase=${phase%:"$generation"}; case "$phase" in backup) acmesh_deploy_stage backup;; replace|metadata) acmesh_deploy_stage backup; acmesh_deploy_stage replace;; reload) acmesh_deploy_stage backup; acmesh_deploy_stage replace; acmesh_deploy_stage reload;; esac; acmesh_deploy_stage rollback; acmesh_deploy_remote_ack_transaction "$key_target" "$cert_target" "$target" "$ssh_key" "$port" "$use_sudo" "$generation" >/dev/null 2>&1 || return 75; return "$status" ;;
		"prepared:$generation") acmesh_deploy_ssh_exec "$target" "$ssh_key" "$port" "$cancel_command" "$use_sudo" >/dev/null 2>&1 || true; return "$status" ;;
		*) return "$status" ;;
	esac
}

acmesh_deploy_managed_key_path() {
	domain="$1"
	key_type="${2:-ecc}"
	home="${ACMESH_ACME_HOME:-/etc/acme}"
	if acmesh_key_type_is_ecc "$key_type"; then
		printf '%s/%s_ecc/%s.key\n' "$home" "$domain" "$domain"
	else
		printf '%s/%s/%s.key\n' "$home" "$domain" "$domain"
	fi
}

acmesh_deploy_managed_fullchain_path() {
	domain="$1"
	key_type="${2:-ecc}"
	home="${ACMESH_ACME_HOME:-/etc/acme}"
	if acmesh_key_type_is_ecc "$key_type"; then
		printf '%s/%s_ecc/fullchain.cer\n' "$home" "$domain"
	else
		printf '%s/%s/fullchain.cer\n' "$home" "$domain"
	fi
}

acmesh_deploy_source_key_path() {
	cert_source="$1"
	domain="$2"
	source_key_file="$3"
	key_type="${4:-ecc}"
	case "$cert_source" in
		paste-pem) printf '%s\n' "${ACMESH_DEPLOY_TEMP_PEM_KEY:-[task-private-pem-key]}" ;;
		local-files) printf '%s\n' "$source_key_file" ;;
		*) acmesh_deploy_managed_key_path "$domain" "$key_type" ;;
	esac
}

acmesh_deploy_source_fullchain_path() {
	cert_source="$1"
	domain="$2"
	source_fullchain_file="$3"
	key_type="${4:-ecc}"
	case "$cert_source" in
		paste-pem) printf '%s\n' "${ACMESH_DEPLOY_TEMP_PEM_FULLCHAIN:-[task-private-pem-fullchain]}" ;;
		local-files) printf '%s\n' "$source_fullchain_file" ;;
		*) acmesh_deploy_managed_fullchain_path "$domain" "$key_type" ;;
	esac
}

acmesh_build_profile_deploy_command() {
	deploy_type="${1:-local}"
	cert_source="${2:-managed-acme}"
	domain="$3"
	key_file="$4"
	fullchain_file="$5"
	cert_file="${6:-}"
	ca_file="${7:-}"
	reloadcmd="${8:-}"
	source_key_file="${9:-}"
	source_fullchain_file="${10:-}"
	key_pem="${11:-}"
	fullchain_pem="${12:-}"
	host="${13:-}"
	port="${14:-22}"
	user="${15:-root}"
	ssh_key="${16:-/etc/acmesh-console/ssh/id_ed25519}"
	key_type="${17:-}"
	sudo_mode="${18:-auto}"
	owner="${19:-}"
	group="${20:-}"
	file_mode="${21:-}"
	acmesh_deploy_metadata_valid "$owner" "$group" "$file_mode" || { echo "invalid deploy metadata" >&2; return 1; }

	[ -n "$key_file" ] || { echo "target key file is required" >&2; return 1; }
	[ -n "$fullchain_file" ] || { echo "target fullchain file is required" >&2; return 1; }
	acmesh_ssh_validate_remote_path "$key_file" || { echo "invalid target key path" >&2; return 2; }
	acmesh_ssh_validate_remote_path "$fullchain_file" || { echo "invalid target fullchain path" >&2; return 2; }

	case "$cert_source" in
		managed-acme|local-files|paste-pem) ;;
		*) echo "unsupported cert source: $cert_source" >&2; return 1 ;;
	esac
	case "$deploy_type" in
		local|ssh) ;;
		*) echo "unsupported deploy type: $deploy_type" >&2; return 1 ;;
	esac

	if [ "$cert_source" = paste-pem ]; then
		[ -n "$key_pem" ] || { echo "private key PEM is required" >&2; return 1; }
		[ -n "$fullchain_pem" ] || { echo "fullchain PEM is required" >&2; return 1; }
	fi

	if [ "$cert_source" = managed-acme ] && [ "$deploy_type" = local ]; then
		acmesh_build_install_cert_command "$domain" "$key_file" "$fullchain_file" "$cert_file" "$ca_file" "" "${key_type:-ecc}" | tr -d '\n'
		acmesh_deploy_metadata_command "$key_file" "$fullchain_file" "$owner" "$group" "$file_mode" || return $?
		[ -n "$reloadcmd" ] && printf ' && %s' "$reloadcmd"
		printf '\n'
		return
	fi

	source_key="$(acmesh_deploy_source_key_path "$cert_source" "$domain" "$source_key_file" "${key_type:-ecc}")"
	source_fullchain="$(acmesh_deploy_source_fullchain_path "$cert_source" "$domain" "$source_fullchain_file" "${key_type:-ecc}")"
	[ -n "$source_key" ] || { echo "source key file is required" >&2; return 1; }
	[ -n "$source_fullchain" ] || { echo "source fullchain file is required" >&2; return 1; }

	if [ "$deploy_type" = ssh ]; then
		[ -n "$host" ] || { echo "SSH host is required" >&2; return 1; }
		[ -n "$user" ] || user="root"
		[ -n "$port" ] || port="22"
		acmesh_ssh_validate_target "$host" "$port" "$user" || { echo "invalid SSH target" >&2; return 2; }
		target="$user@$host"
		case "$sudo_mode" in always) remote_write_sudo=1;; never) remote_write_sudo=0;; ''|auto) remote_write_sudo=0; [ "$user" = root ] || remote_write_sudo=1;; *) return 1;; esac
		fullchain_tmp="$fullchain_file.tmp"
		key_tmp="$key_file.tmp"
		acmesh_deploy_ssh_copy_command "$source_fullchain" "$target" "$fullchain_file" "$ssh_key" "$port" "$remote_write_sudo"
		chain_metadata="chmod ${file_mode:-644} $(acmesh_shell_quote "$fullchain_tmp")"
		[ -n "$owner" ] && chain_metadata="$chain_metadata && chown $(acmesh_shell_quote "$owner") $(acmesh_shell_quote "$fullchain_tmp")"
		[ -n "$group" ] && chain_metadata="$chain_metadata && chgrp $(acmesh_shell_quote "$group") $(acmesh_shell_quote "$fullchain_tmp")"
		acmesh_deploy_ssh_exec_command "$target" "$ssh_key" "$port" "$chain_metadata && mv $(acmesh_shell_quote "$fullchain_tmp") $(acmesh_shell_quote "$fullchain_file")" "$remote_write_sudo"
		acmesh_deploy_ssh_copy_command "$source_key" "$target" "$key_file" "$ssh_key" "$port" "$remote_write_sudo"
		metadata="chmod ${file_mode:-600} $(acmesh_shell_quote "$key_tmp")"
		[ -n "$owner" ] && metadata="$metadata && chown $(acmesh_shell_quote "$owner") $(acmesh_shell_quote "$key_tmp")"
		[ -n "$group" ] && metadata="$metadata && chgrp $(acmesh_shell_quote "$group") $(acmesh_shell_quote "$key_tmp")"
		acmesh_deploy_ssh_exec_command "$target" "$ssh_key" "$port" "$metadata && mv $(acmesh_shell_quote "$key_tmp") $(acmesh_shell_quote "$key_file")" "$remote_write_sudo"
		[ -n "$reloadcmd" ] && acmesh_deploy_ssh_exec_command "$target" "$ssh_key" "$port" "$reloadcmd"
		return 0
	fi

	key_dir="$(dirname "$key_file")"
	fullchain_dir="$(dirname "$fullchain_file")"
	printf 'mkdir -p %s %s && cp %s %s && chmod 600 %s && cp %s %s && chmod 644 %s' \
		"$(acmesh_shell_quote "$key_dir")" \
		"$(acmesh_shell_quote "$fullchain_dir")" \
		"$(acmesh_shell_quote "$source_key")" \
		"$(acmesh_shell_quote "$key_file")" \
		"$(acmesh_shell_quote "$key_file")" \
		"$(acmesh_shell_quote "$source_fullchain")" \
		"$(acmesh_shell_quote "$fullchain_file")" \
		"$(acmesh_shell_quote "$fullchain_file")"
	acmesh_deploy_metadata_command "$key_file" "$fullchain_file" "$owner" "$group" "$file_mode" || return $?
	[ -n "$reloadcmd" ] && printf ' && %s' "$reloadcmd"
	printf '\n'
}

acmesh_deploy_preview_json() {
	command="$(acmesh_build_profile_deploy_command "$@")"
	masked_command="$(acmesh_mask_secret "$command" | sed "s/StrictHostKeyChecking='\*\*\*'/StrictHostKeyChecking=yes/g")"
	printf '{"ok":true,"command":"%s"}\n' "$(acmesh_json_escape "$masked_command")"
}

acmesh_deploy_test_log() {
	printf 'TEST MODE: generated deploy command, but did not write PEM content, copy files, open SSH, or run reload command.\n'
	if [ "${2:-managed-acme}" = paste-pem ]; then
		printf 'PEM content source: private key and fullchain would be written to temporary files without logging PEM content.\n'
	fi
	printf 'Deploy command preview omitted from task log.\n'
}

acmesh_deploy_prepare_pem() {
	cert_source="$1"
	domain="$2"
	key_pem="$3"
	fullchain_pem="$4"
	[ "$cert_source" = paste-pem ] || return 0
	[ -n "${ACMESH_CURRENT_TASK_ID:-}" ] || {
		echo "Temporary PEM deployment requires a task workspace." >&2
		return 1
	}
	workspace="$(acmesh_task_workspace "$ACMESH_CURRENT_TASK_ID")" || return 1
	command -v mktemp >/dev/null 2>&1 || return 1
	umask 077
	ACMESH_DEPLOY_TEMP_PEM_KEY="$(mktemp "$workspace/pem-key.XXXXXX")" || return 1
	ACMESH_DEPLOY_TEMP_PEM_FULLCHAIN="$(mktemp "$workspace/pem-fullchain.XXXXXX")" || {
		acmesh_deploy_cleanup_temp_key
		return 1
	}
	printf '%s\n' "$key_pem" > "$ACMESH_DEPLOY_TEMP_PEM_KEY" || {
		acmesh_deploy_cleanup_temp_key
		return 1
	}
	printf '%s\n' "$fullchain_pem" > "$ACMESH_DEPLOY_TEMP_PEM_FULLCHAIN" || {
		acmesh_deploy_cleanup_temp_key
		return 1
	}
	chmod 600 "$ACMESH_DEPLOY_TEMP_PEM_KEY" "$ACMESH_DEPLOY_TEMP_PEM_FULLCHAIN" || {
		acmesh_deploy_cleanup_temp_key
		return 1
	}
	printf 'Prepared PEM content in temporary files for deployment.\n'
}

acmesh_deploy_target_lock_path() {
	command -v sha256sum >/dev/null 2>&1 || return 127
	lock_id="$({
		printf '%s\n' "${1:-local}" "${13:-}" "${14:-22}" "${15:-root}" "${4:-}" "${5:-}"
	} | sha256sum)" || return 1
	lock_id=${lock_id%% *}
	case "$lock_id" in
		''|*[!0-9a-fA-F]*) return 1 ;;
	esac
	printf '%s/%s.lock\n' "${ACMESH_DEPLOY_LOCK_DIR:-${ACMESH_RUNTIME_DIR:-/var/run/acmesh-console}/deploy-locks}" "$lock_id"
}

acmesh_execute_profile_deploy_locked() {
	deploy_type="${1:-local}"
	cert_source="${2:-managed-acme}"
	domain="$3"
	key_file="$4"
	fullchain_file="$5"
	cert_file="${6:-}"
	ca_file="${7:-}"
	reloadcmd="${8:-}"
	source_key_file="${9:-}"
	source_fullchain_file="${10:-}"
	key_pem="${11:-}"
	fullchain_pem="${12:-}"
	host="${13:-}"
	port="${14:-22}"
	user="${15:-root}"
	ssh_key="${16:-/etc/acmesh-console/ssh/id_ed25519}"
	key_type="${17:-}"
	sudo_mode="${18:-auto}"
	owner="${19:-}"
	group="${20:-}"
	file_mode="${21:-}"
	acmesh_deploy_metadata_valid "$owner" "$group" "$file_mode" || { echo "invalid deploy metadata" >&2; return 1; }

	printf 'REAL MODE: executing deploy profile.\n'
	acmesh_deploy_prepare_pem "$cert_source" "$domain" "$key_pem" "$fullchain_pem" || return $?
	converted_ssh_key=""
	if [ "$deploy_type" = ssh ]; then
		[ -n "$user" ] || user="root"
		[ -n "$port" ] || port="22"
		acmesh_ssh_validate_target "$host" "$port" "$user" || { echo "invalid SSH target" >&2; return 2; }
		acmesh_deploy_prepare_ssh_trust "$host" "$port" || return $?
		original_ssh_key="$ssh_key"
		acmesh_deploy_resolve_ssh_key "$ssh_key" "${ACMESH_DEPLOY_ALLOW_KEY_CONVERT:-0}" || return $?
		ssh_key="$ACMESH_DEPLOY_RESOLVED_SSH_KEY"
		if [ "$ssh_key" != "$original_ssh_key" ]; then
			converted_ssh_key="$ssh_key"
		fi
	fi
	command="$(acmesh_build_profile_deploy_command "$deploy_type" "$cert_source" "$domain" "$key_file" "$fullchain_file" "$cert_file" "$ca_file" "$reloadcmd" "$source_key_file" "$source_fullchain_file" "$key_pem" "$fullchain_pem" "$host" "$port" "$user" "$ssh_key" "$key_type" "$sudo_mode" "$owner" "$group" "$file_mode")" || return $?
	if [ "$deploy_type" = ssh ]; then
		source_key="$(acmesh_deploy_source_key_path "$cert_source" "$domain" "$source_key_file" "${key_type:-ecc}")"
		source_fullchain="$(acmesh_deploy_source_fullchain_path "$cert_source" "$domain" "$source_fullchain_file" "${key_type:-ecc}")"
		[ -n "$host" ] || { echo "SSH host is required" >&2; return 1; }
		[ -n "$user" ] || user="root"
		[ -n "$port" ] || port="22"
		target="$user@$host"
		case "$sudo_mode" in always) remote_write_sudo=1;; never) remote_write_sudo=0;; ''|auto) remote_write_sudo=0; [ "$user" = root ] || remote_write_sudo=1;; *) return 1;; esac
		status=0
		acmesh_deploy_remote_transaction "$source_key" "$source_fullchain" "$key_file" "$fullchain_file" \
			"$target" "$ssh_key" "$port" "$remote_write_sudo" "$reloadcmd" "$owner" "$group" "${file_mode:-644}" || status=$?
		if [ -n "$converted_ssh_key" ]; then
			acmesh_deploy_cleanup_temp_key
			printf 'Removed temporary converted SSH key.\n'
		fi
		return "$status"
	fi
	source_key="$(acmesh_deploy_source_key_path "$cert_source" "$domain" "$source_key_file" "${key_type:-ecc}")"
	source_fullchain="$(acmesh_deploy_source_fullchain_path "$cert_source" "$domain" "$source_fullchain_file" "${key_type:-ecc}")"
	acmesh_deploy_transaction "$source_key" "$source_fullchain" "$key_file" "$fullchain_file" \
		"$reloadcmd" "$owner" "$group" "${file_mode:-644}"
}

acmesh_execute_profile_deploy_guarded() (
	ACMESH_DEPLOY_TEMP_KEY=""
	ACMESH_DEPLOY_TEMP_PEM_KEY=""
	ACMESH_DEPLOY_TEMP_PEM_FULLCHAIN=""
	[ -n "${ACMESH_CURRENT_TASK_ID:-}" ] || return 2
	workspace="$(acmesh_task_workspace "$ACMESH_CURRENT_TASK_ID")" || return 1
	trap 'acmesh_deploy_cleanup_temp_key' EXIT
	acmesh_deploy_run_worker "$workspace" "${ACMESH_DEPLOY_WORKER_SCRIPT:-${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}/deploy-worker.sh}" "$@"
)

acmesh_execute_profile_deploy() {
	acmesh_deploy_destination_preflight "${1:-local}" "${4:-}" "${5:-}" || return $?
	deploy_lock="$(acmesh_deploy_target_lock_path "$@")" || return $?
	acmesh_lock_run "$deploy_lock" acmesh_execute_profile_deploy_guarded "$@"
}
