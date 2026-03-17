# TACE.Oracle.Admin — Stage Roadmap

Tasks are ordered top-to-bottom. Each stage depends on the one above being stable.
`[SEC]` items are first-class requirements — no stage is complete until its `[SEC]`
items are checked off.

---

## Stage 1 — Foundation (v0.1.0) — COMPLETE

See `TODO.md` for the full task list.

---

## Stage 1.3 — Environment Variable Derivation (v0.1.3) — COMPLETE

See `TODO.md` for the full task list.

---

## Stage 1.4 — Multi-Platform Discovery (v0.1.4) — COMPLETE

See `TODO.md` for the full task list.

---

## Stage 2 — PSGallery Publication

### Prerequisites — COMPLETE

- [x] **GitHub repo URL** — confirmed: `https://github.com/scottyleblanc/OracleAdmin`
  Added to `ProjectUri` and `LicenseUri` in the manifest.

- [x] **`Invoke-OraEnv` export policy** — resolved: must remain in `FunctionsToExport`.
  PowerShell resolves exported alias targets in the caller's scope — if `Invoke-OraEnv`
  is not exported, `oraset` and `oraenv` throw "not recognized" at call time.

---

### Phase 1 — Account and Tooling

- [ ] Confirm PSGallery account exists at `powershellgallery.com`
- [ ] Generate a Publish-scoped API key; store in Windows Credential Manager or Oracle Wallet —
      never in any file in this repo
- [ ] Verify `PowerShellGet` 2.x is current:
      `Install-Module PowerShellGet -Force -AllowClobber -Scope CurrentUser`

---

### Phase 2 — Module Naming Resolution — COMPLETE

The manifest and root module files have been renamed directly in the repo.
No staging build step is required.

- [x] Rename `OracleAdmin.psd1` → `TACE.Oracle.Admin.psd1`
- [x] Rename `OracleAdmin.psm1` → `TACE.Oracle.Admin.psm1`
- [x] Rename repo folder `OracleAdmin\` → `TACE.Oracle.Admin\`
- [x] Update `RootModule` in the manifest to `TACE.Oracle.Admin.psm1`
- [x] Update all file headers and `.NOTES` blocks to `TACE.Oracle.Admin`
- [x] Update all test files: `Import-Module` path and `-ModuleName` references

---

### Phase 3 — Manifest and Docs Completion — COMPLETE

- [x] Set `ProjectUri` (`https://github.com/scottyleblanc/OracleAdmin`)
- [x] Add `LicenseUri` (`https://github.com/scottyleblanc/OracleAdmin/blob/main/LICENSE`)
- [x] Expand `Tags` — added `Windows`, `Linux`, `OracleDB`, `PowerShell`
- [x] Resolve `Invoke-OraEnv` export policy — removed from `FunctionsToExport`
- [x] Fill in `LICENSE` effective date (`2026-03-17`)
- [x] Create root `README.md` for PSGallery — `Install-Module` first, absolute GitHub links
- [x] Update `Docs\README.md`, `PREREQUISITES.md`, `SECURITY.md`, `VERSIONING.md`,
      `CHANGELOG.md`, `TODO.md` — all updated to `TACE.Oracle.Admin`
- [x] Create `PSScriptAnalyzerSettings.psd1` — suppresses `PSUseBOMForUnicodeEncodedFile`
      (PS7 false positive) and `PSAvoidUsingWriteHost` (intentional interactive design)

---

### Phase 4 — Pre-Publish Validation — COMPLETE

- [x] `Test-ModuleManifest -Path .\TACE.Oracle.Admin.psd1` — passed; 2 exported functions,
      2 exported aliases, correct module name and version
- [x] `Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1` —
      clean; 3 x Information-level `Join-Path` positional params in test files only (accepted)
- [x] Fixed `PSShouldProcess` finding — removed `SupportsShouldProcess` from `Invoke-OraEnv`
- [x] Fixed `PSAvoidUsingPositionalParameters` in `.psm1` — `Join-Path` now uses named params
- [x] `Invoke-Pester -Path .\Tests\ -Output Detailed` — 101 passed, 0 failed

---

### Phase 5 — Publish

- [ ] `Publish-Module -Path . -NuGetApiKey '<key>' -WhatIf`
- [ ] `Publish-Module -Path . -NuGetApiKey '<key>'`
- [ ] Verify propagation (allow 5–15 minutes):
      `Find-Module -Name 'TACE.Oracle.Admin'`
- [ ] Smoke test in a clean session:
      `Install-Module 'TACE.Oracle.Admin' -Scope CurrentUser`

---

### Phase 6 — Post-Publish Housekeeping

- [ ] Git tag: `git tag v0.1.4`
- [ ] Commit all changes as `chore(publish): prepare TACE.Oracle.Admin for PSGallery`
- [ ] Push `master` and tag
- [ ] Delete `Docs\HANDOFF.md`

---

## Stage 3 — Future Functions (TBD)

- [ ] `Get-OracleStatus` — report instance open mode, database role, archivelog mode
- [ ] `Test-OracleConnection` — validate connectivity via OS auth; return structured result
- [ ] Additional DBA utility functions (to be defined)
