#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"
export ACMESH_TASK_STATE_DIR="$ROOT/tests/.tmp/renew-state"
export ACMESH_TASK_LOG_DIR="$ROOT/tests/.tmp/renew-log"
rm -rf "$ACMESH_TASK_STATE_DIR" "$ACMESH_TASK_LOG_DIR"

home="$ROOT/tests/.tmp/renew-home"
rm -rf "$home"
mkdir -p "$home"
cat > "$home/acme.sh" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$ACME_SH_ARG_LOG"
printf '%s\n' "${CF_Token:-}" >> "$ACME_SH_ENV_LOG"
EOF
chmod +x "$home/acme.sh"

preview="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" renew --home "$home" --domain ecc.example.com --key-type ecc --test-mode)"
case "$preview" in
	*'"ok":true'*'"testMode":true'*'"command"'*'--renew'*"-d 'ecc.example.com'"*'--ecc'*) ;;
	*) echo "renew test should return command preview"; echo "$preview"; exit 1 ;;
esac
case "$preview" in *'"taskId"'*) echo "renew test mode created task"; exit 1;; esac
[ ! -e "$ACMESH_TASK_STATE_DIR" ] && [ ! -e "$ACMESH_TASK_LOG_DIR" ]

arg_log="$ROOT/tests/.tmp/renew-args.log"
env_log="$ROOT/tests/.tmp/renew-env.log"
rm -f "$arg_log"
rm -f "$env_log"
. "$ACMESH_LIB_DIR/command.sh"
ACME_SH_ARG_LOG="$arg_log" ACME_SH_ENV_LOG="$env_log" acmesh_execute_renew "$home" rsa.example.com rsa
case "$(cat "$arg_log")" in
	*"--home $home --renew -d rsa.example.com"*) ;;
	*) echo "renew real did not call acme.sh --renew"; cat "$arg_log"; exit 1 ;;
esac
case "$(cat "$arg_log")" in
	*"--ecc"*) echo "rsa renew should not pass --ecc"; cat "$arg_log"; exit 1 ;;
esac
renew_output="$(ACME_SH_ARG_LOG="$arg_log" ACME_SH_ENV_LOG="$env_log" acmesh_execute_renew "$home" ecc.example.com ecc 'CF_Token=renew-token')"
case "$renew_output" in *renew-token*) echo "renew leaked resolved DNS credentials"; exit 1;; esac
[ "$(tail -n 1 "$env_log")" = renew-token ] || { echo "renew did not export resolved DNS credentials"; cat "$env_log"; exit 1; }

if command -v jsonfilter >/dev/null 2>&1 && [ -r /usr/share/libubox/jshn.sh ] && [ "$(id -u)" = 0 ]; then
	profile_home="$ROOT/tests/.tmp/renew-profile-home"
	rm -rf "$profile_home"
	mkdir -p "$profile_home/gate.example_ecc"
	chmod 700 "$profile_home" "$profile_home/gate.example_ecc"
	profile_conf="$profile_home/gate.example_ecc/gate.example.conf"
	cat > "$profile_conf" <<'EOF'
Le_Domain='gate.example'
Le_Keylength='ec-256'
Le_Webroot='dns_cf'
EOF
	chmod 600 "$profile_conf"
	export ACMESH_CONSOLE_CONFIG="$ROOT/tests/.tmp/renew-profile-config.json"
	cat > "$ACMESH_CONSOLE_CONFIG" <<'EOF'
{"schemaVersion":2,"global":{"defaultAccountEmail":"ops@example.com","coreTag":"v3.1.4","acmeHome":"/tmp/acme"},"accountProfiles":[{"id":"acc","name":"LE","ca":"letsencrypt","accountEmail":"ops@example.com"}],"issueProfiles":[{"id":"gate-profile","name":"Gate","domain":"gate.example","accountProfileId":"acc","deployProfileId":"","keyType":"ec256","validationMethod":"dns","testModeOverride":"force-real-mode","dnsApi":"dns_cf","credentialMode":"token","credentials":{"CF_Token":"profile-token"}}],"deployProfiles":[]}
EOF
	chmod 600 "$ACMESH_CONSOLE_CONFIG"
	. "$ACMESH_LIB_DIR/profile.sh"
	acmesh_profile_resolve_renew_credentials "$profile_conf" gate.example ec256 dns_cf 0
	[ "$ACMESH_RENEW_CREDENTIAL_SOURCE" = issue-profile:gate-profile ] || { echo "renew did not fall back to the matching issue profile"; exit 1; }
	[ "$ACMESH_RENEW_CREDENTIALS" = CF_Token=profile-token ] || { echo "renew selected the wrong issue-profile credential"; exit 1; }
	cat > "$profile_conf" <<'EOF'
Le_Domain='gate.example'
Le_Keylength='ec-256'
Le_Webroot='dns_cf'
CF_Token='local-token'
EOF
	chmod 600 "$profile_conf"
	acmesh_profile_resolve_renew_credentials "$profile_conf" gate.example ec256 dns_cf 0
	[ "$ACMESH_RENEW_CREDENTIAL_SOURCE" = certificate-config ] || { echo "certificate *.conf did not take precedence"; exit 1; }
	[ "$ACMESH_RENEW_CREDENTIALS" = CF_Token=local-token ] || { echo "certificate *.conf credential was not selected"; exit 1; }
	cat > "$profile_conf" <<'EOF'
Le_Domain='gate.example'
Le_Keylength='ec-256'
Le_Webroot='dns_cf'
CF_Key='stale-key'
EOF
	chmod 600 "$profile_conf"
	conflict_before="$ROOT/tests/.tmp/renew-conflict-before"
	cp "$profile_conf" "$conflict_before"
	if acmesh_profile_resolve_renew_credentials "$profile_conf" gate.example ec256 dns_cf 1; then
		echo "conflicting renewal credentials should fail closed"
		exit 1
	fi
	cmp -s "$conflict_before" "$profile_conf" || { echo "failed persistence changed conflicting certificate config"; exit 1; }
	acmesh_private_file_is_secure "$profile_conf" || { echo "failed persistence changed certificate config mode/security"; exit 1; }
	[ -z "$(find "$profile_home/gate.example_ecc" -name '.gate.example.conf.acmesh-renew.*' -print)" ] || { echo "failed persistence left a renewal stage file"; exit 1; }
	cat > "$profile_conf" <<'EOF'
Le_Domain='gate.example'
Le_Keylength='ec-256'
Le_Webroot='dns_cf'
EOF
	chmod 600 "$profile_conf"
	acmesh_profile_resolve_renew_credentials "$profile_conf" gate.example ec256 dns_cf 1
	grep -F "CF_Token='profile-token'" "$profile_conf" >/dev/null || { echo "profile credential was not persisted to certificate config"; exit 1; }
fi

missing="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" renew --home "$home" --real-mode 2>/dev/null || true)"
case "$missing" in
	*'"ok":false'*"domain is required"*) ;;
	*) echo "renew real should require domain"; echo "$missing"; exit 1 ;;
esac

echo "test_renew: ok"
