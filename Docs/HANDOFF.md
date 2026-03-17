# HANDOFF — TACE.Oracle.Admin PSGallery Publish

_Created: 2026-03-17. Delete this file after Phase 6 (post-publish housekeeping) is complete._

---

## What Was Accomplished This Session

The module was fully prepared for PSGallery publication. No code logic was changed —
all changes are naming, manifest, documentation, and PSSA compliance.

### Naming

- Repo folder renamed: `OracleAdmin\` → `TACE.Oracle.Admin\`
- Manifest renamed: `OracleAdmin.psd1` → `TACE.Oracle.Admin.psd1`
- Root module renamed: `OracleAdmin.psm1` → `TACE.Oracle.Admin.psm1`
- Published name updated throughout: `TACE.OracleAdmin` → `TACE.Oracle.Admin`
- Naming convention updated across TACE: `TACE.{Product}` → `TACE.{Family}.{Product}`

### Manifest

- `RootModule` updated to `TACE.Oracle.Admin.psm1`
- `ProjectUri` set to `https://github.com/scottyleblanc/OracleAdmin`
- `LicenseUri` added: `https://github.com/scottyleblanc/OracleAdmin/blob/main/LICENSE`
- `Tags` expanded: added `Windows`, `Linux`, `OracleDB`, `PowerShell`
- `Invoke-OraEnv` removed from `FunctionsToExport` — aliases remain exported
- `LICENSE` effective date filled in: `2026-03-17`

### Documentation

- Root `README.md` created — PSGallery-facing, `Install-Module` first, absolute GitHub links
- `Docs\README.md` — updated module name, install path
- `PREREQUISITES.md` — updated for Linux support and `ORACLE_HOME`/`ORACLE_BASE` now set
- `SECURITY.md`, `VERSIONING.md`, `CHANGELOG.md`, `TODO.md`, `STAGES.md` — all updated
- `NAMING.md` (in OracleBackup repo) — updated to `TACE.{Family}.{Product}` convention

### Code fixes (PSSA compliance)

- `Invoke-OraEnv.ps1` — removed `SupportsShouldProcess` (was flagged by PSSA, not used)
- `TACE.Oracle.Admin.psm1` — `Join-Path` calls converted to named parameters
- `PSScriptAnalyzerSettings.psd1` created — suppresses two intentional rules:
  - `PSUseBOMForUnicodeEncodedFile` (PS7 false positive — UTF-8 without BOM is correct)
  - `PSAvoidUsingWriteHost` (intentional interactive design in `Set-OracleEnv` and `Invoke-OraEnv`)

### Tests

- All three test `BeforeAll` blocks updated with `Remove-Module` before `Import-Module -Force`
  (fixes multiple-module-loaded error when profile pre-imports the module)
- `OracleAdmin.Module.Tests.ps1` — removed `Get-Command Invoke-OraEnv` test (function no
  longer exported; alias tests cover what matters)
- Final result: **101 tests passing, 0 failing**

---

## Current State

| Item | Status |
|---|---|
| Module version | `0.1.4` |
| Manifest | `TACE.Oracle.Admin.psd1` — validated clean |
| PSScriptAnalyzer | Clean (3 x Information in test files only — accepted) |
| Pester | 101 passed, 0 failed |
| Git | **Not yet committed** — all changes are uncommitted working tree |
| PSGallery account | Pending |
| API key | Pending |

---

## What To Do Next

### Step 1 — PSGallery account and API key

1. Go to `https://www.powershellgallery.com` and sign in (Microsoft account)
2. Go to Account Settings → API Keys → Create
3. Set scope to **Push** only; set package name glob to `TACE.Oracle.Admin`
4. Copy the key and store it in Windows Credential Manager — never in any file in this repo

### Step 2 — Verify PowerShellGet

```powershell
Install-Module PowerShellGet -Force -AllowClobber -Scope CurrentUser
```

### Step 3 — Confirm GitHub repo is public

The `ProjectUri` and `LicenseUri` in the manifest point to:
`https://github.com/scottyleblanc/OracleAdmin`

This repo must be **public** for those links to resolve on the PSGallery page.

### Step 4 — Dry run

```powershell
cd C:\Users\scott.leblanc\dev\TACE\repos\TACE.Oracle.Admin
Publish-Module -Path . -NuGetApiKey '<key>' -WhatIf
```

### Step 5 — Live publish

```powershell
Publish-Module -Path . -NuGetApiKey '<key>'
```

### Step 6 — Verify propagation (allow 5–15 minutes)

```powershell
Find-Module -Name 'TACE.Oracle.Admin'
```

### Step 7 — Smoke test in a clean session

Open a fresh PowerShell session (no profile), then:

```powershell
Install-Module 'TACE.Oracle.Admin' -Scope CurrentUser
Import-Module 'TACE.Oracle.Admin'
Get-OracleDatabaseList
```

### Step 8 — Post-publish housekeeping

```powershell
cd C:\Users\scott.leblanc\dev\TACE\repos\TACE.Oracle.Admin
git tag v0.1.4
```

Commit all changes (this is the first commit for this repo under the new name):

```powershell
# Write commit message to file first (Windows heredoc workaround)
# Use Write tool or manually create commit_msg.txt, then:
git add .
git commit -F commit_msg.txt
git push origin master
git push origin refs/tags/v0.1.4
```

Commit message:
```
chore(publish): prepare TACE.Oracle.Admin v0.1.4 for PSGallery

- Rename manifest and root module to TACE.Oracle.Admin.*
- Rename repo folder to TACE.Oracle.Admin
- Add ProjectUri, LicenseUri, expanded Tags to manifest
- Remove Invoke-OraEnv from FunctionsToExport; aliases retained
- Fill in LICENSE effective date
- Create root README.md for PSGallery audience
- Add PSScriptAnalyzerSettings.psd1
- Fix PSShouldProcess and Join-Path PSSA findings
- Add Remove-Module guard to all test BeforeAll blocks
- Update all docs to TACE.Oracle.Admin naming convention
- Update NAMING.md to TACE.{Family}.{Product} pattern
```

Then delete this file:
```powershell
Remove-Item .\Docs\HANDOFF.md
git add .
git commit -m "chore: remove HANDOFF.md post-publish"
```

---

## Key File Locations

| File | Purpose |
|---|---|
| `TACE.Oracle.Admin.psd1` | Module manifest — the PSGallery entry point |
| `TACE.Oracle.Admin.psm1` | Module root |
| `PSScriptAnalyzerSettings.psd1` | PSSA rule suppressions |
| `README.md` | Root README — shown on PSGallery and GitHub |
| `Docs\STAGES.md` | Full publish checklist with phase-by-phase status |
| `Docs\README.md` | Developer reference README |
| `LICENSE` | TACE Software License v1.0, effective 2026-03-17 |

---

## Known Issues / Gotchas

- **Version is permanent.** Once `0.1.4` is published to PSGallery it cannot be overwritten
  or deleted. Any fix requires a new version number.
- **GitHub repo must be public** before publishing, or `ProjectUri`/`LicenseUri` links will
  return 404 on the PSGallery page.
- **Profile import path.** The PowerShell profile currently imports this module by path.
  After PSGallery publish, the profile import can optionally be changed to
  `Import-Module 'TACE.Oracle.Admin'` to use the gallery-installed version instead.
- **Git has not been committed.** All changes from this session are uncommitted.
  Run `git status` to see the full list before committing.
