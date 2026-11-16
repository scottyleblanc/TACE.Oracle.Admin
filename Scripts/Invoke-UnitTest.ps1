#Requires -Version 7.6
<#
.SYNOPSIS
    Runs the unit tier: Pester tests that run module functions against mocks.

.DESCRIPTION
    Builds the module first (Scripts\Build-Module.ps1), then runs every *.Tests.ps1 file
    under Tests\Unit\, searching its subfolders (Public\, Private\, Module\). The tests
    import the built module from Output\, so they never run against a stale build. The
    static tier (Tests\Static\) and the integration tier
    (Tests\Integration\) are outside Tests\Unit\ and are not run here. Rule T-10.

    A failed build stops the run before any test starts, and exits 1.

    Writes NUnit XML results to Tests\TestResults\unit.xml, replacing the previous run.

    Measures code coverage of the built .psm1 while the tests run, and maps each
    command back to its file under Source\ through the #region markers the build writes.
    Prints the share of commands run per source file and overall, and writes JaCoCo XML
    to Tests\TestResults\coverage.xml. Rule T-12: the overall figure must not fall below
    $coverageFloor. Pester counts commands, not lines, so a line with an if/else counts
    as missed when one branch never runs. With -Verbose, every missed command is listed
    by source file and line.

    Exits 1 when any test fails, any test file fails to run, or coverage is below the
    floor, and 0 otherwise.

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
$coverageFile = Join-Path -Path $resultsDir -ChildPath 'coverage.xml'

# Rule T-12: the minimum share of commands in Source\ that the unit tests run. Set at
# Stack 3 from 97.7% measured, rounded down to leave room for a new function's gaps.
# Raise it when coverage rises; lower it only by a decision recorded in Docs\TODO.md.
$coverageFloor = 95.0

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

# The built .psm1 the tests import: the manifest path from the same helper they use.
$getBuiltPath = Join-Path -Path $unitRoot -ChildPath 'Get-BuiltModulePath.ps1'
$builtPsm1    = [System.IO.Path]::ChangeExtension((& $getBuiltPath), '.psm1')

$config = New-PesterConfiguration
$config.Run.Path                  = [string[]]$testFiles
$config.Run.PassThru              = $true
$config.Output.Verbosity          = 'Detailed'
$config.TestResult.Enabled        = $true
$config.TestResult.OutputFormat   = 'NUnitXml'
$config.TestResult.OutputPath     = $resultsFile
$config.CodeCoverage.Enabled      = $true
$config.CodeCoverage.Path         = [string[]]@($builtPsm1)
$config.CodeCoverage.OutputFormat = 'JaCoCo'
$config.CodeCoverage.OutputPath   = $coverageFile
# Pester prints its own summary against this target; keep it the same as the floor.
$config.CodeCoverage.CoveragePercentTarget = $coverageFloor

$result = Invoke-Pester -Configuration $config

# A failure above any Describe block (a parse error, or a throwing file-level block) counts
# only in FailedContainersCount. Checking FailedCount alone would pass a run in which a
# whole test file never ran.
$failed = $result.FailedCount -gt 0 -or $result.FailedContainersCount -gt 0

$label = if ($failed) { '[FAIL]' } else { '[PASS]' }
Write-Output ('{0} unit: {1} passed, {2} failed, {3} skipped, {4} file(s) failed to run. Results: {5}' -f
    $label, $result.PassedCount, $result.FailedCount, $result.SkippedCount, $result.FailedContainersCount, $resultsFile)

# -- Coverage, mapped back to Source\ ------------------------------------------------

# The build wraps each source file in '#region Source\<folder>\<file>' and
# '#endregion ...', with one blank line after the #region line. A merged line between
# them maps to source line (merged line - region line - 1).
$mergedLines = [System.IO.File]::ReadAllLines($builtPsm1)
$regions     = [System.Collections.Generic.List[PSCustomObject]]::new()
$openFile    = $null
$openLine    = 0
for ($i = 0; $i -lt $mergedLines.Count; $i++) {
    if ($mergedLines[$i] -match '^#region (?<file>Source\\.+)$') {
        $openFile = $Matches['file']
        $openLine = $i + 1
    }
    elseif ($null -ne $openFile -and $mergedLines[$i] -match '^#endregion ') {
        $regions.Add([PSCustomObject]@{ File = $openFile; Start = $openLine; End = $i + 1 })
        $openFile = $null
    }
}

$toSource = {
    param([int]$Line)
    foreach ($region in $regions) {
        if ($Line -gt $region.Start + 1 -and $Line -lt $region.End) {
            return [PSCustomObject]@{ File = $region.File; Line = $Line - $region.Start - 1 }
        }
    }
    [PSCustomObject]@{ File = '(module loader)'; Line = $Line }
}

$coverage = $result.CodeCoverage
$commands = @(
    foreach ($command in $coverage.CommandsExecuted) {
        $mapped = & $toSource $command.Line
        [PSCustomObject]@{ File = $mapped.File; Line = $mapped.Line; Hit = $true; Command = $command.Command }
    }
    foreach ($command in $coverage.CommandsMissed) {
        $mapped = & $toSource $command.Line
        [PSCustomObject]@{ File = $mapped.File; Line = $mapped.Line; Hit = $false; Command = $command.Command }
    }
)

Write-Output '[INFO] coverage: the Missed commands list above numbers lines in the merged .psm1. Per source file below; run with -Verbose for each missed command by source line.'
foreach ($group in @($commands | Group-Object -Property File | Sort-Object -Property Name)) {
    $hit = @($group.Group | Where-Object { $PSItem.Hit }).Count
    Write-Output ('       {0,-55} {1,4} of {2,-4} {3,6:N1}%' -f $group.Name, $hit, $group.Count, (100 * $hit / $group.Count))
}
foreach ($missed in @($commands | Where-Object { -not $PSItem.Hit } | Sort-Object -Property File, Line)) {
    $text = ($missed.Command -split "`n")[0].Trim()
    Write-Verbose ('[Invoke-UnitTest] Missed: {0}:{1}  {2}' -f $missed.File, $missed.Line, $text)
}

$hitTotal = @($commands | Where-Object { $PSItem.Hit }).Count
$percent  = if ($commands.Count -gt 0) { 100 * $hitTotal / $commands.Count } else { 0 }
$coverageFailed = $percent -lt $coverageFloor

$label = if ($coverageFailed) { '[FAIL]' } else { '[PASS]' }
Write-Output ('{0} coverage: {1:N1}% of commands ({2} of {3}), floor {4:N1}%. Results: {5}' -f
    $label, $percent, $hitTotal, $commands.Count, $coverageFloor, $coverageFile)

if ($failed -or $coverageFailed) { exit 1 }

# Explicit, so a caller never reads a $LASTEXITCODE left over from an earlier command.
exit 0
