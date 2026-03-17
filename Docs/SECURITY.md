# TACE.Oracle.Admin — Security Reference

## Status

| Field | Value |
|---|---|
| Version | 0.1.5 |
| Last audit | 2026-03-17 |
| Findings resolved | 0 |
| Unit tests | 107 (all passing) |
| Open SEC items | None |

---

## Security Mechanisms

### 1. No Credential Handling

**Status:** N/A — this module does not handle passwords or credentials.

**Why:** `Get-OracleDatabaseList` and `Set-OracleEnv` operate on Windows services
and environment variables only. No Oracle connection is made, no password is
required, and no credential material exists in the module at Stage 1.

**Contract:** If future functions require credentials, they must use `[SecureString]`
parameters and follow the credential handling standards defined in `dev/.claude/CLAUDE.md`.

---

### 2. Environment Variable Isolation

**Status:** Implemented at Stage 1.

**Why:** `Set-OracleEnv` sets `$env:ORACLE_SID`, `$env:ORACLE_HOME`, and
`$env:ORACLE_BASE` in the current session only. No child processes are spawned,
no persistent config is written, and no other session or process is affected.

**Contract:** `Set-OracleEnv` must never write `ORACLE_SID`, `ORACLE_HOME`, or
`ORACLE_BASE` to disk, to the registry, or to any external process environment.
Session-only, always.

---

### 3. Input Validation

**Status:** Implemented at Stage 1.

**Why:** `Set-OracleEnv` validates any supplied SID against the set of
`OracleService*` Windows services before setting it. Arbitrary strings cannot
be injected as `ORACLE_SID`.

**Contract:** The SID allowlist is always derived at runtime from Windows
service discovery — never from a hardcoded list or user-supplied config file.

---

### 4. Output Scrubbing

**Status:** Implemented at Stage 1 (trivially — no credentials exist).

**Contract:** `Message` on every return object must be safe to write to a log.
At Stage 1, all `Message` values contain only SID names, counts, and status
strings. No sensitive data is present on any code path.

---

## Open Items

None at Stage 1.

---

## Audit Record

| Date | Version | Findings | Resolution |
|---|---|---|---|
| 2026-03-11 | 0.1.0 | None | Initial scaffold review — no credential handling, no external processes, input validated against service discovery. |
| 2026-03-13 | 0.1.3 | None | Environment variable derivation review — `ORACLE_HOME` and `ORACLE_BASE` derived from Win32_Service PathName. No credential handling added; session-only contract unchanged. |
| 2026-03-17 | 0.1.5 | None | Verbose display change review — `ORACLE_HOME`/`ORACLE_BASE` `Write-Host` lines gated on `$VerbosePreference`. No credential handling; no new child processes; session-only contract unchanged. |
| 2026-03-13 | 0.1.4 | None | Multi-platform discovery review — Linux path reads `/etc/oratab` and checks `ora_pmon` process. No credential handling; no child processes spawned; session-only contract unchanged. |

---

## Code Signing Guidance

| Context | Execution Policy | Files to Sign |
|---|---|---|
| Interactive dev | RemoteSigned | None required for local files |
| Shared/production | AllSigned | `TACE.Oracle.Admin.psm1`, `TACE.Oracle.Admin.psd1`, all `Public\*.ps1` |

Sign with: `Set-AuthenticodeSignature -FilePath <file> -Certificate <cert>`

---

## STIG Compliance

| Control | Requirement | Status |
|---|---|---|
| APSC-DV-000160 | No plaintext credential storage | Compliant — no credentials at Stage 1 |
| APSC-DV-002000 | Explicit parameter validation | Compliant — `[ValidateNotNullOrEmpty()]` on SID; SID allowlisted at runtime |
| APSC-DV-002560 | Scrub exception messages before re-throw | Compliant — no credential data can appear in exceptions |
| APSC-DV-003235 | No hardcoded credentials or connection strings | Compliant — none present |
| WN22-CC-000460 | Safe under script block logging | Compliant — no plaintext in any logged expression |
| WN22-CC-000470 | No credential-bearing pipeline output | Compliant — no credentials at Stage 1 |
| WN22-CC-000480 | Requires PS 7.0+ | Compliant — `#Requires -Version 7.0` on all files |
