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

| `rman.exe` under `ORACLE_HOME\bin` | `Get-RmanBackupStatus`, `Remove-RmanObsoleteBackup` | Oracle Database installation |
| `tnsping.exe` under `ORACLE_HOME\bin` | The RMAN functions, when `-WalletAlias` is used | Oracle Database or Client installation |

The environment functions need no Oracle binaries. The RMAN functions, added at
Stack 0 (v0.2.0) and not on PSGallery, need the two above. `sqlplus`, `mkstore` and `orapki` are
not used.

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

The RMAN functions are written for Windows and are untested on Linux.

## Known Limitations

- Windows: instance discovery relies on `OracleService*` Windows service naming convention.
  Oracle installations that use non-standard service names will not be detected.
- Linux: instance discovery relies on `/etc/oratab`. Instances not registered in oratab
  will not be detected.
- `Set-OracleEnv` sets `ORACLE_SID`, `ORACLE_HOME`, and `ORACLE_BASE` for the current
  session only. Changes do not persist across sessions or affect other processes.
- The RMAN functions read `ORACLE_HOME` from `Config\OracleBackup.json` in the module
  folder, falling back to `$env:ORACLE_HOME`. The function that sets that value in the
  backup module was not brought across, so the file must be edited by hand.
- The RMAN functions have unit tests only in this repo. They have not been run here
  against a live database.
