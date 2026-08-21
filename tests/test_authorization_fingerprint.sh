#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"
TMP="${TMPDIR:-/tmp}/acmesh-auth-fingerprint.$$"
trap 'rm -rf "$TMP"' 0 HUP INT TERM
mkdir -p "$TMP/state" "$TMP/out"; chmod 700 "$TMP" "$TMP/state" "$TMP/out"
export ACMESH_AUTH_STATE_DIR="$TMP/state"
export ACMESH_AUTH_INSTANCE_FILE="$TMP/state/instance-id"
. "$ROOT/root/usr/libexec/acmesh-console/lib/authorization.sh"

mkdir "$TMP/concurrent"; chmod 700 "$TMP/concurrent"
ACMESH_AUTH_INSTANCE_FILE="$TMP/concurrent/instance-id"; export ACMESH_AUTH_INSTANCE_FILE
for n in 1 2 3 4; do (acmesh_auth_instance_id > "$TMP/concurrent/id.$n") & done
wait
[ "$(sort -u "$TMP"/concurrent/id.* | wc -l | tr -d ' ')" = 1 ]
[ -s "$TMP/concurrent/instance-id" ]
rm -f "$TMP/concurrent/instance-id"
ln -s "$TMP/concurrent/redirected" "$TMP/concurrent/instance-id"
if acmesh_auth_instance_id >/dev/null 2>&1; then echo "symlink instance id was accepted"; exit 1; fi
[ ! -e "$TMP/concurrent/redirected" ]
ACMESH_AUTH_INSTANCE_FILE="$TMP/state/instance-id"; export ACMESH_AUTH_INSTANCE_FILE

fp() { acmesh_auth_fingerprint "$1"; }
issue() {
	out="$1" domains="$2"
	ACMESH_AUTH_ACCOUNT_ID=account-1 ACMESH_AUTH_CA="${CA:-letsencrypt}" \
	ACMESH_AUTH_PRIMARY_DOMAIN="${PRIMARY:-example.com}" \
	ACMESH_AUTH_DOMAINS="$domains" ACMESH_AUTH_KEY_TYPE="${KEY_TYPE:-ec256}" \
	ACMESH_AUTH_VALIDATION="${VALIDATION:-dns}" ACMESH_AUTH_DNS_API="${DNS_API:-dns_cf}" \
	ACMESH_AUTH_CHALLENGE_ALIAS="${ALIAS:-}" ACMESH_AUTH_DNS_SLEEP="${DNS_SLEEP:-30}" \
	ACMESH_AUTH_DEPLOY_PROFILE_ID="${DEPLOY_ID:-deploy-1}" ACMESH_AUTH_DEPLOY_FINGERPRINT="${DEPLOY_FP:-sha256:deploy-a}" \
	ACMESH_AUTH_TEST_MODE=false acmesh_auth_snapshot issue issueProfile issue-1 "$out"
}

issue "$TMP/out/i1" 'Example.com
www.example.com'
issue "$TMP/out/i2" 'www.example.com
example.COM'
[ "$(fp "$TMP/out/i1")" = "$(fp "$TMP/out/i2")" ]

# Caller assignment/config traversal order cannot affect the fixed-order stream.
ACMESH_AUTH_CA=letsencrypt ACMESH_AUTH_ACCOUNT_ID=account-1 \
	ACMESH_AUTH_VALIDATION=dns ACMESH_AUTH_KEY_TYPE=ec256 \
	ACMESH_AUTH_PRIMARY_DOMAIN=example.com \
	ACMESH_AUTH_DNS_API=dns_cf ACMESH_AUTH_DOMAINS='www.example.com
example.com' ACMESH_AUTH_DNS_SLEEP=30 ACMESH_AUTH_DEPLOY_FINGERPRINT=sha256:deploy-a \
	ACMESH_AUTH_DEPLOY_PROFILE_ID=deploy-1 ACMESH_AUTH_TEST_MODE=false \
	acmesh_auth_snapshot issue issueProfile issue-1 "$TMP/out/reordered"
[ "$(fp "$TMP/out/i1")" = "$(fp "$TMP/out/reordered")" ]

control_subject="issue$(printf '\t')unsafe"
if acmesh_auth_snapshot issue issueProfile "$control_subject" "$TMP/out/control" >/dev/null 2>&1; then
	echo "control character subject was accepted"; exit 1
fi
[ ! -e "$TMP/out/control" ] || { echo "failed snapshot left an output file"; exit 1; }

# Cosmetic config order/name/description and token material are never inputs.
ACMESH_AUTH_NAME=renamed ACMESH_AUTH_DESCRIPTION=changed ACMESH_AUTH_DNS_TOKEN=secret-b issue "$TMP/out/i3" 'example.com
www.example.com'
[ "$(fp "$TMP/out/i1")" = "$(fp "$TMP/out/i3")" ]
! grep -E 'renamed|changed|secret-b' "$TMP/out/i3" >/dev/null

for assignment in 'CA=zerossl' 'KEY_TYPE=rsa2048' 'VALIDATION=webroot' 'DNS_API=dns_ali' 'ALIAS=_acme.other' 'DEPLOY_FP=sha256:deploy-b'; do
	unset CA KEY_TYPE VALIDATION DNS_API ALIAS DEPLOY_FP
	eval "$assignment"; export CA KEY_TYPE VALIDATION DNS_API ALIAS DEPLOY_FP
	issue "$TMP/out/changed" 'example.com
www.example.com'
	[ "$(fp "$TMP/out/i1")" != "$(fp "$TMP/out/changed")" ]
done
unset CA KEY_TYPE VALIDATION DNS_API ALIAS DEPLOY_FP
issue "$TMP/out/domain-change" 'example.com
api.example.com'
[ "$(fp "$TMP/out/i1")" != "$(fp "$TMP/out/domain-change")" ]
PRIMARY=www.example.com; export PRIMARY
issue "$TMP/out/primary-change" 'example.com
www.example.com'
[ "$(fp "$TMP/out/i1")" != "$(fp "$TMP/out/primary-change")" ]
unset PRIMARY
ACMESH_AUTH_ACCOUNT_ID=account-1 ACMESH_AUTH_CA=letsencrypt ACMESH_AUTH_PRIMARY_DOMAIN=example.com ACMESH_AUTH_DOMAINS='Example.com
www.example.com' ACMESH_AUTH_KEY_TYPE=ec256 ACMESH_AUTH_VALIDATION=dns ACMESH_AUTH_DNS_API=dns_cf ACMESH_AUTH_DNS_SLEEP=30 ACMESH_AUTH_DEPLOY_PROFILE_ID=deploy-1 ACMESH_AUTH_DEPLOY_FINGERPRINT=sha256:deploy-a ACMESH_AUTH_TEST_MODE=false acmesh_auth_snapshot renew issueProfile issue-1 "$TMP/out/renew"
[ "$(fp "$TMP/out/i1")" != "$(fp "$TMP/out/renew")" ]

ACMESH_AUTH_ACCOUNT_ID=account-1 ACMESH_AUTH_CA=letsencrypt ACMESH_AUTH_PRIMARY_DOMAIN=example.com ACMESH_AUTH_DOMAINS=example.com ACMESH_AUTH_KEY_TYPE=ec256 ACMESH_AUTH_VALIDATION=dns ACMESH_AUTH_DNS_API=dns_cf ACMESH_AUTH_CREDENTIAL_MODE=token ACMESH_AUTH_CREDENTIAL_KEYS=CF_Token ACMESH_AUTH_DNS_SLEEP=0 ACMESH_AUTH_TEST_MODE=false acmesh_auth_snapshot issue issueProfile issue-credentials "$TMP/out/credential-a"
ACMESH_AUTH_ACCOUNT_ID=account-1 ACMESH_AUTH_CA=letsencrypt ACMESH_AUTH_PRIMARY_DOMAIN=example.com ACMESH_AUTH_DOMAINS=example.com ACMESH_AUTH_KEY_TYPE=ec256 ACMESH_AUTH_VALIDATION=dns ACMESH_AUTH_DNS_API=dns_cf ACMESH_AUTH_CREDENTIAL_MODE=global-key ACMESH_AUTH_CREDENTIAL_KEYS='CF_Email
CF_Key' ACMESH_AUTH_DNS_SLEEP=0 ACMESH_AUTH_TEST_MODE=false acmesh_auth_snapshot issue issueProfile issue-credentials "$TMP/out/credential-b"
[ "$(fp "$TMP/out/credential-a")" != "$(fp "$TMP/out/credential-b")" ]

deploy() {
	out="$1"
	ACMESH_AUTH_DEPLOY_TYPE=ssh ACMESH_AUTH_SOURCE_TYPE=paste-pem ACMESH_AUTH_KEY_PEM="$KEY_PEM" ACMESH_AUTH_FULLCHAIN_PEM="$CHAIN_PEM" \
	ACMESH_AUTH_HOST="${HOST:-router.example}" ACMESH_AUTH_PORT=22 ACMESH_AUTH_USER=root ACMESH_AUTH_SSH_CLIENT=dropbear \
	ACMESH_AUTH_HOSTKEY_ALGORITHM=ssh-ed25519 ACMESH_AUTH_HOSTKEY_FINGERPRINT="${HOST_FP:-SHA256:one}" \
	ACMESH_AUTH_KEY_FILE="${DEST_KEY:-/etc/ssl/key.pem}" ACMESH_AUTH_FULLCHAIN_FILE=/etc/ssl/fullchain.pem \
	ACMESH_AUTH_RELOAD="${RELOAD:-/etc/init.d/uhttpd reload}" ACMESH_AUTH_SUDO_MODE=never ACMESH_AUTH_PRESERVE_METADATA="${PRESERVE_METADATA-}" ACMESH_AUTH_TRANSACTION_STRATEGY=pair-rollback-v1 \
	acmesh_auth_snapshot deploy-run deployProfile deploy-1 "$out"
}
KEY_PEM='-----BEGIN PRIVATE KEY-----
top-secret-key
-----END PRIVATE KEY-----'; CHAIN_PEM='-----BEGIN CERTIFICATE-----
certificate-secret
-----END CERTIFICATE-----'; export KEY_PEM CHAIN_PEM
deploy_stdout="$(deploy "$TMP/out/d1")"
[ -z "$deploy_stdout" ] || { echo "PEM snapshot wrote unexpected stdout"; exit 1; }
! grep -E 'top-secret|certificate-secret|BEGIN' "$TMP/out/d1" >/dev/null
for assignment in 'HOST=other.example' 'DEST_KEY=/other/key.pem' 'RELOAD=/bin/true' 'HOST_FP=SHA256:two'; do
	unset HOST DEST_KEY RELOAD HOST_FP; eval "$assignment"; export HOST DEST_KEY RELOAD HOST_FP
	deploy "$TMP/out/d2"; [ "$(fp "$TMP/out/d1")" != "$(fp "$TMP/out/d2")" ]
done
unset HOST DEST_KEY RELOAD HOST_FP
PRESERVE_METADATA=true deploy "$TMP/out/d-preserve"; [ "$(fp "$TMP/out/d1")" != "$(fp "$TMP/out/d-preserve")" ]
unset PRESERVE_METADATA

ACMESH_AUTH_ACME_HOME=/etc/acme ACMESH_AUTH_CORE_TAG=3.1.0 acmesh_auth_snapshot core-upgrade core acme.sh "$TMP/out/core1"
ACMESH_AUTH_ACME_HOME=/etc/acme ACMESH_AUTH_CORE_TAG=3.2.0 acmesh_auth_snapshot core-upgrade core acme.sh "$TMP/out/core2"
[ "$(fp "$TMP/out/core1")" != "$(fp "$TMP/out/core2")" ]
ACMESH_AUTH_ACME_HOME=/etc/acme ACMESH_AUTH_CORE_TAG=3.2.0 ACMESH_AUTH_CORE_EMAIL=first@example.org acmesh_auth_snapshot core-install global core "$TMP/out/core-install-1"
ACMESH_AUTH_ACME_HOME=/etc/acme ACMESH_AUTH_CORE_TAG=3.2.0 ACMESH_AUTH_CORE_EMAIL=second@example.org acmesh_auth_snapshot core-install global core "$TMP/out/core-install-2"
[ "$(fp "$TMP/out/core-install-1")" != "$(fp "$TMP/out/core-install-2")" ]
acmesh_auth_summary "$TMP/out/d1" "$TMP/out/summary"
! grep -E 'top-secret|certificate-secret|BEGIN' "$TMP/out/summary" >/dev/null
grep -F '"canonicalVersion":1,"ackVersion":1' "$TMP/out/summary" >/dev/null
[ "$(jsonfilter -i "$TMP/out/summary" -e '@.host')" = router.example ]
[ "$(jsonfilter -i "$TMP/out/summary" -e '@.keyFile')" = /etc/ssl/key.pem ]
[ "$(jsonfilter -i "$TMP/out/summary" -e '@.reloadCommand')" = '/etc/init.d/uhttpd reload' ]
[ "$(jsonfilter -i "$TMP/out/summary" -e '@.hostKeyFingerprint')" = SHA256:one ]
[ -n "$(jsonfilter -i "$TMP/out/summary" -e '@.keyPemDigest')" ]
ACMESH_AUTH_CANON_VERSION=2 ACMESH_AUTH_ACK_VERSION=3 \
	ACMESH_AUTH_ACME_HOME=/etc/acme ACMESH_AUTH_CORE_TAG=3.2.0 \
	acmesh_auth_snapshot core-upgrade core acme.sh "$TMP/out/versioned"
acmesh_auth_summary "$TMP/out/versioned" "$TMP/out/versioned-summary"
grep -F '"canonicalVersion":2,"ackVersion":3' "$TMP/out/versioned-summary" >/dev/null
sed 's/:canonicalVersion:[0-9][0-9]*:2$/:canonicalVersion:10:2,"x":true/' \
	"$TMP/out/versioned" > "$TMP/out/malformed-version"
chmod 600 "$TMP/out/malformed-version"
if acmesh_auth_summary "$TMP/out/malformed-version" "$TMP/out/malformed-summary" >/dev/null 2>&1; then
	echo "malformed snapshot version was accepted"; exit 1
fi
sed 's/:canonicalVersion:[0-9][0-9]*:2$/:canonicalVersion:2:01/' \
	"$TMP/out/versioned" > "$TMP/out/leading-zero-version"
chmod 600 "$TMP/out/leading-zero-version"
if acmesh_auth_summary "$TMP/out/leading-zero-version" "$TMP/out/leading-zero-summary" >/dev/null 2>&1; then
	echo "leading-zero snapshot version was accepted"; exit 1
fi
set -- $(LC_ALL=C ls -l "$TMP/out/d1"); [ "$1" = -rw------- ]
set -- $(LC_ALL=C ls -l "$TMP/out/summary"); [ "$1" = -rw------- ]
echo "test_authorization_fingerprint: ok"
