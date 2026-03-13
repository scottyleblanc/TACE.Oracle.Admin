# TACE.OracleAdmin — Stage Roadmap

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

### Prerequisites — decisions required before any work begins

- [ ] **GitHub repo URL** — confirm the correct public URL for use in the manifest
  `ProjectUri` and `LicenseUri` fields. Expected value:
  `https://github.com/scottyleblanc/OracleAdmin`
  Confirm this is correct and the repo is public (required for PSGallery).

- [ ] **`Invoke-OraEnv` export policy** — decide whether `Invoke-OraEnv` remains in
  `FunctionsToExport` in the manifest (visible on the gallery, documented as
  interactive-only) or is removed from exports so it is internal to the module.
  This affects what consumers of the published package can call directly.

---

### Phase 1 — Account and Tooling

- [ ] Confirm PSGallery account exists at `powershellgallery.com`
- [ ] Generate a Publish-scoped API key; store in Windows Credential Manager or Oracle Wallet —
      never in any file in this repo
- [ ] Verify `PowerShellGet` 2.x is current:
      `Install-Module PowerShellGet -Force -AllowClobber -Scope CurrentUser`

---

### Phase 2 — Module Naming Resolution

PSGallery derives the published module name from the `.psd1` filename. The working
manifest is `OracleAdmin.psd1` — publishing it directly would register as `OracleAdmin`,
not `TACE.OracleAdmin`. A staging build step is required.

- [ ] Create `Scripts\Publish-ToGallery.ps1` — a publish script that:
  1. Copies module files to a temp staging folder named `TACE.OracleAdmin\`
  2. Renames the manifest copy to `TACE.OracleAdmin.psd1`; updates `RootModule` inside
     it to `TACE.OracleAdmin.psm1`
  3. Renames the root module copy to `TACE.OracleAdmin.psm1`
  4. Runs `Publish-Module -Path <staging>\TACE.OracleAdmin\`
  5. Cleans up the staging folder

---

### Phase 3 — Manifest Completion

- [ ] Set `ProjectUri` (GitHub repo URL — confirmed in prerequisite above)
- [ ] Add `LicenseUri` (URL to LICENSE file on GitHub — e.g. `.../blob/master/LICENSE`)
- [ ] Review and expand `Tags` — consider adding `'Windows'`, `'Linux'`, `'OracleDB'`
      for discoverability
- [ ] Resolve `Invoke-OraEnv` export policy (confirmed in prerequisite above)

---

### Phase 4 — Pre-Publish Validation

- [ ] `Test-ModuleManifest -Path .\OracleAdmin.psd1`
- [ ] Run PSScriptAnalyzer across all module files:
      `Invoke-ScriptAnalyzer -Path . -Recurse`
- [ ] Run full Pester suite: `Invoke-Pester -Path .\Tests\ -Output Detailed`
- [ ] Dry-run via staging script with `-WhatIf`

---

### Phase 5 — Publish

- [ ] Run `Publish-ToGallery.ps1` with live API key
- [ ] Verify propagation (allow 5–15 minutes):
      `Find-Module -Name TACE.OracleAdmin`
- [ ] Smoke test in a clean session:
      `Install-Module TACE.OracleAdmin -Scope CurrentUser`

---

### Phase 6 — Post-Publish Housekeeping

- [ ] Update `README.md` — add PSGallery installation section
- [ ] Commit manifest updates, publish script, and README as `chore(publish)` commit
- [ ] Push `master`; no version bump required (no code change)

---

## Stage 3 — Future (TBD)

- [ ] `Get-OracleStatus` — report instance open mode, database role, archivelog mode
- [ ] `Test-OracleConnection` — validate connectivity via OS auth; return structured result
- [ ] Additional DBA utility functions (to be defined)
