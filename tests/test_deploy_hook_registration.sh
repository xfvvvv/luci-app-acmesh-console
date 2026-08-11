#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="${TMPDIR:-/tmp}/acmesh-hook-registration.$$"
trap 'rm -rf "$TMP"' 0 HUP INT TERM
mkdir -p "$TMP/home" "$TMP/lib"
chmod 700 "$TMP" "$TMP/home" "$TMP/lib"

export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"
export ACMESH_CONSOLE_HOOK_SOURCE="$ROOT/root/usr/libexec/acmesh-console/hooks/acmesh-console-ssh.sh"
. "$ACMESH_LIB_DIR/command.sh"
. "$ACMESH_LIB_DIR/deploy.sh"
acmesh_deploy_install_acme_hooks "$TMP/home"

for hook in acmesh_console_ssh acmesh-console-ssh; do
	path="$TMP/home/deploy/$hook.sh"
	[ -f "$path" ] && [ ! -L "$path" ]
	[ "$(LC_ALL=C ls -l "$path" | awk '{print $1}')" = -rwxr-xr-x ]
	grep -F 'ACMESH_CONSOLE_HOOK_SOURCED=1' "$path" >/dev/null
	if grep -Eq '^[[:space:]]*set[[:space:]]+' "$path"; then
		echo "deploy hook wrapper must not alter acme.sh shell options"
		exit 1
	fi
	sh -n "$path"
done

# Sourcing the wrapper must not enable nounset in acme.sh's shell, including
# while the wrapper sources the shared hook implementation.
if ! sh -c '
	unset ACMESH_HOOK_UNSET_SENTINEL
	ACMESH_CONSOLE_HOOK_SOURCED=1
	export ACMESH_CONSOLE_HOOK_SOURCED
	. "$1"
	: "$ACMESH_HOOK_UNSET_SENTINEL"
' sh "$TMP/home/deploy/acmesh_console_ssh.sh" 2>/dev/null; then
	echo "deploy hook source path must preserve acme.sh shell options"
	exit 1
fi

# The canonical wrapper must be sourceable by the POSIX shell used by acme.sh
# and must expose the function acme.sh invokes after sourcing a deploy hook.
for lib in cert task command dns provider deploy ssh config request_payload authorization operation; do
	: > "$TMP/lib/$lib.sh"
done
cat > "$TMP/lib/operation.sh" <<'SH'
acmesh_console_ssh_deploy() { :; }
SH
export ACMESH_LIB_DIR="$TMP/lib"
ACMESH_CONSOLE_HOOK_SOURCED=1 . "$TMP/home/deploy/acmesh_console_ssh.sh"
command -v acmesh_console_ssh_deploy >/dev/null

echo "test_deploy_hook_registration: ok"
