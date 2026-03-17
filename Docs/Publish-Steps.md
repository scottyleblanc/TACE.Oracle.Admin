# TACE.Oracle.Admin — Publish Steps

_Pick up here after machine restart or session interruption._

---

## Where We Are

All validation is complete. The publish failed with a `dotnet.exe failed to pack`
error caused by an outdated PowerShellGet. The fix requires a machine restart to
release locked module handles.

---

## Step 1 — Update PowerShellGet (after restart)

Open a **single fresh PowerShell session** (no other PS sessions open):

```powershell
Install-Module PowerShellGet -Force -AllowClobber -Scope CurrentUser
```

Close that session and open another fresh one to pick up the new version.

Confirm the update took:

```powershell
Get-Module PowerShellGet -ListAvailable | Select-Object Name, Version
```

Should show 2.2.5 or higher.

---

## Step 2 — Dry run

```powershell
cd C:\Users\scott.leblanc\dev\TACE\repos\TACE.Oracle.Admin
Publish-Module -Path . -NuGetApiKey '<key>' -WhatIf
```

Expected output:
```
What if: Performing the operation "Publish-Module" on target "Version '0.1.4' of module 'TACE.Oracle.Admin'".
```

---

## Step 3 — Live publish

```powershell
Publish-Module -Path . -NuGetApiKey '<key>'
```

No output = success. If it fails, re-run with `-Verbose` for the full dotnet error:

```powershell
Publish-Module -Path . -NuGetApiKey '<key>' -Verbose
```

---

## Step 4 — Verify propagation (allow 5-15 minutes)

```powershell
Find-Module -Name 'TACE.Oracle.Admin'
```

---

## Step 5 — Smoke test in a clean session

Open a fresh PowerShell session with no profile (`pwsh -NoProfile`), then:

```powershell
Install-Module 'TACE.Oracle.Admin' -Scope CurrentUser
Import-Module 'TACE.Oracle.Admin'
Get-OracleDatabaseList
oraset
```

---

## Step 6 — Post-publish housekeeping

```powershell
cd C:\Users\scott.leblanc\dev\TACE\repos\TACE.Oracle.Admin
git tag v0.1.4
```

Write commit message to file, then commit:

```powershell
git add .
git commit -F commit_msg.txt
git push origin master
git push origin refs/tags/v0.1.4
```

Commit message (save as `commit_msg.txt` in repo root):

```
chore(publish): prepare TACE.Oracle.Admin v0.1.4 for PSGallery

- Rename manifest and root module to TACE.Oracle.Admin.*
- Rename repo folder to TACE.Oracle.Admin
- Add ProjectUri, LicenseUri, expanded Tags to manifest
- Keep Invoke-OraEnv in FunctionsToExport (required for alias resolution)
- Fill in LICENSE effective date
- Create root README.md for PSGallery audience
- Add PSScriptAnalyzerSettings.psd1
- Fix PSShouldProcess and Join-Path PSSA findings
- Add Remove-Module guard to all test BeforeAll blocks
- Add alias invocation test to catch export policy regression
- Skip Windows CimInstance tests on Linux (-Skip:(-not $IsWindows))
- Update all docs to TACE.Oracle.Admin naming convention
- Update NAMING.md to TACE.{Family}.{Product} pattern
```

---

## Step 7 — Cleanup

```powershell
Remove-Item .\Docs\HANDOFF.md
Remove-Item .\scripts\Publish-Steps.md
Remove-Item .\scripts\pssa_results.txt
git add .
git commit -m "chore: remove publish working files"
git push origin master
```

---

## API Key

Generate a new Publish-scoped key at `https://www.powershellgallery.com` with
glob pattern `TACE.Oracle.Admin`. Regenerate after each use — never leave a key
in session history.
