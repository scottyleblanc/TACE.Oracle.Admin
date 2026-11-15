#Requires -Version 7.6
<#
.SYNOPSIS
    Runs the static tier: checks that read source text and run no module code.

.DESCRIPTION
    Runs every test under Tests\Static\. These checks are fast and are meant to run on
    every change. Rule T-10.

    Writes NUnit XML results to Tests\TestResults\static.xml, replacing the previous run.
    Exits 1 when any check fails or any test file fails to run, and 0 otherwise.

.EXAMPLE
    .\Scripts\Invoke-StaticTest.ps1

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
$staticPath  = Join-Path -Path $testsRoot -ChildPath 'Static'
$resultsDir  = Join-Path -Path $testsRoot -ChildPath 'TestResults'
$resultsFile = Join-Path -Path $resultsDir -ChildPath 'static.xml'

$null = New-Item -Path $resultsDir -ItemType Directory -Force

$config = New-PesterConfiguration
$config.Run.Path                = $staticPath
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
Write-Output ('{0} static: {1} passed, {2} failed, {3} skipped, {4} file(s) failed to run. Results: {5}' -f
    $label, $result.PassedCount, $result.FailedCount, $result.SkippedCount, $result.FailedContainersCount, $resultsFile)

if ($failed) { exit 1 }

# Explicit, so a caller never reads a $LASTEXITCODE left over from an earlier command.
exit 0
