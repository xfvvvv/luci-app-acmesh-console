acmesh_private_dir_is_secure() (
	candidate="${1:-}"
	[ -n "$candidate" ] || exit 1
	[ -d "$candidate" ] && [ ! -L "$candidate" ] || exit 1
	listing="$(LC_ALL=C ls -ld "$candidate" 2>/dev/null)" || exit 1
	set -- $listing
	[ "${1:-}" = drwx------ ] || exit 1
	listing="$(LC_ALL=C ls -nd "$candidate" 2>/dev/null)" || exit 1
	set -- $listing
	[ "${3:-}" = 0 ]
)

acmesh_private_dir_parent_is_trusted() (
	parent_candidate="${1:-}"
	case "$parent_candidate" in
		/etc|/tmp|/var/run|/var/log) exit 0 ;;
	esac
	acmesh_private_dir_is_secure "$parent_candidate"
)

acmesh_private_dir() (
	candidate="${1:-}"
	[ -n "$candidate" ] || exit 2
	[ "$candidate" != / ] || exit 1
	if [ -e "$candidate" ] || [ -L "$candidate" ]; then
		acmesh_private_dir_is_secure "$candidate"
		exit $?
	fi
	acmesh_path_dir "$candidate"
	parent="$dir"
	if ! acmesh_private_dir_parent_is_trusted "$parent"; then
		acmesh_private_dir "$parent" || exit 1
	fi
	if (umask 077 && mkdir "$candidate"); then
		acmesh_private_dir_is_secure "$candidate"
		exit $?
	fi
	acmesh_private_dir_is_secure "$candidate"
)

acmesh_path_dir() {
	case "$1" in
		*/*)
			dir=${1%/*}
			[ -n "$dir" ] || dir=/
			;;
		*) dir=. ;;
	esac
}

acmesh_atomic_stop_writer() {
	writer_pid="${acmesh_atomic_writer_pid:-}"
	case "$writer_pid" in
		''|0|*[!0-9]*) acmesh_atomic_writer_pid=; return 0 ;;
	esac
	kill -TERM "$writer_pid" 2>/dev/null || :
	attempt=0
	while kill -0 "$writer_pid" 2>/dev/null; do
		attempt=$((attempt + 1))
		if [ "$attempt" -ge 3 ]; then
			kill -KILL "$writer_pid" 2>/dev/null || :
			acmesh_atomic_writer_pid=
			return 0
		fi
		sleep 1
	done
	wait "$writer_pid" 2>/dev/null || :
	acmesh_atomic_writer_pid=
}

acmesh_atomic_close_input() {
	if [ "${acmesh_atomic_input_open:-0}" = 1 ]; then
		exec 5<&-
		acmesh_atomic_input_open=0
	fi
}

acmesh_atomic_signal_cleanup() {
	trap - HUP INT TERM
	acmesh_atomic_close_input
	acmesh_atomic_stop_writer
	[ -z "${acmesh_atomic_tmp:-}" ] || rm -f "$acmesh_atomic_tmp"
	acmesh_atomic_tmp=
	exit 1
}

acmesh_atomic_restore_traps() {
	acmesh_atomic_restore_traps_text="${acmesh_atomic_saved_traps-}"
	trap - HUP INT TERM
	[ -n "$acmesh_atomic_restore_traps_text" ] || return 0
	while IFS= read -r acmesh_atomic_restore_trap; do
		case "$acmesh_atomic_restore_trap" in
			*" HUP"|*" SIGHUP") eval "$acmesh_atomic_restore_trap" || : ;;
			*" INT"|*" SIGINT") eval "$acmesh_atomic_restore_trap" || : ;;
			*" TERM"|*" SIGTERM") eval "$acmesh_atomic_restore_trap" || : ;;
		esac
	done <<EOF
$acmesh_atomic_restore_traps_text
EOF
	acmesh_atomic_saved_traps=
}

acmesh_atomic_write_run() {
	path="${1:-}"
	mode="${2:-600}"
	[ -n "$path" ] || return 2
	case "$mode" in
		600|0600) mode=600 ;;
		*) return 2 ;;
	esac
	acmesh_path_dir "$path"
	acmesh_private_dir "$dir" || return 1
	base=${path##*/}
	[ -n "$base" ] || return 2

	acmesh_atomic_tmp=
	acmesh_atomic_writer_pid=
	acmesh_atomic_input_open=0
	acmesh_atomic_saved_traps="$(trap)"
	trap 'acmesh_atomic_signal_cleanup' HUP INT TERM
	acmesh_atomic_tmp="$(umask 077; mktemp "$dir/.${base}.$$.XXXXXX")" || {
		acmesh_atomic_restore_traps
		return 1
	}
	chmod "$mode" "$acmesh_atomic_tmp" || {
		rm -f "$acmesh_atomic_tmp"
		acmesh_atomic_tmp=
		acmesh_atomic_restore_traps
		return 1
	}
	exec 5<&0 || {
		rm -f "$acmesh_atomic_tmp"
		acmesh_atomic_tmp=
		acmesh_atomic_restore_traps
		return 1
	}
	acmesh_atomic_input_open=1
	cat <&5 > "$acmesh_atomic_tmp" &
	acmesh_atomic_writer_pid=$!
	if wait "$acmesh_atomic_writer_pid"; then
		acmesh_atomic_writer_pid=
	else
		acmesh_atomic_writer_pid=
		acmesh_atomic_close_input
		rm -f "$acmesh_atomic_tmp"
		acmesh_atomic_tmp=
		acmesh_atomic_restore_traps
		return 1
	fi
	acmesh_atomic_close_input
	chmod "$mode" "$acmesh_atomic_tmp" || {
		rm -f "$acmesh_atomic_tmp"
		acmesh_atomic_tmp=
		acmesh_atomic_restore_traps
		return 1
	}
	mv -f "$acmesh_atomic_tmp" "$path" || {
		rm -f "$acmesh_atomic_tmp"
		acmesh_atomic_tmp=
		acmesh_atomic_restore_traps
		return 1
	}
	acmesh_atomic_tmp=
	acmesh_atomic_restore_traps
}

acmesh_atomic_write() {
	IFS=' ' read -r acmesh_atomic_shell_pid _ < /proc/self/stat || return 1
	if [ "$acmesh_atomic_shell_pid" = "$$" ]; then
		( acmesh_atomic_write_run "$@" )
	else
		acmesh_atomic_write_run "$@"
	fi
}

acmesh_private_file_is_secure() (
	candidate="${1:-}"
	[ -n "$candidate" ] || exit 1
	[ -f "$candidate" ] && [ ! -L "$candidate" ] || exit 1
	listing="$(LC_ALL=C ls -ld "$candidate" 2>/dev/null)" || exit 1
	set -- $listing
	[ "${1:-}" = -rw------- ] || exit 1
	listing="$(LC_ALL=C ls -nd "$candidate" 2>/dev/null)" || exit 1
	set -- $listing
	[ "${3:-}" = 0 ]
)

acmesh_lock_file_prepare() (
	lock_file="${1:-}"
	[ -n "$lock_file" ] || exit 1
	if [ -e "$lock_file" ] || [ -L "$lock_file" ]; then
		acmesh_private_file_is_secure "$lock_file"
		exit $?
	fi
	if (umask 077; set -C; : > "$lock_file") 2>/dev/null; then
		acmesh_private_file_is_secure "$lock_file"
		exit $?
	fi
	acmesh_private_file_is_secure "$lock_file"
)

acmesh_lock_run() {
	lock="${1:-}"
	[ -n "$lock" ] || return 2
	shift
	[ "$#" -gt 0 ] || return 2
	flock_bin="${ACMESH_FLOCK_BIN:-flock}"
	command -v "$flock_bin" >/dev/null 2>&1 || {
		echo "Required lock command is unavailable: flock" >&2
		return 127
	}
	acmesh_path_dir "$lock"
	acmesh_private_dir "$dir" || return 1
	acmesh_lock_file_prepare "$lock" || return 1
	(
		exec 9<> "$lock" || exit 1
		acmesh_private_file_is_secure "$lock" || exit 1
		attempt=0
		while ! "$flock_bin" -n 9; do
			attempt=$((attempt + 1))
			[ "$attempt" -lt 10 ] || exit 75
			sleep 1
		done
		"$@"
	)
}

acmesh_task_workspace() {
	id="${1:-}"
	printf '%s\n' "$id" | grep -Eq '^[0-9]{14}-[0-9]+$' || return 2
	base="${ACMESH_TASK_WORKSPACE_DIR:-/tmp/acmesh-console}"
	acmesh_private_dir "$base" || return 1
	workspace="$base/$id"
	acmesh_private_dir "$workspace" || return 1
	printf '%s\n' "$workspace"
}
