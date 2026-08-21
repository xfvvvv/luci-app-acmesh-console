. "${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}/json.sh"

if ! command -v acmesh_atomic_write >/dev/null 2>&1; then
	. "${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}/io.sh"
fi

if ! command -v acmesh_mask_secret >/dev/null 2>&1; then
	. "${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}/command.sh"
fi

if ! command -v acmesh_config_uci_option >/dev/null 2>&1 && [ -f "${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}/config.sh" ]; then
	. "${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}/config.sh"
fi

acmesh_task_default_option() {
	key="$1"
	default="$2"
	value=""
	if command -v acmesh_config_uci_option >/dev/null 2>&1; then
		value="$(acmesh_config_uci_option "$key" || true)"
	fi
	[ -n "$value" ] && printf '%s\n' "$value" || printf '%s\n' "$default"
}

: "${ACMESH_TASK_STATE_DIR:=$(acmesh_task_default_option task_state_dir "${ACMESH_RUNTIME_DIR:-/var/run/acmesh-console}/tasks")}"
: "${ACMESH_TASK_LOG_DIR:=$(acmesh_task_default_option task_log_dir "${ACMESH_LOG_DIR:-/var/log/acmesh-console}/tasks")}"

acmesh_task_lock_file() {
	printf '%s/.state.lock\n' "$ACMESH_TASK_STATE_DIR"
}

acmesh_task_validate_id() {
	id="${1:-}"
	date_part=${id%%-*}
	sequence=${id#*-}
	[ "$date_part" != "$id" ] && [ "${#date_part}" -eq 14 ] || return 1
	case "$date_part" in
		*[!0-9]*) return 1 ;;
	esac
	case "$sequence" in
		''|*[!0-9]*) return 1 ;;
	esac
}

acmesh_task_now() {
	date -u +%Y-%m-%dT%H:%M:%SZ
}

acmesh_task_proc_identity_load() {
	proc_stat="${1:-/proc/self/stat}"
	IFS= read -r proc_line < "$proc_stat" || return 1
	proc_pid=${proc_line%% *}
	proc_tail=${proc_line##*) }
	[ "$proc_tail" != "$proc_line" ] || return 1
	set -- $proc_tail
	[ "$#" -ge 20 ] || return 1
	shift 19
	proc_starttime="$1"
	case "$proc_pid:$proc_starttime" in
		''|*[!0-9:]*) return 1 ;;
	esac
}

acmesh_task_worker_identity_load() {
	acmesh_task_proc_identity_load /proc/self/stat || return 1
	acmesh_worker_pid="$proc_pid"
	acmesh_worker_starttime="$proc_starttime"
	boot_id_file="${ACMESH_BOOT_ID_FILE:-/proc/sys/kernel/random/boot_id}"
	IFS= read -r acmesh_worker_boot_id < "$boot_id_file" || return 1
	[ -n "$acmesh_worker_boot_id" ]
}

acmesh_task_worker_is_alive() {
	worker_pid="${1:-}" worker_starttime="${2:-}" worker_boot_id="${3:-}"
	case "$worker_pid:$worker_starttime" in
		''|*[!0-9:]*) return 1 ;;
	esac
	[ -n "$worker_boot_id" ] || return 1
	boot_id_file="${ACMESH_BOOT_ID_FILE:-/proc/sys/kernel/random/boot_id}"
	IFS= read -r current_boot_id < "$boot_id_file" || return 1
	[ "$current_boot_id" = "$worker_boot_id" ] || return 1
	[ -d "/proc/$worker_pid" ] || return 1
	acmesh_task_proc_identity_load "/proc/$worker_pid/stat" || return 1
	[ "$proc_pid" = "$worker_pid" ] && [ "$proc_starttime" = "$worker_starttime" ]
}

acmesh_task_created_at_from_id() {
	acmesh_task_validate_id "$1" || return 2
	printf '%s\n' "${1%%-*}" | sed -n 's/^\(....\)\(..\)\(..\)\(..\)\(..\)\(..\)$/\1-\2-\3T\4:\5:\6Z/p'
}

acmesh_task_json_string() {
	path="$1"
	field="$2"
	[ "$(jsonfilter -i "$path" -t "@.$field" 2>/dev/null || true)" = string ] || return 1
	jsonfilter -i "$path" -e "@.$field" 2>/dev/null
}

acmesh_task_state_load() {
	path="$1"
	expected_id="$2"
	[ -f "$path" ] && [ ! -L "$path" ] || return 1
	command -v jsonfilter >/dev/null 2>&1 || return 1
	[ "$(jsonfilter -i "$path" -t '@' 2>/dev/null || true)" = object ] || return 1
	task_state_id="$(acmesh_task_json_string "$path" taskId)" || return 1
	[ "$task_state_id" = "$expected_id" ] || return 1
	task_state_status="$(acmesh_task_json_string "$path" status)" || return 1
}

acmesh_task_created_is_stale() {
	created_at="$1"
	stale_seconds="${ACMESH_TASK_CREATED_STALE_SECONDS:-300}"
	case "$stale_seconds" in
		''|*[!0-9]*) return 1 ;;
	esac
	now_epoch="${ACMESH_TASK_RECOVERY_NOW_EPOCH:-$(date +%s)}"
	case "$now_epoch" in
		''|*[!0-9]*) return 1 ;;
	esac
	created_epoch="$(date -u -D '%Y-%m-%dT%H:%M:%SZ' -d "$created_at" +%s 2>/dev/null)" || {
		created_date="$(printf '%s\n' "$created_at" | sed -n 's/^\(....-..-..\)T\(..:..:..\)Z$/\1 \2/p')"
		[ -n "$created_date" ] || return 1
		created_epoch="$(date -u -d "$created_date" +%s 2>/dev/null)" || return 1
	}
	[ "$now_epoch" -ge "$created_epoch" ] || return 1
	[ $((now_epoch - created_epoch)) -ge "$stale_seconds" ]
}

acmesh_task_write_state_atomic_unlocked() {
	id="$1" operation="$2" status="$3" stage="$4" exit_code="$5"
	started_at="${6:-}" finished_at="${7:-}" last_error="${8:-}"
	worker_pid="${9:-}" worker_starttime="${10:-}" worker_boot_id="${11:-}"
	acmesh_task_validate_id "$id" || return 2
	case "$exit_code" in
		''|*[!0-9]*) return 2 ;;
	esac
	state="$ACMESH_TASK_STATE_DIR/$id.json"
	created_at="$(acmesh_task_created_at_from_id "$id")" || return 1
	if acmesh_task_state_load "$state" "$id"; then
		existing_created_at="$(acmesh_task_json_string "$state" createdAt)" || existing_created_at=
		[ -n "$existing_created_at" ] && created_at="$existing_created_at"
	fi
	{
		printf '{"ok":true,"taskId":"%s","operation":"%s"' \
			"$(acmesh_json_escape "$id")" "$(acmesh_json_escape "$operation")"
		printf ',"createdAt":"%s","status":"%s","stage":"%s","exitCode":%s' \
			"$(acmesh_json_escape "$created_at")" \
			"$(acmesh_json_escape "$status")" \
			"$(acmesh_json_escape "$stage")" "$exit_code"
		printf ',"startedAt":"%s","finishedAt":"%s","lastError":"%s"' \
			"$(acmesh_json_escape "$started_at")" \
			"$(acmesh_json_escape "$finished_at")" \
			"$(acmesh_json_escape "$(acmesh_mask_secret "$last_error")")"
		printf ',"workerPid":"%s","workerStarttime":"%s","workerBootId":"%s"}\n' \
			"$(acmesh_json_escape "$worker_pid")" \
			"$(acmesh_json_escape "$worker_starttime")" \
			"$(acmesh_json_escape "$worker_boot_id")"
	} | acmesh_atomic_write "$state" 600
}

acmesh_task_write_state_atomic() {
	id="$1"
	acmesh_task_validate_id "$id" || return 2
	acmesh_private_dir "$ACMESH_TASK_STATE_DIR" || return 1
	acmesh_lock_run "$(acmesh_task_lock_file)" acmesh_task_write_state_atomic_unlocked "$@"
}

acmesh_task_create_unlocked() {
	operation="$1"
	acmesh_private_dir "$ACMESH_TASK_STATE_DIR" || return 1
	acmesh_private_dir "$ACMESH_TASK_LOG_DIR" || return 1
	timestamp="$(date -u +%Y%m%d%H%M%S)"
	attempt=0
	while :; do
		sequence="$$"
		[ "$attempt" -eq 0 ] || sequence="$$${attempt}"
		id="$timestamp-$sequence"
		state="$ACMESH_TASK_STATE_DIR/$id.json"
		log="$ACMESH_TASK_LOG_DIR/$id.log"
		if [ ! -e "$state" ] && [ ! -L "$state" ] && (umask 077; set -C; : > "$log") 2>/dev/null; then
			break
		fi
		attempt=$((attempt + 1))
		[ "$attempt" -lt 1000 ] || return 1
	done
	chmod 600 "$log" || return 1
	if ! acmesh_task_write_state_atomic_unlocked "$id" "$operation" created created 0 '' '' ''; then
		rm -f "$log"
		return 1
	fi
	printf '%s\n' "$id"
}

acmesh_task_create() {
	operation="$1"
	acmesh_private_dir "$ACMESH_TASK_STATE_DIR" || return 1
	acmesh_private_dir "$ACMESH_TASK_LOG_DIR" || return 1
	acmesh_lock_run "$(acmesh_task_lock_file)" acmesh_task_create_unlocked "$operation"
}

# CGI workers must not remain attached to the request process.  uhttpd can
# send SIGHUP when that process exits, which would otherwise interrupt a
# newly-started worker while it is still opening its private input snapshot.
# Run the worker through the internal acmeshctl entry point in a new session;
# the task runner itself still owns all task logging and state transitions.
acmesh_task_spawn() {
	[ "$#" -ge 4 ] || return 2
	setsid_bin="${ACMESH_SETSID_BIN:-setsid}"
	if ! command -v "$setsid_bin" >/dev/null 2>&1; then
		echo "Required session runner is unavailable: setsid" >&2
		return 127
	fi
	if [ -n "${ACMESH_TASK_WORKER_BIN:-}" ]; then
		worker_bin="$ACMESH_TASK_WORKER_BIN"
	elif [ -n "${ACMESH_LIB_DIR:-}" ]; then
		worker_bin="${ACMESH_LIB_DIR%/}/../acmeshctl"
	else
		worker_bin=/usr/libexec/acmesh-console/acmeshctl
	fi
	[ -f "$worker_bin" ] && [ ! -L "$worker_bin" ] || {
		echo "Task worker entry point is unavailable" >&2
		return 127
	}
	"$setsid_bin" sh "$worker_bin" __task-worker "$@" </dev/null >/dev/null 2>&1 &
}

acmesh_task_status() {
	id="$1"
	if ! acmesh_task_validate_id "$id"; then
		printf '{"ok":false,"error":"invalid task id"}\n'
		return 2
	fi
	acmesh_private_dir "$ACMESH_TASK_STATE_DIR" || return 1
	state="$ACMESH_TASK_STATE_DIR/$id.json"
	if [ -f "$state" ] && [ ! -L "$state" ]; then
		cat "$state"
	else
		printf '{"ok":false,"error":"task not found"}\n'
		return 1
	fi
}

acmesh_task_log() {
	id="$1"
	if ! acmesh_task_validate_id "$id"; then
		printf 'invalid task id\n'
		return 2
	fi
	acmesh_private_dir "$ACMESH_TASK_LOG_DIR" || return 1
	log="$ACMESH_TASK_LOG_DIR/$id.log"
	if [ -f "$log" ] && [ ! -L "$log" ]; then
		cat "$log"
	else
		printf 'task log not found\n'
		return 1
	fi
}

acmesh_task_list() {
	limit="${1:-50}"
	acmesh_private_dir "$ACMESH_TASK_STATE_DIR" || return 1
	first=1
	count=0
	printf '{"ok":true,"tasks":['
	for state in $(ls -1t "$ACMESH_TASK_STATE_DIR"/*.json 2>/dev/null || true); do
		[ -f "$state" ] && [ ! -L "$state" ] || continue
		name=${state##*/}
		id=${name%.json}
		[ "$name" = "$id.json" ] && acmesh_task_validate_id "$id" || continue
		[ "$count" -lt "$limit" ] || break
		[ "$first" = 1 ] || printf ','
		first=0
		count=$((count + 1))
		cat "$state"
	done
	printf ']}\n'
}

acmesh_task_write_state() {
	id="$1"
	operation="$2"
	status="$3"
	stage="$4"
	exit_code="${5:-0}"
	acmesh_task_write_state_atomic "$id" "$operation" "$status" "$stage" "$exit_code"
}

acmesh_task_cleanup_one_time_sudo_password() {
	id="${1:-}"
	acmesh_task_validate_id "$id" || return 2
	base="${ACMESH_TASK_WORKSPACE_DIR:-/tmp/acmesh-console}"
	workspace="$base/$id"
	[ -d "$workspace" ] && [ ! -L "$workspace" ] || return 0
	password_file="$workspace/sudo-password"
	[ ! -L "$password_file" ] || return 1
	rm -f -- "$password_file"
}

acmesh_task_run() {
	id="$1"
	operation="$2"
	stage="$3"
	shift 3
	acmesh_task_validate_id "$id" || return 2
	acmesh_private_dir "$ACMESH_TASK_STATE_DIR" || return 1
	acmesh_private_dir "$ACMESH_TASK_LOG_DIR" || return 1
	log="$ACMESH_TASK_LOG_DIR/$id.log"
	started_at="$(acmesh_task_now)"
	acmesh_task_worker_identity_load || return 1
	ACMESH_CURRENT_TASK_ID="$id"
	export ACMESH_CURRENT_TASK_ID
	task_sudo_password_file="${ACMESH_DEPLOY_SUDO_PASSWORD_FILE:-}"
	cleanup_task_sudo_password() {
		[ -z "$task_sudo_password_file" ] || { [ ! -L "$task_sudo_password_file" ] && rm -f -- "$task_sudo_password_file"; }
		acmesh_task_cleanup_one_time_sudo_password "$id" 2>/dev/null || true
	}
	trap 'cleanup_task_sudo_password; exit 129' HUP
	trap 'cleanup_task_sudo_password; exit 130' INT
	trap 'cleanup_task_sudo_password; exit 143' TERM
	trap 'cleanup_task_sudo_password' EXIT
	acmesh_task_write_state_atomic "$id" "$operation" running "$stage" 0 "$started_at" '' '' \
		"$acmesh_worker_pid" "$acmesh_worker_starttime" "$acmesh_worker_boot_id"
	set +e
	(umask 077 && "$@" >> "$log" 2>&1)
	rc=$?
	set -e
	cleanup_task_sudo_password
	finished_at="$(acmesh_task_now)"
	if [ "$rc" = 0 ]; then
		acmesh_task_write_state_atomic "$id" "$operation" success "$stage" "$rc" "$started_at" "$finished_at" ''
	else
		acmesh_task_write_state_atomic "$id" "$operation" failed "$stage" "$rc" "$started_at" "$finished_at" "task exited with status $rc"
	fi
	return "$rc"
}

acmesh_task_recover_one_unlocked() {
	id="$1"
	expected_state="$2"
	state="$ACMESH_TASK_STATE_DIR/$id.json"
	[ -f "$state" ] && [ ! -L "$state" ] || return 0
	current_state="$(cat "$state" 2>/dev/null)" || return 0
	[ "$current_state" = "$expected_state" ] || return 0
	acmesh_task_state_load "$state" "$id" || return 0
	case "$task_state_status" in
		running)
			worker_pid="$(acmesh_task_json_string "$state" workerPid 2>/dev/null || true)"
			worker_starttime="$(acmesh_task_json_string "$state" workerStarttime 2>/dev/null || true)"
			worker_boot_id="$(acmesh_task_json_string "$state" workerBootId 2>/dev/null || true)"
			acmesh_task_worker_is_alive "$worker_pid" "$worker_starttime" "$worker_boot_id" && return 0
			;;
		created)
			created_at="$(acmesh_task_json_string "$state" createdAt)" || return 0
			acmesh_task_created_is_stale "$created_at" || return 0
			;;
		*) return 0 ;;
	esac
	acmesh_task_cleanup_one_time_sudo_password "$id" || true
	operation="$(acmesh_task_json_string "$state" operation)" || return 0
	started_at="$(acmesh_task_json_string "$state" startedAt)" || return 0
	acmesh_task_write_state_atomic_unlocked "$id" "$operation" interrupted recovery 1 \
		"$started_at" "$(acmesh_task_now)" "service restarted before task completion"
}

acmesh_task_recover_interrupted() {
	command -v jsonfilter >/dev/null 2>&1 || return 1
	acmesh_private_dir "$ACMESH_TASK_STATE_DIR" || return 1
	for state in "$ACMESH_TASK_STATE_DIR"/*.json; do
		[ -f "$state" ] && [ ! -L "$state" ] || continue
		name=${state##*/}
		id=${name%.json}
		[ "$name" = "$id.json" ] && acmesh_task_validate_id "$id" || continue
		expected_state="$(cat "$state" 2>/dev/null)" || continue
		acmesh_task_state_load "$state" "$id" || continue
		case "$task_state_status" in
			running) ;;
			created)
				created_at="$(acmesh_task_json_string "$state" createdAt)" || continue
				acmesh_task_created_is_stale "$created_at" || continue
				;;
			*) continue ;;
		esac
		acmesh_lock_run "$(acmesh_task_lock_file)" \
			acmesh_task_recover_one_unlocked "$id" "$expected_state" || return 1
	done
}

acmesh_task_prune_unlocked() {
	max_terminal="${1:-200}"
	case "$max_terminal" in
		''|*[!0-9]*) return 2 ;;
	esac
	terminal_count=0
	for state in "$ACMESH_TASK_STATE_DIR"/*.json; do
		[ -f "$state" ] && [ ! -L "$state" ] || continue
		name=${state##*/}
		id=${name%.json}
		[ "$name" = "$id.json" ] && acmesh_task_validate_id "$id" || continue
		acmesh_task_state_load "$state" "$id" || continue
		case "$task_state_status" in
			success|failed|interrupted|cancelled) terminal_count=$((terminal_count + 1)) ;;
		esac
	done
	remove_count=$((terminal_count - max_terminal))
	[ "$remove_count" -gt 0 ] || return 0
	for state in "$ACMESH_TASK_STATE_DIR"/*.json; do
		[ "$remove_count" -gt 0 ] || break
		[ -f "$state" ] && [ ! -L "$state" ] || continue
		name=${state##*/}
		id=${name%.json}
		[ "$name" = "$id.json" ] && acmesh_task_validate_id "$id" || continue
		acmesh_task_state_load "$state" "$id" || continue
		case "$task_state_status" in
			success|failed|interrupted|cancelled)
				acmesh_task_cleanup_one_time_sudo_password "$id" || true
				rm -f "$state" "$ACMESH_TASK_LOG_DIR/$id.log"
				remove_count=$((remove_count - 1))
				;;
		esac
	done
}

acmesh_task_prune() {
	max_terminal="${1:-200}"
	case "$max_terminal" in
		''|*[!0-9]*) return 2 ;;
	esac
	command -v jsonfilter >/dev/null 2>&1 || return 1
	acmesh_private_dir "$ACMESH_TASK_STATE_DIR" || return 1
	acmesh_private_dir "$ACMESH_TASK_LOG_DIR" || return 1
	acmesh_lock_run "$(acmesh_task_lock_file)" acmesh_task_prune_unlocked "$max_terminal"
}
