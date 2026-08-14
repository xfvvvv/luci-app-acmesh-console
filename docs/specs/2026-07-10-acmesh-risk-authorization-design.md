# acmesh Console Risk Authorization Design

## Status

Drafted from the decisions approved in conversation on 2026-07-10 and awaiting final document review. This document defines the product behavior and security boundary; it does not itself change runtime code.

## Purpose

`luci-app-acmesh-console` is a transparent operator console for `acmesh-official/acme.sh`. It should expose the exact action that will be executed, let the router owner decide whether to proceed, remember that decision when explicitly requested, and then execute the approved action without repeated interruption.

The console does not promise that certificate authorities, DNS providers, SSH targets, remote reload commands, or user-supplied paths are harmless. It does promise that it will:

- describe material effects before a dangerous action;
- require an explicit authorization before the first matching execution;
- record only the scope of the authorization, never the underlying secret;
- invalidate authorization when the material operation changes;
- faithfully execute the approved structured operation;
- enforce security invariants that cannot be waived by a disclaimer.

This design replaces repeated confirmation dialogs with a backend-enforced, independently stored authorization ledger.

## Goals

1. Give the user the final decision for business-risk operations.
2. Support both one-time execution and "run and remember" authorization.
3. Avoid prompting again while the same material operation remains authorized.
4. Force a new decision when dangerous fields, the target identity, or the acknowledgement contract changes.
5. Keep LuCI and command-line execution under the same authorization rules.
6. Keep authorization state separate from profiles, acme.sh state, configuration migration, and secrets.
7. Make authorization history visible and revocable from the Operations page.

## Non-Goals

- Eliminating CA rate limits, DNS mistakes, remote service failures, or user configuration errors.
- Allowing a user to waive basic protections such as secret masking, host-key verification, safe temporary files, or ACL separation.
- Treating a warning banner or terms text as sufficient authorization.
- Exporting remembered trust to another router.
- Remembering destructive deletion, certificate revocation, or certificate removal indefinitely.

## Product Boundary

There are two distinct classes of risk.

### User-Authorizable Business Risk

The router owner may approve operations whose consequences depend on their own infrastructure or external services:

- real certificate issuance and renewal;
- local or remote certificate deployment;
- remote service reload commands;
- acme.sh core installation or upgrade to a selected tag;
- OpenSSH-to-Dropbear temporary key conversion;
- configuration import that overwrites current profiles;
- configuration export that includes secret values;
- certificate revoke, remove, or managed-object deletion.

These operations use the authorization flow defined below.

### Non-Waivable Security Invariants

The following are implementation responsibilities and must remain enforced even after the user authorizes an operation:

- read-only LuCI permissions cannot read private keys or invoke mutating backend subcommands;
- secrets are not written to task logs, command previews, process arguments, or browser responses unless the operation explicitly returns an export file;
- SSH host keys are verified and pinned; unknown or changed keys are never silently accepted;
- SSH user, host, port, paths, and option boundaries are validated so data cannot become client options;
- temporary key and PEM material uses a private per-task directory and is removed on success, failure, signal, and timeout;
- task and ledger writes are atomic and protected against concurrent modification;
- remote certificate and key replacement cannot expose a mismatched pair as the completed result;
- backend validation and authorization cannot be bypassed by directly calling RPC or the helper binary.

## Alternatives Considered

### Repeated Confirmation for Every Run

This is simple but creates confirmation fatigue and makes routine renew/deploy workflows unpleasant. It was rejected because the user explicitly wants a decision to persist.

### Authorization Flags Stored Inside Each Profile

This is convenient to render but mixes trust state with portable configuration. A copied profile could accidentally carry approval to another router, and edits could make stale approval difficult to reason about. It was rejected.

### Independent Authorization Ledger

The selected approach stores remembered decisions in a private backend ledger. Configuration remains portable, while authorization is router-local, operation-specific, revocable, and derived from material fields.

## Storage And Lifecycle

The backend stores remembered authorizations in:

```text
/etc/acmesh-console/authorizations.json
```

Requirements:

- `/etc/acmesh-console` mode is `0700`.
- `authorizations.json` mode is `0600`.
- The file is written through a same-directory temporary file followed by atomic rename.
- A lock serializes read-modify-write operations.
- The file is preserved across ordinary package upgrades and OpenWrt sysupgrade.
- Preservation is registered through the package conffile/sysupgrade mechanism rather than assumed from the path alone.
- The file is excluded from configuration export, import, backup bundles intended for migration, and diagnostic downloads.
- Restoring ordinary configuration on another router never restores remembered authorization.
- A router instance identifier is created locally and included in authorization fingerprinting. If the identifier changes, existing records no longer match.

If the ledger is malformed, the backend fails closed for remembered authorization: it retains a timestamped copy for diagnosis, starts with no active remembered decisions, and requires confirmation for subsequent operations. Read-only status remains available.

## Ledger Model

The file uses a versioned envelope:

```json
{
  "schemaVersion": 1,
  "instanceId": "router-local-random-id",
  "ackVersion": 1,
  "records": [
    {
      "id": "authorization-record-id",
      "operation": "deploy-run",
      "subjectType": "deployProfile",
      "subjectId": "deploy-123",
      "fingerprint": "sha256:...",
      "grantedAt": "2026-07-10T10:00:00Z",
      "lastUsedAt": "2026-07-10T11:00:00Z",
      "useCount": 3,
      "ackVersion": 1
    }
  ]
}
```

The ledger must not contain:

- DNS API tokens, passwords, or secret values;
- private key data or converted key data;
- certificate PEM content;
- arbitrary command output;
- a full configuration snapshot.

`subjectId` is for display and lifecycle cleanup. The fingerprint is the authority for matching.

## Canonical Fingerprints

The backend, not the browser, computes every fingerprint. It constructs a canonical typed object with stable field ordering, explicit nulls where semantically relevant, normalized domain and host names, normalized numeric ports, and no display labels. The serialized canonical form is hashed with SHA-256.

Secret values are excluded. Their identifiers and material routing fields remain included. Rotating a token for the same provider and target therefore does not cause a new business-risk prompt, while changing the provider or target does.

Cosmetic fields such as profile display name, description, and UI sort order are excluded.

### Issue And Renew

Fingerprint fields:

- operation (`issue`, `issue-deploy`, and `renew` are distinct);
- account profile identifier and selected CA/directory;
- normalized primary domain and complete SAN set;
- key type and key length;
- validation method;
- DNS provider API identifier;
- DNS alias/challenge alias and propagation behavior;
- webroot, standalone, or ALPN binding fields when applicable;
- linked deploy profile identifier; for `issue-deploy`, its current material fingerprint and deployment fields;
- explicit issue-profile test/real policy. Test mode itself does not require authorization.

`issue-deploy` is a single authorized operation when the operator chooses the
combined action. Its canonical snapshot contains the issue fields and the
linked deploy fields, and one admitted task performs issuance followed by
deployment. It must not call the independent `deploy-run` authorization after
issuance succeeds.

### Deploy

Fingerprint fields:

- operation and deployment type;
- source certificate identity and key variant;
- source type (issued certificate, file paths, or pasted PEM content digest);
- SSH host, port, user, and selected client;
- pinned SSH host-key algorithm and fingerprint;
- remote certificate, key, and chain paths;
- local destination paths for local install;
- reload command, sudo mode, and execution ordering;
- atomic replacement strategy and ownership/mode settings.

Private key content is not stored. Pasted certificate or key content contributes only a digest.

### Core Install And Upgrade

Fingerprint fields:

- operation (`install` and `upgrade` are distinct);
- normalized acme.sh home;
- selected official acme.sh tag;
- source repository identity;
- backup/rollback policy.

### SSH Key Conversion

Fingerprint fields:

- operation;
- digest of the original public identity derived from the private key;
- source format;
- target client and target format.

The converted private key is always temporary and is never represented by its path in a remembered record.

### Configuration Import And Secret Export

Import uses a digest of the complete validated import envelope plus the overwrite mode. Secret export uses a digest of the current exportable configuration and the export scope.

### Destructive Operations

Revoke, remove, and delete include the operation, object identifier, certificate/domain identity, and relevant variant. They are one-time authorizations only and are never written as persistent ledger records.

## Backend Authorization Protocol

### Prepare

The frontend submits a structured operation request. The backend:

1. validates all fields and resolves referenced profiles;
2. creates the canonical operation snapshot;
3. computes the fingerprint and risk summary;
4. checks for a matching remembered record;
5. either starts the operation or returns an authorization challenge.

Example challenge response:

```json
{
  "ok": false,
  "authorizationRequired": true,
  "challengeId": "random-single-use-id",
  "expiresAt": "2026-07-10T10:05:00Z",
  "fingerprint": "sha256:...",
  "operation": "deploy-run",
  "subject": {
    "type": "deployProfile",
    "id": "deploy-123",
    "name": "ocserv production"
  },
  "riskSummary": {}
}
```

Challenges expire after five minutes and are single-use. They contain or reference the validated canonical snapshot on the backend; a browser-supplied fingerprint alone is never trusted.

Challenge snapshots live only under a mode-`0700` runtime directory such as `/var/run/acmesh-console/authorization-challenges/`. Each challenge file is mode `0600`, contains no plaintext secret value, and is not preserved across reboot.

### Execute Once

The user chooses "Run once". The frontend submits the challenge identifier and explicit acknowledgement. The backend locks authorization state, reloads current profiles, recomputes the operation, verifies the challenge and fingerprint, consumes the challenge, and executes. No persistent record is created.

### Execute And Remember

The user chooses "Run and remember". The backend performs the same revalidation, atomically adds or replaces the matching ledger record, consumes the challenge, and starts the operation. If record persistence fails, execution does not begin.

### Reuse

For a matching remembered authorization, the backend increments `useCount`, updates `lastUsedAt`, and executes without displaying a modal. Usage accounting failure must not produce an untracked execution: ledger update and operation admission occur under the same lock and explicit error handling.

### Time-Of-Check/Time-Of-Use Protection

Immediately before task creation, the backend resolves all references and recomputes the canonical fingerprint. A changed profile, account, deploy target, host key, or acknowledgement version invalidates the challenge or remembered record and returns a new authorization requirement.

## Operation Matrix

| Operation | Test mode | Run once | Remember allowed | Special rule |
| --- | --- | --- | --- | --- |
| Status, logs, preview | No prompt | N/A | No | Read-only ACL only |
| DNS configuration validation | No prompt | N/A | No | Must not call provider mutation APIs |
| Real issue | N/A | Yes | Yes | CA and all domains shown |
| Real issue and deploy | N/A | Yes | Yes | One challenge covers issuance and linked deployment |
| Real renew | N/A | Yes | Yes | Separate operation from issue |
| Local deploy | N/A | Yes | Yes | Destination paths and reload shown |
| Remote SSH deploy | N/A | Yes | Yes | Host key must already be pinned or confirmed in flow |
| Core install | N/A | Yes | Yes | Scoped to selected tag and home |
| Core upgrade | N/A | Yes | Yes | Scoped to selected tag and home |
| SSH key conversion | N/A | Yes | Yes | Temporary output always deleted |
| Config import overwrite | N/A | Yes | No | Scoped to current import digest |
| Export with secrets | N/A | Yes | Yes | Authorization changes with config digest |
| Revoke, remove, delete | N/A | Yes | No | Always one-time |

An issue profile's explicit test-mode policy generates and validates the
acme.sh command but performs no real ACME request, DNS mutation, deployment,
or remote reload. It never consumes or creates an authorization.

## LuCI Interaction

### Confirmation Dialog

The dialog shows only material, human-readable fields:

- operation and mode;
- domain list, CA, and key type;
- DNS provider name without secret values;
- source certificate;
- SSH target, port, user, pinned host-key fingerprint;
- destination paths;
- reload command and privilege mode;
- core home and selected tag;
- expected impact and rollback availability.

Secrets are represented as configured/not configured and are never displayed in the summary.

The acknowledgement text is:

> 插件将严格按照上方参数执行操作。继续即表示您已核对并接受证书签发配额、远端文件覆盖、服务重载及目标系统配置产生的结果。

Buttons:

- `Cancel`
- `Run once`
- `Run and remember`

Destructive one-time operations omit `Run and remember`.

### Remembered State

An operation with a matching record shows an `Authorized` state near its primary action. Clicking the primary action executes immediately. The state includes a link to authorization records but does not add another prompt.

If material fields change, the state disappears immediately after save and the next execution requires authorization. Cosmetic renaming does not invalidate it.

### Authorization Records Page

Configuration migration remains a tab within Operations. Add a sibling `Authorization records` tab containing a table with:

- operation;
- subject name and type;
- summarized scope without secrets;
- granted time;
- last-used time;
- use count;
- status (`Active`, `Stale`, or `Unsupported`);
- revoke action.

The page supports `Revoke all`. Revocation itself is an ordinary authenticated settings action; it does not require a risk authorization. Stale and unsupported records cannot execute and may be removed.

## SSH Host-Key Policy

Unknown SSH hosts produce a dedicated host-identity challenge showing host, port, key algorithm, and fingerprint. The user may cancel or confirm and pin. Confirmation stores the host key in a console-owned private `known_hosts` file.

The deploy authorization fingerprint includes the pinned host-key identity. A changed host key is a hard stop, invalidates remembered deployment authorization, and requires a separate explicit replacement of the pinned identity before deployment can be authorized again.

There is no `-y`, `StrictHostKeyChecking=no`, automatic acceptance, or equivalent bypass in production deployment.

## Invalidation Rules

A remembered authorization becomes non-matching when:

- any operation-specific material field changes;
- the acknowledgement text contract increments `ackVersion`;
- the pinned SSH host key changes or disappears;
- a referenced account, issue profile, deploy profile, or certificate is deleted or replaced;
- the local router instance identifier changes;
- the ledger schema version is unsupported;
- canonicalization rules change in a way that increments their version.

Changing a secret value alone does not invalidate authorization when provider, target, and routing semantics are unchanged. Changing a display name, description, or UI order also does not invalidate it.

Profile save and delete operations should proactively mark affected records stale for display. Runtime matching still relies on recomputed fingerprints, so missed cleanup cannot authorize a changed operation.

## Failure, Concurrency, And Recovery

- Ledger and task-state updates use private same-directory temporary files and atomic rename.
- A lock directory or equivalent OpenWrt-compatible lock protects challenge consumption and ledger updates.
- Duplicate submissions of a consumed challenge fail without starting a second task.
- A crash after task admission must leave enough durable state to mark the task interrupted on the next backend startup.
- Corrupt ledgers are retained as `authorizations.json.corrupt.<timestamp>` with mode `0600`.
- Expired and consumed challenges are periodically removed.
- Temporary SSH conversion and PEM directories are unique per task and cleaned through traps.
- A failed remote deploy reports which stage failed and whether rollback completed; success is never reported for a partially replaced pair.

## Command-Line Behavior

The helper binary follows the same backend policy as LuCI. Interactive stdin is not assumed.

- `--acknowledge-risk <challenge-id>` executes once.
- `--remember-authorization <challenge-id>` executes and stores authorization.
- A non-interactive dangerous call without a matching remembered record returns a structured authorization-required result and a non-zero exit status.
- There is no global `--yes`, `--force-all`, or disable-confirmations switch.
- Direct backend subcommands cannot supply their own fingerprint or claim that authorization exists.

Secret-bearing data is supplied through a mode-`0600` input file, stdin, or an equivalent non-argv channel and is removed after parsing. It is not embedded in `ps`-visible arguments.

## ACL Requirements

RPC permissions are split by capability:

- read-only status and masked logs;
- profile/configuration write;
- task execution;
- core management;
- secret export;
- authorization record management.

Read access does not grant generic `file.exec` over the whole helper and does not grant direct read access to `/etc/acme`, `/etc/acmesh-console`, private keys, raw domain configuration, or unmasked task files.

Every helper command performs its own authorization and input validation because ACL is defense in depth, not the business-authorization mechanism.

## Migration And Versioning

Configuration migration exports a versioned `.tar.gz` archive rather than a JSON-only envelope. The archive includes the ACME home, console configuration files, and the UCI package configuration. An explicit export option adds only the local certificate/key files referenced by deploy profiles; it does not add the complete `/etc/ssl` tree or SSH remote targets. It excludes:

- `authorizations.json`;
- router instance identifier;
- pinned trust decisions unless separately exported through an explicit trust-store feature;
- task history;
- temporary or converted keys.

The migration archive must be fully listed and schema-validated before preview or execution. Archive paths are restricted to the supported roots, and absolute paths, traversal, symlinks, hard links, devices, and other special files are rejected. Preview is bound to a digest of the exact uploaded bytes. Import execution rejects a stale preview, unsupported version, malformed manifest, invalid configuration, or changed upload.

`ackVersion`, ledger `schemaVersion`, and canonicalization version are explicit independent values. Unsupported versions fail closed instead of being guessed.

## Acceptance Criteria

### Authorization Behavior

1. Test mode runs without a prompt and performs no external mutation.
2. `Run once` starts exactly one matching task and creates no ledger record.
3. `Run and remember` starts one task and subsequent identical operations do not prompt.
4. Changing any documented material field requires a new authorization.
5. Changing only display metadata does not require a new authorization.
6. A five-minute-old or previously consumed challenge cannot execute.
7. A direct RPC or CLI call cannot bypass backend authorization.

### Security Regression

1. An unknown host key cannot be silently accepted.
2. A changed pinned host key hard-stops deployment.
3. DNS tokens, private keys, and PEM contents do not appear in logs, task state, command previews, argv, or authorization records.
4. Read-only LuCI credentials cannot read certificate private keys or invoke mutating helper commands.
5. Temporary sensitive files have private permissions, unique paths, and are removed on every exit path.
6. Concurrent authorization submissions cannot duplicate task admission or corrupt the ledger.
7. Remote deployment cannot report success with a mismatched certificate/key pair.

### Persistence And Migration

1. Ledger mode is `0600` and parent directory mode is `0700`.
2. Same-router package upgrade and sysupgrade preserve the ledger and instance identifier.
3. Config migration never transports authorization records or the router instance identifier.
4. Moving configuration to another router requires fresh authorization.
5. Corrupt or unsupported ledgers fail closed while status remains usable.

### Interface

1. Risk summaries show exact domains, CA, host, destination paths, and reload command without secrets.
2. Destructive operations do not offer permanent remembrance.
3. Active authorizations are visible and individually revocable.
4. `Revoke all` immediately prevents reuse of every remembered record.
5. LuCI and CLI produce the same authorization decision for the same canonical operation.

Tests must include backend behavioral tests, malformed input tests, concurrency tests, router integration tests, and browser-level LuCI flows. String-marker tests alone are not sufficient evidence.

## Rollout Order

1. Repair non-waivable foundations: ACL split, secret transport/masking, host-key verification, validated SSH boundaries, private temporary files, atomic task state, and pair-safe deployment.
2. Add canonical operation snapshots, router instance identity, challenge storage, and the authorization ledger backend.
3. Apply authorization to issue, renew, deploy, core operations, conversion, import/export, and destructive actions.
4. Add the LuCI confirmation dialog, authorized-state display, and Authorization records tab.
5. Add CLI parity and migration exclusions.
6. Add behavioral, concurrency, router, and browser acceptance coverage.

The authorization feature must not be enabled for real operations until rollout step 1 is complete. Remembered consent is not a substitute for the security invariants that make approved execution faithful and bounded.
