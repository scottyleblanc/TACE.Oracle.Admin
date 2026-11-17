# TACE.Oracle.Admin

## Overview

TACE.Oracle.Admin is a PowerShell Core 7+ module that provides Oracle database
administration utilities for Windows and Linux environments. It focuses on
environment management and DBA tooling — discovering Oracle instances on the
local host, setting the active session context, and (in future stages) additional
administration functions. It is designed for both interactive DBA use and
scripted automation.

## Prerequisites

See [PREREQUISITES.md](PREREQUISITES.md) for full details.

- PowerShell 7.6 or later
- Windows or Linux
- Oracle 19c client or server installation (for `Set-OracleEnv` to be useful)
- Windows: instance discovery via `Win32_Service` (WMI)
- Linux: instance discovery via `/etc/oratab`

## Installation

During development, build from `Source\`, then import the built module by path:

```powershell
.\Scripts\Build-Module.ps1
Import-Module .\Output\TACE.Oracle.Admin\<version>\TACE.Oracle.Admin.psd1 -Force
```

The files under `Source\` are not importable on their own: the build merges them into one
`.psm1` and generates the manifest's export lists (rules C-28 to C-30).

The profile at `profile.ps1` imports this module automatically on session start.

## Functions

| Function | Description |
|---|---|
| `Get-OracleDatabaseList` | Discovers Oracle database instances on the local host. Windows: via `Win32_Service` (WMI). Linux: via `/etc/oratab`. Returns SID, Status, ServiceName, OracleHome, and OracleBase for each instance. |
| `Set-OracleEnv` | Sets `ORACLE_SID`, `ORACLE_HOME`, and `ORACLE_BASE` for the current session from a validated Oracle instance. With several instances and no `-SID`, returns `Success = $false` and lists them. Never prompts and never writes to the host. Returns a standard `PSCustomObject`. |
| `Invoke-OraEnv` | Interactive terminal wrapper for `Set-OracleEnv`. Shows a numbered menu when several instances are present, prints the result, and with `-Verbose` prints `ORACLE_HOME` and `ORACLE_BASE`; writes `[ERROR]` to host on failure. Target of the `oraset` and `oraenv` aliases. Not intended for scripted use — use `Set-OracleEnv` directly in automation. |
| `Get-RmanBackupStatus` | Added in v0.2.0; not on PSGallery. Runs RMAN `LIST BACKUP SUMMARY` and returns the most recent backup with `IsRecentDay` and `AgeHours`. Read-only. Windows only. |
| `Remove-RmanObsoleteBackup` | Added in v0.2.0; not on PSGallery. Runs RMAN `DELETE NOPROMPT OBSOLETE`. Destructive: `SupportsShouldProcess` with `ConfirmImpact = 'High'`; supports `-WhatIf`. Windows only. |

The two RMAN functions were copied from the Oracle backup module as working
examples for the AI Development Stack (see [STAGES.md](STAGES.md)). They support OS
authentication, a wallet alias (`-WalletAlias`) or a named credential (`-Credential`).

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

Under `-WhatIf`, or a declined `-Confirm`, a state-changing function changes nothing
and returns `Success = $true`, `Data.Applied = $false`, and a `Message` starting with
`WhatIf:`. A real run returns `Data.Applied = $true` (rule C-27).

## Error Handling

- **Terminating throw**: unrecoverable failures (e.g. module load failure for a
  required helper). Private helpers such as `Assert-OracleEnvironment` and
  `Invoke-RmanProcess` throw; the public RMAN functions catch, scrub the message
  and return `Success=$false`.
- **Success=$false**: expected, handleable outcomes (e.g. SID not found, no
  Oracle services present, several instances and no `-SID`). The caller can inspect
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
| Version | 0.2.5 |
| Last audit | 2026-11-16 — Stack 5 agent instructions: `AGENTS.md` is generated from `Docs\standards\` and checked by the gate; with and without it, every agent run ended on a passing gate |
| Tests | 405 unit tests, 163 static checks and 12 integration tests (all passing); coverage 97.7% (floor 95%); 0 analyzer findings |
| Open SEC items | 6 — see the Open Items in SECURITY.md |

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

Changes reach `master` only through a pull request, and the pull request merges only
when the gate passes in CI (`.github\workflows\gate.yml`; see the Gate section of
[PREREQUISITES.md](PREREQUISITES.md)). A change to `Source\` also needs current
integration evidence, which needs a local Oracle database.

- Build task list: [TODO.md](TODO.md)
- Version history: [CHANGELOG.md](CHANGELOG.md)
- Commit and release conventions: [VERSIONING.md](VERSIONING.md)
- License: [LICENSE](../LICENSE)
