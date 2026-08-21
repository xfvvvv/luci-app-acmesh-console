#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="${TMPDIR:-/tmp}/acmesh-migration-modes.$$"
trap 'rm -rf "$TMP"' 0 HUP INT TERM

mkdir -p "$TMP/source/etc/acme/account" "$TMP/source/etc/acmesh-console/ssh" "$TMP/source/etc/config" "$TMP/source/etc/ssl"
chmod 700 "$TMP" "$TMP/source" "$TMP/source/etc" "$TMP/source/etc/acme" "$TMP/source/etc/acmesh-console" "$TMP/source/etc/ssl"
. "$ROOT/tests/lib/host_flock.sh"
chmod 755 "$TMP"
acmesh_test_install_private_ls_shim "$TMP/private-ls" "$TMP"
chmod 700 "$TMP"
printf '%s\n' '{"schemaVersion":2,"global":{},"accountProfiles":[],"issueProfiles":[],"deployProfiles":[]}' > "$TMP/source/etc/acmesh-console/config.json"
printf '%s\n' account-state > "$TMP/source/etc/acme/account/state"
printf '%s\n' console-state > "$TMP/source/etc/acmesh-console/state"
printf '%s\n' config-lock-state > "$TMP/source/etc/acmesh-console/config.lock"
printf '%s\n' known-hosts-lock-state > "$TMP/source/etc/acmesh-console/ssh/known_hosts.lock"
printf '%s\n' uci-state > "$TMP/source/etc/config/acmesh-console"
printf '%s\n' certificate-key > "$TMP/source/etc/ssl/example.key"
chmod 600 "$TMP/source/etc/acmesh-console/config.json" "$TMP/source/etc/acme/account/state" "$TMP/source/etc/acmesh-console/state" "$TMP/source/etc/acmesh-console/config.lock" "$TMP/source/etc/acmesh-console/ssh/known_hosts.lock" "$TMP/source/etc/config/acmesh-console"
chmod 600 "$TMP/source/etc/ssl/example.key"

export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"
export ACMESH_CONSOLE_CONFIG="$TMP/source/etc/acmesh-console/config.json"
export ACMESH_MIGRATION_ACME_ROOT="$TMP/source/etc/acme"
export ACMESH_MIGRATION_CONSOLE_ROOT="$TMP/source/etc/acmesh-console"
export ACMESH_MIGRATION_SSL_ROOT="$TMP/source/etc/ssl"
export ACMESH_MIGRATION_UCI_CONFIG="$TMP/source/etc/config/acmesh-console"

. "$ACMESH_LIB_DIR/migration.sh"

acmesh_config_path() {
	printf '%s\n' "$ACMESH_CONSOLE_CONFIG"
}

acmesh_config_validate_file() {
	[ -f "$1" ] || return 1
	grep -Fq '"schemaVersion":2' "$1"
}

acmesh_config_get() {
	printf '%s\n' '{"schemaVersion":2,"global":{"acmeHome":"/etc/acme"},"accountProfiles":[],"issueProfiles":[],"deployProfiles":[]}'
}

jsonfilter() {
	[ "${ACMESH_TEST_JSONFILTER_ENABLED:-0}" = 1 ] || {
		echo "jsonfilter must not be called while building an archive" >&2
		return 127
	}
	input= expression= operation=
	while [ "$#" -gt 0 ]; do
		case "$1" in
			-i)
				input="$2"
				shift 2
				;;
			-e|-t)
				operation="$1" expression="$2"
				shift 2
				;;
			*) shift ;;
		esac
	done
	if [ "$operation" = -t ]; then
		[ "$expression" = '@.archiveBase64' ] || return 1
		printf 'string\n'
		return 0
	fi
	case "$expression" in
		'@.format') printf 'acmesh-console-backup\n' ;;
		'@.version') printf '1\n' ;;
		'@.includeDeploymentCertificates') sed -n 's/.*"includeDeploymentCertificates":\([^,}]*\).*/\1/p' "$input" ;;
		'@.deployProfiles[*].keyFile') printf '/etc/ssl/example.key\n' ;;
		'@.deployProfiles[*].fullchainFile'|'@.deployProfiles[*].certFile'|'@.deployProfiles[*].caFile'|'@.deployProfiles[*].sourceKeyFile'|'@.deployProfiles[*].sourceFullchainFile') : ;;
		'@.archiveBase64') sed -n 's/.*"archiveBase64":"\([^"]*\)".*/\1/p' "$input" ;;
		'@.accountProfiles[*]'|'@.issueProfiles[*]'|'@.deployProfiles[*]') : ;;
		*) return 1 ;;
	esac
}

archive="$TMP/archive.tar.gz"
( acmesh_migration_build_archive false "$archive" )
if tar -tzf "$archive" | grep -F 'etc/acmesh-console/ssh/known_hosts.lock' >/dev/null; then
	echo "migration archives must exclude the SSH known-hosts lock"
	exit 1
fi
if tar -tzf "$archive" | grep -F 'etc/acmesh-console/config.lock' >/dev/null; then
	echo "migration archives must exclude the runtime config lock"
	exit 1
fi

export ACMESH_TEST_JSONFILTER_ENABLED=1
validated_stage="$TMP/validated-stage"
if ! acmesh_migration_archive_validate "$archive" "$validated_stage"; then
	echo "an archive produced by build_archive must pass archive_validate, including directory entries"
	exit 1
fi

archive_b64="$(base64 "$archive" | tr -d '\n')"
request="$TMP/import-request.json"
printf '{"archiveBase64":"%s"}\n' "$archive_b64" > "$request"
export ACMESH_PENDING_IMPORT_DIR="$TMP/pending"
mkdir "$ACMESH_PENDING_IMPORT_DIR"
chmod 700 "$ACMESH_PENDING_IMPORT_DIR"
if ! preview="$(acmesh_migration_import_preview "$request")"; then
	echo "import_preview should accept an archive produced by build_archive"
	exit 1
fi
case "$preview" in
	*'"ok":true'*) ;;
	*)
		echo "import_preview should accept an archive produced by build_archive"
		exit 1
		;;
esac
if find "$ACMESH_PENDING_IMPORT_DIR" -maxdepth 1 -name '.archive-preview.*' -print | grep -q .; then
	echo "successful import_preview must remove validation sidecars"
	exit 1
fi

acmesh_migration_safe_relative 'etc/config/' || {
	echo "directory entries with trailing slashes should be safe relative paths"
	exit 1
}
for unsafe in '../escape' '/etc/config' 'etc/../escape' 'etc\\escape' 'etc/..'; do
	if acmesh_migration_safe_relative "$unsafe"; then
		echo "unsafe migration path was accepted: $unsafe"
		exit 1
	fi
done

symlink_root="$TMP/symlink-root"
mkdir "$symlink_root"
tar -xzf "$archive" -C "$symlink_root"
ln -s "$TMP/outside" "$symlink_root/etc/acmesh-console/escape"
symlink_archive="$TMP/symlink.tar.gz"
tar -czf "$symlink_archive" -C "$symlink_root" acmesh-console-backup.json etc
symlink_archive_b64="$(base64 "$symlink_archive" | tr -d '\n')"
invalid_request="$TMP/invalid-import-request.json"
printf '{"archiveBase64":"%s"}\n' "$symlink_archive_b64" > "$invalid_request"
if acmesh_migration_import_preview "$invalid_request" >/dev/null 2>&1; then
	echo "import_preview must reject archives containing symlinks"
	exit 1
fi
if find "$ACMESH_PENDING_IMPORT_DIR" -maxdepth 1 -name '.archive-preview.*' -print | grep -q .; then
	echo "failed import_preview must remove validation sidecars"
	exit 1
fi
if acmesh_migration_archive_validate "$symlink_archive" "$TMP/symlink-stage"; then
	echo "migration archives containing symlinks must be rejected"
	exit 1
fi

rm "$ACMESH_CONSOLE_CONFIG"
default_archive="$TMP/archive-default.tar.gz"
if ! ( acmesh_migration_build_archive false "$default_archive" ); then
	echo "missing persistent config should export a default config"
	exit 1
fi
default_root="$TMP/fake-default-root"
mkdir "$default_root"
tar -xzf "$default_archive" -C "$default_root"
[ -f "$default_root/etc/acmesh-console/config.json" ] || {
	echo "missing persistent config should export a default config"
	exit 1
}
grep -F '"schemaVersion":2' "$default_root/etc/acmesh-console/config.json" >/dev/null || {
	echo "default migration config should be validated and packaged"
	exit 1
}

ssl_archive="$TMP/archive-with-ssl.tar.gz"
( acmesh_migration_build_archive true "$ssl_archive" )
tar -tzf "$ssl_archive" | grep -Fx 'etc/ssl/example.key' >/dev/null || {
	echo "production deploy-file collection should include the safe SSL file"
	exit 1
}
ssl_root="$TMP/ssl-root"
mkdir "$ssl_root"
tar -xzf "$ssl_archive" -C "$ssl_root"
grep -F '"skippedDeploymentFiles":0' "$ssl_root/acmesh-console-backup.json" >/dev/null || {
	echo "production deploy-file collection should not skip the safe SSL file"
	exit 1
}

fake_root="$TMP/fake-root"
mkdir "$fake_root"
tar -xzf "$archive" -C "$fake_root"

legacy_source_root="$TMP/legacy-source-root"
mkdir "$legacy_source_root"
tar -xzf "$TMP/archive.tar.gz" -C "$legacy_source_root"
printf '%s\n' legacy-known-hosts-lock > "$legacy_source_root/etc/acmesh-console/ssh/known_hosts.lock"
legacy_archive="$TMP/archive-legacy-lock.tar.gz"
tar -czf "$legacy_archive" -C "$legacy_source_root" acmesh-console-backup.json etc
legacy_root="$TMP/legacy-root"
mkdir -p "$legacy_root/etc/config"
chmod 700 "$legacy_root"
export ACMESH_MIGRATION_ACME_ROOT="$legacy_root/etc/acme"
export ACMESH_MIGRATION_CONSOLE_ROOT="$legacy_root/etc/acmesh-console"
export ACMESH_MIGRATION_SSL_ROOT="$legacy_root/etc/ssl"
export ACMESH_MIGRATION_UCI_CONFIG="$legacy_root/etc/config/acmesh-console"
export ACMESH_PENDING_IMPORT_DIR="$legacy_root/pending"
mkdir "$ACMESH_PENDING_IMPORT_DIR"
chmod 700 "$ACMESH_PENDING_IMPORT_DIR"
( umask 077; acmesh_migration_install_archive "$legacy_archive" )
[ ! -e "$legacy_root/etc/acmesh-console/ssh/known_hosts.lock" ] || {
	echo "legacy migration restore must not install the SSH known-hosts lock"
	exit 1
}

mode() {
	[ -d "$1" ] || return 1
	permissions="$(LC_ALL=C ls -ld "$1" | cut -c 2-10)"
	[ "$(printf '%s' "$permissions" | wc -c | tr -d ' ')" = 9 ] || return 1
	mode_digit() {
		case "$1" in
			---) printf '0' ;; --x) printf '1' ;; -w-) printf '2' ;; -wx) printf '3' ;;
			r--) printf '4' ;; r-x) printf '5' ;; rw-) printf '6' ;; rwx) printf '7' ;;
			*) return 1 ;;
		esac
	}
	printf '%s%s%s\n' \
		"$(mode_digit "$(printf '%s' "$permissions" | cut -c 1-3)")" \
		"$(mode_digit "$(printf '%s' "$permissions" | cut -c 4-6)")" \
		"$(mode_digit "$(printf '%s' "$permissions" | cut -c 7-9)")"
}

[ "$(mode "$fake_root/etc")" = 755 ] || {
	echo "extracted etc must remain 0755"
	exit 1
}
[ "$(mode "$fake_root/etc/config")" = 755 ] || {
	echo "extracted etc/config must remain 0755"
	exit 1
}
[ "$(mode "$fake_root/etc/acme")" = 700 ] || {
	echo "extracted etc/acme must remain 0700"
	exit 1
}
[ "$(mode "$fake_root/etc/acmesh-console")" = 700 ] || {
	echo "extracted etc/acmesh-console must remain 0700"
	exit 1
}

fresh_root="$TMP/fresh-root"
fresh_archive="$TMP/archive-fresh.tar.gz"
existing_archive="$TMP/archive-existing.tar.gz"
cp "$ssl_archive" "$fresh_archive"
cp "$ssl_archive" "$existing_archive"
mkdir "$fresh_root"
chmod 700 "$fresh_root"
export ACMESH_MIGRATION_ACME_ROOT="$fresh_root/etc/acme"
export ACMESH_MIGRATION_CONSOLE_ROOT="$fresh_root/etc/acmesh-console"
export ACMESH_MIGRATION_SSL_ROOT="$fresh_root/etc/ssl"
export ACMESH_MIGRATION_UCI_CONFIG="$fresh_root/etc/config/acmesh-console"
export ACMESH_PENDING_IMPORT_DIR="$fresh_root/pending"
mkdir "$ACMESH_PENDING_IMPORT_DIR"
chmod 700 "$ACMESH_PENDING_IMPORT_DIR"
( umask 077; acmesh_migration_install_archive "$ssl_archive" )
if find "$ACMESH_PENDING_IMPORT_DIR" -maxdepth 1 -name '.archive-apply.*' -print | grep -q .; then
	echo "successful install_archive must remove validation sidecars"
	exit 1
fi
[ "$(mode "$fresh_root/etc")" = 755 ] || {
	echo "fresh import should keep etc at 0755"
	exit 1
}
[ "$(mode "$fresh_root/etc/config")" = 755 ] || {
	echo "fresh import should create etc/config at 0755"
	exit 1
}
[ "$(mode "$fresh_root/etc/ssl")" = 755 ] || {
	echo "fresh import should create etc/ssl at 0755"
	exit 1
}
[ "$(mode "$fresh_root/etc/acme")" = 700 ] || {
	echo "fresh import should keep etc/acme at 0700"
	exit 1
}
[ "$(mode "$fresh_root/etc/acmesh-console")" = 700 ] || {
	echo "fresh import should keep etc/acmesh-console at 0700"
	exit 1
}

existing_root="$TMP/existing-root"
mkdir -p "$existing_root/etc/config" "$existing_root/etc/ssl"
chmod 700 "$existing_root"
chmod 755 "$existing_root/etc" "$existing_root/etc/config" "$existing_root/etc/ssl"
export ACMESH_MIGRATION_ACME_ROOT="$existing_root/etc/acme"
export ACMESH_MIGRATION_CONSOLE_ROOT="$existing_root/etc/acmesh-console"
export ACMESH_MIGRATION_SSL_ROOT="$existing_root/etc/ssl"
export ACMESH_MIGRATION_UCI_CONFIG="$existing_root/etc/config/acmesh-console"
export ACMESH_PENDING_IMPORT_DIR="$existing_root/pending"
mkdir "$ACMESH_PENDING_IMPORT_DIR"
chmod 700 "$ACMESH_PENDING_IMPORT_DIR"
( umask 077; acmesh_migration_install_archive "$existing_archive" )
[ "$(mode "$existing_root/etc/config")" = 755 ] || {
	echo "fresh import must not chmod an existing etc/config to 0700"
	exit 1
}
[ "$(mode "$existing_root/etc/ssl")" = 755 ] || {
	echo "fresh import must not chmod an existing etc/ssl to 0700"
	exit 1
}

echo "test_migration_archive_modes: ok"
