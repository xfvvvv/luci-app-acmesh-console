: "${ACMESH_REQUEST_DIR:=/var/run/acmesh-console/requests}"
: "${ACMESH_REQUEST_MAX_CHUNKS:=2048}"
: "${ACMESH_REQUEST_MAX_BYTES:=25165824}"

acmesh_request_validate_id() {
	printf '%s\n' "${1:-}" | grep -Eq '^[a-f0-9]{32}$'
}

acmesh_request_dir_is_private() (
	request_dir="${1:-}"
	[ -n "$request_dir" ] || exit 1
	[ -d "$request_dir" ] && [ ! -L "$request_dir" ] || exit 1
	listing="$(LC_ALL=C ls -ld "$request_dir" 2>/dev/null)" || exit 1
	set -- $listing
	[ "${1:-}" = drwx------ ] || exit 1
	listing="$(LC_ALL=C ls -nd "$request_dir" 2>/dev/null)" || exit 1
	set -- $listing
	[ "${3:-}" = 0 ]
)

acmesh_request_file_is_private() (
	request_file="${1:-}"
	[ -n "$request_file" ] || exit 1
	[ -f "$request_file" ] && [ ! -L "$request_file" ] || exit 1
	listing="$(LC_ALL=C ls -ld "$request_file" 2>/dev/null)" || exit 1
	set -- $listing
	[ "${1:-}" = -rw------- ] || exit 1
	listing="$(LC_ALL=C ls -nd "$request_file" 2>/dev/null)" || exit 1
	set -- $listing
	[ "${3:-}" = 0 ]
)

acmesh_request_validate_chunk_count() {
	chunk_count="${1:-}"
	case "$chunk_count" in
		''|*[!0-9]*) return 1 ;;
	esac
	[ "$chunk_count" -gt 0 ] 2>/dev/null || return 1
	[ "$chunk_count" -le "$ACMESH_REQUEST_MAX_CHUNKS" ] 2>/dev/null
}

acmesh_request_remove_chunks() (
	chunk_id="${1:-}"
	chunk_count="${2:-}"
	acmesh_request_dir_is_private "$ACMESH_REQUEST_DIR" || exit 1
	acmesh_request_validate_id "$chunk_id" || exit 2
	acmesh_request_validate_chunk_count "$chunk_count" || exit 2
	chunk_index=0
	while [ "$chunk_index" -lt "$chunk_count" ]; do
		rm -f "$ACMESH_REQUEST_DIR/$chunk_id.part.$chunk_index"
		chunk_index=$((chunk_index + 1))
	done
)

acmesh_request_assemble_chunks() (
	chunk_id="${1:-}"
	chunk_count="${2:-}"
	acmesh_request_dir_is_private "$ACMESH_REQUEST_DIR" || exit 1
	acmesh_request_validate_id "$chunk_id" || exit 2
	acmesh_request_validate_chunk_count "$chunk_count" || exit 2
	request_source="$ACMESH_REQUEST_DIR/$chunk_id.json"
	[ ! -e "$request_source" ] || exit 1
	request_target="$(umask 077; mktemp "$ACMESH_REQUEST_DIR/.$chunk_id.assembled.XXXXXX")" || exit 1
	if ! acmesh_request_file_is_private "$request_target"; then
		rm -f "$request_target"
		exit 1
	fi
	chunk_index=0
	request_bytes=0
	while [ "$chunk_index" -lt "$chunk_count" ]; do
		chunk_file="$ACMESH_REQUEST_DIR/$chunk_id.part.$chunk_index"
		if ! acmesh_request_file_is_private "$chunk_file"; then
			rm -f "$request_target"
			exit 1
		fi
		chunk_bytes="$(wc -c < "$chunk_file" | tr -d ' ')"
		case "$chunk_bytes" in
			''|*[!0-9]*)
				rm -f "$request_target"
				exit 1
			;;
		esac
		request_bytes=$((request_bytes + chunk_bytes))
		[ "$request_bytes" -le "$ACMESH_REQUEST_MAX_BYTES" ] || {
			rm -f "$request_target"
			exit 1
		}
		cat "$chunk_file" >> "$request_target" || {
			rm -f "$request_target"
			exit 1
		}
		chunk_index=$((chunk_index + 1))
	done
	chmod 600 "$request_target" || {
		rm -f "$request_target"
		exit 1
	}
	mv -f "$request_target" "$request_source" || {
		rm -f "$request_target"
		exit 1
	}
	chunk_index=0
	while [ "$chunk_index" -lt "$chunk_count" ]; do
		rm -f "$ACMESH_REQUEST_DIR/$chunk_id.part.$chunk_index"
		chunk_index=$((chunk_index + 1))
	done
)

acmesh_request_consume() {
	id="${1:-}"
	if ! acmesh_request_dir_is_private "$ACMESH_REQUEST_DIR"; then
		printf '{"ok":false,"error":"request inbox unavailable"}\n'
		return 1
	fi
	if ! acmesh_request_validate_id "$id"; then
		printf '{"ok":false,"error":"invalid request id"}\n'
		return 2
	fi
	source="$ACMESH_REQUEST_DIR/$id.json"
	if ! acmesh_request_file_is_private "$source"; then
		printf '{"ok":false,"error":"request not found"}\n'
		return 1
	fi
	target="$(umask 077; mktemp "$ACMESH_REQUEST_DIR/.$id.processing.XXXXXX")" || return 1
	if ! acmesh_request_file_is_private "$target"; then
		rm -f "$target"
		return 1
	fi
	if ! acmesh_request_file_is_private "$source" || ! mv "$source" "$target"; then
		rm -f "$target"
		printf '{"ok":false,"error":"request not found"}\n'
		return 1
	fi
	if ! acmesh_request_file_is_private "$target"; then
		rm -f "$target"
		printf '{"ok":false,"error":"request not found"}\n'
		return 1
	fi
	printf '%s\n' "$target"
}
