# Prerequisites — TACE.Oracle.Admin

## Language Version

| Requirement | Value |
|---|---|
| Minimum | PowerShell 7.6 LTS |
| Tested against | PowerShell 7.6 LTS |

All `.ps1` files carry `#Requires -Version 7.6`. The module will not load on
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

## Build

The module is built from `Source\` into `Output\TACE.Oracle.Admin\<version>\` (rule
C-28). The build needs PowerShell 7.6 or later and nothing else. Packaging (`-Package`)
also needs `Microsoft.PowerShell.PSResourceGet` and git.

```powershell
.\Scripts\Build-Module.ps1            # build into Output\
.\Scripts\Build-Module.ps1 -Package   # build, then make and list a local .nupkg
```

`Output\` is not committed. The unit tier builds before it runs, so a separate build
is only needed to import the module by hand or to run one test file.

## Test Framework

| Requirement | Value |
|---|---|
| Framework | Pester 5.x |
| Minimum version | 5.0 |
| Install | `Install-Module Pester -MinimumVersion 5.0 -Force` |
| Analyzer | PSScriptAnalyzer 1.25.0, exactly (decision 25) |
| Install | `Install-PSResource PSScriptAnalyzer -Version 1.25.0` |
| Secret scanner | gitleaks 8.30.1, exactly. Runs locally; needs no account or network |
| Install | `winget install --id Gitleaks.Gitleaks --version 8.30.1 --exact` (Linux: the release binary) |

The analyzer settings are in `Tests\Lint\PSScriptAnalyzerSettings.psd1`. The analyzer
covers `Source\`, `Scripts\` and `Tests\Lint\`, but not the `*.Tests.ps1` files.
The settings load the custom rules in `Tests\Lint\PSScriptAnalyzerRules\` by a path
relative to the current directory, so run the analyzer from the repository root:

```powershell
Invoke-ScriptAnalyzer -Path .\Source -Recurse -Settings .\Tests\Lint\PSScriptAnalyzerSettings.psd1
```

The VS Code PowerShell extension bundles its own analyzer (1.24.0 at the time of
writing), so live editor results can differ slightly from the pinned version. The
committed `.vscode\settings.json` points the editor at the same settings file. It takes
effect only when this repository folder is opened as the workspace.

Each test tier has its own script (rule T-10). Each runs from any working directory,
writes NUnit XML results to `Tests\TestResults\<tier>.xml`, and exits 1 on any failure.

| Tier | Command | Runs |
|---|---|---|
| Static | `.\Scripts\Invoke-StaticTest.ps1` | `Tests\Static\` — checks that read source text only; the linters they call are in `Tests\Lint\` |
| Unit | `.\Scripts\Invoke-UnitTest.ps1` | Builds the module, then `Tests\Unit\` — functions run against mocks, imported from the built module |

Run a single test file, after building once:
```powershell
.\Scripts\Build-Module.ps1
Invoke-Pester -Path .\Tests\Unit\Public\Set-OracleEnv.Tests.ps1
```

A unit test file run without a build fails at once with an instruction to build. Do not
run `Invoke-Pester -Path .\Tests\` to run the unit tests: it recurses into
`Tests\Static\` and mixes the tiers.

No unit test requires a live Oracle instance. All Oracle service calls are mocked.

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
- The RMAN functions read `ORACLE_HOME` from `Config\OracleBackup.json` in the module's
  version folder, falling back to `$env:ORACLE_HOME`. A rebuild or an upgrade to a new
  version starts with no config file. The function that sets that value in the
  backup module was not brought across, so the file must be edited by hand.
- The RMAN functions have unit tests only in this repo. They have not been run here
  against a live database.
