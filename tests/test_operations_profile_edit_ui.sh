#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PAGE="$ROOT/htdocs/luci-static/resources/view/acmesh/operations_v2.js"
MENU="$ROOT/root/usr/share/luci/menu.d/luci-app-acmesh-console.json"

require_text() {
	needle="$1"
	if ! grep -Fq -- "$needle" "$PAGE"; then
		echo "operations page missing: $needle"
		exit 1
	fi
}

reject_text() {
	needle="$1"
	if grep -Fq -- "$needle" "$PAGE"; then
		echo "operations page still has inline form marker: $needle"
		exit 1
	fi
}

require_count_at_least() {
	needle="$1"
	wanted="$2"
	actual="$(grep -F -- "$needle" "$PAGE" | wc -l | tr -d ' ')"
	if [ "$actual" -lt "$wanted" ]; then
		echo "operations page needs at least $wanted occurrences: $needle"
		exit 1
	fi
}

require_text "renderAccountsList"
require_text "renderAccountEdit"
require_text "renderIssueList"
require_text "renderIssueEdit"
require_text "renderDeployList"
require_text "renderDeployEdit"
require_text "renderDeployFields"
require_text "renderConfigMigration"
require_text "migration-archive-with-deployment-certs"
require_text "archiveBase64"
require_text "Edit account"
require_text "Edit issue profile"
require_text "Edit deploy profile"
require_text "Configuration migration"
require_text "activeTab === 'migration'"
require_text "data-acmesh-tab': 'migration'"
require_text "Export configuration"
require_text "Import configuration"
require_text "Include deployment certificates"
require_text "Restore migration archive"
require_text "Imported configuration summary"
require_text "The archive contains sensitive ACME account data and console credentials. Deployment certificates are included only when selected."
require_text "const showMigrationError = function(result, fallback)"
require_text "setSummary(message, false);"
require_text "ui.addNotification(null, E('p', {}, message), 'danger');"
require_text "showMigrationError(archive, _('Archive export failed'))"
require_text "showMigrationError(result, _('Archive preview failed'))"
require_text "showMigrationError(applied, _('Migration archive import failed'))"
require_count_at_least ".catch(function(error)" 3
require_text "Do not manually extract migration archives over /. Use this page to preview and restore them safely."
reject_text "const envelope = buildMigrationEnvelope(config);"
require_text "Save account"
require_text "Save issue profile"
require_text "Save deploy profile"
require_text "setEdit('account'"
require_text "setEdit('issue'"
require_text "setEdit('deploy'"
require_text "accountEmail: email"
require_text "accountEmail(account)"
require_text "type.addEventListener('change', renderDeployFields)"
require_text "certSource"
require_text "rsa8192"
require_text "if (certSource.value === 'managed-acme')"
require_text "if (type.value === 'ssh')"
require_text "runDeployProfile(profile"
require_text "validateDeployProfile"
reject_text "confirmSshKeyConversionRetry"
require_text "authorization.run(method, payload, authorizationOptions)"
require_text "ACMESH_DEPLOY_CONVERTIBLE_SSH_KEY=1"
require_text "allowKeyConvert: !!options.allowKeyConvert"
reject_text "Convert SSH key and retry deployment?"
require_text "Remote sudo requires passwordless sudo"
require_text "deployPayload"
require_text "keyPem"
require_text "fullchainPem"
require_text "const owner = input(existing.owner || 'root', 'root');"
require_text "const group = input(existing.group || 'root', 'root');"
require_text "const mode = input(existing.mode || '600', '600');"
require_text "const preserveMetadata = E('input', { 'type': 'checkbox' });"
require_text "owner: owner.value.trim(),"
require_text "group: group.value.trim(),"
require_text "mode: mode.value.trim(),"
require_text "preserveMetadata: preserveMetadata.checked,"
require_text "Keep existing owner/group/mode"
require_text "Resolved file metadata"
require_text "host"
require_text "port"
require_text "managed-acme"
require_text "paste-pem"
require_text "Private key PEM"
require_text "Fullchain PEM"
require_text "Effective configuration"
require_text "Inherit default"
require_text "Override"
require_text "Resolved account email"
require_text "Resolved test mode"
require_text "Resolved deploy profile"
require_text "resolveIssueProfile"
require_text "resolveDeployProfile"
require_text "defaultOverlaySelect"
require_text "overlayEnabled"
require_text "acmesh-tabbar"
require_text "acmesh-local-tabs"
require_text "acmesh-edit-grid"
require_text "acmesh-effective-strip"
require_text "summaryNodes"
require_text "setEffectiveSummaryRows"
require_text "deploySummary.update"
require_text "acmesh-effective-label"
require_text "acmesh-form-actions is-sticky"
require_text "background:rgba(127,127,127,.08)"
require_text "border-top:1px solid rgba(127,127,127,.24)"
require_text "background:rgba(47,128,237,.18)"
require_text "margin:14px 0 12px"
require_text ".acmesh-ops .acmesh-form-actions { max-width:980px"
require_text "background:transparent; border-top:1px solid rgba(127,127,127,.24); border-bottom:1px solid rgba(127,127,127,.24)"

if ! grep -Fq -- '"path": "acmesh/operations_v2"' "$MENU"; then
	echo "operations menu still points at old view module"
	exit 1
fi

reject_text "Add account'))"
reject_text "Add issue profile'))"
reject_text "Add deploy profile'))"
reject_text "profile.domain || 'example.com'"
reject_text "profile.keyFile || '/etc/ssl/example.key'"
reject_text "profile.fullchainFile || '/etc/ssl/example.fullchain.pem'"
reject_text "max-width:520px"
reject_text "acmesh-effective {"
reject_text "E('dl', {}, rows.map(function(row)"
reject_text "background:#fff"
reject_text "background:#f7f9fb"
reject_text "background:#f1f4f8"
reject_text "border-bottom:1px solid #e2e7ef"
reject_text "margin:14px 0 80px"
reject_text "badge(_('Effective configuration')"
reject_text ".acmesh-ops .acmesh-badge"
reject_text "E('h2', {}, _('Operations'))"
reject_text "--credential"
reject_text "--key-pem"
reject_text "--fullchain-pem"
reject_text "--json"

if grep -Fq "renderConfigMigration()," "$PAGE"; then
	echo "configuration migration should not be rendered as a standalone block above operations tabs"
	exit 1
fi

echo "test_operations_profile_edit_ui: ok"
