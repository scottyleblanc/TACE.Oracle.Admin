# Prerequisites — TACE.OracleAdmin

## Language Version

| Requirement | Value |
|---|---|
| Minimum | PowerShell 7.0 |
| Tested against | PowerShell 7.4 LTS |

All `.ps1` files carry `#Requires -Version 7.0`. The module will not load on
Windows PowerShell 5.1.

## External Tools

| Tool | Required by | Source |
|---|---|---|
| `OracleService*` Windows services | `Get-OracleDatabaseList`, `Set-OracleEnv` | Installed by Oracle Database or Client |

No Oracle binaries (`sqlplus`, `rman`, `mkstore`, `orapki`) are required at Stage 1.
Future functions may introduce binary dependencies — they will be documented here.

## Environment Setup

`Set-OracleEnv` sets `ORACLE_SID` in the current session. `ORACLE_HOME` and PATH
must be pre-configured in the profile (via `profile.local.ps1`). The module does
not set `ORACLE_HOME`.

## Test Framework

| Requirement | Value |
|---|---|
| Framework | Pester 5.x |
| Minimum version | 5.0 |
| Install | `Install-Module Pester -MinimumVersion 5.0 -Force` |

Run all unit tests:
```powershell
Invoke-Pester -Path .\Tests\
```

Run a single test file:
```powershell
Invoke-Pester -Path .\Tests\Set-OracleEnv.Tests.ps1
```

No test requires a live Oracle instance. All Oracle service calls are mocked.

## Execution Policy

| Context | Minimum policy |
|---|---|
| Interactive dev (local files) | `RemoteSigned` |
| Shared / production deployment | `AllSigned` |

## Platform Support

| Platform | Status |
|---|---|
| Windows 11 / Windows Server | Supported |
| Linux | Not supported — depends on Windows `Get-Service` |
| macOS | Not supported — depends on Windows `Get-Service` |

## Known Limitations

- Instance discovery relies on `OracleService*` Windows service naming convention.
  Oracle installations that use non-standard service names will not be detected.
- `Set-OracleEnv` sets `ORACLE_SID` for the current session only. It does not
  persist across sessions or affect other processes.
