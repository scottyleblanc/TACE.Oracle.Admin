# Coding Standards

## Repository layout

- **C-28** — Module source lives under `Source\`: `Source\Public\` for exported functions, `Source\Private\` for helpers, and `Source\Classes\` once a class exists. A build merges it, classes then private then public, into one `.psm1` under `Output\<Module>\<version>\` with a generated manifest. That built module is what is tested and released.
  Example: `Source\Public\Get-RmanBackupStatus.ps1` ships inside `Output\TACE.Oracle.Admin\0.2.2\TACE.Oracle.Admin.psm1`; `Tests\`, `Docs\` and `Scripts\` never ship. *Test.*
- **C-29** — The manifest lists exported functions explicitly, and the list equals the file names in `Source\Public\`; a function is exported if and only if it lives there.
  Example: `FunctionsToExport = @('Get-OracleDatabaseList', 'Set-OracleEnv', ...)`, never `'*'`. *Test.*
- **C-30** — A command alias is declared with an `[Alias()]` attribute on the public function it targets, never with `Set-Alias`, and is listed in the README's Aliases table. The build generates `AliasesToExport` from those attributes.
  Example: `[Alias('oraset', 'oraenv')]` below `[CmdletBinding()]` in `Invoke-OraEnv`. *Test.*
- **C-32** — A script in `Scripts\` is named Verb-Noun with an approved verb and a singular noun, and its `.NOTES` declares how it is invoked: `**Invocation:**` followed by `Standalone`, `Session-scoped`, `Helper` or `lib helper`, and one line of detail. A dot-sourced helper lives in `Scripts\Lib\`.
  Example: `Scripts\Invoke-UnitTest.ps1` with `**Invocation:** Standalone — self-contained; safe to run with pwsh -File.`. *Linter.*

## Language and structure

- **C-01** — Every `.ps1` file starts with `#Requires -Version 7.0`.
  Example: line 1 of `Source\Public\Set-OracleEnv.ps1`. *Linter.*
- **C-02** — Every function sets strict mode and stop-on-error as its first statements.
  Example: `Set-StrictMode -Version Latest` then `$ErrorActionPreference = 'Stop'`. *Linter.*
- **C-03** — One function per file, and the file is named for the function.
  Example: `Source\Private\Set-RestrictiveAcl.ps1` defines only `Set-RestrictiveAcl`. *Linter.*
- **C-04** — Function names use approved PowerShell verbs.
  Example: `Get-RmanBackupStatus`, not `Fetch-RmanBackupStatus`. *Linter.*
- **C-05** — Every function declares its output type.
  Example: `[OutputType([PSCustomObject])]` directly below `[CmdletBinding()]`. *Linter.*
- **C-06** — A state-changing public function supports `ShouldProcess`.
  Example: `[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]` on `Remove-RmanObsoleteBackup`. *Linter and Test.*
- **C-07** — A platform-specific function checks the platform first and returns `Success = $false` anywhere it does not support.
  Example: `if (-not $IsWindows) { return [PSCustomObject]@{ Success = $false; Data = $null; Message = 'Windows only.' } }`. *Test.*
- **C-08** — Platform is detected with `$IsWindows`, `$IsLinux` or `$IsMacOS`, never from environment variables.
  Example: `if ($IsLinux) { ... }`, not `if ($env:OS -eq 'Windows_NT') { ... }`. *Linter.*

## Parameters

- **C-09** — Every parameter has an explicit type.
  Example: `[string]$DatabaseName`, never `$DatabaseName`. *Linter.*
- **C-10** — Every parameter of a public function has a type and at least one `[Validate*]` attribute, except switches and credential types.
  Example: `[ValidateNotNullOrEmpty()] [string]$DatabaseName`. *Linter.*

## Statements

- **C-11** — A call with several parameters uses splatting, never backtick line continuation.
  Example: `$params = @{ Path = $path; Encoding = 'UTF8' }` then `Set-Content @params`. *Linter.*
- **C-12** — A pipeline result that is used as an array is wrapped in `@()`.
  Example: `$running = @($services | Where-Object { $PSItem.Status -eq 'Running' })`. *Review.*
- **C-13** — A value that can be an array is passed to `ConvertTo-Json` with `-InputObject`, never piped.
  Example: `ConvertTo-Json -InputObject @($items) -Depth 5`. *Review.*
- **C-14** — Paths are built with `Join-Path`, never by joining strings with `\` or `/`.
  Example: `Join-Path -Path $oracleHome -ChildPath 'bin'`, not `"$oracleHome\bin"`. *Linter.*
- **C-15** — Every file write names its encoding.
  Example: `Set-Content -Path $path -Value $text -Encoding UTF8`. *Linter.*
- **C-16** — Code that edits an existing config file keeps that file's line endings.
  Example: a file read with CRLF endings is written back with CRLF. *Test.*
- **C-17** — The current pipeline item is written `$PSItem`, never `$_`.
  Example: `"Failed: $($PSItem.Exception.Message)"`. *Linter.*
- **C-18** — No emojis in code, scripts or output; status uses a `[LABEL]` prefix.
  Example: `Write-Host '[ERROR] SID not found.'`. *Linter.*
- **C-31** — `PSAvoidUsingWriteHost` stays enabled. A function whose purpose is terminal interaction may use `Write-Host` only with a `SuppressMessageAttribute` on that function stating why; every other function reports through its return object, `Write-Verbose` or `Write-Warning`.
  Example: `[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive: ...')]` on `Set-OracleEnv`. *Linter.*

## Output contract and error model

- **C-19** — Every public function returns a `PSCustomObject` with exactly `Success`, `Data` and `Message`.
  Example: `[PSCustomObject]@{ Success = $true; Data = $record; Message = 'Backup found.' }`. *Test.*
- **C-20** — A caller checks `Success` before it uses `Data`.
  Example: `if ($result.Success) { $result.Data.AgeHours }`. *Review.*
- **C-21** — A private helper reports failure by throwing a terminating error whose message is already scrubbed.
  Example: `throw "RMAN process invocation failed: $safeMessage"`. *Test.*
- **C-22** — A public function throws only when its parameters are invalid; every other failure is caught, scrubbed and returned as `Success = $false`.
  Example: a missing `rman.exe` returns `Success = $false` with a message; it does not throw to the caller. *Test.*
- **C-27** — When `ShouldProcess` declines, under `-WhatIf` or a "No" at `-Confirm`, a function changes nothing and returns `Success = $true`, `Data` with `Applied = $false`, and a Message that starts with `WhatIf:` and says what would have happened. A real run returns `Applied = $true`, and a Message that reports a change is built only inside the `ShouldProcess` block.
  Example: `Set-OracleEnv -SID ORCL -WhatIf` returns `Success = $true`, `Data.Applied = $false` and `WhatIf: would set ORACLE_SID to 'ORCL'.`. *Test.*

## Help and comments

- **C-23** — Every public function has comment-based help with `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER` for each parameter, `.EXAMPLE`, `.OUTPUTS` and `.NOTES`.
  Example: the help block above `Get-RmanBackupStatus`. *Linter.*
- **C-24** — A security requirement in a comment or `.NOTES` block carries the `[SEC]` tag.
  Example: `[SEC] ORACLE_SID set on child process only.` *Review.*

## Verbose logging

- **C-25** — A progress line is `[FunctionName] message`.
  Example: `Write-Verbose '[Get-RmanBackupStatus] Querying most recent backup.'`. *Linter.*
- **C-26** — An audit line is `[FunctionName] ACTION on TARGET at UTC-TIMESTAMP`.
  Example: `[Remove-RmanObsoleteBackup] DELETE obsolete for CDB1 at 2026-11-14T16:00:00Z`. *Test.*
