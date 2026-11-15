#Requires -Version 7.0
<#
.SYNOPSIS
    Runs the unit tier: Pester tests that run module functions against mocks.

.DESCRIPTION
    Builds the module first (Scripts\Build-Module.ps1), then runs every *.Tests.ps1 file
    under Tests\Unit\, searching its subfolders (Public\, Private\, Module\). The tests
    import the built module from Output\, so they never run against a stale build. The
    static tier (Tests\Static\) and, from Stack 3, the integration tier
    (Tests\Integration\) are outside Tests\Unit\ and are not run here. Rule T-10.

    A failed build stops the run before any test starts, and exits 1.

    Writes NUnit XML results to Tests\TestResults\unit.xml, replacing the previous run.
    Exits 1 when any test fails or any test file fails to run, and 0 otherwise.

.EXAMPLE
    .\Scripts\Invoke-UnitTest.ps1

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
$unitRoot    = Join-Path -Path $testsRoot -ChildPath 'Unit'
$resultsDir  = Join-Path -Path $testsRoot -ChildPath 'TestResults'
$resultsFile = Join-Path -Path $resultsDir -ChildPath 'unit.xml'

# Build first: the tests import Output\TACE.Oracle.Admin\<version>\.
$buildScript = Join-Path -Path $PSScriptRoot -ChildPath 'Build-Module.ps1'
try {
    & $buildScript
}
catch {
    Write-Output "[FAIL] unit: build failed, no tests run. $($PSItem.Exception.Message)"
    exit 1
}

$testFiles = @(Get-ChildItem -Path $unitRoot -Filter '*.Tests.ps1' -File -Recurse |
    Select-Object -ExpandProperty FullName)
if ($testFiles.Count -eq 0) {
    throw "[unit] No test files found under $unitRoot"
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
