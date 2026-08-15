#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"
export ACMESH_REQUEST_DIR="$ROOT/tests/.tmp/requests"
id="0123456789abcdef0123456789abcdef"

rm -rf "$ROOT/tests/.tmp"
mkdir -p "$ACMESH_REQUEST_DIR"
chmod 700 "$ACMESH_REQUEST_DIR"
printf '%s\n' '{"operation":"renew"}' > "$ACMESH_REQUEST_DIR/$id.json"
chmod 600 "$ACMESH_REQUEST_DIR/$id.json"

. "$ACMESH_LIB_DIR/request.sh"

acmesh_test_mode() {
	if command -v stat >/dev/null 2>&1; then
		stat -c %a "$1"
	elif busybox stat -c %a "$1" >/dev/null 2>&1; then
		busybox stat -c %a "$1"
	else
		permissions="$(ls -ld "$1")"
		permissions=${permissions%% *}
		case "$permissions" in
			drwx------) printf '700\n' ;;
			-rw-------) printf '600\n' ;;
			*) printf 'unknown\n' ;;
		esac
	fi
}

processing="$(acmesh_request_consume "$id")"
[ -f "$processing" ]
[ "$(acmesh_test_mode "$processing")" = 600 ]
[ ! -e "$ACMESH_REQUEST_DIR/$id.json" ]

printf '%s\n' '{"operation":"renew-again"}' > "$ACMESH_REQUEST_DIR/$id.json"
chmod 600 "$ACMESH_REQUEST_DIR/$id.json"
processing_again="$(acmesh_request_consume "$id")"
[ "$processing_again" != "$processing" ] || {
	echo "repeated request consumption should use collision-safe processing names"
	exit 1
}
[ "$(cat "$processing")" = '{"operation":"renew"}' ] || {
	echo "repeated request consumption should not overwrite an earlier processing file"
	exit 1
}
[ "$(cat "$processing_again")" = '{"operation":"renew-again"}' ]
[ "$(acmesh_test_mode "$processing_again")" = 600 ]
rm -f "$processing" "$processing_again"

if second="$(acmesh_request_consume "$id")"; then
	echo "second request consumption should fail"
	exit 1
else
	rc=$?
	[ "$rc" = 1 ] || { echo "second request consumption should return 1"; exit 1; }
	case "$second" in
		*'request not found'*) ;;
		*) echo "second request consumption should report request not found"; exit 1 ;;
	esac
fi

invalid="$(acmesh_request_consume not-an-id 2>/dev/null || true)"
case "$invalid" in
	*'invalid request id'*) ;;
	*) echo "invalid request id should be rejected"; exit 1 ;;
esac

symlink_id="fedcba9876543210fedcba9876543210"
outside="$ROOT/tests/.tmp/outside.json"
printf '%s\n' '{"outside":true}' > "$outside"
chmod 600 "$outside"
ln -s "$outside" "$ACMESH_REQUEST_DIR/$symlink_id.json"
if symlink_result="$(acmesh_request_consume "$symlink_id")"; then
	echo "symlink request should be rejected"
	exit 1
else
	rc=$?
	[ "$rc" = 1 ] || { echo "symlink request should return 1"; exit 1; }
	case "$symlink_result" in
		*'request not found'*) ;;
		*) echo "symlink request should report request not found"; exit 1 ;;
	esac
fi
[ "$(cat "$outside")" = '{"outside":true}' ]

chunk_id="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
printf '%s' '{"archiveBase64":"chunked' > "$ACMESH_REQUEST_DIR/$chunk_id.part.0"
printf '%s' '"}' > "$ACMESH_REQUEST_DIR/$chunk_id.part.1"
chmod 600 "$ACMESH_REQUEST_DIR/$chunk_id.part.0" "$ACMESH_REQUEST_DIR/$chunk_id.part.1"
acmesh_request_assemble_chunks "$chunk_id" 2
[ "$(cat "$ACMESH_REQUEST_DIR/$chunk_id.json")" = '{"archiveBase64":"chunked"}' ] || {
	echo "chunk assembly should preserve the request payload"
	exit 1
}
[ "$(acmesh_test_mode "$ACMESH_REQUEST_DIR/$chunk_id.json")" = 600 ] || {
	echo "assembled requests should be private"
	exit 1
}
[ ! -e "$ACMESH_REQUEST_DIR/$chunk_id.part.0" ] || { echo "assembled chunks should be removed"; exit 1; }
[ ! -e "$ACMESH_REQUEST_DIR/$chunk_id.part.1" ] || { echo "assembled chunks should be removed"; exit 1; }
rm -f "$ACMESH_REQUEST_DIR/$chunk_id.json"

chunk_symlink_id="cccccccccccccccccccccccccccccccc"
chunk_outside="$ROOT/tests/.tmp/chunk-outside"
printf '%s' 'not-trusted' > "$chunk_outside"
chmod 600 "$chunk_outside"
ln -s "$chunk_outside" "$ACMESH_REQUEST_DIR/$chunk_symlink_id.part.0"
if acmesh_request_assemble_chunks "$chunk_symlink_id" 1; then
	echo "symlink chunks should be rejected"
	exit 1
fi
[ ! -e "$ACMESH_REQUEST_DIR/$chunk_symlink_id.json" ] || { echo "rejected chunks should not publish a request"; exit 1; }

chunk_cleanup_id="dddddddddddddddddddddddddddddddd"
printf '%s' 'stale-0' > "$ACMESH_REQUEST_DIR/$chunk_cleanup_id.part.0"
printf '%s' 'stale-1' > "$ACMESH_REQUEST_DIR/$chunk_cleanup_id.part.1"
chmod 600 "$ACMESH_REQUEST_DIR/$chunk_cleanup_id.part.0" "$ACMESH_REQUEST_DIR/$chunk_cleanup_id.part.1"
acmesh_request_remove_chunks "$chunk_cleanup_id" 2
[ ! -e "$ACMESH_REQUEST_DIR/$chunk_cleanup_id.part.0" ] || { echo "chunk cleanup should remove part 0"; exit 1; }
[ ! -e "$ACMESH_REQUEST_DIR/$chunk_cleanup_id.part.1" ] || { echo "chunk cleanup should remove part 1"; exit 1; }

trusted_request_dir="$ACMESH_REQUEST_DIR"
symlink_inbox_outside="$ROOT/tests/.tmp/symlink-inbox-outside"
symlink_inbox="$ROOT/tests/.tmp/symlink-inbox"
symlink_inbox_id="11111111111111111111111111111111"
mkdir "$symlink_inbox_outside"
chmod 700 "$symlink_inbox_outside"
printf '%s\n' '{"outside":"symlink-inbox"}' > "$symlink_inbox_outside/$symlink_inbox_id.json"
chmod 600 "$symlink_inbox_outside/$symlink_inbox_id.json"
ln -s "$symlink_inbox_outside" "$symlink_inbox"
ACMESH_REQUEST_DIR="$symlink_inbox"
if acmesh_request_consume "$symlink_inbox_id" > "$ROOT/tests/.tmp/symlink-inbox.out"; then
	echo "symlink request inboxes should be rejected"
	exit 1
fi
[ -f "$symlink_inbox_outside/$symlink_inbox_id.json" ] || {
	echo "symlink request inbox rejection should not move the outside request"
	exit 1
}
for processing in "$symlink_inbox_outside"/.$symlink_inbox_id.*; do
	[ ! -e "$processing" ] || {
		echo "symlink request inbox rejection should not create outside processing files"
		exit 1
	}
done

non_private_inbox="$ROOT/tests/.tmp/non-private-inbox"
non_private_id="22222222222222222222222222222222"
mkdir "$non_private_inbox"
chmod 755 "$non_private_inbox"
printf '%s\n' '{"outside":"non-private-inbox"}' > "$non_private_inbox/$non_private_id.json"
chmod 600 "$non_private_inbox/$non_private_id.json"
ACMESH_REQUEST_DIR="$non_private_inbox"
if acmesh_request_consume "$non_private_id" > "$ROOT/tests/.tmp/non-private-inbox.out"; then
	echo "non-private request inboxes should be rejected"
	exit 1
fi
[ -f "$non_private_inbox/$non_private_id.json" ] || {
	echo "non-private request inbox rejection should not move the request"
	exit 1
}
for processing in "$non_private_inbox"/.$non_private_id.*; do
	[ ! -e "$processing" ] || {
		echo "non-private request inbox rejection should not create processing files"
		exit 1
	}
done
ACMESH_REQUEST_DIR="$trusted_request_dir"

weak_mode_id="33333333333333333333333333333333"
printf '%s\n' '{"operation":"weak-mode"}' > "$ACMESH_REQUEST_DIR/$weak_mode_id.json"
chmod 644 "$ACMESH_REQUEST_DIR/$weak_mode_id.json"
if acmesh_request_consume "$weak_mode_id" > "$ROOT/tests/.tmp/weak-mode.out"; then
	echo "non-0600 request sources should be rejected before publication"
	exit 1
fi
[ -f "$ACMESH_REQUEST_DIR/$weak_mode_id.json" ] || {
	echo "rejected non-0600 requests should remain in the inbox"
	exit 1
}
[ "$(acmesh_test_mode "$ACMESH_REQUEST_DIR/$weak_mode_id.json")" != 600 ] || {
	echo "rejected request sources should not be chmodded"
	exit 1
}
for processing in "$ACMESH_REQUEST_DIR"/.$weak_mode_id.*; do
	[ ! -e "$processing" ] || {
		echo "non-0600 request rejection should not publish a processing file"
		exit 1
	}
done

collision_id="44444444444444444444444444444444"
collision_target="$ACMESH_REQUEST_DIR/.$collision_id.$$.processing"
printf '%s\n' '{"operation":"collision"}' > "$ACMESH_REQUEST_DIR/$collision_id.json"
chmod 600 "$ACMESH_REQUEST_DIR/$collision_id.json"
printf '%s\n' sentinel > "$collision_target"
chmod 600 "$collision_target"
collision_processing="$(acmesh_request_consume "$collision_id")"
[ "$collision_processing" != "$collision_target" ] || {
	echo "request consumption should not overwrite an existing processing path"
	exit 1
}
[ "$(cat "$collision_target")" = sentinel ] || {
	echo "existing processing files should remain unchanged"
	exit 1
}
[ "$(cat "$collision_processing")" = '{"operation":"collision"}' ]

race_id="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
printf '%s\n' '{"operation":"renew"}' > "$ACMESH_REQUEST_DIR/$race_id.json"
chmod 600 "$ACMESH_REQUEST_DIR/$race_id.json"
for worker in 1 2 3 4 5 6 7 8; do
	(
		if acmesh_request_consume "$race_id" > "$ROOT/tests/.tmp/consume-$worker.out" 2>/dev/null; then
			printf '%s\n' success > "$ROOT/tests/.tmp/consume-$worker.status"
		else
			printf '%s\n' failure > "$ROOT/tests/.tmp/consume-$worker.status"
		fi
	) &
done
for worker in 1 2 3 4 5 6 7 8; do
	wait
done
successes=0
for worker in 1 2 3 4 5 6 7 8; do
	[ "$(cat "$ROOT/tests/.tmp/consume-$worker.status")" = success ] && successes=$((successes + 1))
done
[ "$successes" = 1 ] || {
	echo "concurrent request consumers should have exactly one winner"
	exit 1
}
processing_count=0
for processing in "$ACMESH_REQUEST_DIR"/.$race_id.*; do
	[ -f "$processing" ] && processing_count=$((processing_count + 1))
done
[ "$processing_count" = 1 ] || {
	echo "concurrent request consumers should create one processing file"
	exit 1
}

rm -rf "$ROOT/tests/.tmp"
echo "test_request_transport: ok"
