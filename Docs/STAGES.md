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

## Stage 2 — PSGallery Publication (v0.1.5, v0.1.6) — COMPLETE

Published to PSGallery on 2026-03-17. See `CHANGELOG.md` entries 0.1.5 and 0.1.6.

### Prerequisites — COMPLETE

- [x] **GitHub repo URL** — confirmed: `https://github.com/scottyleblanc/TACE.Oracle.Admin`
  Added to `ProjectUri` and `LicenseUri` in the manifest.

- [x] **`Invoke-OraEnv` export policy** — resolved: must remain in `FunctionsToExport`.
  PowerShell resolves exported alias targets in the caller's scope — if `Invoke-OraEnv`
  is not exported, `oraset` and `oraenv` throw "not recognized" at call time.

---

### Phase 1 — Account and Tooling — COMPLETE

- [x] Confirm PSGallery account exists at `powershellgallery.com`
- [x] Generate a Publish-scoped API key; store in Windows Credential Manager or Oracle Wallet —
      never in any file in this repo
- Superseded: the `PowerShellGet` 2.x check. Publishing uses `Publish-PSResource`
  (`Microsoft.PowerShell.PSResourceGet`) via `scripts\Publish-ToGallery.ps1`.

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

- [x] Set `ProjectUri` (`https://github.com/scottyleblanc/TACE.Oracle.Admin`)
- [x] Add `LicenseUri` (`https://github.com/scottyleblanc/TACE.Oracle.Admin/blob/master/LICENSE`)
- [x] Expand `Tags` — added `Windows`, `Linux`, `OracleDB`, `PowerShell`
- [x] Resolve `Invoke-OraEnv` export policy — retained in `FunctionsToExport`
      (see Prerequisites)
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

### Phase 5 — Publish — COMPLETE

The `Publish-Module` steps originally planned here were replaced by the staged
build and publish workflow added in v0.1.5.

- [x] `scripts\Build-Module.ps1` — stage publishable files, build the `.nupkg`,
      list package contents for review
- [x] `scripts\Publish-ToGallery.ps1` — `Publish-PSResource` from the staged build;
      requires a clean working tree and a matching git tag
- [x] v0.1.5 published. The package was incomplete (no `FileList` in the manifest)
      and PSGallery versions cannot be overwritten.
- [x] v0.1.6 published — version bump to resolve the resulting 409 conflict.
      No functional changes.

No record was kept of the propagation check or the clean-session install smoke test.

---

### Phase 6 — Post-Publish Housekeeping — COMPLETE

- [x] Push `master` and tag (`v0.1.6`)
- [x] Delete `Docs\HANDOFF.md` (removed in v0.1.5)

---

## Stage 3 — Future Functions (TBD)

- [ ] `Get-OracleStatus` — report instance open mode, database role, archivelog mode
- [ ] `Test-OracleConnection` — validate connectivity via OS auth; return structured result
- [ ] Additional DBA utility functions (to be defined)
