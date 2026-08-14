# acmesh Console Config Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add full configuration import and export for migrating acmesh-console between routers or plugin versions.

**Architecture:** Use the existing JSON config as the source of truth inside a versioned `.tar.gz` archive. The archive carries ACME state, console configuration, and UCI configuration; an explicit export option adds only local certificate/key files referenced by deploy profiles. Preview and restore use the existing authorization path and reject unsafe archive entries.

**Tech Stack:** LuCI JavaScript view, existing `fs.exec_direct` acmeshctl bridge, shell host tests.

## Global Constraints

- Export includes sensitive fields such as DNS credentials, pasted PEM, and SSH deployment settings.
- Import is overwrite-only for now.
- Import accepts the migration `.tar.gz` archive and shows a backend-validated summary before restoring.
- Remembered authorization records and the router instance identifier are never migrated.
- Do not create a second database or a second config path.

---

### Task 1: Operations UI Migration Panel

**Files:**
- Modify: `htdocs/luci-static/resources/view/acmesh/operations_v2.js`
- Modify: `tests/test_operations_profile_edit_ui.sh`
- Modify: `tests/test_i18n_support.sh`

**Interfaces:**
- Consumes: existing `config`, `saveConfig()`, `run([ 'config-get' ])`, `ui.addNotification`.
- Produces: a versioned migration archive protocol and `renderConfigMigration()`.

- [x] **Step 1: Write failing tests**

Add marker tests for `renderConfigMigration`, archive export/import, the deployment-certificate option, and the restore authorization path.

- [ ] **Step 2: Run tests to verify failure**

Run: `sh tests/test_operations_profile_edit_ui.sh`
Expected: FAIL because the new migration markers are absent.

- [ ] **Step 3: Implement frontend panel**

Add archive download, deployment-certificate selection, archive upload/preview, and authorized restore through `import-preview`/`import-apply`.

- [ ] **Step 4: Run focused and full tests**

Run: `node --check htdocs/luci-static/resources/view/acmesh/operations_v2.js`
Run: `sh tests/test_operations_profile_edit_ui.sh`
Run: `sh tests/run_host_tests.sh`
Expected: all pass.
