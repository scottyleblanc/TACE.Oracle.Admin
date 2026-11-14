# Stack 0 — Baseline

The state of the test bed before any stack layer is built. Later stages are
measured against these numbers.

| Field | Value |
|---|---|
| Recorded | 2026-11-14 |
| Branch | `v0.2.0-dev` |
| PowerShell | 7.6.10 |
| Pester | 5.7.1 |
| PSScriptAnalyzer | 1.24.0, settings from `PSScriptAnalyzerSettings.psd1` |

## What was copied in

Three working examples from the Oracle backup module, with the private helpers
they depend on and their existing unit tests.

| Role | Function | Private helpers |
|---|---|---|
| Credential path | `Invoke-RmanProcess` (with `Invoke-CredentialScrub`) | `ConvertFrom-SecureStringToPlaintext`, `Assert-OracleEnvironment` (with `Invoke-TnspingProcess`) |
| Read-only | `Get-RmanBackupStatus` | `ConvertFrom-RmanListBackup` |
| State-changing | `Remove-RmanObsoleteBackup` | `Get-OracleBackupConfigStore`, `Set-RestrictiveAcl` |

Source files were copied unchanged, with one exception. `Get-RmanBackupStatus`
read its configuration from a module-level cache that the backup module fills at
import. It now calls `Get-OracleBackupConfigStore` directly, as
`Remove-RmanObsoleteBackup` already did, so importing this module still writes
nothing to disk.

Test files were changed only to refer to this module's name and manifest.

## Size

| Area | Lines |
|---|--:|
| Module code (`Public\`, `Private\`, root module, manifest) | 1,883 |
| Unit tests (`Tests\`) | 3,847 |

## Unit tests

| | Passed | Failed |
|---|--:|--:|
| Before the copy | 117 | 0 |
| After the copy | 291 | 0 |

## Analyzer findings

74 findings: 4 in module code, 70 in test files. Before the copy there were 4,
all in test files.

| Rule | Severity | Module code | Tests |
|---|---|--:|--:|
| `PSReviewUnusedParameter` | Warning | 0 | 20 |
| `PSAvoidUsingPositionalParameters` | Information | 3 | 16 |
| `PSAvoidUsingConvertToSecureStringWithPlainText` | Error | 0 | 16 |
| `PSAvoidUsingPlainTextForPassword` | Warning | 0 | 15 |
| `PSUseDeclaredVarsMoreThanAssignments` | Warning | 0 | 2 |
| `PSUseShouldProcessForStateChangingFunctions` | Warning | 1 | 1 |

Module code findings:

- `Private\Assert-OracleEnvironment.ps1` lines 149 and 175 — positional parameters
- `Private\Get-OracleBackupConfigStore.ps1` line 47 — positional parameters
- `Private\Set-RestrictiveAcl.ps1` line 41 — state-changing function without `ShouldProcess`

## Known gaps, recorded and not fixed

These are left in place on purpose. They are what the stack layers should find.

- **Analyzer not installed.** PSScriptAnalyzer is not installed as a PowerShell 7
  module on the build machine; these numbers came from a copy bundled with an
  editor extension. Stack 2 needs it installed and version-pinned.
- **Two functions per file.** `Invoke-RmanProcess.ps1` also defines
  `Invoke-CredentialScrub`; `Assert-OracleEnvironment.ps1` also defines
  `Invoke-TnspingProcess`.
- **No unit test file** for `ConvertFrom-RmanListBackup` or `Get-OracleBackupConfigStore`.
- **Open `[SEC]` TODOs in the copied code.** `Invoke-CredentialScrub` is marked
  best-effort with patterns to expand. `Remove-RmanObsoleteBackup` accepts
  `-CatalogCredential` but does not yet use it.
- **Possible defect, read from the code and not yet confirmed by a test.** When
  `OracleHome` is empty in the config file, `Assert-OracleEnvironment` falls back
  to `$env:ORACLE_HOME`, but both public RMAN functions then pass the empty config
  value to `Invoke-RmanProcess`, whose `-OracleHome` parameter rejects an empty
  string. The fallback would appear to fail one step later.
- **Reference to a function that was not copied.** An error message in
  `Assert-OracleEnvironment` tells the user to run `Set-OracleBackupConfig`.
- **Windows-only assumptions.** Paths built with `\bin;`, `.exe` binary names and
  `C:\` defaults in the config store. The existing functions in this module
  support Windows and Linux.
- **Config store naming.** The file (`Config\OracleBackup.json`) and the override
  variable (`ORACLE_BACKUP_CONFIG_PATH`) keep the backup module's names. The file
  is created in the module folder on first use; `Config/` is gitignored.
- **House standards not checked by the analyzer.** For example, piping to
  `ConvertTo-Json` and backtick line continuation both appear in the copied code.
- **Integration tests not copied.** They need a live Oracle database and further
  functions from the backup module; they are picked up in Stack 3.
