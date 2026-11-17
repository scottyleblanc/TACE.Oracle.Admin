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
| Unit | `.\Scripts\Invoke-UnitTest.ps1` | Builds the module, then `Tests\Unit\` — functions run against mocks, imported from the built module. Measures coverage per source file and fails below the floor (rule T-12); `-Verbose` lists each missed command by source line |

Run a single test file, after building once:
```powershell
.\Scripts\Build-Module.ps1
Invoke-Pester -Path .\Tests\Unit\Public\Set-OracleEnv.Tests.ps1
```

A unit test file run without a build fails at once with an instruction to build. Do not
run `Invoke-Pester -Path .\Tests\` to run the unit tests: it recurses into
`Tests\Static\` and mixes the tiers.

No unit test requires a live Oracle instance. All Oracle service calls are mocked.

### Integration tier (local only)

`.\Scripts\Invoke-IntegrationTest.ps1` runs `Tests\Integration\` against a real Oracle
database on this machine, with OS authentication. It is never run by the pre-push hook;
`.\Scripts\Invoke-Gate.ps1 -Integration` runs it after the gate.

The tests take control file backups into a test folder and run `DELETE OBSOLETE`, which
acts on the whole database. Only use a database that may lose backups.

Setup, once per machine:

1. Copy `Tests\Integration\IntegrationConfig.local.example.ps1` to
   `IntegrationConfig.local.ps1` in the same folder. It is gitignored. Fill in this
   host's name, the Oracle home, the SID and the test folder.
2. Create the test folder by hand.
3. Your Windows account must be able to connect with `rman target /`, normally through
   membership of the `ORA_DBA` group.

Before each run, in the same session:

```powershell
$env:ORACLE_ADMIN_RUN_INTEGRATION = '1'
.\Scripts\Invoke-IntegrationTest.ps1
```

Five guards run before any test: the host is on the allowlist, the opt-in variable is
set, the local configuration is complete, the database name matches no production
pattern, and the test folder exists. A failed guard fails the run and names the guard.

Each run writes `Tests\Integration\LastRun.json`, the evidence a pull request carries
(rule T-14). It is evidence only when the run passed on a clean working tree. Commit
your changes first, run the tier, then commit `LastRun.json` on its own as the last
commit of the branch.

## The Gate

`.\Scripts\Invoke-Gate.ps1` runs every static check in one command and exits 1 if any
fails (decision 28):

| Check | What it runs |
|---|---|
| tools | PSScriptAnalyzer 1.25.0, gitleaks 8.30.1, Pester 5 and git are installed |
| analyzer | PSScriptAnalyzer, built-in and custom rules, over `Source\`, `Scripts\` and `Tests\Lint\` |
| static | The static tier |
| secrets | gitleaks over the working tree (`.gitleaks.toml`) |
| commits | gitleaks over every commit not yet on a remote |
| messages | Those commits' messages, through gitleaks and the S-16 patterns |

Two switches add the test tiers, after the six checks (decision 31):

| Switch | Check | What it runs |
|---|---|---|
| `-Unit` | unit | The unit tier with its coverage floor. CI passes this from Stack 4 |
| `-Integration` | integration | The integration tier, behind its own guards (see above) |

The pre-push hook passes neither, so a push runs only the six checks.

`-Base <branch>` is for pull requests. In CI every commit is already on a remote, so
`commits` and `messages` check the commits in `<branch>..HEAD` instead, and two more
checks run:

| Check | What it runs |
|---|---|
| evidence | Rule T-14: when the pull request changes `Source\`, `Tests\Integration\LastRun.json` shows `Evidence = true` for a commit HEAD contains, and only that file changed since |
| review | Decision 35: when the pull request changes any file other than the two evidence files, `Review\LastReview.json` shows a completed review from the merge base, of a commit HEAD contains, with only the evidence files changed since and every finding answered |

### Review

`.\Scripts\Invoke-ModelReview.ps1` runs the second-model review (`Docs\REVIEW.md`). It
needs Claude Code (`claude`) on `PATH`, signed in; tested with 2.1.308. It runs on the
author's machine, not in CI, and costs a few US dollars per review at the default model
and effort; `-MaxBudgetUsd` caps it (default 10). Run it after the gate passes and every
change is committed, and before the integration run.

### CI

`.github\workflows\gate.yml` runs on every pull request into `master`, on a Windows
runner. It calls `.\Scripts\Install-GateTool.ps1`, which installs the pinned tool
versions (the gitleaks zip is checked against a pinned SHA-256), then
`.\Scripts\Invoke-Gate.ps1 -Unit -Base origin/master`. The workflow holds no logic of its
own and no secrets, and its token is read-only.

Turn on the pre-push hook once in each clone, so the gate runs before every push:

```powershell
git config core.hooksPath .githooks
```

`.\Scripts\Test-SeededDefect.ps1` proves the gate works: in a temporary copy of the
repository it plants a lint violation, secrets, a behaviour defect, a secret in a
commit message that is already on a remote, stale integration evidence, and a review
record that is missing, from the wrong base, unanswered or stale, and checks that the gate fails on each with
the expected check. It takes about fifteen minutes.

`.\Scripts\Test-InvariantMutation.ps1` proves the tests prove the invariants (rule I-10):
for each mutation in `Tests\Mutation\InvariantMutations.psd1` it breaks one invariant in
a temporary copy, builds the module and runs the cited tests, which must fail. It refuses
to run when a security invariant with a cited proof has no mutation. It takes several
minutes and is not part of the gate. `-Function` limits it to named functions.

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
