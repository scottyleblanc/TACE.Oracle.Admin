# Changelog — TACE.Oracle.Admin

All notable changes to this project will be documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versioning follows [Semantic Versioning](https://semver.org/).

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

---

## [0.1.5] - 2026-03-17

### Added

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
- Unit tests for both public functions (`Tests\*.Tests.ps1`).
- Required project documentation: `README.md`, `SECURITY.md`, `CHANGELOG.md`,
  `VERSIONING.md`, `PREREQUISITES.md`, `TODO.md`.
