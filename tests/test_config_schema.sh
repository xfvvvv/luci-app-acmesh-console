#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"
. "$ACMESH_LIB_DIR/io.sh"
. "$ACMESH_LIB_DIR/config.sh"

TMP="$ROOT/tests/.tmp/config-schema"
rm -rf "$TMP"
mkdir -p "$TMP"

write() { printf '%s\n' "$2" > "$TMP/$1.json"; }
reject() { acmesh_config_validate_file "$TMP/$1.json" >/dev/null 2>&1 && { echo "accepted invalid config: $1"; exit 1; } || :; }
accept() { acmesh_config_validate_file "$TMP/$1.json" >/dev/null || { echo "rejected valid config: $1"; exit 1; }; }

write valid '{"schemaVersion":2,"global":{"defaultAccountEmail":"ops@example.org","coreTag":"v3.1.4","acmeHome":"/etc/acme"},"accountProfiles":[{"id":"acc","name":"LE","ca":"letsencrypt","accountEmail":""}],"issueProfiles":[{"id":"issue","name":"Example","domain":"example.org","accountProfileId":"acc","deployProfileId":"deploy","keyType":"ec256","validationMethod":"dns","testModeOverride":"force-real-mode","dnsApi":"dns_cf","credentialMode":"token","credentials":{"CF_Token":"secret"}}],"deployProfiles":[{"id":"deploy","name":"nginx","type":"ssh","certSource":"managed-acme","domain":"example.org","keyType":"ec256","host":"192.0.2.10","user":"root","port":"22","sshKey":"/root/.ssh/id_ed25519","keyFile":"/etc/ssl/example.key","fullchainFile":"/etc/ssl/example.pem","reloadcmd":"service nginx reload","preserveMetadata":true}]}'
accept valid

write nested-types '{"schemaVersion":2,"global":[],"accountProfiles":{},"issueProfiles":[],"deployProfiles":[]}'
reject nested-types
write unknown '{"schemaVersion":2,"global":{"defaultAccountEmail":"ops@example.org","coreTag":"v3.1.4","acmeHome":"/etc/acme"},"accountProfiles":[],"issueProfiles":[],"deployProfiles":[],"surprise":true}'
reject unknown
write duplicate '{"schemaVersion":2,"global":{"defaultAccountEmail":"ops@example.org","coreTag":"v3.1.4","acmeHome":"/etc/acme"},"accountProfiles":[{"id":"same","name":"a","ca":"letsencrypt","accountEmail":""},{"id":"same","name":"b","ca":"letsencrypt","accountEmail":""}],"issueProfiles":[],"deployProfiles":[]}'
reject duplicate
sed 's/"id":"acc"/"id":"..\/bad"/' "$TMP/valid.json" > "$TMP/unsafe-id.json"; reject unsafe-id
sed 's/"accountProfileId":"acc"/"accountProfileId":"missing"/' "$TMP/valid.json" > "$TMP/dangling-account.json"; reject dangling-account
sed 's/"deployProfileId":"deploy"/"deployProfileId":"missing"/' "$TMP/valid.json" > "$TMP/dangling-deploy.json"; reject dangling-deploy
sed 's/"port":"22"/"port":"70000"/' "$TMP/valid.json" > "$TMP/bad-port.json"; reject bad-port
sed 's#"keyFile":"/etc/#"keyFile":"etc/#' "$TMP/valid.json" > "$TMP/relative-path.json"; reject relative-path
sed 's/"keyType":"ec256"/"keyType":"ec25519"/' "$TMP/valid.json" > "$TMP/bad-key.json"; reject bad-key
sed 's/"credentials":{"CF_Token":"secret"}/"credentials":{}/' "$TMP/valid.json" > "$TMP/missing-dns-credential.json"; reject missing-dns-credential
sed 's/"credentialMode":"token","credentials":{"CF_Token":"secret"}/"credentialMode":"global-key","credentials":{"CF_Key":"secret"}/' "$TMP/valid.json" > "$TMP/cf-global-without-email.json"; reject cf-global-without-email
sed 's/"credentialMode":"token","credentials":{"CF_Token":"secret"}/"credentialMode":"global-key","credentials":{"CF_Email":"ops@example.org","CF_Key":"secret"}/' "$TMP/valid.json" > "$TMP/cf-global.json"; accept cf-global
sed 's/"credentials":{"CF_Token":"secret"}/"credentials":{"CF_Email":"ops@example.org","CF_Key":"secret"}/' "$TMP/valid.json" > "$TMP/cf-token-with-global.json"; reject cf-token-with-global
sed 's/"credentialMode":"token","credentials":{"CF_Token":"secret"}/"credentialMode":"global-key","credentials":{"CF_Token":"secret"}/' "$TMP/valid.json" > "$TMP/cf-global-with-token.json"; reject cf-global-with-token
sed 's/"dnsApi":"dns_cf","credentialMode":"token","credentials":{"CF_Token":"secret"}/"dnsApi":"dns_azure","credentialMode":"service-principal","credentials":{"AZUREDNS_SUBSCRIPTIONID":"sub"}/' "$TMP/valid.json" > "$TMP/azure-incomplete.json"; reject azure-incomplete
sed 's/"dnsApi":"dns_cf","credentialMode":"token","credentials":{"CF_Token":"secret"}/"dnsApi":"dns_azure","credentialMode":"service-principal","credentials":{"AZUREDNS_SUBSCRIPTIONID":"sub","AZUREDNS_BEARERTOKEN":"token"}/' "$TMP/valid.json" > "$TMP/azure-mode-mismatch.json"; reject azure-mode-mismatch
sed 's/"dnsApi":"dns_cf","credentialMode":"token","credentials":{"CF_Token":"secret"}/"dnsApi":"dns_azure","credentialMode":"managed-identity","credentials":{"AZUREDNS_SUBSCRIPTIONID":"sub","AZUREDNS_TENANTID":"tenant","AZUREDNS_APPID":"app","AZUREDNS_CLIENTSECRET":"secret"}/' "$TMP/valid.json" > "$TMP/azure-managed-mismatch.json"; reject azure-managed-mismatch
sed 's/"dnsApi":"dns_cf","credentialMode":"token","credentials":{"CF_Token":"secret"}/"dnsApi":"dns_gcloud","credentialMode":"gcloud","credentials":{}/' "$TMP/valid.json" > "$TMP/gcloud-empty.json"; accept gcloud-empty
sed 's/"CF_Token":"secret"/"PATH":"evil"/' "$TMP/valid.json" > "$TMP/dangerous-env.json"; reject dangerous-env
sed 's/"CF_Token":"secret"/"bad-key":"secret"/' "$TMP/valid.json" > "$TMP/bad-env-name.json"; reject bad-env-name
printf '%s\n' '{"schemaVersion":2,"global":{"defaultAccountEmail":"ops@example.org","coreTag":"v3.1.4","acmeHome":"/etc/acme"},"accountProfiles":[{"id":"acc","name":"LE","ca":"letsencrypt","accountEmail":""}],"issueProfiles":[{"id":"issue","name":"Example","domain":"example.org","accountProfileId":"acc","deployProfileId":"","keyType":"ec256","validationMethod":"dns","testModeOverride":"force-real-mode","dnsApi":"dns_cf","credentialMode":"token","credentials":{"CF_Token":"line1\\nline2"}}],"deployProfiles":[]}' > "$TMP/multiline-credential.json"; reject multiline-credential

sed 's/"domain":"example.org"/"domain":"example.org","domains":["example.org","www.example.org"]/' "$TMP/valid.json" > "$TMP/multi-domain.json"; accept multi-domain
sed 's/"domain":"example.org"/"domain":"example.org","domains":[]/' "$TMP/valid.json" > "$TMP/empty-domains.json"; reject empty-domains
sed 's/"domain":"example.org"/"domain":"example.org","domains":["www.example.org","example.org"]/' "$TMP/valid.json" > "$TMP/domain-first-mismatch.json"; reject domain-first-mismatch
sed 's/"domain":"example.org"/"domain":"example.org","domains":["example.org","example.org"]/' "$TMP/valid.json" > "$TMP/duplicate-domain.json"; reject duplicate-domain
sed 's/"domain":"example.org"/"domain":"example.org","domains":["bad domain"]/' "$TMP/valid.json" > "$TMP/bad-domain.json"; reject bad-domain
sed 's/"credentialMode":"token"/"credentialMode":"mystery"/' "$TMP/valid.json" > "$TMP/bad-credential-mode.json"; reject bad-credential-mode
sed 's/"validationMethod":"dns"/"validationMethod":"webroot"/' "$TMP/valid.json" > "$TMP/webroot-with-dns.json"; reject webroot-with-dns
sed 's/"validationMethod":"dns","testModeOverride":"force-real-mode","dnsApi":"dns_cf","credentialMode":"token","credentials":{"CF_Token":"secret"}/"validationMethod":"webroot","testModeOverride":"force-real-mode","webroot":"relative"/' "$TMP/valid.json" > "$TMP/relative-webroot.json"; reject relative-webroot
sed 's/"validationMethod":"dns","testModeOverride":"force-real-mode","dnsApi":"dns_cf","credentialMode":"token","credentials":{"CF_Token":"secret"}/"validationMethod":"standalone","testModeOverride":"force-real-mode","listenPort":"65536"/' "$TMP/valid.json" > "$TMP/bad-listen-port.json"; reject bad-listen-port
sed 's/"reloadcmd":"service nginx reload"/"reloadcmd":"service nginx reload","sudoMode":"sometimes"/' "$TMP/valid.json" > "$TMP/bad-sudo-mode.json"; reject bad-sudo-mode
sed 's/"reloadcmd":"service nginx reload"/"reloadcmd":"service nginx reload","owner":"root;id"/' "$TMP/valid.json" > "$TMP/bad-owner.json"; reject bad-owner
sed 's/"reloadcmd":"service nginx reload"/"reloadcmd":"service nginx reload","mode":"999"/' "$TMP/valid.json" > "$TMP/bad-mode.json"; reject bad-mode
sed 's/"preserveMetadata":true/"preserveMetadata":"true"/' "$TMP/valid.json" > "$TMP/bad-preserve-metadata.json"; reject bad-preserve-metadata
printf '%s\n' "$(sed 's/\"reloadcmd\":\"service nginx reload\"/\"reloadcmd\":\"service nginx reload\",\"mode\":\"0640\\n;id\"/' "$TMP/valid.json")" > "$TMP/multiline-mode.json"; reject multiline-mode
printf '%s\n' "$(sed 's/\"domain\":\"example.org\"/\"domain\":\"example.org\\nattacker.example\"/' "$TMP/valid.json")" > "$TMP/multiline-domain.json"; reject multiline-domain
sed 's/"type":"ssh"/"type":"local"/' "$TMP/valid.json" > "$TMP/local-with-ssh-fields.json"; reject local-with-ssh-fields
sed 's/"domain":"example.org","keyType":"ec256"/"domain":"example.org","keyType":"ec256","sourceKeyFile":"\/tmp\/foreign.key"/' "$TMP/valid.json" > "$TMP/managed-with-local-source.json"; reject managed-with-local-source
sed 's/"certSource":"managed-acme","domain":"example.org","keyType":"ec256"/"certSource":"local-files","domain":"example.org","keyType":"ec256","sourceKeyFile":"\/tmp\/source.key","sourceFullchainFile":"\/tmp\/source.pem"/' "$TMP/valid.json" > "$TMP/local-source-with-domain.json"; reject local-source-with-domain
sed 's/"reloadcmd":"service nginx reload"/"reloadcmd":"service nginx reload","certFile":"\/etc\/ssl\/unused.crt"/' "$TMP/valid.json" > "$TMP/ssh-with-cert-file.json"; reject ssh-with-cert-file

for spec in \
	'dns_cloudns regular-auth CLOUDNS_SUB_AUTH_ID=sub,CLOUDNS_AUTH_PASSWORD=pass' \
	'dns_cloudns sub-auth CLOUDNS_AUTH_ID=main,CLOUDNS_AUTH_PASSWORD=pass' \
	'dns_dynv6 token KEY=ssh-key-material' \
	'dns_dynv6 ssh-key DYNV6_TOKEN=token' \
	'dns_la id-secret LA_Token=token' \
	'dns_la token LA_Id=id,LA_Sk=secret'; do
	set -- $spec; dns="$1" mode="$2" pairs="$3"; credentials="$(printf '%s' "$pairs" | sed 's/,/","/g; s/=/":"/g')"
	sed "s/\"dnsApi\":\"dns_cf\",\"credentialMode\":\"token\",\"credentials\":{\"CF_Token\":\"secret\"}/\"dnsApi\":\"$dns\",\"credentialMode\":\"$mode\",\"credentials\":{\"$credentials\"}/" "$TMP/valid.json" > "$TMP/mode-$dns-$mode.json"
	reject "mode-$dns-$mode"
done

for spec in \
	'dns_cf token CF_Token=token' \
	'dns_cf global-key CF_Email=ops@example.org,CF_Key=key' \
	'dns_azure service-principal AZUREDNS_SUBSCRIPTIONID=sub,AZUREDNS_TENANTID=tenant,AZUREDNS_APPID=app,AZUREDNS_CLIENTSECRET=secret' \
	'dns_azure managed-identity AZUREDNS_SUBSCRIPTIONID=sub,AZUREDNS_MANAGEDIDENTITY=identity' \
	'dns_azure bearer-token AZUREDNS_SUBSCRIPTIONID=sub,AZUREDNS_BEARERTOKEN=token' \
	'dns_cloudns regular-auth CLOUDNS_AUTH_ID=id,CLOUDNS_AUTH_PASSWORD=pass' \
	'dns_cloudns sub-auth CLOUDNS_SUB_AUTH_ID=id,CLOUDNS_AUTH_PASSWORD=pass' \
	'dns_dynv6 token DYNV6_TOKEN=token' \
	'dns_dynv6 ssh-key KEY=ssh-key-material' \
	'dns_la id-secret LA_Id=id,LA_Sk=secret' \
	'dns_la token LA_Token=token'; do
	set -- $spec; dns="$1" mode="$2" pairs="$3"; credentials="$(printf '%s' "$pairs" | sed 's/,/","/g; s/=/":"/g')"
	sed "s/\"dnsApi\":\"dns_cf\",\"credentialMode\":\"token\",\"credentials\":{\"CF_Token\":\"secret\"}/\"dnsApi\":\"$dns\",\"credentialMode\":\"$mode\",\"credentials\":{\"$credentials\"}/" "$TMP/valid.json" > "$TMP/valid-mode-$dns-$mode.json"
	accept "valid-mode-$dns-$mode"
done

for key in ec256 ec384 ec521 rsa2048 rsa3072 rsa4096 rsa8192; do
	sed "0,/\"keyType\":\"ec256\"/s//\"keyType\":\"$key\"/" "$TMP/valid.json" > "$TMP/key-$key.json"
	accept "key-$key"
done

echo "test_config_schema: ok"
