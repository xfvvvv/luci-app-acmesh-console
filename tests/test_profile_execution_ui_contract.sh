#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OPS="$ROOT/htdocs/luci-static/resources/view/acmesh/operations_v2.js"
CERTS="$ROOT/htdocs/luci-static/resources/view/acmesh/certificates_v2.js"

require() { grep -Fq -- "$2" "$1" || { echo "missing execution contract: $2"; exit 1; }; }

require "$OPS" "authorization.run('issue', { profileId: profile.id }, issueHostKeyOptions)"
require "$OPS" "return { profileId: profile.id, allowKeyConvert: !!options.allowKeyConvert };"
require "$CERTS" "payload: { profileId: profile.id }"

issue_block="$(sed -n '/const runIssueProfile = function/,/const importCredentialsFromRaw/p' "$OPS")"
deploy_block="$(sed -n '/const deployPayload = function/,/const runDeployProfile/p' "$OPS")"
cert_block="$(sed -n '/const prepareDeploy = function/,/const coreTagChoices/p' "$CERTS")"
for forbidden in 'credentials:' 'keyPem:' 'fullchainPem:' 'domain:' 'ca:' 'accountEmail:' 'testMode:'; do
	printf '%s\n' "$issue_block" | grep -Fq -- "$forbidden" && { echo "issue payload contains snapshot field: $forbidden"; exit 1; } || :
	printf '%s\n' "$deploy_block" | grep -Fq -- "$forbidden" && { echo "deploy payload contains snapshot field: $forbidden"; exit 1; } || :
	printf '%s\n' "$cert_block" | grep -Fq -- "$forbidden" && { echo "certificate deploy payload contains snapshot field: $forbidden"; exit 1; } || :
done

echo "test_profile_execution_ui_contract: ok"
