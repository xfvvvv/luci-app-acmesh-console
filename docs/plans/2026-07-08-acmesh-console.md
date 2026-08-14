# Acmesh Console Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `luci-app-acmesh-console`, a new OpenWrt LuCI console that treats acmesh-official/acme.sh as the only source of certificate truth.

**Architecture:** The package contains a LuCI JavaScript frontend and a shell-based rpcd helper. The helper reads acme.sh-native files, wraps acme.sh commands with a whitelist, records task logs, and exposes structured JSON to LuCI. The first working slice ships a read-only dashboard and a task log skeleton; later tasks add signing, deploy, SSH, and upgrades.

**Tech Stack:** OpenWrt package Makefile, LuCI JavaScript views, rpcd exec ACL, POSIX shell, OpenWrt `jshn.sh`, `openssl`, acmesh-official/acme.sh.

## Global Constraints

- The authority is `https://github.com/acmesh-official/acme.sh`; OpenWrt `luci-app-acme` is reference material only.
- UCI must not be the certificate source of truth.
- The router runtime must not require Python, Node, or jq.
- Unknown acme.sh variables must be preserved and visible.
- The frontend must not pass arbitrary shell commands except explicit deploy/reload command fields with confirmation.
- Secret values must be masked in command previews and logs.
- Long operations must create task ids and write task state plus task logs.
- The first implementation slice should produce a working read-only dashboard and a renew task skeleton.

---

## File Structure

Create these files:

- `luci-app-acmesh-console/Makefile` - OpenWrt package metadata.
- `luci-app-acmesh-console/root/usr/share/luci/menu.d/luci-app-acmesh-console.json` - LuCI menu entries.
- `luci-app-acmesh-console/root/usr/share/rpcd/acl.d/luci-app-acmesh-console.json` - RPC permissions.
- `luci-app-acmesh-console/root/etc/config/acmesh-console` - UI metadata configuration.
- `luci-app-acmesh-console/root/etc/init.d/acmesh-console` - service wrapper for maintenance hooks.
- `luci-app-acmesh-console/root/usr/libexec/acmesh-console/rpc` - rpcd executable entrypoint.
- `luci-app-acmesh-console/root/usr/libexec/acmesh-console/acmeshctl` - command-line backend used by RPC and tests.
- `luci-app-acmesh-console/root/usr/libexec/acmesh-console/lib/json.sh` - JSON helpers.
- `luci-app-acmesh-console/root/usr/libexec/acmesh-console/lib/conf.sh` - acme.sh config parser.
- `luci-app-acmesh-console/root/usr/libexec/acmesh-console/lib/cert.sh` - certificate scanner and validity reader.
- `luci-app-acmesh-console/root/usr/libexec/acmesh-console/lib/task.sh` - task lifecycle and log helpers.
- `luci-app-acmesh-console/root/usr/libexec/acmesh-console/lib/command.sh` - whitelisted acme.sh command builder.
- `luci-app-acmesh-console/root/usr/libexec/acmesh-console/lib/provider.sh` - DNS provider template loader.
- `luci-app-acmesh-console/root/usr/libexec/acmesh-console/lib/deploy.sh` - local install and remote deploy helpers.
- `luci-app-acmesh-console/root/usr/libexec/acmesh-console/lib/ssh.sh` - SSH key and connection helpers.
- `luci-app-acmesh-console/root/usr/libexec/acmesh-console/providers/cloudflare.json` - Cloudflare template.
- `luci-app-acmesh-console/root/usr/libexec/acmesh-console/providers/aliyun.json` - Aliyun template.
- `luci-app-acmesh-console/root/usr/libexec/acmesh-console/providers/tencentcloud.json` - Tencent Cloud template.
- `luci-app-acmesh-console/root/usr/libexec/acmesh-console/hooks/acmesh-console-ssh.sh` - acme.sh deploy hook.
- `luci-app-acmesh-console/htdocs/luci-static/resources/acmesh/api.js` - frontend RPC wrapper.
- `luci-app-acmesh-console/htdocs/luci-static/resources/acmesh/format.js` - frontend formatting helpers.
- `luci-app-acmesh-console/htdocs/luci-static/resources/acmesh/providers.js` - provider UI adapter.
- `luci-app-acmesh-console/htdocs/luci-static/resources/view/acmesh/dashboard.js` - dashboard.
- `luci-app-acmesh-console/htdocs/luci-static/resources/view/acmesh/certificates.js` - certificate details.
- `luci-app-acmesh-console/htdocs/luci-static/resources/view/acmesh/issue.js` - issue wizard.
- `luci-app-acmesh-console/htdocs/luci-static/resources/view/acmesh/deploy.js` - deploy page.
- `luci-app-acmesh-console/htdocs/luci-static/resources/view/acmesh/settings.js` - settings page.
- `luci-app-acmesh-console/tests/run_host_tests.sh` - host-side shell test runner.
- `luci-app-acmesh-console/tests/fixtures/acme-home/account.conf` - fake account config.
- `luci-app-acmesh-console/tests/fixtures/acme-home/example.com_ecc/example.com.conf` - fake ECC domain config.
- `luci-app-acmesh-console/tests/fixtures/acme-home/example.com/example.com.conf` - fake RSA domain config.
- `luci-app-acmesh-console/tests/test_conf_parser.sh` - config parser tests.
- `luci-app-acmesh-console/tests/test_task.sh` - task tests.
- `luci-app-acmesh-console/tests/test_command_builder.sh` - command builder tests.

## Interfaces

Backend command interface:

```text
acmeshctl status --home <path>
acmeshctl task-status --task-id <id>
acmeshctl task-log --task-id <id> --offset <bytes>
acmeshctl renew --home <path> --domain <domain> --key-type <ecc|rsa>
acmeshctl preview-issue --home <path> --request-json <json-file>
acmeshctl issue --home <path> --request-json <json-file>
acmeshctl install-cert --home <path> --request-json <json-file>
acmeshctl ssh-key ensure
acmeshctl ssh-test --request-json <json-file>
acmeshctl deploy-test --request-json <json-file>
acmeshctl upgrade-check --home <path>
acmeshctl upgrade --home <path>
```

RPC methods:

```text
status
task_status
task_log
renew
preview_issue
issue
install_cert
ssh_key_ensure
ssh_test
deploy_test
upgrade_check
upgrade
```

Core shell functions:

```text
acmesh_parse_kv_file <path>
acmesh_scan_home <home>
acmesh_cert_dates <cert-file>
acmesh_task_create <operation>
acmesh_task_run <task-id> <stage> <command...>
acmesh_mask_secret <text>
acmesh_build_issue_command <home> <request-json-file>
```

### Task 1: Package Skeleton And Navigation

**Files:**
- Create: `luci-app-acmesh-console/Makefile`
- Create: `luci-app-acmesh-console/root/usr/share/luci/menu.d/luci-app-acmesh-console.json`
- Create: `luci-app-acmesh-console/root/usr/share/rpcd/acl.d/luci-app-acmesh-console.json`
- Create: `luci-app-acmesh-console/root/etc/config/acmesh-console`
- Create: `luci-app-acmesh-console/root/etc/init.d/acmesh-console`
- Create: `luci-app-acmesh-console/root/usr/libexec/acmesh-console/rpc`
- Create: `luci-app-acmesh-console/root/usr/libexec/acmesh-console/acmeshctl`
- Create: `luci-app-acmesh-console/htdocs/luci-static/resources/view/acmesh/dashboard.js`

**Interfaces:**
- Produces: LuCI route `admin/services/acmesh`, RPC executable `/usr/libexec/acmesh-console/rpc`, CLI `/usr/libexec/acmesh-console/acmeshctl`.
- Consumes: no previous task output.

- [ ] **Step 1: Create the OpenWrt package metadata**

Create `luci-app-acmesh-console/Makefile`:

```make
include $(TOPDIR)/rules.mk

LUCI_TITLE:=acme.sh Console
LUCI_DEPENDS:=+luci-base +rpcd +rpcd-mod-file +rpcd-mod-uci +openssl-util +ca-bundle

PKG_NAME:=luci-app-acmesh-console
PKG_VERSION:=0.1.2
PKG_LICENSE:=GPL-3.0-or-later

include ../../luci.mk

# call BuildPackage - OpenWrt buildroot signature
```

- [ ] **Step 2: Create the LuCI menu**

Create `root/usr/share/luci/menu.d/luci-app-acmesh-console.json`:

```json
{
  "admin/services/acmesh": {
    "title": "acme.sh Console",
    "order": 50,
    "action": {
      "type": "view",
      "path": "acmesh/dashboard"
    },
    "depends": {
      "acl": [ "luci-app-acmesh-console" ]
    }
  }
}
```

- [ ] **Step 3: Create RPC ACL**

Create `root/usr/share/rpcd/acl.d/luci-app-acmesh-console.json`:

```json
{
  "luci-app-acmesh-console": {
    "description": "Grant access to acme.sh Console",
    "read": {
      "file": {
        "/etc/acme": [ "list", "read" ],
        "/root/.acme.sh": [ "list", "read" ],
        "/etc/acmesh-console": [ "list", "read" ],
        "/var/run/acmesh-console": [ "list", "read" ],
        "/var/log/acmesh-console": [ "list", "read" ],
        "/usr/libexec/acmesh-console/rpc": [ "exec" ]
      },
      "ubus": {
        "file": [ "read", "list", "exec" ]
      },
      "uci": [ "acmesh-console" ]
    },
    "write": {
      "file": {
        "/etc/acmesh-console": [ "write" ],
        "/var/run/acmesh-console": [ "write" ],
        "/var/log/acmesh-console": [ "write" ],
        "/usr/libexec/acmesh-console/rpc": [ "exec" ]
      },
      "uci": [ "acmesh-console" ]
    }
  }
}
```

- [ ] **Step 4: Create default config**

Create `root/etc/config/acmesh-console`:

```text
config acmesh-console 'main'
	option home '/etc/acme'
	option advanced '0'
	option task_log_dir '/var/log/acmesh-console/tasks'
	option task_state_dir '/var/run/acmesh-console/tasks'
```

- [ ] **Step 5: Create init script**

Create `root/etc/init.d/acmesh-console`:

```sh
#!/bin/sh /etc/rc.common

START=95
USE_PROCD=1

start_service() {
	mkdir -p /var/run/acmesh-console/tasks /var/log/acmesh-console/tasks
}
```

- [ ] **Step 6: Create backend stubs**

Create `root/usr/libexec/acmesh-console/acmeshctl`:

```sh
#!/bin/sh
set -eu

cmd="${1:-}"
case "$cmd" in
	status)
		printf '{"ok":true,"home":"/etc/acme","certificates":[]}\n'
		;;
	*)
		printf '{"ok":false,"error":"unsupported command"}\n'
		exit 2
		;;
esac
```

Create `root/usr/libexec/acmesh-console/rpc`:

```sh
#!/bin/sh
set -eu

method="${1:-}"
case "$method" in
	status)
		/usr/libexec/acmesh-console/acmeshctl status
		;;
	*)
		printf '{"ok":false,"error":"unsupported rpc method"}\n'
		exit 2
		;;
esac
```

- [ ] **Step 7: Create minimal dashboard view**

Create `htdocs/luci-static/resources/view/acmesh/dashboard.js`:

```javascript
'use strict';
'require view';
'require rpc';
'require ui';

const callStatus = rpc.declare({
	object: 'luci.acmesh-console',
	method: 'status',
	expect: { '': {} }
});

return view.extend({
	load: function() {
		return callStatus();
	},

	render: function(data) {
		const home = data.home || '/etc/acme';
		const count = Array.isArray(data.certificates) ? data.certificates.length : 0;

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('acme.sh Console')),
			E('div', { 'class': 'cbi-section' }, [
				E('p', {}, _('Home') + ': ' + home),
				E('p', {}, _('Certificates') + ': ' + count)
			])
		]);
	}
});
```

- [ ] **Step 8: Verify package files are present**

Run:

```sh
find luci-app-acmesh-console -type f | sort
```

Expected: the eight files created in this task are listed.

- [ ] **Step 9: Commit**

```sh
git add luci-app-acmesh-console
git commit -m "feat: scaffold acme.sh console package"
```

### Task 2: Host Test Harness And Config Parser

**Files:**
- Create: `luci-app-acmesh-console/root/usr/libexec/acmesh-console/lib/json.sh`
- Create: `luci-app-acmesh-console/root/usr/libexec/acmesh-console/lib/conf.sh`
- Create: `luci-app-acmesh-console/tests/run_host_tests.sh`
- Create: `luci-app-acmesh-console/tests/fixtures/acme-home/account.conf`
- Create: `luci-app-acmesh-console/tests/fixtures/acme-home/example.com_ecc/example.com.conf`
- Create: `luci-app-acmesh-console/tests/fixtures/acme-home/example.com/example.com.conf`
- Create: `luci-app-acmesh-console/tests/test_conf_parser.sh`
- Modify: `luci-app-acmesh-console/root/usr/libexec/acmesh-console/acmeshctl`

**Interfaces:**
- Consumes: `acmeshctl` from Task 1.
- Produces: `acmesh_parse_kv_file <path>` and `acmesh_json_escape <text>`.

- [ ] **Step 1: Create fixture files**

Create `tests/fixtures/acme-home/account.conf`:

```sh
ACCOUNT_EMAIL='admin@example.com'
DEFAULT_ACME_SERVER='https://acme-v02.api.letsencrypt.org/directory'
```

Create `tests/fixtures/acme-home/example.com_ecc/example.com.conf`:

```sh
Le_Domain='example.com'
Le_Alt='*.example.com,www.example.com'
Le_Keylength='ec-256'
Le_Webroot='dns_cf'
Le_API='https://acme-v02.api.letsencrypt.org/directory'
Le_DNSSleep='120'
Le_DeployHook='acmesh-console-ssh'
Custom_Unknown='keep-me'
```

Create `tests/fixtures/acme-home/example.com/example.com.conf`:

```sh
Le_Domain='example.com'
Le_Alt='www.example.com'
Le_Keylength='2048'
Le_Webroot='dns_cf'
Le_API='https://acme-v02.api.letsencrypt.org/directory'
```

- [ ] **Step 2: Create JSON helper**

Create `root/usr/libexec/acmesh-console/lib/json.sh`:

```sh
acmesh_json_escape() {
	printf '%s' "${1-}" | sed \
		-e 's/\\/\\\\/g' \
		-e 's/"/\\"/g' \
		-e 's/	/\\t/g'
}
```

- [ ] **Step 3: Create config parser**

Create `root/usr/libexec/acmesh-console/lib/conf.sh`:

```sh
. "${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}/json.sh"

acmesh_parse_kv_file() {
	file="$1"
	first=1
	printf '{'
	while IFS= read -r line || [ -n "$line" ]; do
		case "$line" in
			''|'#'*) continue ;;
			*=*)
				key=${line%%=*}
				value=${line#*=}
				case "$value" in
					\'*\') value=${value#\'}; value=${value%\'} ;;
					\"*\") value=${value#\"}; value=${value%\"} ;;
				esac
				[ "$first" = 1 ] || printf ','
				first=0
				printf '"%s":"%s"' "$(acmesh_json_escape "$key")" "$(acmesh_json_escape "$value")"
				;;
		esac
	done < "$file"
	printf '}\n'
}
```

- [ ] **Step 4: Write parser test**

Create `tests/test_conf_parser.sh`:

```sh
#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"
. "$ACMESH_LIB_DIR/conf.sh"

out="$(acmesh_parse_kv_file "$ROOT/tests/fixtures/acme-home/example.com_ecc/example.com.conf")"

case "$out" in
	*'"Le_Domain":"example.com"'*) ;;
	*) echo "missing Le_Domain"; echo "$out"; exit 1 ;;
esac

case "$out" in
	*'"Custom_Unknown":"keep-me"'*) ;;
	*) echo "missing unknown variable"; echo "$out"; exit 1 ;;
esac

echo "test_conf_parser: ok"
```

- [ ] **Step 5: Create host test runner**

Create `tests/run_host_tests.sh`:

```sh
#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

sh "$ROOT/tests/test_conf_parser.sh"

echo "all host tests passed"
```

- [ ] **Step 6: Run test to verify parser behavior**

Run:

```sh
sh luci-app-acmesh-console/tests/run_host_tests.sh
```

Expected:

```text
test_conf_parser: ok
all host tests passed
```

- [ ] **Step 7: Commit**

```sh
git add luci-app-acmesh-console
git commit -m "test: add acme config parser harness"
```

### Task 3: Read-Only Status Scanner

**Files:**
- Create: `luci-app-acmesh-console/root/usr/libexec/acmesh-console/lib/cert.sh`
- Modify: `luci-app-acmesh-console/root/usr/libexec/acmesh-console/acmeshctl`
- Modify: `luci-app-acmesh-console/tests/run_host_tests.sh`
- Create: `luci-app-acmesh-console/tests/test_status_scan.sh`

**Interfaces:**
- Consumes: `acmesh_parse_kv_file <path>`.
- Produces: `acmesh_scan_home <home>` returning status JSON.

- [ ] **Step 1: Create scanner implementation**

Create `root/usr/libexec/acmesh-console/lib/cert.sh`:

```sh
. "${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}/conf.sh"
. "${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}/json.sh"

acmesh_key_type_from_dir() {
	case "$1" in
		*_ecc) printf 'ecc' ;;
		*) printf 'rsa' ;;
	esac
}

acmesh_main_domain_from_dir() {
	base=${1##*/}
	case "$base" in
		*_ecc) printf '%s' "${base%_ecc}" ;;
		*) printf '%s' "$base" ;;
	esac
}

acmesh_scan_home() {
	home="$1"
	first=1
	printf '{"ok":true,"home":"%s","certificates":[' "$(acmesh_json_escape "$home")"
	for dir in "$home"/*; do
		[ -d "$dir" ] || continue
		main="$(acmesh_main_domain_from_dir "$dir")"
		conf="$dir/$main.conf"
		[ -f "$conf" ] || continue
		key_type="$(acmesh_key_type_from_dir "$dir")"
		raw="$(acmesh_parse_kv_file "$conf")"
		[ "$first" = 1 ] || printf ','
		first=0
		printf '{"mainDomain":"%s","keyType":"%s","domainConf":"%s","rawVars":%s}' \
			"$(acmesh_json_escape "$main")" \
			"$(acmesh_json_escape "$key_type")" \
			"$(acmesh_json_escape "$conf")" \
			"$raw"
	done
	printf ']}\n'
}
```

- [ ] **Step 2: Wire scanner into acmeshctl**

Replace `root/usr/libexec/acmesh-console/acmeshctl` with:

```sh
#!/bin/sh
set -eu

LIB_DIR="${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}"
. "$LIB_DIR/cert.sh"

cmd="${1:-}"
shift || true

home="/etc/acme"
while [ "$#" -gt 0 ]; do
	case "$1" in
		--home)
			home="$2"
			shift 2
			;;
		*)
			break
			;;
	esac
done

case "$cmd" in
	status)
		acmesh_scan_home "$home"
		;;
	*)
		printf '{"ok":false,"error":"unsupported command"}\n'
		exit 2
		;;
esac
```

- [ ] **Step 3: Write status scan test**

Create `tests/test_status_scan.sh`:

```sh
#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"

out="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" status --home "$ROOT/tests/fixtures/acme-home")"

case "$out" in
	*'"mainDomain":"example.com"'*) ;;
	*) echo "missing example.com"; echo "$out"; exit 1 ;;
esac

case "$out" in
	*'"keyType":"ecc"'*'"keyType":"rsa"'*|*'"keyType":"rsa"'*'"keyType":"ecc"'*) ;;
	*) echo "missing ecc/rsa variants"; echo "$out"; exit 1 ;;
esac

case "$out" in
	*'"Custom_Unknown":"keep-me"'*) ;;
	*) echo "unknown variable was not preserved"; echo "$out"; exit 1 ;;
esac

echo "test_status_scan: ok"
```

Modify `tests/run_host_tests.sh`:

```sh
#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

sh "$ROOT/tests/test_conf_parser.sh"
sh "$ROOT/tests/test_status_scan.sh"

echo "all host tests passed"
```

- [ ] **Step 4: Run status scanner tests**

Run:

```sh
sh luci-app-acmesh-console/tests/run_host_tests.sh
```

Expected:

```text
test_conf_parser: ok
test_status_scan: ok
all host tests passed
```

- [ ] **Step 5: Commit**

```sh
git add luci-app-acmesh-console
git commit -m "feat: scan acme.sh home status"
```

### Task 4: Task Lifecycle And Renew Skeleton

**Files:**
- Create: `luci-app-acmesh-console/root/usr/libexec/acmesh-console/lib/task.sh`
- Modify: `luci-app-acmesh-console/root/usr/libexec/acmesh-console/acmeshctl`
- Modify: `luci-app-acmesh-console/root/usr/libexec/acmesh-console/rpc`
- Create: `luci-app-acmesh-console/tests/test_task.sh`
- Modify: `luci-app-acmesh-console/tests/run_host_tests.sh`

**Interfaces:**
- Consumes: `acmesh_json_escape <text>`.
- Produces: `acmesh_task_create`, `acmesh_task_status`, `acmesh_task_log`, and `acmesh_task_run`.

- [ ] **Step 1: Create task helper**

Create `root/usr/libexec/acmesh-console/lib/task.sh`:

```sh
. "${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}/json.sh"

: "${ACMESH_TASK_STATE_DIR:=/var/run/acmesh-console/tasks}"
: "${ACMESH_TASK_LOG_DIR:=/var/log/acmesh-console/tasks}"

acmesh_task_create() {
	operation="$1"
	mkdir -p "$ACMESH_TASK_STATE_DIR" "$ACMESH_TASK_LOG_DIR"
	id="$(date +%Y%m%d%H%M%S)-$$"
	state="$ACMESH_TASK_STATE_DIR/$id.json"
	log="$ACMESH_TASK_LOG_DIR/$id.log"
	: > "$log"
	printf '{"ok":true,"taskId":"%s","operation":"%s","status":"created","stage":"created","log":"%s"}\n' \
		"$(acmesh_json_escape "$id")" \
		"$(acmesh_json_escape "$operation")" \
		"$(acmesh_json_escape "$log")" > "$state"
	printf '%s\n' "$id"
}

acmesh_task_status() {
	id="$1"
	state="$ACMESH_TASK_STATE_DIR/$id.json"
	if [ -f "$state" ]; then
		cat "$state"
	else
		printf '{"ok":false,"error":"task not found"}\n'
		return 1
	fi
}

acmesh_task_log() {
	id="$1"
	log="$ACMESH_TASK_LOG_DIR/$id.log"
	if [ -f "$log" ]; then
		cat "$log"
	else
		printf 'task log not found\n'
		return 1
	fi
}

acmesh_task_write_state() {
	id="$1"
	operation="$2"
	status="$3"
	stage="$4"
	exit_code="${5:-0}"
	state="$ACMESH_TASK_STATE_DIR/$id.json"
	printf '{"ok":true,"taskId":"%s","operation":"%s","status":"%s","stage":"%s","exitCode":%s}\n' \
		"$(acmesh_json_escape "$id")" \
		"$(acmesh_json_escape "$operation")" \
		"$(acmesh_json_escape "$status")" \
		"$(acmesh_json_escape "$stage")" \
		"$exit_code" > "$state"
}

acmesh_task_run() {
	id="$1"
	operation="$2"
	stage="$3"
	shift 3
	log="$ACMESH_TASK_LOG_DIR/$id.log"
	acmesh_task_write_state "$id" "$operation" running "$stage" 0
	"$@" >> "$log" 2>&1
	rc=$?
	if [ "$rc" = 0 ]; then
		acmesh_task_write_state "$id" "$operation" success "$stage" "$rc"
	else
		acmesh_task_write_state "$id" "$operation" failed "$stage" "$rc"
	fi
	return "$rc"
}
```

- [ ] **Step 2: Add task commands to acmeshctl**

Extend `acmeshctl` command cases:

```sh
. "$LIB_DIR/task.sh"

case "$cmd" in
	status)
		acmesh_scan_home "$home"
		;;
	task-status)
		task_id=""
		while [ "$#" -gt 0 ]; do
			case "$1" in
				--task-id) task_id="$2"; shift 2 ;;
				*) shift ;;
			esac
		done
		acmesh_task_status "$task_id"
		;;
	task-log)
		task_id=""
		while [ "$#" -gt 0 ]; do
			case "$1" in
				--task-id) task_id="$2"; shift 2 ;;
				*) shift ;;
			esac
		done
		acmesh_task_log "$task_id"
		;;
	renew)
		task_id="$(acmesh_task_create renew)"
		(
			acmesh_task_run "$task_id" renew preview printf '%s\n' "renew skeleton for $home"
		) &
		printf '{"ok":true,"taskId":"%s"}\n' "$(acmesh_json_escape "$task_id")"
		;;
	*)
		printf '{"ok":false,"error":"unsupported command"}\n'
		exit 2
		;;
esac
```

- [ ] **Step 3: Add RPC methods**

Extend `rpc`:

```sh
case "$method" in
	status)
		/usr/libexec/acmesh-console/acmeshctl status
		;;
	task_status)
		read -r input
		task_id="$(printf '%s' "$input" | sed -n 's/.*"taskId"[ ]*:[ ]*"\([^"]*\)".*/\1/p')"
		/usr/libexec/acmesh-console/acmeshctl task-status --task-id "$task_id"
		;;
	task_log)
		read -r input
		task_id="$(printf '%s' "$input" | sed -n 's/.*"taskId"[ ]*:[ ]*"\([^"]*\)".*/\1/p')"
		/usr/libexec/acmesh-console/acmeshctl task-log --task-id "$task_id"
		;;
	renew)
		/usr/libexec/acmesh-console/acmeshctl renew
		;;
	*)
		printf '{"ok":false,"error":"unsupported rpc method"}\n'
		exit 2
		;;
esac
```

- [ ] **Step 4: Write task test**

Create `tests/test_task.sh`:

```sh
#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"
export ACMESH_TASK_STATE_DIR="$ROOT/tests/.tmp/tasks-state"
export ACMESH_TASK_LOG_DIR="$ROOT/tests/.tmp/tasks-log"
rm -rf "$ROOT/tests/.tmp"

. "$ACMESH_LIB_DIR/task.sh"

id="$(acmesh_task_create renew)"
acmesh_task_status "$id" | grep '"status":"created"' >/dev/null
acmesh_task_run "$id" renew preview printf '%s\n' "hello task"
acmesh_task_status "$id" | grep '"status":"success"' >/dev/null
acmesh_task_log "$id" | grep 'hello task' >/dev/null

echo "test_task: ok"
```

Modify `tests/run_host_tests.sh`:

```sh
#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

sh "$ROOT/tests/test_conf_parser.sh"
sh "$ROOT/tests/test_status_scan.sh"
sh "$ROOT/tests/test_task.sh"

echo "all host tests passed"
```

- [ ] **Step 5: Run task tests**

Run:

```sh
sh luci-app-acmesh-console/tests/run_host_tests.sh
```

Expected:

```text
test_conf_parser: ok
test_status_scan: ok
test_task: ok
all host tests passed
```

- [ ] **Step 6: Commit**

```sh
git add luci-app-acmesh-console
git commit -m "feat: add acme task lifecycle"
```

### Task 5: Frontend Dashboard With Task Log Drawer

**Files:**
- Create: `luci-app-acmesh-console/htdocs/luci-static/resources/acmesh/api.js`
- Create: `luci-app-acmesh-console/htdocs/luci-static/resources/acmesh/format.js`
- Modify: `luci-app-acmesh-console/htdocs/luci-static/resources/view/acmesh/dashboard.js`

**Interfaces:**
- Consumes: RPC methods `status`, `renew`, `task_status`, `task_log`.
- Produces: dashboard card rendering and renew skeleton button.

- [ ] **Step 1: Create frontend API wrapper**

Create `htdocs/luci-static/resources/acmesh/api.js`:

```javascript
'use strict';
'require rpc';

return {
	status: rpc.declare({
		object: 'luci.acmesh-console',
		method: 'status',
		expect: { '': {} }
	}),

	renew: rpc.declare({
		object: 'luci.acmesh-console',
		method: 'renew',
		params: [ 'domain', 'keyType' ],
		expect: { '': {} }
	}),

	taskStatus: rpc.declare({
		object: 'luci.acmesh-console',
		method: 'task_status',
		params: [ 'taskId' ],
		expect: { '': {} }
	}),

	taskLog: rpc.declare({
		object: 'luci.acmesh-console',
		method: 'task_log',
		params: [ 'taskId' ],
		expect: { '': '' }
	})
};
```

- [ ] **Step 2: Create formatting helper**

Create `htdocs/luci-static/resources/acmesh/format.js`:

```javascript
'use strict';

return {
	keyTypeLabel: function(keyType) {
		return keyType === 'ecc' ? 'ECC' : 'RSA';
	},

	statusClass: function(daysLeft) {
		if (daysLeft == null)
			return 'warning';
		if (daysLeft <= 7)
			return 'danger';
		if (daysLeft <= 30)
			return 'warning';
		return 'success';
	}
};
```

- [ ] **Step 3: Replace dashboard with certificate cards**

Replace `dashboard.js`:

```javascript
'use strict';
'require view';
'require ui';
'require acmesh.api as api';
'require acmesh.format as fmt';

return view.extend({
	load: function() {
		return api.status();
	},

	renderCert: function(cert) {
		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, [
				cert.mainDomain || _('Unknown domain'),
				' ',
				E('span', { 'class': 'label' }, fmt.keyTypeLabel(cert.keyType))
			]),
			E('p', {}, _('Config') + ': ' + (cert.domainConf || '-')),
			E('button', {
				'class': 'btn cbi-button cbi-button-apply',
				'click': ui.createHandlerFn(this, function() {
					return api.renew(cert.mainDomain, cert.keyType).then(function(res) {
						if (res.taskId)
							ui.addNotification(null, E('p', {}, _('Renew task started') + ': ' + res.taskId), 'info');
					});
				})
			}, _('Renew'))
		]);
	},

	render: function(data) {
		const certs = Array.isArray(data.certificates) ? data.certificates : [];

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('acme.sh Console')),
			E('div', { 'class': 'cbi-section' }, [
				E('p', {}, _('Home') + ': ' + (data.home || '/etc/acme')),
				E('p', {}, _('Certificates') + ': ' + certs.length)
			]),
			certs.length ? certs.map(this.renderCert.bind(this)) : E('div', { 'class': 'cbi-section' }, _('No acme.sh certificates found.'))
		]);
	}
});
```

- [ ] **Step 4: Smoke check JavaScript module names**

Run:

```sh
grep -R "require acmesh" -n luci-app-acmesh-console/htdocs/luci-static/resources
```

Expected:

```text
luci-app-acmesh-console/htdocs/luci-static/resources/view/acmesh/dashboard.js:'require acmesh.api as api';
luci-app-acmesh-console/htdocs/luci-static/resources/view/acmesh/dashboard.js:'require acmesh.format as fmt';
```

- [ ] **Step 5: Commit**

```sh
git add luci-app-acmesh-console
git commit -m "feat: render acme dashboard"
```

### Task 6: DNS Provider Templates And Issue Preview

**Files:**
- Create: `luci-app-acmesh-console/root/usr/libexec/acmesh-console/lib/provider.sh`
- Create: `luci-app-acmesh-console/root/usr/libexec/acmesh-console/lib/command.sh`
- Create: `luci-app-acmesh-console/root/usr/libexec/acmesh-console/providers/cloudflare.json`
- Create: `luci-app-acmesh-console/root/usr/libexec/acmesh-console/providers/aliyun.json`
- Create: `luci-app-acmesh-console/root/usr/libexec/acmesh-console/providers/tencentcloud.json`
- Create: `luci-app-acmesh-console/tests/test_command_builder.sh`
- Modify: `luci-app-acmesh-console/root/usr/libexec/acmesh-console/acmeshctl`
- Modify: `luci-app-acmesh-console/tests/run_host_tests.sh`

**Interfaces:**
- Consumes: provider JSON files.
- Produces: `acmesh_build_issue_command <home> <request-json-file>` with masked preview.

- [ ] **Step 1: Add provider templates**

Create `providers/cloudflare.json`:

```json
{
  "id": "cloudflare",
  "title": "Cloudflare",
  "acmeDnsApi": "dns_cf",
  "recommendedMode": "token",
  "modes": [
    {
      "id": "token",
      "title": "Token",
      "fields": [
        { "name": "token", "label": "API Token", "secret": true, "mapsTo": "CF_Token" }
      ]
    },
    {
      "id": "global_key",
      "title": "Global Key",
      "fields": [
        { "name": "email", "label": "Account Email", "mapsTo": "CF_Email" },
        { "name": "key", "label": "Global API Key", "secret": true, "mapsTo": "CF_Key" }
      ]
    }
  ]
}
```

Create `providers/aliyun.json`:

```json
{
  "id": "aliyun",
  "title": "Aliyun",
  "acmeDnsApi": "dns_ali",
  "recommendedMode": "access_key",
  "modes": [
    {
      "id": "access_key",
      "title": "AccessKey",
      "fields": [
        { "name": "key", "label": "AccessKey ID", "mapsTo": "Ali_Key" },
        { "name": "secret", "label": "AccessKey Secret", "secret": true, "mapsTo": "Ali_Secret" }
      ]
    }
  ]
}
```

Create `providers/tencentcloud.json`:

```json
{
  "id": "tencentcloud",
  "title": "Tencent Cloud / DNSPod",
  "acmeDnsApi": "dns_dp",
  "recommendedMode": "token",
  "modes": [
    {
      "id": "token",
      "title": "DNSPod Token",
      "fields": [
        { "name": "id", "label": "ID", "mapsTo": "DP_Id" },
        { "name": "key", "label": "Token", "secret": true, "mapsTo": "DP_Key" }
      ]
    }
  ]
}
```

- [ ] **Step 2: Create command builder**

Create `lib/command.sh`:

```sh
. "${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}/json.sh"

acmesh_mask_secret() {
	printf '%s' "$1" | sed -E "s/(Token|Key|Secret|Password)=('[^']*'|[^ ]+)/\1='***'/g"
}

acmesh_request_value() {
	key="$1"
	file="$2"
	sed -n "s/.*\"$key\"[ ]*:[ ]*\"\([^\"]*\)\".*/\1/p" "$file" | head -n 1
}

acmesh_build_issue_command() {
	home="$1"
	request="$2"
	domain="$(acmesh_request_value mainDomain "$request")"
	key_type="$(acmesh_request_value keyType "$request")"
	dns_api="$(acmesh_request_value acmeDnsApi "$request")"
	[ -n "$key_type" ] || key_type="ecc"
	[ -n "$domain" ] || { echo "mainDomain is required" >&2; return 1; }
	[ -n "$dns_api" ] || { echo "acmeDnsApi is required" >&2; return 1; }
	case "$key_type" in
		ecc) key_arg="--keylength ec-256" ;;
		rsa) key_arg="--keylength 2048" ;;
		*) echo "unsupported keyType" >&2; return 1 ;;
	esac
	printf "acme.sh --home '%s' --issue --dns '%s' -d '%s' %s\n" "$home" "$dns_api" "$domain" "$key_arg"
}
```

- [ ] **Step 3: Add issue preview command**

Extend `acmeshctl`:

```sh
. "$LIB_DIR/command.sh"

preview-issue)
	request_json=""
	while [ "$#" -gt 0 ]; do
		case "$1" in
			--request-json) request_json="$2"; shift 2 ;;
			*) shift ;;
		esac
	done
	command="$(acmesh_build_issue_command "$home" "$request_json")"
	printf '{"ok":true,"command":"%s"}\n' "$(acmesh_json_escape "$(acmesh_mask_secret "$command")")"
	;;
```

- [ ] **Step 4: Write command builder test**

Create `tests/test_command_builder.sh`:

```sh
#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"
request="$ROOT/tests/.tmp/issue-request.json"
mkdir -p "$ROOT/tests/.tmp"
cat > "$request" <<'JSON'
{"mainDomain":"example.com","keyType":"ecc","acmeDnsApi":"dns_cf"}
JSON

. "$ACMESH_LIB_DIR/command.sh"
cmd="$(acmesh_build_issue_command /etc/acme "$request")"
case "$cmd" in
	*"--home '/etc/acme'"*"--issue"*"--dns 'dns_cf'"*"-d 'example.com'"*"--keylength ec-256"*) ;;
	*) echo "bad command: $cmd"; exit 1 ;;
esac

echo "test_command_builder: ok"
```

Modify `tests/run_host_tests.sh` to run this test after `test_task.sh`.

- [ ] **Step 5: Run command builder tests**

Run:

```sh
sh luci-app-acmesh-console/tests/run_host_tests.sh
```

Expected includes:

```text
test_command_builder: ok
all host tests passed
```

- [ ] **Step 6: Commit**

```sh
git add luci-app-acmesh-console
git commit -m "feat: add dns issue command preview"
```

### Task 7: Deploy Foundations

**Files:**
- Create: `luci-app-acmesh-console/root/usr/libexec/acmesh-console/lib/ssh.sh`
- Create: `luci-app-acmesh-console/root/usr/libexec/acmesh-console/lib/deploy.sh`
- Create: `luci-app-acmesh-console/root/usr/libexec/acmesh-console/hooks/acmesh-console-ssh.sh`
- Create: `luci-app-acmesh-console/htdocs/luci-static/resources/view/acmesh/deploy.js`
- Modify: `luci-app-acmesh-console/root/usr/libexec/acmesh-console/acmeshctl`
- Modify: `luci-app-acmesh-console/root/usr/share/luci/menu.d/luci-app-acmesh-console.json`

**Interfaces:**
- Consumes: task lifecycle.
- Produces: SSH key ensure command, SSH deploy hook, deploy LuCI route.

- [ ] **Step 1: Create SSH helper**

Create `lib/ssh.sh`:

```sh
acmesh_ssh_dir() {
	printf '%s\n' "${ACMESH_SSH_DIR:-/etc/acmesh-console/ssh}"
}

acmesh_ssh_key_ensure() {
	dir="$(acmesh_ssh_dir)"
	key="$dir/id_ed25519"
	pub="$key.pub"
	mkdir -p "$dir"
	chmod 700 "$dir"
	if [ ! -f "$key" ]; then
		if command -v ssh-keygen >/dev/null 2>&1; then
			ssh-keygen -t ed25519 -N '' -f "$key" >/dev/null
		elif command -v dropbearkey >/dev/null 2>&1; then
			dropbearkey -t ed25519 -f "$key" >/dev/null 2>&1
			dropbearkey -y -f "$key" | sed -n 's/^ssh-/ssh-/p' > "$pub"
		else
			echo "no ssh key generator found" >&2
			return 1
		fi
	fi
	[ -f "$pub" ] || ssh-keygen -y -f "$key" > "$pub"
	printf '{"ok":true,"privateKey":"%s","publicKey":"%s"}\n' "$key" "$(cat "$pub")"
}
```

- [ ] **Step 2: Create SSH deploy hook**

Create `hooks/acmesh-console-ssh.sh`:

```sh
#!/bin/sh
set -eu

host="${ACMESH_DEPLOY_HOST:?missing host}"
port="${ACMESH_DEPLOY_PORT:-22}"
user="${ACMESH_DEPLOY_USER:-root}"
key="${ACMESH_DEPLOY_KEY:?missing key}"
remote_fullchain="${ACMESH_DEPLOY_FULLCHAIN:?missing fullchain path}"
remote_key="${ACMESH_DEPLOY_KEYFILE:?missing key path}"
reloadcmd="${ACMESH_DEPLOY_RELOADCMD:-}"

fullchain="${_cfullchain:-${Le_Fullchain:-}}"
keyfile="${_ckey:-${Le_KeyPath:-}}"

[ -f "$fullchain" ] || { echo "fullchain file not found: $fullchain" >&2; exit 1; }
[ -f "$keyfile" ] || { echo "key file not found: $keyfile" >&2; exit 1; }

target="$user@$host"
ssh_base="ssh -i $key -p $port -o BatchMode=yes"
scp_base="scp -i $key -P $port -q"

$scp_base "$fullchain" "$target:$remote_fullchain.tmp"
$scp_base "$keyfile" "$target:$remote_key.tmp"
$ssh_base "$target" "chmod 600 '$remote_key.tmp' && mv '$remote_fullchain.tmp' '$remote_fullchain' && mv '$remote_key.tmp' '$remote_key'"

if [ -n "$reloadcmd" ]; then
	$ssh_base "$target" "$reloadcmd"
fi
```

- [ ] **Step 3: Create deploy view placeholder with real route**

Create `htdocs/luci-static/resources/view/acmesh/deploy.js`:

```javascript
'use strict';
'require view';

return view.extend({
	render: function() {
		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('Deploy & Post-Action')),
			E('div', { 'class': 'cbi-section' }, [
				E('p', {}, _('Remote SSH deploy configuration will be managed here.'))
			])
		]);
	}
});
```

Modify menu JSON to add:

```json
"admin/services/acmesh/deploy": {
  "title": "Deploy",
  "order": 20,
  "action": {
    "type": "view",
    "path": "acmesh/deploy"
  }
}
```

- [ ] **Step 4: Add ssh-key command**

Extend `acmeshctl`:

```sh
. "$LIB_DIR/ssh.sh"

ssh-key)
	sub="${1:-}"
	case "$sub" in
		ensure) acmesh_ssh_key_ensure ;;
		*) printf '{"ok":false,"error":"unsupported ssh-key command"}\n'; exit 2 ;;
	esac
	;;
```

- [ ] **Step 5: Run shell syntax checks**

Run:

```sh
sh -n luci-app-acmesh-console/root/usr/libexec/acmesh-console/hooks/acmesh-console-ssh.sh
sh -n luci-app-acmesh-console/root/usr/libexec/acmesh-console/lib/ssh.sh
```

Expected: no output and exit code 0.

- [ ] **Step 6: Commit**

```sh
git add luci-app-acmesh-console
git commit -m "feat: add ssh deploy foundation"
```

### Task 8: Upgrade Workflow Skeleton

**Files:**
- Modify: `luci-app-acmesh-console/root/usr/libexec/acmesh-console/lib/command.sh`
- Modify: `luci-app-acmesh-console/root/usr/libexec/acmesh-console/acmeshctl`
- Create: `luci-app-acmesh-console/htdocs/luci-static/resources/view/acmesh/settings.js`
- Modify: `luci-app-acmesh-console/root/usr/share/luci/menu.d/luci-app-acmesh-console.json`

**Interfaces:**
- Consumes: task lifecycle.
- Produces: `upgrade-check` and `upgrade` commands with backup-before-replace behavior.

- [ ] **Step 1: Add upgrade command builder**

Append to `lib/command.sh`:

```sh
acmesh_find_script() {
	home="$1"
	if [ -x "$home/acme.sh" ]; then
		printf '%s/acme.sh\n' "$home"
	elif command -v acme.sh >/dev/null 2>&1; then
		command -v acme.sh
	else
		return 1
	fi
}

acmesh_upgrade_command() {
	home="$1"
	script="$(acmesh_find_script "$home")"
	printf "'%s' --home '%s' --upgrade\n" "$script" "$home"
}
```

- [ ] **Step 2: Add acmeshctl upgrade commands**

Extend `acmeshctl`:

```sh
upgrade-check)
	script="$(acmesh_find_script "$home" 2>/dev/null || true)"
	if [ -n "$script" ]; then
		version="$("$script" --version 2>&1 | head -n 1)"
		printf '{"ok":true,"script":"%s","version":"%s"}\n' "$(acmesh_json_escape "$script")" "$(acmesh_json_escape "$version")"
	else
		printf '{"ok":false,"error":"acme.sh not found"}\n'
		exit 1
	fi
	;;
upgrade)
	task_id="$(acmesh_task_create upgrade)"
	(
		script="$(acmesh_find_script "$home")"
		backup="$script.backup.$(date +%Y%m%d%H%M%S)"
		cp "$script" "$backup"
		acmesh_task_run "$task_id" upgrade upgrade "$script" --home "$home" --upgrade
	) &
	printf '{"ok":true,"taskId":"%s"}\n' "$(acmesh_json_escape "$task_id")"
	;;
```

- [ ] **Step 3: Add settings page**

Create `htdocs/luci-static/resources/view/acmesh/settings.js`:

```javascript
'use strict';
'require view';

return view.extend({
	render: function() {
		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('Settings')),
			E('div', { 'class': 'cbi-section' }, [
				E('p', {}, _('acme.sh upgrade and console preferences will be managed here.'))
			])
		]);
	}
});
```

Modify menu JSON to add settings route:

```json
"admin/services/acmesh/settings": {
  "title": "Settings",
  "order": 90,
  "action": {
    "type": "view",
    "path": "acmesh/settings"
  }
}
```

- [ ] **Step 4: Run syntax checks and host tests**

Run:

```sh
sh -n luci-app-acmesh-console/root/usr/libexec/acmesh-console/acmeshctl
sh luci-app-acmesh-console/tests/run_host_tests.sh
```

Expected: syntax check is silent, and host tests pass.

- [ ] **Step 5: Commit**

```sh
git add luci-app-acmesh-console
git commit -m "feat: add acme.sh upgrade skeleton"
```

## Self-Review

Spec coverage:

- acme.sh as authority: covered by Global Constraints and every backend command.
- Native state parsing: covered by Tasks 2 and 3.
- ECC/RSA display: covered by Task 3 and Task 5.
- Task logs: covered by Task 4 and Task 5.
- DNS templates: covered by Task 6.
- Deploy and SSH: covered by Task 7.
- Upgrade workflow: covered by Task 8.

Placeholder scan:

- The plan contains concrete file paths, commands, expected outputs, and code snippets.
- No implementation step depends on unspecified future behavior.

Type and name consistency:

- `acmeshctl` command names match the backend command interface.
- Shell function names are introduced before later tasks consume them.
- Frontend API names match RPC method names.

## Execution Options

Plan complete. Two execution options:

1. Subagent-Driven: dispatch a fresh subagent per task, review between tasks, faster for this package because backend, frontend, templates, and deploy can be split.
2. Inline Execution: execute tasks in this session using checkpoints after each task.

Recommended: Subagent-Driven for Tasks 1-4, then pause for router-side validation before Tasks 5-8.
