# acmesh Risk Authorization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add backend-enforced, router-local remembered authorization for dangerous acme.sh console operations while first repairing the ACL, secret transport, SSH trust, temporary-file, task-state, and deployment guarantees that consent cannot waive.

**Architecture:** Keep the existing POSIX shell backend and LuCI JavaScript views. Add focused shell libraries for private I/O, request consumption, profile resolution, canonical operation snapshots, authorization storage, and operation admission. LuCI sends sensitive structured payloads through mode-`0600` request files and may execute only narrow read/write wrappers; `/usr/libexec/acmesh-console/acmeshctl` remains the local CLI and is removed from LuCI ACLs. Remembered decisions live in `/etc/acmesh-console/authorizations.json`, while five-minute single-use challenges live under `/var/run/acmesh-console/authorization-challenges`.

**Tech Stack:** OpenWrt/ImmortalWrt, POSIX `sh`, BusyBox, `jsonfilter`, `sha256sum`, Dropbear/OpenSSH client detection, LuCI JavaScript (`view`, `fs`, `ui`), shell host tests, Node.js syntax/i18n checks, OpenWrt router integration tests.

## Global Constraints

- The only ACME implementation source of truth is `acmesh-official/acme.sh`.
- `/etc/acmesh-console` is mode `0700`; `authorizations.json` and `instance-id` are mode `0600`.
- Authorization state is preserved on the same router but excluded from configuration export/import and cross-router migration.
- Test mode never performs an ACME request, DNS mutation, deployment, remote reload, authorization consumption, or authorization creation.
- Real issue, renew, deploy, core install/upgrade, SSH key conversion, and secret export offer `Run once` and `Run and remember`.
- Revoke, remove, profile deletion, and import overwrite are always one-time authorizations.
- Dangerous-field changes, host-key changes, router instance changes, schema changes, or `ackVersion` changes invalidate remembered authorization.
- DNS tokens, passwords, private keys, and PEM contents never appear in task logs, command previews, process arguments, authorization records, or ordinary RPC responses.
- Read-only LuCI access cannot read `/etc/acme`, `/etc/acmesh-console`, private task files, or execute mutating backend commands.
- Unknown or changed SSH host keys are never accepted during production deploy; host identity is confirmed and pinned in a separate flow.
- Temporary keys and PEM files use a private per-task directory and are removed on success, failure, signal, and timeout.
- Remote deployment cannot report success after a partial pair replacement; reload failure restores both previous files.
- The exact acknowledgement copy is: `插件将严格按照上方参数执行操作。继续即表示您已核对并接受证书签发配额、远端文件覆盖、服务重载及目标系统配置产生的结果。`
- The deprecated `htdocs/luci-static/resources/view/acmesh/operations.js` must not exist. Keep `operations_v2.js` as the active Operations view and remove stale `operations.js` during upgrades.
- No Python, Node.js, or jq runtime dependency is introduced on the router.

## File Responsibility Map

### New Backend Files

- `root/usr/libexec/acmesh-console/lib/io.sh`: private directories, atomic writes, locks, unique task workspaces, cleanup traps.
- `root/usr/libexec/acmesh-console/lib/request.sh`: request-id validation and single-use request-file consumption.
- `root/usr/libexec/acmesh-console/lib/profile.sh`: strict config validation, profile resolution, normalized operation inputs, reference checks.
- `root/usr/libexec/acmesh-console/lib/authorization.sh`: canonical typed stream, SHA-256 fingerprints, ledger/challenge CRUD, expiry, corruption recovery.
- `root/usr/libexec/acmesh-console/lib/operation.sh`: operation policy matrix, authorization admission, challenge execution, and task dispatch.
- `root/usr/libexec/acmesh-console/rpc-read`: fixed read-only method dispatcher.
- `root/usr/libexec/acmesh-console/rpc-write`: fixed mutating/secret-bearing method dispatcher consuming request files.
- `root/etc/uci-defaults/99-acmesh-console-cleanup`: removes deprecated LuCI view artifacts and creates private persistent directories.

### New Frontend Files

- `htdocs/luci-static/resources/acmesh/api.js`: shared read calls, private request upload, write calls, response parsing, cleanup.
- `htdocs/luci-static/resources/acmesh/authorization.js`: risk and SSH identity dialogs, remembered execution flow, authorization badges.

### Existing Files With Narrowed Roles

- `root/usr/libexec/acmesh-console/acmeshctl`: local CLI parser only; delegates profile-based real operations to `operation.sh`.
- `root/usr/libexec/acmesh-console/lib/task.sh`: atomic private task lifecycle only.
- `root/usr/libexec/acmesh-console/lib/config.sh`: strict validated configuration persistence only.
- `root/usr/libexec/acmesh-console/lib/ssh.sh`: key generation, SSH target validation, host-key probe/pin/verify.
- `root/usr/libexec/acmesh-console/lib/deploy.sh`: local and remote transactional certificate installation.
- `root/usr/libexec/acmesh-console/lib/command.sh`: acme.sh command construction and execution after admission.
- `htdocs/luci-static/resources/view/acmesh/operations_v2.js`: profile editors, migration, authorization records, confirmation modal.
- `htdocs/luci-static/resources/view/acmesh/certificates_v2.js`: certificate actions and authorization status.
- `htdocs/luci-static/resources/view/acmesh/logs.js`: read-only task list/detail polling.

### Removed Files

- `root/usr/libexec/acmesh-console/rpc`: replaced by `rpc-read` and `rpc-write`.
- `htdocs/luci-static/resources/view/acmesh/operations.js`: deprecated; assert absence and remove stale installed copies.

---

### Task 1: Remove Legacy Operations View Artifacts

**Files:**
- Create: `luci-app-acmesh-console/root/etc/uci-defaults/99-acmesh-console-cleanup`
- Create: `luci-app-acmesh-console/tests/test_no_legacy_views.sh`
- Modify: `luci-app-acmesh-console/tests/run_host_tests.sh`
- Verify: `luci-app-acmesh-console/root/usr/share/luci/menu.d/luci-app-acmesh-console.json`

**Interfaces:**
- Consumes: active menu path `acmesh/operations_v2`.
- Produces: an upgrade cleanup guarantee that `/www/luci-static/resources/view/acmesh/operations.js` is absent.

- [ ] **Step 1: Write the failing legacy-view regression test**

Create `tests/test_no_legacy_views.sh`:

```sh
#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
MENU="$ROOT/root/usr/share/luci/menu.d/luci-app-acmesh-console.json"
CLEANUP="$ROOT/root/etc/uci-defaults/99-acmesh-console-cleanup"

[ ! -e "$ROOT/htdocs/luci-static/resources/view/acmesh/operations.js" ] || {
	echo "deprecated operations.js must not be packaged"
	exit 1
}
grep -F '"path": "acmesh/operations_v2"' "$MENU" >/dev/null
grep -F 'rm -f /www/luci-static/resources/view/acmesh/operations.js' "$CLEANUP" >/dev/null
echo "test_no_legacy_views: ok"
```

Append `sh "$ROOT/tests/test_no_legacy_views.sh"` to `tests/run_host_tests.sh` immediately before UI tests.

- [ ] **Step 2: Run the focused test and verify it fails**

```sh
sh tests/test_no_legacy_views.sh
```

Expected: failure because `99-acmesh-console-cleanup` does not exist.

- [ ] **Step 3: Add the idempotent upgrade cleanup script**

Create:

```sh
#!/bin/sh

rm -f /www/luci-static/resources/view/acmesh/operations.js
mkdir -p /etc/acmesh-console /etc/acmesh-console/ssh
chmod 700 /etc/acmesh-console /etc/acmesh-console/ssh
exit 0
```

Do not rename `operations_v2.js` and do not change the active menu path.

- [ ] **Step 4: Run the focused and full host suites**

```sh
sh tests/test_no_legacy_views.sh
sh tests/run_host_tests.sh
```

Expected: focused test prints `ok`; full suite ends with `all host tests passed`.

- [ ] **Step 5: Commit the isolated cleanup**

```sh
git add luci-app-acmesh-console/root/etc/uci-defaults/99-acmesh-console-cleanup \
  luci-app-acmesh-console/tests/test_no_legacy_views.sh \
  luci-app-acmesh-console/tests/run_host_tests.sh
git commit -m "chore: remove legacy operations view artifacts"
```

---

### Task 2: Add Private Atomic I/O And Single-Use Request Transport

**Files:**
- Create: `luci-app-acmesh-console/root/usr/libexec/acmesh-console/lib/io.sh`
- Create: `luci-app-acmesh-console/root/usr/libexec/acmesh-console/lib/request.sh`
- Create: `luci-app-acmesh-console/tests/test_private_io.sh`
- Create: `luci-app-acmesh-console/tests/test_request_transport.sh`
- Modify: `luci-app-acmesh-console/root/etc/init.d/acmesh-console`
- Modify: `luci-app-acmesh-console/tests/run_host_tests.sh`

**Interfaces:**
- Produces: `acmesh_private_dir(path)`, `acmesh_atomic_write(path, mode)`, `acmesh_lock_run(lock, command...)`, `acmesh_task_workspace(task_id)`, `acmesh_request_consume(request_id)`.
- `acmesh_atomic_write` consumes content from stdin.
- `acmesh_request_consume` prints one private processing path and removes the inbox name before returning.

- [ ] **Step 1: Write failing permission, atomicity, lock, and consumption tests**

`tests/test_private_io.sh` includes:

```sh
workspace="$(acmesh_task_workspace 20260710120000-123)"
[ "$(stat -c %a "$workspace")" = 700 ]
printf '%s\n' first | acmesh_atomic_write "$ROOT/tests/.tmp/io/state.json" 600
printf '%s\n' second | acmesh_atomic_write "$ROOT/tests/.tmp/io/state.json" 600
[ "$(cat "$ROOT/tests/.tmp/io/state.json")" = second ]
[ "$(stat -c %a "$ROOT/tests/.tmp/io/state.json")" = 600 ]
```

`tests/test_request_transport.sh` creates a 32-hex request id, writes a mode-`0600` JSON file, consumes it once, verifies the returned processing file is mode `0600`, and verifies a second consumption returns `request not found`.

- [ ] **Step 2: Run both tests and verify missing functions**

```sh
sh tests/test_private_io.sh
sh tests/test_request_transport.sh
```

Expected: both fail because the new libraries do not exist.

- [ ] **Step 3: Implement private I/O primitives**

`lib/io.sh` uses same-directory rename and lock directories:

```sh
acmesh_private_dir() {
	dir="$1"
	mkdir -p "$dir"
	chmod 700 "$dir"
}

acmesh_atomic_write() {
	path="$1"
	mode="${2:-600}"
	dir="${path%/*}"
	acmesh_private_dir "$dir"
	(
		tmp="$dir/.${path##*/}.$$.$(date +%s).tmp"
		trap 'rm -f "$tmp"' HUP INT TERM EXIT
		cat > "$tmp"
		chmod "$mode" "$tmp"
		mv -f "$tmp" "$path"
		chmod "$mode" "$path"
		trap - HUP INT TERM EXIT
	)
}

acmesh_lock_run() {
	lock="$1"
	shift
	(
		attempt=0
		while ! mkdir "$lock" 2>/dev/null; do
			attempt=$((attempt + 1))
			[ "$attempt" -lt 10 ] || exit 75
			sleep 1
		done
		trap 'rmdir "$lock" 2>/dev/null || true' HUP INT TERM EXIT
		"$@"
	)
}
```

`acmesh_task_workspace()` validates the task id, creates `/tmp/acmesh-console/<task-id>`, enforces mode `0700`, and prints the path. Callers own cleanup.

- [ ] **Step 4: Implement single-use request consumption**

`lib/request.sh` defines:

```sh
: "${ACMESH_REQUEST_DIR:=/var/run/acmesh-console/requests}"

acmesh_request_validate_id() {
	printf '%s\n' "${1:-}" | grep -Eq '^[a-f0-9]{32}$'
}

acmesh_request_consume() {
	id="$1"
	acmesh_request_validate_id "$id" || {
		printf '{"ok":false,"error":"invalid request id"}\n'
		return 2
	}
	source="$ACMESH_REQUEST_DIR/$id.json"
	target="$ACMESH_REQUEST_DIR/.$id.$$.processing"
	[ -f "$source" ] || {
		printf '{"ok":false,"error":"request not found"}\n'
		return 1
	}
	mv "$source" "$target"
	chmod 600 "$target"
	printf '%s\n' "$target"
}
```

The caller traps removal of the returned path. The init script creates request, challenge, pending-import, task-state, and task-log directories mode `0700`.

- [ ] **Step 5: Run tests, syntax checks, and commit**

```sh
sh -n root/usr/libexec/acmesh-console/lib/io.sh
sh -n root/usr/libexec/acmesh-console/lib/request.sh
sh tests/test_private_io.sh
sh tests/test_request_transport.sh
sh tests/run_host_tests.sh
git add luci-app-acmesh-console/root/usr/libexec/acmesh-console/lib/io.sh \
  luci-app-acmesh-console/root/usr/libexec/acmesh-console/lib/request.sh \
  luci-app-acmesh-console/root/etc/init.d/acmesh-console \
  luci-app-acmesh-console/tests
git commit -m "feat: add private backend request transport"
```

---

### Task 3: Split Read And Write RPC Boundaries And Remove Secret Arguments

**Files:**
- Create: `luci-app-acmesh-console/root/usr/libexec/acmesh-console/rpc-read`
- Create: `luci-app-acmesh-console/root/usr/libexec/acmesh-console/rpc-write`
- Create: `luci-app-acmesh-console/htdocs/luci-static/resources/acmesh/api.js`
- Create: `luci-app-acmesh-console/tests/test_rpc_boundaries.sh`
- Modify: `luci-app-acmesh-console/htdocs/luci-static/resources/view/acmesh/certificates_v2.js`
- Modify: `luci-app-acmesh-console/htdocs/luci-static/resources/view/acmesh/operations_v2.js`
- Modify: `luci-app-acmesh-console/htdocs/luci-static/resources/view/acmesh/logs.js`
- Modify: `luci-app-acmesh-console/root/usr/share/rpcd/acl.d/luci-app-acmesh-console.json`
- Modify: `luci-app-acmesh-console/tests/test_rpc_core_methods.sh`
- Delete: `luci-app-acmesh-console/root/usr/libexec/acmesh-console/rpc`

**Interfaces:**
- Produces frontend `api.read(method, args)` and `api.write(method, payload)`.
- `rpc-read <method> [safe scalar args]` accepts only non-secret read methods.
- `rpc-write <method> --request-id <32hex>` consumes one private JSON request.
- `acmeshctl` is not executable through LuCI ACL after this task.

- [ ] **Step 1: Write failing boundary tests**

`tests/test_rpc_boundaries.sh` asserts:

```sh
grep -F '"/usr/libexec/acmesh-console/rpc-read": [ "exec" ]' "$ACL" >/dev/null
grep -F '"/usr/libexec/acmesh-console/rpc-write": [ "exec" ]' "$ACL" >/dev/null
! grep -F '"/usr/libexec/acmesh-console/acmeshctl": [ "exec" ]' "$ACL" >/dev/null
! grep -F '"/etc/acme": [ "list", "read" ]' "$ACL" >/dev/null
! grep -R -- '--credential\|--key-pem\|--fullchain-pem\|--json' "$VIEWS" >/dev/null
```

It calls `rpc-read unsupported` and `rpc-write unsupported` and expects structured `unsupported method` errors without invoking fake `ACMESHCTL`.

- [ ] **Step 2: Run the test and verify the current ACL fails**

```sh
sh tests/test_rpc_boundaries.sh
```

Expected: failure because read ACL exposes `/etc/acme` and generic `acmeshctl` execution.

- [ ] **Step 3: Implement narrow backend wrappers**

`rpc-read` accepts exactly:

```text
status providers config_get core_status task_status task_log task_list authorization_list
```

Use a closed `case`. Task methods validate the existing task-id grammar. `task_log` returns `{ "ok": true, "log": "..." }` with `acmesh_json_escape`, not raw text.

`rpc-write` accepts exactly:

```text
config_save import_preview import_apply secret_export
issue renew deploy_run deploy_test dns_test
core_install core_upgrade ssh_key_ensure ssh_hostkey_probe ssh_hostkey_confirm
authorization_execute authorization_revoke authorization_revoke_all
certificate_revoke certificate_remove profile_delete
```

Its common prelude is:

```sh
request_id=""
while [ "$#" -gt 0 ]; do
	case "$1" in
		--request-id) request_id="$2"; shift 2 ;;
		*) printf '{"ok":false,"error":"unsupported argument"}\n'; exit 2 ;;
	esac
done
request_file="$(acmesh_request_consume "$request_id")" || exit $?
trap 'rm -f "$request_file"' HUP INT TERM EXIT
```

Each case passes the path, never JSON text, to `acmeshctl --request-file`.

- [ ] **Step 4: Implement the shared LuCI API and migrate all views**

Create `acmesh/api.js`:

```javascript
'use strict';
'require fs';

function requestId() {
	const bytes = new Uint8Array(16);
	window.crypto.getRandomValues(bytes);
	return Array.prototype.map.call(bytes, function(value) {
		return value.toString(16).padStart(2, '0');
	}).join('');
}

function read(method, args) {
	return fs.exec_direct('/usr/libexec/acmesh-console/rpc-read',
		[ method ].concat(args || []), 'json', false, true);
}

function write(method, payload) {
	const id = requestId();
	const path = '/var/run/acmesh-console/requests/' + id + '.json';
	return fs.write(path, JSON.stringify(payload || {}), 384).then(function() {
		return fs.exec_direct('/usr/libexec/acmesh-console/rpc-write',
			[ method, '--request-id', id ], 'json', false, true);
	}).finally(function() {
		return L.resolveDefault(fs.remove(path), 0);
	});
}

return { read: read, write: write };
```

Replace each view-local `run(args)` with `'require acmesh.api as acmeshApi';`. Read calls use `acmeshApi.read()`. Configuration, DNS credentials, pasted PEM, deploy, issue, renew, and core operations use `acmeshApi.write()` with structured objects. No secret remains in an argument array.

- [ ] **Step 5: Replace ACL and run integration checks**

Read ACL grants only `rpc-read` execution and required `ubus.file` execution. Write ACL grants `rpc-write`, plus write/remove under `/var/run/acmesh-console/requests`. It grants no direct read of `/etc/acme`, `/root/.acme.sh`, `/etc/acmesh-console`, task directories, or `acmeshctl`.

```sh
node --check htdocs/luci-static/resources/acmesh/api.js
node --check htdocs/luci-static/resources/view/acmesh/certificates_v2.js
node --check htdocs/luci-static/resources/view/acmesh/operations_v2.js
node --check htdocs/luci-static/resources/view/acmesh/logs.js
sh tests/test_rpc_boundaries.sh
sh tests/test_rpc_core_methods.sh
sh tests/run_host_tests.sh
```

Expected: all pass and no secret-bearing legacy argument marker remains.

- [ ] **Step 6: Commit the RPC boundary migration**

```sh
git add luci-app-acmesh-console/root/usr/libexec/acmesh-console/rpc-read \
  luci-app-acmesh-console/root/usr/libexec/acmesh-console/rpc-write \
  luci-app-acmesh-console/htdocs/luci-static/resources/acmesh/api.js \
  luci-app-acmesh-console/htdocs/luci-static/resources/view/acmesh \
  luci-app-acmesh-console/root/usr/share/rpcd/acl.d/luci-app-acmesh-console.json \
  luci-app-acmesh-console/tests
git rm luci-app-acmesh-console/root/usr/libexec/acmesh-console/rpc
git commit -m "security: split acmesh read and write RPC boundaries"
```

---

### Task 4: Make Task State And Logs Private, Atomic, And Recoverable

**Files:**
- Modify: `luci-app-acmesh-console/root/usr/libexec/acmesh-console/lib/task.sh`
- Modify: `luci-app-acmesh-console/root/etc/init.d/acmesh-console`
- Modify: `luci-app-acmesh-console/htdocs/luci-static/resources/view/acmesh/operations_v2.js`
- Modify: `luci-app-acmesh-console/tests/test_task.sh`
- Create: `luci-app-acmesh-console/tests/test_task_recovery.sh`

**Interfaces:**
- Produces: `acmesh_task_write_state_atomic(...)`, `acmesh_task_recover_interrupted()`, `acmesh_task_prune(max_terminal)`.
- Task states include `createdAt`, `startedAt`, `finishedAt`, `status`, `stage`, `exitCode`, and masked `lastError`.
- Terminal statuses are `success`, `failed`, `interrupted`, and `cancelled`; `created` is nonterminal.

- [ ] **Step 1: Extend task tests before implementation**

Add assertions that state/log directories are `0700`, state/log files are `0600`, no partial JSON is observable during 20 concurrent reads, and a synthetic `running` state is changed to `interrupted` by recovery. Create 205 terminal tasks plus one running task, prune to 200, and prove the latest 200 terminal tasks plus the running task and matching logs remain.

Add the frontend constant and reject the old `status.status !== 'running'` condition:

```javascript
const TERMINAL_TASK_STATES = [ 'success', 'failed', 'interrupted', 'cancelled' ];
```

- [ ] **Step 2: Run focused tests and verify failure**

```sh
sh tests/test_task.sh
sh tests/test_task_recovery.sh
```

Expected: permission, recovery, and terminal-state assertions fail.

- [ ] **Step 3: Refactor task writes through `acmesh_atomic_write`**

Replace direct state redirection with:

```sh
acmesh_task_write_state_atomic() {
	id="$1" operation="$2" status="$3" stage="$4" exit_code="$5"
	started_at="${6:-}" finished_at="${7:-}" last_error="${8:-}"
	{
		printf '{"ok":true,"taskId":"%s","operation":"%s"' \
			"$(acmesh_json_escape "$id")" "$(acmesh_json_escape "$operation")"
		printf ',"status":"%s","stage":"%s","exitCode":%s' \
			"$(acmesh_json_escape "$status")" "$(acmesh_json_escape "$stage")" "$exit_code"
		printf ',"startedAt":"%s","finishedAt":"%s","lastError":"%s"}\n' \
			"$(acmesh_json_escape "$started_at")" \
			"$(acmesh_json_escape "$finished_at")" \
			"$(acmesh_json_escape "$(acmesh_mask_secret "$last_error")")"
	} | acmesh_atomic_write "$ACMESH_TASK_STATE_DIR/$id.json" 600
}
```

Create logs under `umask 077`; never append an unmasked command preview. Recovery scans only validated task state filenames and atomically marks `running` or stale `created` states `interrupted` during service start. Pruning removes only the oldest terminal state/log pairs, never running/created tasks, and runs after recovery during service start.

- [ ] **Step 4: Fix polling semantics and verify**

`waitTask()` continues while status is absent, `created`, or `running`. It stops only for a terminal status or exhausted attempts.

```sh
node --check htdocs/luci-static/resources/view/acmesh/operations_v2.js
sh tests/test_task.sh
sh tests/test_task_recovery.sh
sh tests/run_host_tests.sh
```

Expected: all pass.

- [ ] **Step 5: Commit task durability**

```sh
git add luci-app-acmesh-console/root/usr/libexec/acmesh-console/lib/task.sh \
  luci-app-acmesh-console/root/etc/init.d/acmesh-console \
  luci-app-acmesh-console/htdocs/luci-static/resources/view/acmesh/operations_v2.js \
  luci-app-acmesh-console/tests
git commit -m "security: make acmesh tasks private and atomic"
```

---

### Task 5: Enforce Strict Configuration Schema And Backend Profile Resolution

**Files:**
- Create: `luci-app-acmesh-console/root/usr/libexec/acmesh-console/lib/profile.sh`
- Create: `luci-app-acmesh-console/tests/test_config_schema.sh`
- Create: `luci-app-acmesh-console/tests/test_profile_resolution.sh`
- Modify: `luci-app-acmesh-console/root/usr/libexec/acmesh-console/lib/config.sh`
- Modify: `luci-app-acmesh-console/root/usr/libexec/acmesh-console/acmeshctl`
- Modify: `luci-app-acmesh-console/Makefile`
- Modify: `luci-app-acmesh-console/tests/test_config_profiles.sh`

**Interfaces:**
- Produces: `acmesh_config_validate_file(path)`, `acmesh_profile_validate_id(id)`, `acmesh_profile_extract(kind, id, output)`, `acmesh_profile_resolve_issue(id, output)`, `acmesh_profile_resolve_deploy(id, output)`.
- Runtime config schema is version `2`; a missing version is accepted as legacy version `1` and normalized before save.
- Real operations consume a profile/certificate identifier and re-resolve current data at execution time.

- [ ] **Step 1: Write failing nested-schema and reference tests**

Reject this shape:

```json
{"schemaVersion":2,"global":[],"accountProfiles":{},"issueProfiles":[],"deployProfiles":[]}
```

Also reject duplicate/unsafe ids, missing account/deploy references, invalid ports, non-absolute destinations, unsupported key types, and DNS profiles missing required credentials. Accept exactly `ec256`, `ec384`, `ec521`, `rsa2048`, `rsa3072`, `rsa4096`, and `rsa8192`. Accept current valid config and normalize a legacy config without `schemaVersion` to version `2`.

- [ ] **Step 2: Run tests and verify the braces-only validator fails**

```sh
sh tests/test_config_schema.sh
sh tests/test_profile_resolution.sh
```

Expected: malformed nested JSON is accepted by current code, so tests fail.

- [ ] **Step 3: Add `jsonfilter` and strict file-based save**

Add `+jsonfilter` to `LUCI_DEPENDS`. Change config save to accept only `--request-file`; remove raw `--json` support.

Validation starts with:

```sh
jsonfilter -i "$path" -e '@' >/dev/null 2>&1 || return 1
[ "$(jsonfilter -i "$path" -t '@.global')" = object ] || return 1
[ "$(jsonfilter -i "$path" -t '@.accountProfiles')" = array ] || return 1
[ "$(jsonfilter -i "$path" -t '@.issueProfiles')" = array ] || return 1
[ "$(jsonfilter -i "$path" -t '@.deployProfiles')" = array ] || return 1
```

Use explicit validators for every supported field. Reject unknown top-level keys other than `schemaVersion`, `global`, `accountProfiles`, `issueProfiles`, and `deployProfiles`. Save only after full validation through `acmesh_atomic_write`.

- [ ] **Step 4: Implement backend profile resolution**

IDs match `^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$` before use in a filter expression. Extract exactly one profile, resolve inherited global/account values, and emit a private normalized JSON file.

Normalized issue data has this contract:

```json
{
  "id":"issue-id",
  "accountId":"account-id",
  "accountEmail":"resolved@example.org",
  "ca":"letsencrypt",
  "domains":["example.org","*.example.org"],
  "keyType":"ec256",
  "validationMethod":"dns",
  "dnsApi":"dns_cf",
  "challengeAlias":"",
  "dnsSleep":0,
  "deployProfileId":"deploy-id",
  "testMode":false
}
```

Credentials stay in the private resolved file and never appear in stdout. Normalized deploy data contains source identity/digest, target, destinations, reload command, sudo mode, ownership/mode, and SSH key path.

- [ ] **Step 5: Run schema/profile/full tests and commit**

```sh
sh -n root/usr/libexec/acmesh-console/lib/profile.sh
sh tests/test_config_schema.sh
sh tests/test_profile_resolution.sh
sh tests/test_config_profiles.sh
sh tests/run_host_tests.sh
git add luci-app-acmesh-console/Makefile \
  luci-app-acmesh-console/root/usr/libexec/acmesh-console/lib/config.sh \
  luci-app-acmesh-console/root/usr/libexec/acmesh-console/lib/profile.sh \
  luci-app-acmesh-console/root/usr/libexec/acmesh-console/acmeshctl \
  luci-app-acmesh-console/tests
git commit -m "security: validate and resolve acmesh profiles on backend"
```

---

### Task 6: Pin SSH Host Identity And Make Deployment Transactional

**Files:**
- Modify: `luci-app-acmesh-console/root/usr/libexec/acmesh-console/lib/ssh.sh`
- Modify: `luci-app-acmesh-console/root/usr/libexec/acmesh-console/lib/deploy.sh`
- Modify: `luci-app-acmesh-console/root/usr/libexec/acmesh-console/hooks/acmesh-console-ssh.sh`
- Create: `luci-app-acmesh-console/tests/test_ssh_security.sh`
- Create: `luci-app-acmesh-console/tests/test_deploy_transaction.sh`
- Modify: `luci-app-acmesh-console/tests/test_deploy_install.sh`
- Modify: `luci-app-acmesh-console/Makefile`

**Interfaces:**
- Produces: `acmesh_ssh_validate_target(host, port, user)`, `acmesh_ssh_probe_host_key(...)`, `acmesh_ssh_confirm_host_key(challenge_file)`, `acmesh_ssh_verify_pinned_host(...)`, `acmesh_deploy_transaction(...)`.
- Host-key confirmation is distinct from deployment authorization.
- Production OpenSSH uses `StrictHostKeyChecking=yes`; production Dropbear runs without `-y` against its private known-hosts home.

- [ ] **Step 1: Replace unsafe test expectations with failing security expectations**

Reject hosts/users beginning with `-`, semicolons, whitespace, controls, and newline. Port is numeric `1..65535`. Remote paths are absolute and contain no controls.

Replace current auto-accept assertions with:

```sh
case "$deploy_log" in
	*"StrictHostKeyChecking=yes"*"UserKnownHostsFile="*) ;;
	*"ssh -y"*|*"StrictHostKeyChecking=accept-new"*) exit 1 ;;
esac
```

Fake SSH clients simulate unknown, pinned, and changed fingerprints.

- [ ] **Step 2: Run focused tests and verify current behavior fails**

```sh
sh tests/test_ssh_security.sh
sh tests/test_deploy_install.sh
```

Expected: current auto-accept behavior and permissive target handling fail.

- [ ] **Step 3: Implement target validation and host-key lifecycle**

Use:

```sh
acmesh_ssh_validate_host() {
	case "$1" in ''|-*|*[!A-Za-z0-9._:-]*) return 1 ;; esac
}
acmesh_ssh_validate_user() {
	printf '%s\n' "$1" | grep -Eq '^[A-Za-z_][A-Za-z0-9_.-]*$'
}
acmesh_ssh_validate_port() {
	printf '%s\n' "$1" | grep -Eq '^[0-9]+$' || return 1
	[ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}
```

Unknown-host probe returns `hostKeyRequired` with challenge id, algorithm, and fingerprint. Confirmation probes again, requires an exact fingerprint match, then pins the identity. Changed identity returns `hostKeyChanged` and never reaches upload.

The canonical trust store is `/etc/acmesh-console/ssh/known_hosts` mode `0600`. OpenSSH points to it with `UserKnownHostsFile`. For Dropbear, create a private per-task `HOME/.ssh/known_hosts` copy from the canonical store and run without `-y`; host-key confirmation updates the canonical store only after the second probe matches. Never expose a shared writable Dropbear home under `/tmp`.

- [ ] **Step 4: Replace deterministic temporary paths and cleanup every exit**

```sh
workspace="$(acmesh_task_workspace "$task_id")"
cleanup() {
	[ -n "${workspace:-}" ] && rm -rf "$workspace"
}
trap cleanup HUP INT TERM EXIT
```

PEM and converted Dropbear keys live only inside the workspace, mode `0600`. Add `+dropbearconvert` to dependencies; still report a structured unavailable error if missing.

- [ ] **Step 5: Implement pair-safe local and remote transactions**

Create adjacent `.acmesh-new-<taskId>` and `.acmesh-backup-<taskId>` paths. Upload both new files before replacing targets. The remote transaction follows:

```sh
set -eu
rollback() {
	[ ! -e "$cert_backup" ] || mv -f "$cert_backup" "$cert_target"
	[ ! -e "$key_backup" ] || mv -f "$key_backup" "$key_target"
}
trap rollback HUP INT TERM
[ ! -e "$cert_target" ] || mv -f "$cert_target" "$cert_backup"
[ ! -e "$key_target" ] || mv -f "$key_target" "$key_backup"
mv -f "$key_new" "$key_target"
chmod 600 "$key_target"
mv -f "$cert_new" "$cert_target"
if ! sh -c "$reload_command"; then
	rollback
	exit 70
fi
rm -f "$cert_backup" "$key_backup"
trap - HUP INT TERM
```

All interpolated values use `acmesh_shell_quote`. Log `upload`, `backup`, `replace`, `reload`, and `rollback`. Success is impossible after partial replacement or failed reload.

- [ ] **Step 6: Run failure-injection tests and commit**

```sh
sh tests/test_ssh_security.sh
sh tests/test_deploy_transaction.sh
sh tests/test_deploy_install.sh
sh tests/run_host_tests.sh
git add luci-app-acmesh-console/Makefile \
  luci-app-acmesh-console/root/usr/libexec/acmesh-console/lib/ssh.sh \
  luci-app-acmesh-console/root/usr/libexec/acmesh-console/lib/deploy.sh \
  luci-app-acmesh-console/root/usr/libexec/acmesh-console/hooks/acmesh-console-ssh.sh \
  luci-app-acmesh-console/tests
git commit -m "security: pin ssh hosts and transact certificate deploys"
```

Expected: upload failure leaves old pair; replace/reload failure restores both; success removes backups and temporary keys.

---

### Task 7: Build Canonical Material Snapshots And Fingerprints

**Files:**
- Create: `luci-app-acmesh-console/root/usr/libexec/acmesh-console/lib/authorization.sh`
- Create: `luci-app-acmesh-console/tests/test_authorization_fingerprint.sh`
- Modify: `luci-app-acmesh-console/root/usr/libexec/acmesh-console/acmeshctl`
- Modify: `luci-app-acmesh-console/tests/run_host_tests.sh`

**Interfaces:**
- Produces: `acmesh_auth_snapshot(operation, subject_type, subject_id, output)`, `acmesh_auth_fingerprint(snapshot)`, `acmesh_auth_summary(snapshot, output)`.
- Canonicalization version is `1`; `ackVersion` is `1`.
- Snapshot files contain no secret values and are mode `0600`.

- [ ] **Step 1: Write failing fingerprint invariance tests**

Prove:

1. Reordered config keys produce the same fingerprint.
2. Reordered SANs normalize to the same fingerprint.
3. Name/description changes do not change the fingerprint.
4. DNS token rotation alone does not change the fingerprint.
5. CA, domain/SAN, key type, validation, provider, deploy target, path, reload, core tag, or pinned host key changes do change it.
6. Issue and renew fingerprints differ.
7. Pasted PEM contributes only a digest; PEM text is absent from snapshot and stdout.

- [ ] **Step 2: Run the test and verify missing functions**

```sh
sh tests/test_authorization_fingerprint.sh
```

Expected: failure because `authorization.sh` is absent.

- [ ] **Step 3: Implement a typed length-prefixed canonical stream**

Set `LC_ALL=C`. Emit fixed-order records:

```sh
acmesh_canon_string() {
	key="$1" value="${2-}"
	if printf '%s' "$key$value" | LC_ALL=C grep -q '[[:cntrl:]]'; then
		return 2
	fi
	printf 's:%s:%s:%s:%s\n' "${#key}" "$key" "${#value}" "$value"
}
acmesh_canon_bool() {
	printf 'b:%s:%s\n' "$1" "$2"
}
acmesh_canon_null() {
	printf 'n:%s\n' "$1"
}
```

Arrays are normalized, sorted with `LC_ALL=C sort -u`, and emitted as `a:<key>:<index>:<length>:<value>`. Begin every snapshot with canonicalization version, router instance id, operation, subject type, and subject id.

Hash with:

```sh
printf 'sha256:%s\n' "$(sha256sum "$snapshot" | awk '{print $1}')"
```

- [ ] **Step 4: Implement operation-specific material fields**

Issue/renew include resolved account/CA, complete domains, key type, validation, provider id, alias/propagation, real/test mode, and linked deploy material fingerprint. Deploy includes source identity/digest, host/port/user, client, pinned key identity, destinations, reload/sudo/mode/ownership, and transaction strategy. Core includes operation, official source identity, home, tag, and backup policy. Import/export use validated configuration digest and scope. Destructive operations include object/certificate identity and variant.

Exclude display metadata, DNS secrets, passwords, private key bytes, and PEM bytes.

- [ ] **Step 5: Run tests and commit**

```sh
sh -n root/usr/libexec/acmesh-console/lib/authorization.sh
sh tests/test_authorization_fingerprint.sh
sh tests/run_host_tests.sh
git add luci-app-acmesh-console/root/usr/libexec/acmesh-console/lib/authorization.sh \
  luci-app-acmesh-console/root/usr/libexec/acmesh-console/acmeshctl \
  luci-app-acmesh-console/tests
git commit -m "feat: fingerprint material acmesh operations"
```

---

### Task 8: Implement The Authorization Ledger And Single-Use Challenges

**Files:**
- Modify: `luci-app-acmesh-console/root/usr/libexec/acmesh-console/lib/authorization.sh`
- Create: `luci-app-acmesh-console/tests/test_authorization_ledger.sh`
- Create: `luci-app-acmesh-console/tests/test_authorization_concurrency.sh`
- Modify: `luci-app-acmesh-console/root/etc/init.d/acmesh-console`

**Interfaces:**
- Produces: `acmesh_auth_prepare(...)`, `acmesh_auth_execute(challenge_id, decision)`, `acmesh_auth_list()`, `acmesh_auth_revoke(id)`, `acmesh_auth_revoke_all()`, `acmesh_auth_prune_challenges(now)`.
- Decisions are `once` and `remember` only.
- Prepare returns admission or a five-minute challenge; execution recomputes the current fingerprint under lock.

- [ ] **Step 1: Write failing lifecycle and corruption tests**

Cover first challenge, once without ledger, remember and reuse, consumed/expired challenge rejection, dangerous-field invalidation, cosmetic-field stability, router/ack/schema invalidation, migration exclusion, corrupt-ledger retention, fail-closed behavior, and removal of expired or orphaned `.consuming` challenge files without touching live challenges.

Concurrency starts ten attempts to consume one challenge and asserts exactly one admission and one task-admission marker.

- [ ] **Step 2: Run tests and verify failure**

```sh
sh tests/test_authorization_ledger.sh
sh tests/test_authorization_concurrency.sh
```

Expected: both fail because ledger/challenge behavior is absent.

- [ ] **Step 3: Create router identity and versioned ledger**

Create `/etc/acmesh-console/instance-id` from `/proc/sys/kernel/random/uuid`, or 32 random bytes rendered as hex. Write mode `0600`.

Initial ledger:

```json
{"schemaVersion":1,"instanceId":"...","ackVersion":1,"records":[]}
```

Validate every field with `jsonfilter`. Rebuild the full envelope for add/update/revoke, then atomically replace it. On corruption, retain `authorizations.json.corrupt.<timestamp>` mode `0600` and continue with no active records.

Each record contains exactly `id`, `operation`, `subjectType`, `subjectId`, `fingerprint`, `grantedAt`, `lastUsedAt`, `useCount`, and `ackVersion`. It contains no material snapshot, risk summary, secret, command, path contents, or arbitrary output.

Every admitted reuse updates `lastUsedAt` and increments `useCount` under the same lock before task creation. A failed ledger update prevents execution so usage accounting cannot silently diverge.

- [ ] **Step 4: Implement challenge creation and fail-closed execution**

Challenge JSON contains no secret:

```json
{
  "schemaVersion":1,
  "challengeId":"...",
  "operation":"deploy-run",
  "subjectType":"deployProfile",
  "subjectId":"deploy-123",
  "fingerprint":"sha256:...",
  "createdAt":1783658400,
  "expiresAt":1783658700,
  "ackVersion":1,
  "summary":{}
}
```

Store mode `0600` under `/var/run/acmesh-console/authorization-challenges`. Under lock, rename to `.consuming`, check expiry/version/instance, rebuild current snapshot, compare, optionally persist a record, remove challenge, then admit. A mismatch returns `authorizationChanged` plus a fresh challenge and performs no task creation.

`acmesh_auth_prune_challenges` runs during service start and before challenge creation. It removes expired normal challenges and `.consuming` files older than ten minutes, using validated filenames only.

- [ ] **Step 5: Implement list and revocation**

List records without secrets and compute `Active`, `Stale`, or `Unsupported`. Revoke filters one id; revoke-all writes an empty records array. Neither requires risk confirmation.

- [ ] **Step 6: Run permissions/concurrency/full tests and commit**

```sh
sh tests/test_authorization_ledger.sh
sh tests/test_authorization_concurrency.sh
sh tests/run_host_tests.sh
git add luci-app-acmesh-console/root/usr/libexec/acmesh-console/lib/authorization.sh \
  luci-app-acmesh-console/root/etc/init.d/acmesh-console \
  luci-app-acmesh-console/tests
git commit -m "feat: add router-local authorization ledger"
```

---

### Task 9: Route Every Real Operation Through Authorization Admission

**Files:**
- Create: `luci-app-acmesh-console/root/usr/libexec/acmesh-console/lib/operation.sh`
- Create: `luci-app-acmesh-console/tests/test_operation_admission.sh`
- Modify: `luci-app-acmesh-console/root/usr/libexec/acmesh-console/acmeshctl`
- Modify: `luci-app-acmesh-console/root/usr/libexec/acmesh-console/rpc-write`
- Modify: `luci-app-acmesh-console/root/usr/libexec/acmesh-console/lib/command.sh`
- Modify: `luci-app-acmesh-console/root/usr/libexec/acmesh-console/lib/deploy.sh`
- Modify: `luci-app-acmesh-console/root/usr/libexec/acmesh-console/hooks/acmesh-console-ssh.sh`
- Create: `luci-app-acmesh-console/tests/test_core_upgrade_rollback.sh`
- Create: `luci-app-acmesh-console/tests/test_deploy_hook_authorization.sh`
- Modify: existing issue/renew/core/deploy tests.

**Interfaces:**
- Produces: `acmesh_operation_submit(request_file)`, `acmesh_operation_start(operation, subject_type, subject_id, parameters_file)`, `acmesh_operation_execute_challenge(request_file)`.
- Response is task, authorization challenge, host-key challenge, or structured validation error.
- Test mode bypasses authorization and external mutation.

- [ ] **Step 1: Write a failing operation-matrix test**

Test `issue`, `renew`, `deploy-run`, `core-install`, `core-upgrade`, and `ssh-key-convert`. Test mode creates no ledger/challenge. Real mode creates challenge before task. Once creates one task. Remember creates one task and allows repeat without prompt. Direct legacy real-mode calls without profile id/admission fail before task creation. Command-builder cases cover every supported key type including `rsa8192`, complete SAN emission as repeated `-d`, challenge alias, and DNS propagation delay.

- [ ] **Step 2: Run the test and verify current bypass**

```sh
sh tests/test_operation_admission.sh
```

Expected: failure because current real operations create tasks immediately.

- [ ] **Step 3: Implement the closed operation matrix**

```sh
case "$operation" in
	issue) subject_type=issueProfile ;;
	renew) subject_type=certificate ;;
	deploy-run) subject_type=deployProfile ;;
	core-install|core-upgrade) subject_type=global ;;
	ssh-key-convert) subject_type=sshKey ;;
	secret-export) subject_type=config ;;
	certificate-revoke|certificate-remove|profile-delete|import-apply) one_time=1 ;;
	*) printf '{"ok":false,"error":"unsupported operation"}\n'; return 2 ;;
esac
```

RPC names map explicitly to operation names: `deploy_run -> deploy-run`, `core_install -> core-install`, `core_upgrade -> core-upgrade`, `secret_export -> secret-export`, `certificate_revoke -> certificate-revoke`, `certificate_remove -> certificate-remove`, `profile_delete -> profile-delete`, and `import_apply -> import-apply`. No caller supplies a free-form operation name.

Test mode calls only preview/test functions. Real mode resolves current backend state, performs host-key/key-format preflight, builds snapshot/summary, calls `acmesh_auth_prepare`, and starts only after admission.

- [ ] **Step 4: Recompute and dispatch after challenge execution**

`authorization_execute` contains only `challengeId` and `decision`. Backend retrieves operation/subject from the private challenge, recomputes current state, consumes under lock, and dispatches current resolved data. Browser operation/fingerprint/target fields are ignored.

Host identity and key conversion are sequential gates before deploy authorization. Remembered conversion is scoped to original key identity/client type; converted key stays temporary.

- [ ] **Step 5: Register linked deploy profiles in the renewal lifecycle**

After successful issue, configure `acmesh-console-ssh` as the acme.sh deploy hook when the issue profile links a deploy profile. The hook resolves the current issue/deploy profile from backend config using domain and key variant, recomputes the deploy fingerprint, and runs non-interactively only when a matching remembered deploy authorization exists. Without authorization it exits nonzero with a masked `authorization required for deploy profile <id>` message; it never invents or remembers consent.

Test initial issue, manual renew, and hook invocation. Prove a changed target/path/reload command prevents automatic redeploy until reauthorized.

- [ ] **Step 6: Add core backup and rollback, and make Let's Encrypt explicit**

Before core install/upgrade replaces `acme.sh`, copy the current executable and version metadata into a private per-task backup. Verify the selected official tag archive and installed script are usable before removing the backup. On download, extraction, install, or post-install version-check failure, atomically restore the previous script and report rollback status. `test_core_upgrade_rollback.sh` injects each failure stage and compares the restored SHA-256.

Map production to `--server letsencrypt` and staging to `--server letsencrypt_test`. Test neither silently falls back to acme.sh's default CA. DNS Test remains non-mutating and does not consume risk authorization.

- [ ] **Step 7: Run focused/full tests and commit**

```sh
sh tests/test_operation_admission.sh
sh tests/test_issue_real_mode.sh
sh tests/test_issue_test_mode.sh
sh tests/test_issue_staging_ca.sh
sh tests/test_renew.sh
sh tests/test_core_install_mode.sh
sh tests/test_core_upgrade_mode.sh
sh tests/test_core_upgrade_rollback.sh
sh tests/test_deploy_install.sh
sh tests/test_deploy_hook_authorization.sh
sh tests/run_host_tests.sh
git add luci-app-acmesh-console/root/usr/libexec/acmesh-console \
  luci-app-acmesh-console/tests
git commit -m "feat: authorize every real acmesh operation"
```

---

### Task 10: Authorize Migration, Secret Export, And Destructive Actions

**Files:**
- Create: `luci-app-acmesh-console/tests/test_secure_migration.sh`
- Create: `luci-app-acmesh-console/tests/test_destructive_authorization.sh`
- Modify: `luci-app-acmesh-console/root/usr/libexec/acmesh-console/lib/operation.sh`
- Modify: `luci-app-acmesh-console/root/usr/libexec/acmesh-console/lib/config.sh`
- Modify: `luci-app-acmesh-console/root/usr/libexec/acmesh-console/lib/command.sh`
- Modify: `luci-app-acmesh-console/root/usr/libexec/acmesh-console/rpc-write`
- Modify: `luci-app-acmesh-console/root/usr/libexec/acmesh-console/acmeshctl`

**Interfaces:**
- Produces: `import-preview`, one-time `import-apply`, rememberable `secret-export`, one-time `certificate-revoke`, `certificate-remove`, and `profile-delete`.
- Import preview is bound to the SHA-256 of exact uploaded bytes.
- Secret export returns the requested download only after admission and never writes it to task logs.

- [ ] **Step 1: Write failing migration and destructive tests**

Reject malformed/unsupported envelopes, stale preview ids, changed bytes, nested type errors, duplicate ids, and dangling references. Prove authorization, instance, trust, task, and challenge data are absent from export.

For revoke/remove/delete, prove `remember` is rejected, each challenge is single-use, and deleting a referenced profile returns a dependency list.

- [ ] **Step 2: Run tests and verify current frontend-only import fails**

```sh
sh tests/test_secure_migration.sh
sh tests/test_destructive_authorization.sh
```

Expected: failure because current preview is browser-local and config save is not fully validated.

- [ ] **Step 3: Move import preview and apply to backend**

`import-preview` validates exact payload, writes candidate to `/var/run/acmesh-console/pending-imports/<digest>.json` mode `0600`, and returns summary/digest. No secret is copied into the challenge.

`import-apply` snapshot includes digest and overwrite mode. On one-time execution, verify pending file hash, revalidate, atomically replace config, remove pending data, and never create a remembered record.

- [ ] **Step 4: Implement secret export admission**

Snapshot includes full current config digest and export scope. A remembered record matches only while the digest is unchanged. Export excludes:

```text
authorizations.json
instance-id
known_hosts and trust decisions
task history
temporary and converted keys
pending imports and challenges
```

Return export JSON directly to LuCI; do not create a log containing it.

- [ ] **Step 5: Implement one-time certificate/profile destruction**

Add structured acme.sh builders for `--revoke` and `--remove` with explicit domain/key variant. `profile-delete` edits validated config after one-time admission and reference checks. Reject decision `remember` for all destructive operations.

- [ ] **Step 6: Run tests and commit**

```sh
sh tests/test_secure_migration.sh
sh tests/test_destructive_authorization.sh
sh tests/run_host_tests.sh
git add luci-app-acmesh-console/root/usr/libexec/acmesh-console \
  luci-app-acmesh-console/tests
git commit -m "feat: authorize migration and destructive operations"
```

---

### Task 11: Add LuCI Risk Dialog, Authorized State, And Authorization Records

**Files:**
- Create: `luci-app-acmesh-console/htdocs/luci-static/resources/acmesh/authorization.js`
- Create: `luci-app-acmesh-console/tests/test_authorization_ui.sh`
- Modify: `luci-app-acmesh-console/htdocs/luci-static/resources/view/acmesh/operations_v2.js`
- Modify: `luci-app-acmesh-console/htdocs/luci-static/resources/view/acmesh/certificates_v2.js`
- Modify: `luci-app-acmesh-console/po/zh_Hans/acmesh-console.po`
- Modify: `luci-app-acmesh-console/tools/check_i18n_coverage.js` only if extraction requires the new module path.

**Interfaces:**
- Produces: `authorization.run(method, payload, options)`, `authorization.showChallenge(response)`, `authorization.showHostKey(response)`, `authorization.badge(status)`.
- Adds `Authorization records` beside `Configuration migration` in Operations.
- Destructive challenges render only Cancel and Run once.

- [ ] **Step 1: Write failing UI behavior tests**

Require exact acknowledgement copy, buttons, material summary rows, secret masking, destructive no-remember behavior, Authorized badges, records table, revoke/revoke-all, and changed-host hard stop. Require the issue editor to persist and render primary domain, SAN list, challenge alias, DNS propagation delay, and key choices `ec256`, `ec384`, `ec521`, `rsa2048`, `rsa3072`, `rsa4096`, and `rsa8192`; the confirmation summary must show the complete normalized domain set.

Reject `window.confirm`, `confirmSshKeyConversionRetry`, and rendering raw `keyPem`, `fullchainPem`, credentials, or token values in the modal.

- [ ] **Step 2: Run syntax/marker tests and verify failure**

```sh
sh tests/test_authorization_ui.sh
node --check htdocs/luci-static/resources/view/acmesh/operations_v2.js
```

Expected: missing authorization module/modal/records tab.

- [ ] **Step 3: Implement the shared controller**

```javascript
function run(method, payload, options) {
	return acmeshApi.write(method, payload).then(function(response) {
		if (response.hostKeyRequired || response.hostKeyChanged)
			return showHostKey(response, options);
		if (!response.authorizationRequired)
			return response;
		return showChallenge(response, options);
	});
}
```

`showChallenge` renders only backend `riskSummary`. Run once sends `{challengeId,decision:'once'}`; Run and remember sends `{challengeId,decision:'remember'}`. Close modal before task polling. Changed/expired challenge renders the fresh summary and requires a new click.

- [ ] **Step 4: Wire profile and certificate actions**

Issue/deploy submit ids, not secrets. Core submits selected tag/home. Renew/revoke/remove submit certificate identity. Delete calls backend `profile-delete` instead of editing browser config directly.

The issue editor stores `domains` as an array with the primary domain first and deduplicated SANs after it. Challenge alias and DNS propagation delay live in the existing advanced DNS section with plain-language help; blank alias remains the default. The backend remains authoritative for normalization and validation.

Remove the key-conversion `window.confirm`; conversion uses the authorization controller. Show Authorized only when backend status says the current material fingerprint matches.

- [ ] **Step 5: Add Authorization records tab**

Add `data-acmesh-tab="authorizations"` and columns:

```text
Operation | Subject | Scope | Granted | Last used | Uses | Status | Actions
```

Rows expose Revoke; toolbar exposes Revoke all. Stale/unsupported rows cannot execute. Migration remains a sibling tab, not a standalone block.

- [ ] **Step 6: Update translations and verify coverage**

Add translations for modal, status, host-key, stale challenge, revoke, and records strings. Preserve the exact Chinese acknowledgement from Global Constraints.

```sh
node --check htdocs/luci-static/resources/acmesh/authorization.js
node --check htdocs/luci-static/resources/view/acmesh/operations_v2.js
node --check htdocs/luci-static/resources/view/acmesh/certificates_v2.js
node tools/check_i18n_coverage.js
sh tests/test_authorization_ui.sh
sh tests/test_operations_profile_edit_ui.sh
sh tests/test_certificates_list_detail_ui.sh
sh tests/run_host_tests.sh
```

Expected: syntax/tests pass and i18n prints `i18n coverage ok`.

- [ ] **Step 7: Commit LuCI authorization experience**

```sh
git add luci-app-acmesh-console/htdocs/luci-static/resources/acmesh/authorization.js \
  luci-app-acmesh-console/htdocs/luci-static/resources/view/acmesh \
  luci-app-acmesh-console/po/zh_Hans/acmesh-console.po \
  luci-app-acmesh-console/tests \
  luci-app-acmesh-console/tools/check_i18n_coverage.js
git commit -m "feat: add remembered risk authorization UI"
```

---

### Task 12: Add CLI Parity, Persistence, Documentation, And Release Gates

**Files:**
- Modify: `luci-app-acmesh-console/root/usr/libexec/acmesh-console/acmeshctl`
- Modify: `luci-app-acmesh-console/Makefile`
- Modify: `luci-app-acmesh-console/root/etc/uci-defaults/99-acmesh-console-cleanup`
- Create: `luci-app-acmesh-console/tests/test_cli_authorization.sh`
- Create: `luci-app-acmesh-console/tests/test_package_contract.sh`
- Create: `luci-app-acmesh-console/README.md`
- Create: `luci-app-acmesh-console/LICENSE`
- Modify: `luci-app-acmesh-console/tests/run_host_tests.sh`

**Interfaces:**
- CLI supports `--request-stdin`, `--acknowledge-risk <challenge-id>`, and `--remember-authorization <challenge-id>`.
- Dangerous CLI calls without a matching record return authorization-required JSON and nonzero status.
- Package/sysupgrade preserves config, instance id, ledger, SSH key, and pinned host identities.

- [ ] **Step 1: Write failing CLI and package-contract tests**

Pipe request JSON through stdin and assert secrets are absent from `/proc/<pid>/cmdline`, output, and logs. Once executes once; remember persists. Assert no `--yes`, `--force-all`, or disable-confirmation flag exists.

Require:

```make
define Package/luci-app-acmesh-console/conffiles
/etc/config/acmesh-console
/etc/acmesh-console/config.json
/etc/acmesh-console/instance-id
/etc/acmesh-console/authorizations.json
/etc/acmesh-console/ssh/id_ed25519
/etc/acmesh-console/ssh/id_ed25519.pub
/etc/acmesh-console/ssh/known_hosts
endef
```

Also require dependencies `jsonfilter` and `dropbearconvert`, active `operations_v2`, and stale `operations.js` cleanup.

- [ ] **Step 2: Run tests and verify missing behavior**

```sh
sh tests/test_cli_authorization.sh
sh tests/test_package_contract.sh
```

Expected: failure until CLI and conffile declarations exist.

- [ ] **Step 3: Implement CLI parity without secret argv**

`--request-stdin` copies stdin to mode-`0600` processing file, validates, dispatches, and removes through trap. Challenge flags call the same backend path as LuCI. Authorization-required is nonzero in CLI mode.

Delete parsing of `--credential`, `--key-pem`, `--fullchain-pem`, and `--json`; direct callers receive guidance to use `--request-stdin`.

- [ ] **Step 4: Add package persistence and public documentation**

Add the exact conffile block. README sections:

```text
Purpose
Supported OpenWrt and LuCI baseline
Official acme.sh relationship
Installation and dependencies
Accounts, issue profiles, deploy profiles
Test mode versus Let's Encrypt staging
Risk authorization and revocation
SSH host-key pinning and temporary key conversion
Configuration migration exclusions
Router-side verification commands
Security reporting and license
```

State that user authorization accepts business consequences but never disables plugin security guarantees. Add the standard Apache-2.0 text matching `PKG_LICENSE`.

- [ ] **Step 5: Run complete local verification**

```sh
find root -type f \( -name '*.sh' -o -path '*/acmeshctl' -o -path '*/rpc-read' -o -path '*/rpc-write' \) -exec sh -n {} \;
node --check htdocs/luci-static/resources/acmesh/api.js
node --check htdocs/luci-static/resources/acmesh/authorization.js
node --check htdocs/luci-static/resources/view/acmesh/certificates_v2.js
node --check htdocs/luci-static/resources/view/acmesh/operations_v2.js
node --check htdocs/luci-static/resources/view/acmesh/logs.js
node tools/check_i18n_coverage.js
sh tests/run_host_tests.sh
```

Expected: syntax checks silent, i18n passes, host suite ends `all host tests passed`.

- [ ] **Step 6: Build package in an OpenWrt SDK**

```sh
make defconfig
make package/luci-app-acmesh-console/compile V=s
```

Expected: `.ipk` or `.apk` is produced with no dependency/packaging error. Archive contains no deprecated `operations.js`.

- [ ] **Step 7: Deploy to the current private test router**

Use `10.0.0.227` only as the integration target, never a product default. After install/restart:

```sh
sh /usr/libexec/acmesh-console/tests/run_host_tests.sh
busybox stat -c '%a %n' /etc/acmesh-console /etc/acmesh-console/authorizations.json \
  /var/run/acmesh-console/requests /var/run/acmesh-console/authorization-challenges
ls /www/luci-static/resources/view/acmesh/operations*.js
```

Expected: tests pass, directories/files are `700/600`, and only `operations_v2.js` exists.

Chrome acceptance:

1. Test-mode issue has no prompt and no challenge/ledger mutation.
2. Real issue offers once/remember and displays CA/domains/key type.
3. Remembered repeat runs without modal and shows Authorized.
4. Material change prompts again; rename does not.
5. Unknown SSH identity asks to pin; changed identity hard-stops.
6. Remote failure reports rollback; converted key disappears.
7. Import is one-time and excludes authorization; config change invalidates secret export authorization.
8. Authorization records list/revoke/revoke-all update immediately.
9. Read-only ACL cannot execute `rpc-write`/`acmeshctl` or read private keys.

- [ ] **Step 8: Commit release gates and documentation**

```sh
git add luci-app-acmesh-console/Makefile \
  luci-app-acmesh-console/root/usr/libexec/acmesh-console/acmeshctl \
  luci-app-acmesh-console/root/etc/uci-defaults/99-acmesh-console-cleanup \
  luci-app-acmesh-console/tests \
  luci-app-acmesh-console/README.md \
  luci-app-acmesh-console/LICENSE
git commit -m "docs: prepare acmesh console authorization release"
```

## Spec Coverage Map

| Specification area | Implemented and proved by |
| --- | --- |
| Deprecated Operations view cleanup | Task 1, Task 12 router archive/view checks |
| Private request transport and ACL separation | Tasks 2-3, CLI parity in Task 12 |
| Atomic private task state and crash recovery | Task 4 |
| Strict nested config and backend profile truth | Task 5 |
| SSH validation, pinning, temporary cleanup, pair rollback | Task 6 |
| Canonical dangerous-field fingerprints | Task 7 |
| Router-local ledger, challenge expiry, reuse, invalidation, corruption, concurrency | Task 8 |
| Issue/renew/deploy/core/conversion operation admission and test-mode bypass | Task 9 |
| Import/export and one-time destructive policy | Task 10 |
| Confirmation copy, once/remember controls, Authorized state, records/revocation | Task 11 |
| CLI flags, sysupgrade persistence, migration exclusion, package/browser/router release evidence | Task 12 |

## Final Acceptance Gate

Do not complete this plan without evidence from the same run:

- full host suite output;
- JavaScript and shell syntax output;
- i18n coverage output;
- OpenWrt SDK package build output;
- router permission and ACL evidence;
- router authorization lifecycle tests;
- Chrome screenshots for challenge, authorized state, records tab, and host-key change;
- real remote deployment success and failure-injection rollback using non-production certificate material;
- `git diff --check` and final review with no unresolved P0/P1 findings.

The implementation order is intentional: Tasks 1-6 establish non-waivable safety, Tasks 7-10 add backend authorization, Task 11 exposes it in LuCI, and Task 12 proves CLI/package/release parity. Do not enable remembered production authorization before Tasks 1-6 pass on the router.
