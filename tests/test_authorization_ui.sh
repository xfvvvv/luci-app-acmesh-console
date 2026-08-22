#!/bin/sh
set -eu

AUTH=htdocs/luci-static/resources/acmesh/authorization_v2.js
OPS=htdocs/luci-static/resources/view/acmesh/operations_v2.js
CERTS=htdocs/luci-static/resources/view/acmesh/certificates_v2.js
PO=po/zh_Hans/acmesh-console.po

require() { grep -F "$2" "$1" >/dev/null || { echo "missing $2 in $1"; exit 1; }; }
reject() { ! grep -F "$2" "$1" >/dev/null || { echo "forbidden $2 in $1"; exit 1; }; }

require "$AUTH" 'function run(method, payload, options)'
require "$AUTH" 'function showChallenge(response, options)'
require "$AUTH" 'function showHostKey(response, options)'
require "$AUTH" 'function badge(status)'
require "$AUTH" "'authorization_execute'"
require "$AUTH" "'once'"
require "$AUTH" "'remember'"
require "$AUTH" 'response.riskSummary'
require "$AUTH" 'function isBooleanTrue(value)'
require "$AUTH" '.trim().toLowerCase()'
require "$AUTH" "normalized === 'true'"
require "$AUTH" "normalized === '1'"
require "$AUTH" 'sudoPasswordRequired'
require "$AUTH" 'sudoPassword'
require "$AUTH" "'type': 'password'"
require "$AUTH" "response.error === 'hostKeyChanged'"
require "$AUTH" "probed.ok || (!probed.challengeId"
require "$AUTH" "!probed.challengeId"
require "$AUTH" 'new Promise(function(resolve, reject)'
require "$AUTH" '.then(resolve, reject)'
require "$AUTH" 'showChallenge(next, options).then(resolve, reject)'
reject "$AUTH" 'keyPem'
reject "$AUTH" 'fullchainPem'
reject "$AUTH" 'credentials'
reject "$AUTH" 'token'
reject "$OPS" 'window.confirm'
reject "$OPS" 'confirmSshKeyConversionRetry'

require "$OPS" "data-acmesh-tab': 'authorizations'"
for label in Operation Subject Scope Granted 'Last used' Uses Status Actions; do require "$OPS" "$label"; done
require "$OPS" "'authorization_revoke'"
require "$OPS" "'authorization_revoke_all'"
require "$OPS" "authorization.run('profile_delete'"
require "$OPS" 'const issueHostKeyOptions = deployAfterIssue && deploy && (deploy.type || '\''local'\'') === '\''ssh'\'''
require "$OPS" "const operation = deployAfterIssue ? 'issue-deploy' : 'issue';"
require "$OPS" "const rpcMethod = deployAfterIssue ? 'issue_deploy' : operation;"
require "$OPS" "authorization.run(rpcMethod, { profileId: profile.id }, issueHostKeyOptions)"
for key in domains challengeAlias dnsSleep ec256 ec384 ec521 rsa2048 rsa3072 rsa4096 rsa8192; do require "$OPS" "$key"; done
require "$CERTS" "authorization.run('renew'"
require "$CERTS" "'certificate_revoke'"
require "$CERTS" "'certificate_remove'"
require "$PO" '插件将严格按照上方参数执行操作。继续即表示您已核对并接受证书签发配额、远端文件覆盖、服务重载及目标系统配置产生的结果。'

echo 'authorization ui tests passed'
