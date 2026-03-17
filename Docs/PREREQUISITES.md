# Prerequisites — TACE.Oracle.Admin

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
| `OracleService*` Windows services | `Get-OracleDatabaseList`, `Set-OracleEnv` (Windows) | Installed by Oracle Database or Client |
| `/etc/oratab` | `Get-OracleDatabaseList` (Linux) | Created by Oracle installer |
| `ora_pmon_<SID>` process | `Get-OracleDatabaseList` (Linux) | Running Oracle instance |

No Oracle binaries (`sqlplus`, `rman`, `mkstore`, `orapki`) are required at Stage 1.
Future functions may introduce binary dependencies — they will be documented here.

## Environment Setup

`Set-OracleEnv` sets `ORACLE_SID`, `ORACLE_HOME`, and `ORACLE_BASE` in the current
session from values discovered via the platform's instance discovery mechanism.
PATH is not modified — that is managed by the profile.

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
| Windows 11 / Windows Server | Supported — discovery via `Win32_Service` |
| Linux | Supported — discovery via `/etc/oratab` and `ora_pmon` process check |
| macOS | Not supported |

## Known Limitations

- Windows: instance discovery relies on `OracleService*` Windows service naming convention.
  Oracle installations that use non-standard service names will not be detected.
- Linux: instance discovery relies on `/etc/oratab`. Instances not registered in oratab
  will not be detected.
- `Set-OracleEnv` sets `ORACLE_SID`, `ORACLE_HOME`, and `ORACLE_BASE` for the current
  session only. Changes do not persist across sessions or affect other processes.
