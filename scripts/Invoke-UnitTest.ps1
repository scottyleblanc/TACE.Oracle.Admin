#Requires -Version 7.0
<#
.SYNOPSIS
    Runs the unit tier: Pester tests that run module functions against mocks.

.DESCRIPTION
    Runs every Tests\*.Tests.ps1 file at the top level of Tests\. The search is not
    recursive, so the static tier (Tests\Static\) and, from Stack 3, the integration
    tier (Tests\Integration\) are not run here. Rule T-10.

    Writes NUnit XML results to Tests\TestResults\unit.xml, replacing the previous run.
    Exits 1 when any test fails or any test file fails to run, and 0 otherwise.

.EXAMPLE
    .\scripts\Invoke-UnitTest.ps1

.NOTES
    Copyright © TACE Data Management Inc.
    **Invocation:** Standalone — self-contained; safe to run with `pwsh -File`. Runs from
    any working directory: every path is resolved from this script's location.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module Pester -MinimumVersion 5.0

$repoRoot    = Split-Path -Path $PSScriptRoot -Parent
$testsRoot   = Join-Path -Path $repoRoot -ChildPath 'Tests'
$resultsDir  = Join-Path -Path $testsRoot -ChildPath 'TestResults'
$resultsFile = Join-Path -Path $resultsDir -ChildPath 'unit.xml'

$testFiles = @(Get-ChildItem -Path $testsRoot -Filter '*.Tests.ps1' -File |
    Select-Object -ExpandProperty FullName)
if ($testFiles.Count -eq 0) {
    throw "[unit] No test files found under $testsRoot"
}

$null = New-Item -Path $resultsDir -ItemType Directory -Force

$config = New-PesterConfiguration
$config.Run.Path                = [string[]]$testFiles
$config.Run.PassThru            = $true
$config.Output.Verbosity        = 'Detailed'
$config.TestResult.Enabled      = $true
$config.TestResult.OutputFormat = 'NUnitXml'
$config.TestResult.OutputPath   = $resultsFile

$result = Invoke-Pester -Configuration $config

# A failure above any Describe block (a parse error, or a throwing file-level block) counts
# only in FailedContainersCount. Checking FailedCount alone would pass a run in which a
# whole test file never ran.
$failed = $result.FailedCount -gt 0 -or $result.FailedContainersCount -gt 0

$label = if ($failed) { '[FAIL]' } else { '[PASS]' }
Write-Output ('{0} unit: {1} passed, {2} failed, {3} skipped, {4} file(s) failed to run. Results: {5}' -f
    $label, $result.PassedCount, $result.FailedCount, $result.SkippedCount, $result.FailedContainersCount, $resultsFile)

if ($failed) { exit 1 }

# Explicit, so a caller never reads a $LASTEXITCODE left over from an earlier command.
exit 0
