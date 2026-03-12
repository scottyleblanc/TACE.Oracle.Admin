# TACE.OracleAdmin

## Overview

TACE.OracleAdmin is a PowerShell Core 7+ module that provides Oracle database
administration utilities for Windows environments. It focuses on environment
management and DBA tooling — discovering Oracle instances on the local host,
setting the active session context, and (in future stages) additional
administration functions. It is designed for both interactive DBA use and
scripted automation.

## Prerequisites

See [PREREQUISITES.md](PREREQUISITES.md) for full details.

- PowerShell 7.0 or later
- Windows (Windows Service discovery via `Get-Service`)
- Oracle 19c client or server installation (for `Set-OracleEnv` to be useful)

## Installation

During development, import by path:

```powershell
Import-Module <path-to-module>\OracleAdmin.psd1 -Force
```

The profile at `profile.ps1` imports this module automatically on session start.

## Functions

| Function | Description |
|---|---|
| `Get-OracleDatabaseList` | Discovers Oracle database instances on the local host via `OracleService*` Windows services. Returns SID, Status, and ServiceName for each instance. |
| `Set-OracleEnv` | Sets `ORACLE_SID` for the current session to a validated Oracle instance. Prompts interactively when no SID is supplied. Returns a standard `PSCustomObject`. |
| `Invoke-OraEnv` | Interactive terminal wrapper for `Set-OracleEnv`. Suppresses the return object for clean terminal output; writes `[ERROR]` to host on failure. Target of the `oraset` and `oraenv` aliases. Not intended for scripted use — use `Set-OracleEnv` directly in automation. |

## Aliases

| Alias | Target | Purpose |
|---|---|---|
| `oraset` | `Invoke-OraEnv` | Interactive shorthand — sets `ORACLE_SID` with clean output |
| `oraenv` | `Invoke-OraEnv` | Alternative interactive shorthand |

## Output Contract

Every public function returns a `PSCustomObject` with exactly this shape:

```powershell
[PSCustomObject]@{
    Success = [bool]     # $true if the operation completed as intended
    Data    = $null      # payload object, array, or $null for void operations
    Message = [string]   # human-readable status — always safe to log
}
```

Callers must check `Success` before consuming `Data`. `Message` is always safe
to write to a log file — it will never contain passwords or credential values.

## Error Handling

- **Terminating throw**: unrecoverable failures (e.g. module load failure for a
  required helper).
- **Success=$false**: expected, handleable outcomes (e.g. SID not found, no
  Oracle services present, invalid menu selection). The caller can inspect
  `Message` and decide how to proceed.

## Logging and Diagnostics

Verbose output follows this format:

```
[FunctionName] Message text here
[FunctionName] ACTION on TARGET at UTC-TIMESTAMP
```

Run with `-Verbose` to see audit-level detail. Verbose output never contains
passwords, credential values, or sensitive path fragments.

## Current Security State

| Field | Value |
|---|---|
| Version | 0.1.1 |
| Last audit | 2026-03-11 |
| Tests | 52 unit tests (all passing) |
| Open SEC items | None at Stage 1 |

See [SECURITY.md](SECURITY.md) for the full security reference.

## AI-Assisted Development and Support

This module was developed by TACE as a generic, reusable artifact. AI tooling was used during development
as part of TACE's standard engineering practice.

Once this module has been adopted and integrated into your environment, any AI-assisted
activity involving it — including troubleshooting, triage, incident response, or code
modification — should be conducted through your organization's enterprise AI tooling.

At that point, interactions with the module will occur in the context of your specific
infrastructure, and the data governance protections of an enterprise AI account apply.

Using personal or consumer-tier AI accounts for support work involving deployed modules
introduces data handling risks that are outside TACE's control and may conflict with your
organization's own data governance obligations.

## Contributing

- Build task list: [TODO.md](TODO.md)
- Version history: [CHANGELOG.md](CHANGELOG.md)
- Commit and release conventions: [VERSIONING.md](VERSIONING.md)
- License: [LICENSE](../LICENSE)
