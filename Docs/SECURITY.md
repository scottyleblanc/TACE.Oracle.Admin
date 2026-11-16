# TACE.Oracle.Admin — Security Reference

## Status

| Field | Value |
|---|---|
| Version | 0.2.3 |
| Last audit | 2026-11-16 — Stack 3 tests |
| Findings resolved | Stack 3: 12 security invariants whose cited tests passed with the invariant broken now have tests that fail; every invariant is proven by a test or a static check; no defect in the module's security behaviour was found |
| Unit tests | 405 (all passing); 160 static checks; 12 integration tests; coverage 97.7%; 0 analyzer findings; gitleaks clean |
| Open SEC items | 6 — see Open Items |

The RMAN functions added at Stack 0 (v0.2.0, not on PSGallery) were copied from
the Oracle backup module. Their security mechanisms are described below as built.
At Stack 1 every function was given an invariant block stating what must hold and
what enforces it; the defects that exposed are in the Audit Record.

---

## Security Mechanisms

### 1. Credential Handling

**Status:** Implemented at Stack 0 for the RMAN functions. Not applicable to
`Get-OracleDatabaseList`, `Set-OracleEnv` and `Invoke-OraEnv`, which make no Oracle
connection and take no credentials.

**Why:** `Get-RmanBackupStatus` and `Remove-RmanObsoleteBackup` connect to a
database through RMAN and support three authentication modes: OS authentication,
wallet alias, and a named credential.

**How:** Passwords are accepted only as `[PSCredential]` or `[SecureString]`.
Plaintext is extracted by `ConvertFrom-SecureStringToPlaintext`, called inline at
the point the value is written to the RMAN process's stdin. It is never assigned
to a variable.

**Contract:** No function accepts a plaintext password parameter. No password
appears in a process argument list. A wallet alias is a connection name, not a
credential, and may appear in the argument list.

---

### 2. Stdin-Only Injection

**Status:** Implemented at Stack 0.

**Why:** Process argument lists are visible to other users and to process logging.

**How:** `Invoke-RmanProcess` starts RMAN with redirected stdin. For a named
credential it starts RMAN with no target and writes the `CONNECT TARGET` statement
as the first stdin line, followed by the RMAN script.

**Contract:** Credentials reach Oracle tools through stdin only.

---

### 3. Child Process Environment Isolation

**Status:** Implemented at Stack 0.

**How:** `Invoke-RmanProcess` and `Invoke-TnspingProcess` set `ORACLE_HOME`,
`ORACLE_SID`, `PATH` and `NLS_DATE_FORMAT` on the child process's environment
collection only.

**Contract:** The RMAN functions never modify the current session environment.
Changing the session environment is the stated purpose of `Set-OracleEnv` alone
(see section 5).

---

### 4. Oracle Binary Validation

**Status:** Implemented at Stack 0.

**How:** `Assert-OracleEnvironment` resolves the binary from `ORACLE_HOME\bin`,
never from `PATH` alone, and checks that it exists. It checks the Authenticode
signature and fails on `HashMismatch` or `TrustFailure`, or when a valid signature
is not Oracle's. A wallet alias is resolved with `tnsping` before RMAN is started.

**Contract:** `ORACLE_HOME` from configuration or the environment is untrusted
input and is validated before use in any path or process start.

**Limit:** Oracle binaries are not signed. On a 21c home every binary checked (`rman.exe`, `tnsping.exe`, `sqlplus.exe`, `oracle.exe`) reports `NotSigned`,
so the signature check cannot tell a patched binary from a tampered one, and passes
both. It catches only a broken signature or a non-Oracle signer. Detecting a replaced
binary would need a recorded baseline; that is not built.

---

### 5. Session Environment Variables (`Set-OracleEnv`)

**Status:** Implemented at Stage 1.

**Why:** `Set-OracleEnv` sets `$env:ORACLE_SID`, `$env:ORACLE_HOME`, and
`$env:ORACLE_BASE` in the current session only. No child processes are spawned,
no persistent config is written, and no other session or process is affected.

**Contract:** `Set-OracleEnv` must never write `ORACLE_SID`, `ORACLE_HOME`, or
`ORACLE_BASE` to disk, to the registry, or to any external process environment.
Session-only, always.

---

### 6. Input Validation

**Status:** Implemented at Stage 1.

**Why:** `Set-OracleEnv` validates any supplied SID against the set of
`OracleService*` Windows services before setting it. Arbitrary strings cannot
be injected as `ORACLE_SID`.

**Contract:** The SID allowlist is always derived at runtime from Windows
service discovery — never from a hardcoded list or user-supplied config file.

**Wallet alias (Stack 2):** `-WalletAlias` on `Get-RmanBackupStatus` and
`Remove-RmanObsoleteBackup` accepts only letters, digits, `_`, `.` and `-`
(`ValidatePattern('^[A-Za-z0-9_.-]*\z')`). The alias is written into the
`CONNECT` line on RMAN's stdin and passed to tnsping, so a newline, `;`, space or
quote could otherwise add an RMAN command or an argument. The anchor is `\z`, not
`$`, because `$` also matches before a trailing newline. The tnsping check proves an
alias resolves; the pattern is what makes it safe to write. Invariants S6 and S10,
with tests.

**Every public parameter is validated:** rule C-10 is now checked by the analyzer
(decision 26), so a public parameter with no `[Validate*]` attribute fails the gate.

---

### 7. Output Scrubbing

**Status:** Implemented at Stack 0 for the RMAN functions; best-effort.

**How:** `Invoke-CredentialScrub` replaces the password in any
`user/password@service` pattern. `Invoke-RmanProcess` applies it to RMAN stdout,
stderr and exception messages before they are returned or re-thrown. The public
RMAN functions apply it again to exception text placed in `Message`.

**Contract:** `Message` on every return object must be safe to write to a log.
The primary defence is that credentials are never placed where they could be
echoed; the scrub is a second line, not a guarantee.

---

### 8. Configuration File Permissions

**Status:** Implemented at Stack 0 (Windows).

**How:** `Get-OracleBackupConfigStore` creates `Config\OracleBackup.json` on first
use and `Set-RestrictiveAcl` disables inheritance and grants access to the current
user and Administrators only. The file holds paths and defaults, not credentials.

**Contract:** Importing the module writes nothing to disk. The configuration file
is created only when an RMAN function first runs.

---

### 9. Confirmation on Destructive Operations

**Status:** Implemented at Stack 0.

**How:** `Remove-RmanObsoleteBackup` declares `SupportsShouldProcess` with
`ConfirmImpact = 'High'`. RMAN is run with `NOPROMPT`, so the PowerShell
confirmation is the only gate.

**Contract:** No function deletes backups without passing `ShouldProcess`.

---

## Open Items

Carried in with the code copied at Stack 0. See `audit\stack-0-baseline.md`.

- The binary signature check cannot detect a replaced Oracle binary, because Oracle
  binaries are unsigned. See section 4.
- `Invoke-CredentialScrub` covers one pattern (`user/password@service`). Other
  credential formats would pass through.
- `Set-RestrictiveAcl` changes file permissions without `ShouldProcess`. Decided in
  Stack 2: it only secures a path the module has just created, so it is never skipped
  by a caller's `-WhatIf` (invariant L1).
- No check compares this public repository against a list of private identifiers
  (Stack 2, deferred). The S-16 patterns and gitleaks catch values with a known shape
  and credentials. A real resource name, such as a bucket or host name, is caught only
  by review. The design of a private list affects every public repository, so it is
  decided across repositories first. The S3 staging bucket name is in this
  repository's history from before v0.2.1.
- The RMAN functions are Windows only. Off Windows they return `Success = $false`
  before touching the config or RMAN (rule C-07); Linux support is not built.
- The copied code has had the Stack 1 invariant review, not a STIG assessment. The
  STIG table below reflects the module before Stack 0.

---

## Audit Record

| Date | Version | Findings | Resolution |
|---|---|---|---|
| 2026-03-11 | 0.1.0 | None | Initial scaffold review — no credential handling, no external processes, input validated against service discovery. |
| 2026-03-13 | 0.1.3 | None | Environment variable derivation review — `ORACLE_HOME` and `ORACLE_BASE` derived from Win32_Service PathName. No credential handling added; session-only contract unchanged. |
| 2026-03-17 | 0.1.5 | None | Verbose display change review — `ORACLE_HOME`/`ORACLE_BASE` `Write-Host` lines gated on `$VerbosePreference`. No credential handling; no new child processes; session-only contract unchanged. |
| 2026-03-13 | 0.1.4 | None | Multi-platform discovery review — Linux path reads `/etc/oratab` and checks `ora_pmon` process. No credential handling; no child processes spawned; session-only contract unchanged. |
| 2026-11-14 | 0.2.1 | 14 (5 `[SEC]`) | Stack 1 invariant review of all 14 functions. `[SEC]`: catalog parameters let caller text into the RMAN script and accepted an unused credential (removed); `-WhatIf` could write the config file and run `tnsping` (gate moved first); an environment variable chose the config file (replaced by a test-only override); `tnsping.exe` is unsigned like every Oracle binary (accepted, documented in section 4). Nine others fixed, among them a `tnsping` that could hang its caller indefinitely and a timeout kill that left child processes running. Details in `CHANGELOG.md` 0.2.1 and `TODO.md` Stack 1. |
| 2026-11-15 | 0.2.2 | 3 (1 `[SEC]`) | Stack 2 deterministic checks. `[SEC]`: `-WalletAlias` reached the RMAN `CONNECT` line unvalidated (now `ValidatePattern` ending in `\z`). A caller's `-WhatIf` skipped creating the default config and its ACL, so a first run failed (writes pinned `-WhatIf:$false`; rule C-33 checks every such call). No check compares the repository against private identifiers (deferred, Open Items). gitleaks found nothing in the full history or the working tree. Details in `CHANGELOG.md` 0.2.2 and `Docs\audit\stack-2-seeded-defects.md`. |
| 2026-11-16 | 0.2.3 | 12 (12 `[SEC]`) | Stack 3 tests. Every security invariant's proof was broken on purpose in a copy of the repository: for 12, the cited tests still passed, through tests that compared the session environment with an already-polluted value, credential tests run with no credential, or code the test never reached. All fixed and proven by the mutation script; no defect was in the module's own security behaviour. One behaviour defect, introduced in this stack and not security-related, was found and fixed (`Invoke-OraEnv` with no instance). Integration tests against Oracle Database 21c XE pass. Details in `CHANGELOG.md` 0.2.3 and `Docs\audit\stack-3-*.md`. |

---

## Code Signing Guidance

| Context | Execution Policy | Files to Sign |
|---|---|---|
| Interactive dev | RemoteSigned | None required for local files |
| Shared/production | AllSigned | The built `TACE.Oracle.Admin.psm1` and `TACE.Oracle.Admin.psd1` in `Output\TACE.Oracle.Admin\<version>\`; the source files under `Source\` do not ship |

Sign with: `Set-AuthenticodeSignature -FilePath <file> -Certificate <cert>`

---

## STIG Compliance

Status as of v0.1.7, before the RMAN functions were added. To be re-assessed for
the credential-handling code during the AI Development Stack work.

| Control | Requirement | Status |
|---|---|---|
| APSC-DV-000160 | No plaintext credential storage | Compliant — no credentials at Stage 1 |
| APSC-DV-002000 | Explicit parameter validation | Compliant — `[ValidateNotNullOrEmpty()]` on SID; SID allowlisted at runtime |
| APSC-DV-002560 | Scrub exception messages before re-throw | Compliant — no credential data can appear in exceptions |
| APSC-DV-003235 | No hardcoded credentials or connection strings | Compliant — none present |
| WN22-CC-000460 | Safe under script block logging | Compliant — no plaintext in any logged expression |
| WN22-CC-000470 | No credential-bearing pipeline output | Compliant — no credentials at Stage 1 |
| WN22-CC-000480 | Requires PS 7.0+ | Compliant — `#Requires -Version 7.6` on all files (stricter than the STIG minimum) |
