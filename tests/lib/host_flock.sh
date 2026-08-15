#!/bin/sh

acmesh_test_install_flock_shim() {
	shim_root="$1"
	command -v flock >/dev/null 2>&1 && return 0
	mkdir -p "$shim_root/bin" "$shim_root/lock"
	cat > "$shim_root/bin/flock" <<'EOF'
#!/bin/sh
[ "${1:-}" = -n ] && [ "${2:-}" = 9 ] || exit 2
held="$ACMESH_TEST_FLOCK_ROOT/held"
parent="$PPID"
if ! mkdir "$held" 2>/dev/null; then
	owner="$(cat "$held/owner" 2>/dev/null || true)"
	case "$owner" in
		''|*[!0-9]*) exit 1 ;;
	esac
	kill -0 "$owner" 2>/dev/null && exit 1
	rm -f "$held/owner"
	rmdir "$held" 2>/dev/null || exit 1
	mkdir "$held" 2>/dev/null || exit 1
fi
printf '%s\n' "$parent" > "$held/owner"
(
	while kill -0 "$parent" 2>/dev/null; do
		sleep 0.05
	done
	if [ "$(cat "$held/owner" 2>/dev/null || true)" = "$parent" ]; then
		rm -f "$held/owner"
		rmdir "$held" 2>/dev/null || true
	fi
) </dev/null >/dev/null 2>&1 &
exit 0
EOF
	chmod +x "$shim_root/bin/flock"
	ACMESH_TEST_FLOCK_ROOT="$shim_root/lock"
	PATH="$shim_root/bin:$PATH"
	export ACMESH_TEST_FLOCK_ROOT PATH
}

acmesh_test_install_private_ls_shim() {
	shim_root="$1"
	private_root="$2"
	private_root_extra="${3:-}"
	private_mode="$(LC_ALL=C ls -ld "$private_root" 2>/dev/null | awk '{print $1}')"
	private_extra_mode=
	if [ -n "$private_root_extra" ]; then
		private_extra_mode="$(LC_ALL=C ls -ld "$private_root_extra" 2>/dev/null | awk '{print $1}')"
	fi
	[ "$private_mode" = drwx------ ] && {
		[ -z "$private_root_extra" ] || [ "$private_extra_mode" = drwx------ ]
	} && return 0
	mkdir -p "$shim_root/bin"
	ACMESH_TEST_REAL_LS="$(command -v ls)"
	ACMESH_TEST_REAL_STAT="$(command -v stat 2>/dev/null || true)"
	ACMESH_TEST_REAL_CHMOD="$(command -v chmod)"
	ACMESH_TEST_REAL_MKTEMP="$(command -v mktemp 2>/dev/null || true)"
	ACMESH_TEST_PRIVATE_ROOT="$private_root"
	ACMESH_TEST_PRIVATE_ROOT_EXTRA="$private_root_extra"
	ACMESH_TEST_MODE_REGISTRY="$shim_root/modes"
	: > "$ACMESH_TEST_MODE_REGISTRY"
	printf '700\t%s\n' "$private_root" >> "$ACMESH_TEST_MODE_REGISTRY"
	[ -z "$private_root_extra" ] || printf '700\t%s\n' "$private_root_extra" >> "$ACMESH_TEST_MODE_REGISTRY"
	export ACMESH_TEST_REAL_LS ACMESH_TEST_REAL_STAT ACMESH_TEST_REAL_CHMOD ACMESH_TEST_REAL_MKTEMP
	export ACMESH_TEST_PRIVATE_ROOT ACMESH_TEST_PRIVATE_ROOT_EXTRA ACMESH_TEST_MODE_REGISTRY
	cat > "$shim_root/bin/ls" <<'EOF'
#!/bin/sh
private_root_matches() {
	path="${1:-}"
	root="${2:-}"
	[ -n "$root" ] || return 1
	case "$path" in
		"$root"|"$root"/*) return 0 ;;
	esac
	return 1
}
private_mode_for() {
	path="$1"
	mode="$(awk -F '\t' -v path="$path" '$2 == path { mode=$1 } END { print mode }' "$ACMESH_TEST_MODE_REGISTRY" 2>/dev/null)"
	[ -n "$mode" ] || return 1
	printf '%s\n' "$mode"
}
private_perm_for() {
	case "$1" in
		700|0700) printf '%s\n' drwx------ ;;
		750|0750) printf '%s\n' drwxr-x--- ;;
		755|0755) printf '%s\n' drwxr-xr-x ;;
		770|0770) printf '%s\n' drwxrwx--- ;;
		775|0775) printf '%s\n' drwxrwxr-x ;;
		777|0777) printf '%s\n' drwxrwxrwx ;;
		600|0600) printf '%s\n' -rw------- ;;
		640|0640) printf '%s\n' -rw-r----- ;;
		644|0644) printf '%s\n' -rw-r--r-- ;;
		660|0660) printf '%s\n' -rw-rw---- ;;
		664|0664) printf '%s\n' -rw-rw-r-- ;;
		666|0666) printf '%s\n' -rw-rw-rw- ;;
		*) return 1 ;;
	esac
}
case "${1:-}" in
	-ld|-nd)
		candidate="${2:-}"
		if { private_root_matches "$candidate" "$ACMESH_TEST_PRIVATE_ROOT" ||
			private_root_matches "$candidate" "$ACMESH_TEST_PRIVATE_ROOT_EXTRA"; } &&
			{ [ -d "$candidate" ] || [ -f "$candidate" ]; } && [ ! -L "$candidate" ]; then
			private_perm="$(private_perm_for "$(private_mode_for "$candidate")")" || exec "$ACMESH_TEST_REAL_LS" "$@"
			printf '%s 1 0 0 0 Jan 1 00:00 %s\n' "$private_perm" "$candidate"
			exit 0
		fi
		;;
esac
exec "$ACMESH_TEST_REAL_LS" "$@"
EOF
	cat > "$shim_root/bin/stat" <<'EOF'
#!/bin/sh
private_root_matches() {
	path="${1:-}"
	root="${2:-}"
	[ -n "$root" ] || return 1
	case "$path" in
		"$root"|"$root"/*) return 0 ;;
	esac
	return 1
}
private_mode_for() {
	path="$1"
	mode="$(awk -F '\t' -v path="$path" '$2 == path { mode=$1 } END { print mode }' "$ACMESH_TEST_MODE_REGISTRY" 2>/dev/null)"
	[ -n "$mode" ] || return 1
	printf '%s\n' "${mode#0}"
}
if [ "${1:-}" = -c ] && [ "${2:-}" = %a ]; then
	candidate="${3:-}"
	if private_root_matches "$candidate" "$ACMESH_TEST_PRIVATE_ROOT" ||
		private_root_matches "$candidate" "$ACMESH_TEST_PRIVATE_ROOT_EXTRA"; then
		private_mode_for "$candidate" && exit 0
	fi
elif [ "${1:-}" = -c%a ]; then
	candidate="${2:-}"
	if private_root_matches "$candidate" "$ACMESH_TEST_PRIVATE_ROOT" ||
		private_root_matches "$candidate" "$ACMESH_TEST_PRIVATE_ROOT_EXTRA"; then
		private_mode_for "$candidate" && exit 0
	fi
fi
exec "$ACMESH_TEST_REAL_STAT" "$@"
EOF
	cat > "$shim_root/bin/mktemp" <<'EOF'
#!/bin/sh
private_root_matches() {
	path="${1:-}"
	root="${2:-}"
	[ -n "$root" ] || return 1
	case "$path" in
		"$root"|"$root"/*) return 0 ;;
	esac
	return 1
}
record_mode=600
for argument in "$@"; do
	case "$argument" in
		-d|--directory) record_mode=700 ;;
	esac
done
result="$("$ACMESH_TEST_REAL_MKTEMP" "$@")" || exit $?
printf '%s\n' "$result"
printf '%s\n' "$result" | while IFS= read -r path; do
	[ -n "$path" ] || continue
	if private_root_matches "$path" "$ACMESH_TEST_PRIVATE_ROOT" ||
		private_root_matches "$path" "$ACMESH_TEST_PRIVATE_ROOT_EXTRA"; then
		printf '%s\t%s\n' "$record_mode" "$path" >> "$ACMESH_TEST_MODE_REGISTRY"
	fi
done
EOF
	cat > "$shim_root/bin/chmod" <<'EOF'
#!/bin/sh
private_root_matches() {
	path="${1:-}"
	root="${2:-}"
	[ -n "$root" ] || return 1
	case "$path" in
		"$root"|"$root"/*) return 0 ;;
	esac
	return 1
}
record_mode=
case "${1:-}" in
	600|0600) record_mode=600 ;;
	640|0640) record_mode=640 ;;
	644|0644) record_mode=644 ;;
	660|0660) record_mode=660 ;;
	664|0664) record_mode=664 ;;
	666|0666) record_mode=666 ;;
	700|0700) record_mode=700 ;;
	750|0750) record_mode=750 ;;
	755|0755) record_mode=755 ;;
	770|0770) record_mode=770 ;;
	775|0775) record_mode=775 ;;
	777|0777) record_mode=777 ;;
esac
if [ -n "$record_mode" ]; then
	first=1
	for path in "$@"; do
		if [ "$first" = 1 ]; then first=0; continue; fi
		if private_root_matches "$path" "$ACMESH_TEST_PRIVATE_ROOT" ||
			private_root_matches "$path" "$ACMESH_TEST_PRIVATE_ROOT_EXTRA"; then
			printf '%s\t%s\n' "$record_mode" "$path" >> "$ACMESH_TEST_MODE_REGISTRY"
		fi
	done
fi
exec "$ACMESH_TEST_REAL_CHMOD" "$@"
EOF
	chmod +x "$shim_root/bin/ls" "$shim_root/bin/chmod"
	[ -z "$ACMESH_TEST_REAL_STAT" ] || chmod +x "$shim_root/bin/stat"
	[ -z "$ACMESH_TEST_REAL_MKTEMP" ] || chmod +x "$shim_root/bin/mktemp"
	PATH="$shim_root/bin:$PATH"
	export PATH
}
