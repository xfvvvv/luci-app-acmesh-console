#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
MAKEFILE="$ROOT/Makefile"
CLEANUP="$ROOT/root/etc/uci-defaults/99-acmesh-console-cleanup"
API_MODULE="$ROOT/htdocs/luci-static/resources/acmesh/api_v2.js"
AUTHORIZATION_MODULE="$ROOT/htdocs/luci-static/resources/acmesh/authorization_v2.js"
KEEPD="$ROOT/root/lib/upgrade/keep.d/luci-app-acmesh-console"

require() { grep -F "$2" "$1" >/dev/null || { echo "missing package contract: $2"; exit 1; }; }

require "$MAKEFILE" 'define Package/luci-app-acmesh-console/conffiles'
for path in \
	/etc/config/acmesh-console \
	/etc/acmesh-console/config.json \
	/etc/acmesh-console/instance-id \
	/etc/acmesh-console/authorizations.json \
	/etc/acmesh-console/ssh/id_ed25519 \
	/etc/acmesh-console/ssh/id_ed25519.pub \
	/etc/acmesh-console/ssh/known_hosts
do
	require "$MAKEFILE" "$path"
done
require "$MAKEFILE" '+jsonfilter'
require "$MAKEFILE" '+dropbearconvert'
require "$MAKEFILE" 'define Build/Prepare/luci-app-acmesh-console'
require "$MAKEFILE" 'PKG_LICENSE:=Apache-2.0'
require "$MAKEFILE" 'PKG_LICENSE_FILES:=LICENSE'
require "$MAKEFILE" 'find $(PKG_BUILD_DIR) -type f -exec chmod 0644 {} +'
require "$MAKEFILE" '$(PKG_BUILD_DIR)/root/usr/libexec/acmesh-console/acmeshctl'
require "$CLEANUP" '/www/luci-static/resources/view/acmesh/operations.js'
require "$CLEANUP" '/www/luci-static/resources/acmesh/api.js'
require "$CLEANUP" '/www/luci-static/resources/acmesh/authorization.js'
require "$API_MODULE" "'require baseclass';"
require "$API_MODULE" 'return baseclass.extend({'
require "$AUTHORIZATION_MODULE" "'require baseclass';"
require "$AUTHORIZATION_MODULE" 'return baseclass.extend({'
[ -f "$ROOT/htdocs/luci-static/resources/view/acmesh/operations_v2.js" ]
[ ! -f "$ROOT/htdocs/luci-static/resources/view/acmesh/operations.js" ]
[ -f "$API_MODULE" ]
[ -f "$AUTHORIZATION_MODULE" ]
[ ! -f "$ROOT/htdocs/luci-static/resources/acmesh/api.js" ]
[ ! -f "$ROOT/htdocs/luci-static/resources/acmesh/authorization.js" ]
[ -f "$ROOT/README.md" ] || { echo 'README.md missing'; exit 1; }
[ -f "$ROOT/LICENSE" ] || { echo 'LICENSE missing'; exit 1; }
[ -f "$KEEPD" ] || { echo 'sysupgrade keep.d entry missing'; exit 1; }
grep -Fx '/etc/acme' "$KEEPD" >/dev/null || { echo 'sysupgrade keep.d entry must preserve /etc/acme'; exit 1; }
if grep -Fx '/etc/ssl' "$KEEPD" >/dev/null; then echo 'sysupgrade keep.d entry must not claim /etc/ssl'; exit 1; fi
grep -F 'Apache License' "$ROOT/LICENSE" >/dev/null || { echo 'Apache license text missing'; exit 1; }
grep -F 'Version 2.0' "$ROOT/LICENSE" >/dev/null || { echo 'Apache license version missing'; exit 1; }

echo 'test_package_contract: ok'
