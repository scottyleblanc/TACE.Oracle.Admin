#Requires -Version 7.6
<#
.SYNOPSIS
    Proves that the tests cited for each invariant fail when the invariant is broken
    (rule I-10), by breaking the code in a temporary copy and running those tests.

.DESCRIPTION
    Reads the mutations in Tests\Mutation\InvariantMutations.psd1. Each one names an
    invariant (function and identifier) and an exact edit to one source file: Find is
    replaced by Replace, or the file is moved to MoveTo.

    The script:
      1. Refuses to run if a security invariant with a cited test or static check has no
         mutation, or if any Find text does not occur exactly once in its file.
      2. Copies the files the next commit could contain into a new folder under the
         system temp folder. This repository is never changed.
      3. For each test file involved, runs it once unmutated: every cited test must pass.
      4. For each mutation, applies it, builds the module in a fresh pwsh process, runs
         the cited test file (Tests\Unit\...) or, for a static proof, the static file,
         and restores the file.

    A mutation is caught when at least one cited test fails. It survives when every
    cited test passes. The copy is deleted at the end.

    It takes several minutes: every mutation builds the module and runs a test file.
    It is a local check, not part of the gate.

.PARAMETER MutationPath
    The mutation data file. Defaults to Tests\Mutation\InvariantMutations.psd1.

.PARAMETER Function
    Runs only the mutations for these functions. The coverage check still covers all.

.PARAMETER RunTimeoutSeconds
    How long one build-and-test run may take. A mutated run still going after this is
    killed and counts as caught: the mutation turned a bounded wait into a hang. A
    control run that times out is a failure. Defaults to 300.

.EXAMPLE
    .\Scripts\Test-InvariantMutation.ps1

    Runs every mutation. Exits 0 when all are caught, 1 otherwise.

.EXAMPLE
    .\Scripts\Test-InvariantMutation.ps1 -Function Invoke-RmanProcess

    Runs the mutations for one function.

.NOTES
    Copyright © TACE Data Management Inc.
    **Invocation:** Standalone — self-contained; safe to run with `pwsh -File`. Needs
    git and Pester 5 (PREREQUISITES.md). Writes only inside its temporary copy.
#>
[CmdletBinding(PositionalBinding = $false)]
[OutputType([string])]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $MutationPath = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Tests' -AdditionalChildPath 'Mutation', 'InvariantMutations.psd1'),

    [Parameter()]
    [ValidateNotNull()]
    [string[]] $Function = @(),

    [Parameter()]
    [ValidateRange(30, 3600)]
    [int] $RunTimeoutSeconds = 300
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot   = Split-Path -Path $PSScriptRoot -Parent
$tempRoot   = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$copy       = Join-Path -Path $tempRoot -ChildPath ('tace-mutation-' + [guid]::NewGuid().ToString('N'))
$staticFile = Join-Path -Path 'Tests' -ChildPath 'Static' -AdditionalChildPath 'SourceInvariants.Tests.ps1'

# Every write below goes inside the copy. This refuses anything else.
function Assert-InCopy {
    [OutputType([void])]
    param([Parameter(Mandatory)] [string] $Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith($copy + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "[Test-InvariantMutation] Refusing to write outside the temporary copy: $full"
    }
}

# Builds the module in the copy and runs one test file, in a fresh process so no module
# state or environment change carries from one run to the next. A run that passes
# $RunTimeoutSeconds has its process tree killed and is reported as TimedOut: a mutation
# can turn a bounded wait into a hang, which a test cannot report as a failure.
$runTemplate = @'
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$copyRoot = '__COPY__'
$testFile = '__TEST__'
$outFile  = '__OUT__'
$record = try {
    $null = & (Join-Path -Path $copyRoot -ChildPath 'Scripts' -AdditionalChildPath 'Build-Module.ps1') *>&1
    Import-Module Pester -MinimumVersion 5.0
    $config = New-PesterConfiguration
    $config.Run.Path         = [string[]]@((Join-Path -Path $copyRoot -ChildPath $testFile))
    $config.Run.PassThru     = $true
    $config.Output.Verbosity = 'None'
    $result = Invoke-Pester -Configuration $config
    [PSCustomObject]@{
        BuildFailed = $false; TimedOut = $false; Error = ''
        Tests = @($result.Tests | ForEach-Object { [PSCustomObject]@{ Name = $PSItem.Name; ExpandedName = $PSItem.ExpandedName; Result = "$($PSItem.Result)" } })
    }
}
catch {
    [PSCustomObject]@{ BuildFailed = $true; TimedOut = $false; Error = "$($PSItem.Exception.Message)"; Tests = @() }
}
[System.IO.File]::WriteAllText($outFile, (ConvertTo-Json -InputObject $record -Depth 5), [System.Text.UTF8Encoding]::new($false))
'@

function Invoke-CopyTestFile {
    [OutputType([PSCustomObject])]
    param([Parameter(Mandatory)] [string] $TestFile)

    $outFile = Join-Path -Path $copy -ChildPath ('run-' + [guid]::NewGuid().ToString('N') + '.json')
    Assert-InCopy -Path $outFile
    # The paths are under the temp folder and this repository; neither holds a quote.
    $script = $runTemplate.Replace('__COPY__', $copy).Replace('__TEST__', $TestFile).Replace('__OUT__', $outFile)
    $encoded = [System.Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($script))

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName        = (Get-Process -Id $PID).Path
    $psi.Arguments       = "-NoProfile -NonInteractive -EncodedCommand $encoded"
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow  = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    try {
        $null = $process.Start()
        $null = $process.StandardOutput.ReadToEndAsync()
        $null = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($RunTimeoutSeconds * 1000)) {
            try { $process.Kill($true) } catch { Write-Verbose "[Test-InvariantMutation] KILL failed at $([datetime]::UtcNow.ToString('o'))" }
            $null = $process.WaitForExit(10000)
            return [PSCustomObject]@{ BuildFailed = $false; TimedOut = $true; Error = ''; Tests = @() }
        }
        $null = $process.WaitForExit()
    }
    finally {
        $process.Dispose()
    }

    if (-not (Test-Path -LiteralPath $outFile)) {
        return [PSCustomObject]@{ BuildFailed = $true; TimedOut = $false; Error = 'the run wrote no result'; Tests = @() }
    }
    $record = Get-Content -LiteralPath $outFile -Raw | ConvertFrom-Json
    Remove-Item -LiteralPath $outFile
    $record
}

# The result of each cited title in a run: Passed, Failed, Skipped or NotFound. A title
# with -ForEach cases counts as Failed when any case fails.
function Get-CitedResult {
    [OutputType([PSCustomObject])]
    param([Parameter(Mandatory)] [PSCustomObject] $Run, [Parameter(Mandatory)] [string[]] $Title)
    foreach ($item in $Title) {
        $hits = @($Run.Tests | Where-Object { $PSItem.Name -eq $item -or $PSItem.ExpandedName -eq $item })
        $result = if ($hits.Count -eq 0) { 'NotFound' }
                  elseif (@($hits | Where-Object { $PSItem.Result -eq 'Failed' }).Count -gt 0) { 'Failed' }
                  elseif (@($hits | Where-Object { $PSItem.Result -eq 'Passed' }).Count -eq $hits.Count) { 'Passed' }
                  else { $hits[0].Result }
        [PSCustomObject]@{ Title = $item; Result = $result }
    }
}

# --- Load and check the mutations ------------------------------------------------------
$mutations = @((Import-PowerShellDataFile -LiteralPath $MutationPath).Mutations)
$lint      = & (Join-Path -Path $repoRoot -ChildPath 'Tests' -AdditionalChildPath 'Lint', 'Invoke-InvariantLint.ps1') -RepoRoot $repoRoot
if (-not $lint.Success) { throw "[Test-InvariantMutation] The invariant linter fails: $($lint.Message)" }
$catalog = @($lint.Data.Catalog)

$uncovered = @($catalog | Where-Object {
        $entry = $PSItem
        $entry.Sec -and $entry.State -eq 'Proven' -and
        @($mutations | Where-Object { $PSItem.Function -eq $entry.Function -and $PSItem.Id -eq $entry.Id }).Count -eq 0
    })
if ($uncovered.Count -gt 0) {
    throw "[Test-InvariantMutation] Security invariants with no mutation: $(@($uncovered | ForEach-Object { "$($PSItem.Function) $($PSItem.Id)" }) -join ', ')"
}

$plan = [System.Collections.Generic.List[PSCustomObject]]::new()
foreach ($mutation in $mutations) {
    $entry = @($catalog | Where-Object { $PSItem.Function -eq $mutation.Function -and $PSItem.Id -eq $mutation.Id })
    if ($entry.Count -ne 1) { throw "[Test-InvariantMutation] No invariant $($mutation.Function) $($mutation.Id)." }
    if ($entry[0].State -ne 'Proven') { throw "[Test-InvariantMutation] $($mutation.Function) $($mutation.Id) is not proven; nothing to run." }

    $moveTo  = if ($mutation.ContainsKey('MoveTo')) { $mutation.MoveTo } else { '' }
    $find    = if ($mutation.ContainsKey('Find')) { $mutation.Find } else { '' }
    $replace = if ($mutation.ContainsKey('Replace')) { $mutation.Replace } else { '' }
    if ($moveTo -eq '') {
        if ($find -eq '') { throw "[Test-InvariantMutation] $($mutation.Function) $($mutation.Id) '$($mutation.Label)': give Find and Replace, or MoveTo." }
        $text  = [System.IO.File]::ReadAllText((Join-Path -Path $repoRoot -ChildPath $mutation.File))
        $count = ([regex]::Matches($text, [regex]::Escape($find))).Count
        if ($count -ne 1) { throw "[Test-InvariantMutation] $($mutation.Function) $($mutation.Id) '$($mutation.Label)': Find occurs $count times in $($mutation.File)." }
    }

    $testFile = if ($entry[0].ProofKind -eq 'Static') { $staticFile } else {
        $folder = Split-Path -Path (Split-Path -Path $entry[0].File -Parent) -Leaf
        $name   = [System.IO.Path]::GetFileNameWithoutExtension($entry[0].File)
        Join-Path -Path 'Tests' -ChildPath 'Unit' -AdditionalChildPath $folder, "$name.Tests.ps1"
    }

    if ($Function.Count -gt 0 -and $Function -notcontains $mutation.Function) { continue }
    $plan.Add([PSCustomObject]@{
            Function = $mutation.Function; Id = $mutation.Id; Label = $mutation.Label; Sec = $entry[0].Sec
            File = $mutation.File; Find = $find; Replace = $replace; MoveTo = $moveTo
            TestFile = $testFile; Titles = @($entry[0].ProofTitles)
        })
}
Write-Output "[INFO] $($plan.Count) mutation(s) to run; every security invariant with a proof is covered."

$caught   = 0
$problems = 0
try {
    # --- Build the copy ----------------------------------------------------------------
    $null = New-Item -Path $copy -ItemType Directory
    $listed = @(& git -C $repoRoot ls-files --cached --others --exclude-standard)
    if ($LASTEXITCODE -ne 0) { throw '[Test-InvariantMutation] git ls-files failed: this needs a git checkout.' }
    foreach ($relative in $listed) {
        $source = Join-Path -Path $repoRoot -ChildPath $relative
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { continue }
        $target = Join-Path -Path $copy -ChildPath $relative
        Assert-InCopy -Path $target
        $null = New-Item -Path (Split-Path -Path $target -Parent) -ItemType Directory -Force
        Copy-Item -LiteralPath $source -Destination $target
    }

    # --- Control runs ------------------------------------------------------------------
    $controls = @{}
    foreach ($testFile in @($plan | ForEach-Object { $PSItem.TestFile } | Sort-Object -Unique)) {
        $controls[$testFile] = Invoke-CopyTestFile -TestFile $testFile
    }

    # --- Mutations ---------------------------------------------------------------------
    foreach ($item in $plan) {
        $control = $controls[$item.TestFile]
        $controlBad = @(Get-CitedResult -Run $control -Title $item.Titles | Where-Object { $PSItem.Result -ne 'Passed' })
        if ($control.BuildFailed -or $controlBad.Count -gt 0) {
            $problems++
            Write-Output "[FAIL] $($item.Function) $($item.Id) - $($item.Label): a cited test does not pass unmutated: $(@($controlBad | ForEach-Object { "$($PSItem.Result) '$($PSItem.Title)'" }) -join '; ')"
            continue
        }

        $target   = Join-Path -Path $copy -ChildPath $item.File
        Assert-InCopy -Path $target
        $original = [System.IO.File]::ReadAllText($target)
        $moved    = ''
        try {
            if ($item.MoveTo -ne '') {
                $moved = Join-Path -Path $copy -ChildPath $item.MoveTo
                Assert-InCopy -Path $moved
                Move-Item -LiteralPath $target -Destination $moved
            }
            else {
                [System.IO.File]::WriteAllText($target, $original.Replace($item.Find, $item.Replace), [System.Text.UTF8Encoding]::new($false))
            }
            $run = Invoke-CopyTestFile -TestFile $item.TestFile
        }
        finally {
            if ($moved -ne '' -and (Test-Path -LiteralPath $moved)) { Move-Item -LiteralPath $moved -Destination $target }
            [System.IO.File]::WriteAllText($target, $original, [System.Text.UTF8Encoding]::new($false))
        }

        $tag = if ($item.Sec) { ' [SEC]' } else { '' }
        if ($run.TimedOut) {
            # The cited tests hang instead of passing: in the unit tier the run never
            # completes, so the defect cannot pass unnoticed.
            $caught++
            Write-Output "[PASS] $($item.Function) $($item.Id)$tag - $($item.Label): caught; the test run hung and was killed after $RunTimeoutSeconds seconds"
            continue
        }
        if ($run.BuildFailed) {
            $problems++
            Write-Output "[FAIL] $($item.Function) $($item.Id)$tag - $($item.Label): the mutated module does not build."
            continue
        }
        $failed = @(Get-CitedResult -Run $run -Title $item.Titles | Where-Object { $PSItem.Result -eq 'Failed' })
        if ($failed.Count -gt 0) {
            $caught++
            Write-Output "[PASS] $($item.Function) $($item.Id)$tag - $($item.Label): caught by '$($failed[0].Title)'"
        }
        else {
            $problems++
            Write-Output "[FAIL] $($item.Function) $($item.Id)$tag - $($item.Label): survived; every cited test passed"
        }
    }
}
finally {
    if (Test-Path -LiteralPath $copy) { Remove-Item -LiteralPath $copy -Recurse -Force }
}

$label = if ($problems -eq 0) { '[PASS]' } else { '[FAIL]' }
Write-Output "$label mutation: $caught of $($plan.Count) caught, $problems not."
if ($problems -gt 0) { exit 1 }
exit 0
