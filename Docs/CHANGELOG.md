# Changelog — TACE.Oracle.Admin

All notable changes to this project will be documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versioning follows [Semantic Versioning](https://semver.org/).

---

## [Unreleased]

---

## [0.2.1] - 2026-11-14

Stack 1 of the AI Development Stack — intent. Not published to PSGallery.

### Added

- `Docs/standards/` — the ratified standards, one sentence plus one example each, with
  an ID and the layer that enforces each: `coding.md`, `security.md`, `testing.md`,
  `documentation.md`, and `decisions.md` for contested, deferred and open questions.
- `Docs/standards/invariants.md` — the format of the invariant block: sections,
  identifiers, and the five ways an entry can be enforced.
- An `# INVARIANTS` block in every function under `Public\` and `Private\`: 149
  invariants in 13 functions, 54 of them security invariants. Comments only; no
  behaviour changes.
- `scripts/Invoke-InvariantLint.ps1` — checks every block and generates
  `Docs/standards/invariants-index.md`.
- `Tests/Static/InvariantConformance.Tests.ps1` and `scripts/Invoke-StaticTest.ps1` — the
  first checks in the static tier. They fail when a function has no block, an entry is
  malformed, or the committed index is out of date.
- `Tests/Get-OracleBackupConfigStore.Tests.ps1` — tests for S4, R1 and R2.
- `Tests/Static/PublicRepoHygiene.Tests.ps1` — the machine check for rule S-16 in the
  static tier: fails on an AWS account ID, an ARN, an access key ID, a literal S3
  target, an email address outside the reserved example domains, or a private key in
  any file git tracks or would add. Failure messages show only a value's first
  characters.
- `Private/Test-WindowsPlatform.ps1` — returns `$IsWindows`, so a test can simulate
  another platform; `$IsWindows` itself is read-only.
- Rules C-28 and C-29 in `Docs/standards/coding.md`: module source under `source\`,
  built into one merged `.psm1` with a generated manifest, and exports equal to the
  `source\Public\` file names. Recorded as decision 16; the move is the first task of
  Stack 2, and the current layout is listed as a known finding until then.
- Rule C-27 in `Docs/standards/coding.md`: when `ShouldProcess` declines, a function
  changes nothing and returns `Success = $true`, `Data.Applied = $false`, and a Message
  starting with `WhatIf:`. Recorded as decision 14.

### Changed

- `Set-OracleEnv` and `Remove-RmanObsoleteBackup` follow C-27. Both add `Applied` to
  `Data`. Under `-WhatIf`, `Remove-RmanObsoleteBackup` now returns `Success = $true`
  with `DatabaseName` and `Applied = $false`, where it returned `Success = $false` and
  no `Data`. Breaking for a caller that read `Success = $false` as "skipped".
- The `oraset` and `oraenv` aliases are declared with `[Alias('oraset', 'oraenv')]` on
  `Invoke-OraEnv`, replacing the two `Set-Alias` lines in the root module (new rule
  C-30, decision 17). Same names, same target, still exported.
- `Build-Module.ps1`, `Sync-ToS3.ps1` and `Test-LinuxBuild.ps1` take the S3 staging
  bucket as `-S3Bucket` instead of a name written into the scripts. It is required by
  `Sync-ToS3.ps1` and `Test-LinuxBuild.ps1`; `Build-Module.ps1` skips the upload when
  it is omitted. No bucket name is kept in the repository.
- Scripts in `scripts/` follow new rule C-32 (decision 20): Verb-Noun names and an
  `**Invocation:**` line in `.NOTES`. `scripts/test.unit.ps1` is renamed
  `scripts/Invoke-UnitTest.ps1`; the static runner is `scripts/Invoke-StaticTest.ps1`.
- `PSAvoidUsingWriteHost` is no longer excluded for the whole repository (new rule C-31,
  decision 18). `Set-OracleEnv` and `Invoke-OraEnv`, the two interactive functions, carry
  a `SuppressMessageAttribute` with the reason, so every other function is checked.
- Rules D-11 and T-09 reworded and ratified, and I-05 ratified (decision 19). D-11 now
  says a document-code contradiction is fixed in whichever side is wrong. T-09 now says
  a cited test's title starts with each ID it is cited for, and security tests carry
  the Pester tag `SEC`; four tests from this stage are renamed or tagged to match.
- Test runners follow new rule T-10: one script per tier, holding its own configuration.
  the unit runner is rewritten to the house rules and no longer runs
  `Unblock-File`. `Tests/UnitTests.pester.ps1` is removed. Results go to
  `Tests/TestResults/static.xml` and `unit.xml`; the unit file was `UnitTests.xml`.
- `Get-RmanBackupStatus` and `Remove-RmanObsoleteBackup` check the platform first (rule
  C-07). Off Windows they return `Success = $false`, "Windows only. Linux support is not
  yet built.", before reading the config or starting a process. Before, they failed
  later with a misleading "rman.exe not found".

### Fixed

- `Get-RmanBackupStatus` and `Remove-RmanObsoleteBackup` failed whenever the config had
  no `OracleHome`. `Assert-OracleEnvironment` found and validated the home through
  `ORACLE_HOME`, but the callers then passed the empty config value to
  `Invoke-RmanProcess`, which rejected it at parameter binding. The callers now use
  the home that `Assert-OracleEnvironment` validated.
- `Get-OracleBackupConfigStore` failed to load a config file that was missing any
  setting: under StrictMode, reading a missing property throws. A missing or null
  setting now takes its default, as documented.
- `Assert-OracleEnvironment` told the reader to run `Set-OracleBackupConfig` when no
  Oracle home was found; this module has no such function. The message now names the
  two ways to set one: `OracleHome` in `Config\OracleBackup.json`, or `ORACLE_HOME`.
- `Set-OracleEnv -WhatIf` set nothing but returned "ORACLE_SID set to '<SID>'." It now
  returns a `WhatIf:` preview with `Data.Applied = $false`.
- `Invoke-TnspingProcess` could hang its caller indefinitely. It read stdout to the end
  before waiting, so a `tnsping` that never exited was never timed out, and heavy stderr
  output could stall the child. It now reads both streams asynchronously, waits up to
  `-TimeoutSeconds` (default 30), and on timeout kills the process tree and throws.
- `Invoke-RmanProcess` on timeout now kills the whole process tree rather than the RMAN
  process alone, guards the kill so it cannot replace the timeout error, and waits for
  the killed process to exit.
- `Get-OracleDatabaseList` on Windows reported "No Oracle database services found" when
  the service query itself failed (WMI stopped, access denied, an invalid query): the
  query suppressed its errors. It now returns `Success = $false` with the error, and
  `Set-OracleEnv` passes that on instead of saying the host has no instances.
- The unit test runner exited 0 when tests failed, and worked only from the repository
  root. Both tier scripts now exit 1 when any test or any test file fails, including a
  file that fails to parse, which counts only as a failed container.
- Both process helpers build the child `PATH` with `Join-Path` and
  `[System.IO.Path]::PathSeparator`, under the exact name `PATH`, in place of a string
  joined with `\` and `;`.

### Removed

- `Remove-RmanObsoleteBackup` `-CatalogConnection` and `-CatalogCredential`. Recovery
  catalog support was half-built and is withdrawn until a catalog is in scope. Breaking
  for any caller that passed either parameter; `0.2.0` was not published to PSGallery.

### Security

- `Remove-RmanObsoleteBackup` no longer places caller text in the RMAN script.
  `-CatalogConnection` was inserted after a non-empty check only, so a crafted value
  could append RMAN commands; `-CatalogCredential` was accepted and silently ignored.
  New invariant S9: the RMAN script is fixed text, with a test. S6 and S7 are retired.
- `Remove-RmanObsoleteBackup` `-WhatIf` no longer has side effects. The `ShouldProcess`
  gate now runs before the config read and the environment check, so a preview cannot
  create the config file or run `tnsping`. Invariant L1 changes from a limitation to a
  tested guarantee.
- `Get-OracleBackupConfigStore` no longer reads `ORACLE_BACKUP_CONFIG_PATH`. The
  variable let anything that could set the process environment choose which config
  file supplied `OracleHome` and where a new one was created. Tests now set the
  module-scoped `$script:ConfigPathOverride` through `InModuleScope`; production
  always uses `Config\OracleBackup.json` under the module folder. Invariant S4
  changes from a limitation to a tested guarantee.
- `Docs/SECURITY.md` now states that the binary signature check cannot detect a
  replaced Oracle binary: Oracle executables are unsigned, so a patched binary and a
  tampered one both pass. Recorded as an open item; no behaviour change.

---

## [0.2.0] - 2026-11-14

Stack 0 of the AI Development Stack — setup and baseline. Not published to PSGallery.

### Added

- `Docs/STAGES.md` and `Docs/TODO.md`: AI Development Stack plan recorded — the layer
  model, build rules, test bed, and goals, deliverables and tasks for Stack 0 to Stack 10.
- `Get-RmanBackupStatus` — reports the most recent RMAN backup for a database. Read-only.
- `Remove-RmanObsoleteBackup` — runs RMAN `DELETE OBSOLETE`. `SupportsShouldProcess`,
  `ConfirmImpact = 'High'`.
- Private helpers: `Invoke-RmanProcess` (with `Invoke-CredentialScrub`),
  `ConvertFrom-SecureStringToPlaintext`, `Assert-OracleEnvironment` (with
  `Invoke-TnspingProcess`), `ConvertFrom-RmanListBackup`, `Get-OracleBackupConfigStore`,
  `Set-RestrictiveAcl`.
- Unit tests for the copied functions. Unit test count: 117 → 291 (all passing).
- `Docs/audit/stack-0-baseline.md` — size, test and analyzer baseline, and known gaps.
- These functions were copied from the Oracle backup module as working examples for the
  AI Development Stack. `Get-RmanBackupStatus` reads its configuration through
  `Get-OracleBackupConfigStore` in place of a module-level cache, so importing the module
  still writes nothing to disk.
- `.gitignore`: `Config/` (local runtime configuration, created on first use).

### Changed

- Completed Stage 1, 1.3, 1.4 and 2 items removed from `Docs/TODO.md` and
  `Docs/STAGES.md`. Items not already in this changelog were added to the 0.1.0,
  0.1.3, 0.1.4, 0.1.5 and 0.1.6 entries.

---

## [0.1.7] - 2026-11-14

### Changed

- `Docs/STAGES.md` and `Docs/TODO.md`: Stage 2 (PSGallery publication) closed out. It was
  still shown as pending although the module was published at v0.1.5 and v0.1.6. The
  planned `Publish-Module` steps are replaced with the build and publish workflow actually
  used (`Build-Module.ps1`, `Publish-ToGallery.ps1`).
- `Docs/README.md` and `Docs/SECURITY.md`: status blocks corrected — version, and unit
  test count 107 → 117.
- Documentation only. No functional changes; not published to PSGallery.

---

## [0.1.6] - 2026-03-17

### Changed

- Version bump to resolve PSGallery 409 conflict. v0.1.5 was published with an
  incomplete package (no `FileList`) during an earlier session and cannot be
  overwritten. No functional changes.
- Published to PSGallery; `master` pushed and tagged `v0.1.6`. No record was kept of
  the propagation check or the clean-session install smoke test.

---

## [0.1.5] - 2026-03-17

Stage 2 — PSGallery publication. Published to PSGallery with an incomplete package
(see 0.1.6).

### Added

- Root `README.md` for PSGallery — `Install-Module` first, absolute GitHub links.
- `PSScriptAnalyzerSettings.psd1` — suppresses `PSUseBOMForUnicodeEncodedFile`
  (PS7 false positive) and `PSAvoidUsingWriteHost` (intentional interactive design).

- `scripts/Build-Module.ps1` — stages module files to `build\<version>\staging\`, builds
  a `.nupkg` to `build\<version>\repo\`, lists package contents, and uploads the `.nupkg`
  and `Test-LinuxBuild.ps1` to S3 staging. Enforces version consistency across all build
  files and warns if the matching git tag does not exist. Build artifacts are retained by
  version and never overwritten.
- `scripts/Publish-ToGallery.ps1` — publishes the staged build to PSGallery. Requires
  `Build-Module.ps1` to have run first. Enforces a clean git working tree and a matching
  git tag before publishing.
- `scripts/Test-LinuxBuild.ps1` — downloads the latest versioned build from S3, installs
  it into a temporary local PSResource repository, and runs 9 smoke tests covering module
  load, exported functions, aliases, return object shape, and credential safety. Linux only.
  Exits 0 on pass, 1 on failure.
- `Tests\Invoke-OraEnv.Tests.ps1` — 10 unit tests covering parameter validation,
  SID pass-through, verbose pass-through, output suppression, error host output, and
  security (no credential fragments in output).

### Changed

- `Set-OracleEnv`: `ORACLE_HOME` and `ORACLE_BASE` are always set in the session but
  are only printed to the host when `-Verbose` is specified. `ORACLE_SID` is always printed.
- `Invoke-OraEnv`: passes `-Verbose` through to `Set-OracleEnv` so that `oraset -v`
  and `oraset <SID> -v` display all three environment variables.
- Manifest: added `FileList` to restrict the published PSGallery package to module source
  files only — excludes `.git`, `Tests`, `Docs`, `scripts`, and build artifacts.
- Manifest: `ProjectUri` and `LicenseUri` updated to
  `https://github.com/scottyleblanc/TACE.Oracle.Admin` with branch `master`.
- `README.md`: added Session Usage section documenting PowerShell session scope,
  the `$env:` prefix requirement, and a real Linux example.
- `.gitignore`: added `build/`; `Docs/HANDOFF.md` and `Docs/Publish-Steps.md` removed
  from the repository (ephemeral planning docs).
- Unit test count: 102 → 117 (all passing).
- Module renamed for publication: `OracleAdmin.psd1` → `TACE.Oracle.Admin.psd1`,
  `OracleAdmin.psm1` → `TACE.Oracle.Admin.psm1`, repo folder `OracleAdmin\` →
  `TACE.Oracle.Admin\`. `RootModule`, all file headers and `.NOTES` blocks, and the
  `Import-Module` path and `-ModuleName` references in all test files updated to match.
- Manifest: `Tags` expanded — added `Windows`, `Linux`, `OracleDB`, `PowerShell`.
- Manifest: `Invoke-OraEnv` retained in `FunctionsToExport`. PowerShell resolves
  exported alias targets in the caller's scope — if `Invoke-OraEnv` is not exported,
  `oraset` and `oraenv` throw "not recognized" at call time.
- `LICENSE`: effective date filled in (`2026-03-17`).
- `Docs\README.md`, `PREREQUISITES.md`, `SECURITY.md`, `VERSIONING.md`, `CHANGELOG.md`,
  `TODO.md` — all updated to the `TACE.Oracle.Admin` name.
- PSGallery account confirmed; Publish-scoped API key generated and stored outside
  this repo. Publishing uses `Publish-PSResource` (`Microsoft.PowerShell.PSResourceGet`)
  in place of the `PowerShellGet` 2.x `Publish-Module` steps originally planned.
- Pre-publish validation: `Test-ModuleManifest` passed; `Invoke-ScriptAnalyzer` clean
  apart from 3 Information-level `Join-Path` positional parameter findings in test
  files (accepted); `Invoke-Pester` 101 passed, 0 failed.

### Fixed

- `PSShouldProcess` analyzer finding — removed `SupportsShouldProcess` from `Invoke-OraEnv`.
- `PSAvoidUsingPositionalParameters` in the `.psm1` — `Join-Path` now uses named parameters.

---

## [0.1.4] - 2026-03-13

### Added

- `Get-OracleDatabaseList`: multi-platform support via `$Platform` parameter
  (auto-detected from `$IsWindows`/`$IsLinux`; override with `-Platform` for testing).
  - Windows path: existing `Win32_Service` discovery, unchanged.
  - Linux path: parses `/etc/oratab`; derives `OracleHome` from the file directly and
    `OracleBase` via string split (preserves `/` on all platforms); determines `Status`
    by checking for an `ora_pmon_<SID>` process; `ServiceName` is `$null`.
  - Unsupported platform: returns `Success=$false` with a descriptive message.
- Unit test count: 82 → 102 (all passing). New contexts cover Linux oratab happy path,
  file not found, comment/blank line skipping, malformed lines, wildcard SID entries,
  `Get-Content` failure, and unsupported platform.
- `VERSIONING.md`: documented branch/tag naming convention (`vX.Y.Z-dev` for branches,
  `vX.Y.Z` for tags) to prevent push ambiguity.
- Project documentation updated for the multi-platform release.

---

## [0.1.3] - 2026-03-13

### Changed

- `Get-OracleDatabaseList`: switched service discovery from `Get-Service` to
  `Get-CimInstance Win32_Service` to expose the `PathName` (service executable path).
  `ORACLE_HOME` is now derived from `PathName` by stripping `\bin\ORACLE.EXE`.
  `ORACLE_BASE` is derived from `ORACLE_HOME` by stripping `\product\{version}\{home}`.
  Both values are added to each Data entry as `OracleHome` and `OracleBase`.
  Returns `$null` for either field if `PathName` cannot be parsed.
- `Set-OracleEnv`: now sets `$env:ORACLE_HOME` and `$env:ORACLE_BASE` from the
  resolved instance's discovered values. Warns (but still sets `ORACLE_SID`) if
  either value cannot be determined. Returns `OracleHome` and `OracleBase` in
  the `Data` object.
- Unit test count: 70 → 82 (all passing). New tests cover `OracleBase` derivation,
  quoted and unquoted `PathName` parsing, null `PathName` handling, and
  `$env:ORACLE_BASE` set/not-set behaviour.
- Project documentation updated for the environment variable derivation.

---

## [0.1.2] - 2026-03-12

### Changed

- `README.md`: added AI-assisted development and support guidance section.
- `LICENSE`: incorporated AI language.

---

## [0.1.1] - 2026-03-11

### Added

- `Invoke-OraEnv` (`Private\Invoke-OraEnv.ps1`) — interactive wrapper for
  `Set-OracleEnv` that discards the return object for clean terminal output.
  Writes `[ERROR]` to host on failure. Target of the `oraset` and `oraenv` aliases.
- `oraset` and `oraenv` aliases registered in `OracleAdmin.psm1` and exported
  via `OracleAdmin.psd1`.
- `Tests\OracleAdmin.Module.Tests.ps1` — module-level tests verifying both
  aliases exist, resolve to `Invoke-OraEnv`, and are exported by the module.

### Fixed

- `Set-OracleEnv`: service status check now applies to both the interactive
  menu path and the `-SID` parameter path; previously only checked on the
  parameter path.
- `Set-OracleEnv`: `Write-Host` confirmation now emits before `Write-Warning`
  so the SID confirmation always appears first.
- `Set-OracleEnv`: initialize `$serviceWarning = $null` to satisfy
  `Set-StrictMode -Version Latest` on the interactive menu path.
- `Set-OracleEnv`: `Write-Host` output changed from
  `[Set-OracleEnv] ORACLE_SID = <SID>` to `ORACLE_SID set to '<SID>'`.
- `Set-OracleEnv`: service-stopped warning shortened to
  `[Set-OracleEnv] OracleService<SID> is Stopped.`

---

## [0.1.0] - 2026-03-11

### Added

- Module scaffold: `OracleAdmin.psm1`, `OracleAdmin.psd1`, `Public\`, `Private\`,
  `Tests\`, `Docs\` directories.
- `Get-OracleDatabaseList` — discovers Oracle database instances on the local
  Windows host via `OracleService*` service query. Returns SID, Status, and
  ServiceName. Migrated and hardened from `powershell\functions\get-oracledatabaselist.ps1`.
- `Set-OracleEnv` — sets `ORACLE_SID` for the current session. Validates SID
  against discovered instances. Auto-selects when one instance found; presents
  numbered menu when multiple instances found. Warns on stopped service but
  allows the set. Session-only — no disk writes.
- Unit tests for both public functions (`Tests\*.Tests.ps1`). Pester suite run;
  all tests passing.
- Required project documentation: `README.md`, `SECURITY.md`, `CHANGELOG.md`,
  `VERSIONING.md`, `PREREQUISITES.md`, `TODO.md`.
- Local shell profiles (`profile.ps1`, `profile.common.ps1`, outside this repo)
  updated to import the module and alias `oraset`.
- Git repository initialised; initial commit.

### Security

- Confirmed no credential leakage in `Message`, verbose output, or pipeline output.
