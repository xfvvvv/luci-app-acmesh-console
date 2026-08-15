#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="${TMPDIR:-/tmp}/acmesh-console-rpc-chunked.$$"
export ACMESH_REQUEST_DIR="$TMP/requests"
bin="$TMP/bin"
payload="$TMP/received.json"
trap 'rm -rf "$TMP"' 0 HUP INT TERM
mkdir -p "$ACMESH_REQUEST_DIR" "$bin"
chmod 700 "$TMP" "$ACMESH_REQUEST_DIR"
mkdir "$TMP/untrusted"
chmod 755 "$TMP/untrusted"
. "$ROOT/tests/lib/host_flock.sh"
acmesh_test_install_private_ls_shim "$TMP/private-ls" "$TMP" "$TMP/untrusted"
chmod 700 "$ACMESH_REQUEST_DIR"

cat > "$bin/acmeshctl-wrapper" <<SH
#!/bin/sh
set -eu
[ "\${1:-}" = import-preview ] || exit 2
[ "\${2:-}" = --request-file ] || exit 2
cat "\$3" > "$payload"
printf '%s\\n' '{"ok":true,"received":true}'
SH
chmod 755 "$bin/acmeshctl-wrapper"
export ACMESHCTL="$bin/acmeshctl-wrapper"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"

id="eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
printf '%s' '{"archiveBase64":"chunked' > "$ACMESH_REQUEST_DIR/$id.part.0"
printf '%s' 'payload' > "$ACMESH_REQUEST_DIR/$id.part.1"
printf '%s' '"}' > "$ACMESH_REQUEST_DIR/$id.part.2"
chmod 600 "$ACMESH_REQUEST_DIR/$id.part.0" "$ACMESH_REQUEST_DIR/$id.part.1" "$ACMESH_REQUEST_DIR/$id.part.2"
printf '600\t%s\n' "$ACMESH_REQUEST_DIR/$id.json" >> "$ACMESH_TEST_MODE_REGISTRY"
response="$(sh "$ROOT/root/usr/libexec/acmesh-console/rpc-write" import_preview --request-id "$id" --chunk-count 3)"
case "$response" in
	*'"ok":true'*'"received":true'*) ;;
	*) echo "chunked import preview should return backend JSON"; echo "$response"; exit 1 ;;
esac
[ "$(cat "$payload")" = '{"archiveBase64":"chunkedpayload"}' ] || {
	echo "chunked import preview should assemble request parts in order"
	exit 1
}
[ ! -e "$ACMESH_REQUEST_DIR/$id.json" ] || { echo "assembled request should be consumed"; exit 1; }
[ ! -e "$ACMESH_REQUEST_DIR/$id.part.0" ] || { echo "chunk 0 should be consumed"; exit 1; }
[ ! -e "$ACMESH_REQUEST_DIR/$id.part.1" ] || { echo "chunk 1 should be consumed"; exit 1; }
[ ! -e "$ACMESH_REQUEST_DIR/$id.part.2" ] || { echo "chunk 2 should be consumed"; exit 1; }

cleanup_id="ffffffffffffffffffffffffffffffff"
printf '%s' stale-0 > "$ACMESH_REQUEST_DIR/$cleanup_id.part.0"
printf '%s' stale-1 > "$ACMESH_REQUEST_DIR/$cleanup_id.part.1"
chmod 600 "$ACMESH_REQUEST_DIR/$cleanup_id.part.0" "$ACMESH_REQUEST_DIR/$cleanup_id.part.1"
cleanup="$(sh "$ROOT/root/usr/libexec/acmesh-console/rpc-write" import_preview_cleanup --request-id "$cleanup_id" --chunk-count 2)"
case "$cleanup" in
	*'"ok":true'*) ;;
	*) echo "chunk cleanup should return success"; echo "$cleanup"; exit 1 ;;
esac
[ ! -e "$ACMESH_REQUEST_DIR/$cleanup_id.part.0" ] || { echo "cleanup should remove chunk 0"; exit 1; }
[ ! -e "$ACMESH_REQUEST_DIR/$cleanup_id.part.1" ] || { echo "cleanup should remove chunk 1"; exit 1; }

echo "test_rpc_chunked_import: ok"
