#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"
export ACMESH_CONSOLE_CONFIG="$ROOT/tests/.tmp/profile-resolution/config.json"
export ACMESH_TASK_WORKSPACE_DIR="$ROOT/tests/.tmp/profile-resolution/work"
export ACMESH_DEPLOY_LOCK_DIR="$ROOT/tests/.tmp/profile-resolution/deploy-locks"
. "$ACMESH_LIB_DIR/io.sh"
. "$ACMESH_LIB_DIR/config.sh"
. "$ACMESH_LIB_DIR/profile.sh"

rm -rf "${ACMESH_CONSOLE_CONFIG%/*}"
mkdir -p "${ACMESH_CONSOLE_CONFIG%/*}"
chmod 700 "${ACMESH_CONSOLE_CONFIG%/*}"
cat > "$ACMESH_CONSOLE_CONFIG" <<JSON
{"schemaVersion":2,"global":{"defaultAccountEmail":"default@example.org","coreTag":"v3.1.4","acmeHome":"/etc/acme"},"accountProfiles":[{"id":"acc","name":"LE","ca":"letsencrypt_staging","accountEmail":"overlay@example.org"}],"issueProfiles":[{"id":"issue","name":"Example","domain":"example.org","domains":["example.org","www.example.org"],"accountProfileId":"acc","deployProfileId":"deploy","keyType":"ec256","validationMethod":"dns","testModeOverride":"force-test-mode","dnsApi":"dns_cf","credentialMode":"token","credentials":{"CF_Token":"top-secret"},"challengeAlias":"alias.example.net","dnsSleep":42}],"deployProfiles":[{"id":"deploy","name":"nginx","type":"ssh","certSource":"managed-acme","domain":"example.org","keyType":"ec256","host":"192.0.2.10","user":"root","port":"22","sshKey":"/root/.ssh/id_ed25519","keyFile":"/etc/ssl/example.key","fullchainFile":"/etc/ssl/example.pem","reloadcmd":"service nginx reload","sudoMode":"always","owner":"root","group":"ssl-cert","mode":"0640"},{"id":"local-deploy","name":"local","type":"local","certSource":"paste-pem","keyPem":"profile-private-key","fullchainPem":"profile-fullchain","keyFile":"$ROOT/tests/.tmp/profile-resolution/deployed.key","fullchainFile":"$ROOT/tests/.tmp/profile-resolution/deployed.fullchain"}]}
JSON
chmod 600 "$ACMESH_CONSOLE_CONFIG"

issue="$ROOT/tests/.tmp/profile-resolution/issue.json"
stdout="$ROOT/tests/.tmp/profile-resolution/stdout"
acmesh_profile_resolve_issue issue "$issue" > "$stdout"
[ ! -s "$stdout" ] || { echo "resolver leaked output"; exit 1; }
[ "$(jsonfilter -i "$issue" -e '@.accountEmail')" = overlay@example.org ]
[ "$(jsonfilter -i "$issue" -e '@.ca')" = letsencrypt_staging ]
[ "$(jsonfilter -i "$issue" -e '@.testMode')" = true ]
[ "$(jsonfilter -i "$issue" -e '@.credentials.CF_Token')" = top-secret ]
[ "$(jsonfilter -i "$issue" -e '@.domains[1]')" = www.example.org ]
[ "$(jsonfilter -i "$issue" -e '@.challengeAlias')" = alias.example.net ]
[ "$(jsonfilter -i "$issue" -e '@.dnsSleep')" = 42 ]
[ "$(LC_ALL=C ls -ld "$issue" | awk '{print $1}')" = -rw------- ]

deploy="$ROOT/tests/.tmp/profile-resolution/deploy.json"
acmesh_profile_resolve_deploy deploy "$deploy" > "$stdout"
[ ! -s "$stdout" ] || { echo "deploy resolver leaked output"; exit 1; }
[ "$(jsonfilter -i "$deploy" -e '@.id')" = deploy ]
[ "$(jsonfilter -i "$deploy" -e '@.target.host')" = 192.0.2.10 ]
[ "$(jsonfilter -i "$deploy" -e '@.destinations.keyFile')" = /etc/ssl/example.key ]
[ "$(jsonfilter -i "$deploy" -e '@.target.sudoMode')" = always ]
[ "$(jsonfilter -i "$deploy" -e '@.destinations.owner')" = root ]
[ "$(jsonfilter -i "$deploy" -e '@.destinations.group')" = ssl-cert ]
[ "$(jsonfilter -i "$deploy" -e '@.destinations.mode')" = 0640 ]

defaults="$ROOT/tests/.tmp/profile-resolution/defaults.json"
acmesh_profile_resolve_deploy local-deploy "$defaults" > "$stdout"
[ "$(jsonfilter -i "$defaults" -e '@.destinations.owner')" = root ]
[ "$(jsonfilter -i "$defaults" -e '@.destinations.group')" = root ]
[ "$(jsonfilter -i "$defaults" -e '@.destinations.mode')" = 600 ]

acmesh_profile_resolve_issue missing "$issue" >/dev/null 2>&1 && { echo "missing profile accepted"; exit 1; } || :
acmesh_profile_resolve_issue '../issue' "$issue" >/dev/null 2>&1 && { echo "unsafe id accepted"; exit 1; } || :

export ACMESH_TASK_STATE_DIR="$ROOT/tests/.tmp/profile-resolution/state"
export ACMESH_TASK_LOG_DIR="$ROOT/tests/.tmp/profile-resolution/log"
request="$ROOT/tests/.tmp/profile-resolution/issue-request.json"
printf '%s\n' '{"profileId":"issue"}' > "$request"
chmod 600 "$request"
run_out="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" issue --request-file "$request")"
case "$run_out" in *'"command"'*) ;; *) echo "issue did not accept profile id"; exit 1;; esac
case "$run_out" in *'"testMode":true'*) ;; *) echo "issue profile test mode was not preserved"; exit 1;; esac
case "$run_out" in *top-secret*) echo "issue response leaked credentials"; exit 1;; esac
case "$run_out" in *"--dns 'dns_cf'"*"-d 'example.org'"*"-d 'www.example.org'"*"--challenge-alias 'alias.example.net'"*"--dnssleep '42'"*) ;; *) echo "issue preview did not consume complete current profile"; echo "$run_out"; exit 1;; esac

deploy_request="$ROOT/tests/.tmp/profile-resolution/deploy-request.json"
printf '%s\n' '{"profileId":"local-deploy"}' > "$deploy_request"
# Real deploy admission is covered by test_operation_admission; this test only
# verifies that resolution itself never exposes or writes the profile material.
[ ! -e "$ROOT/tests/.tmp/profile-resolution/deployed.key" ]

echo "test_profile_resolution: ok"
