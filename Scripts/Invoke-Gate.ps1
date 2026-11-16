#Requires -Version 7.6
<#
.SYNOPSIS
    Runs every static check in one command: the gate.

.DESCRIPTION
    Runs each check in turn, reports [PASS] or [FAIL] for each, and exits 1 if any
    failed. Every check runs even after an earlier one fails, so one run shows every
    problem.

      1. tools      PSScriptAnalyzer 1.25.0, gitleaks 8.30.1 and Pester 5 are installed
      2. analyzer   PSScriptAnalyzer with Tests\Lint\PSScriptAnalyzerSettings.psd1, the
                    built-in and custom rules, over Source\, Scripts\ and Tests\Lint\
                    (not *.Tests.ps1). Any finding fails (decisions 25 and 26)
      3. static     The static tier, Scripts\Invoke-StaticTest.ps1
      4. secrets    gitleaks over the working tree, using .gitleaks.toml
      5. commits    gitleaks over every commit not yet on a remote
      6. messages   The messages of those commits, through gitleaks and the S-16
                    patterns in Tests\Lint\PublicRepoPatterns.psd1. gitleaks does not
                    read commit messages, so they are checked separately

    "Not yet on a remote" means not reachable from any remote-tracking branch, as git
    last saw it. A branch never pushed has all its commits checked.

    Found values are never printed in full: gitleaks runs with --redact, and a pattern
    match shows only its first characters.

    The unit tier is not part of the gate. It runs module code against mocks; the gate
    holds the checks that read source text.

    With -Integration, a seventh check runs the integration tier
    (Scripts\Invoke-IntegrationTest.ps1) against the local Oracle database, after the six
    above. Its own guards decide whether it may run; a failed guard fails the check. The
    pre-push hook never passes -Integration.

.PARAMETER Integration
    Also run the integration tier. Needs the local integration setup and the opt-in
    variable; see Scripts\Invoke-IntegrationTest.ps1.

.EXAMPLE
    .\Scripts\Invoke-Gate.ps1

    Runs the gate from any working directory. Exits 0 when every check passes.

.EXAMPLE
    $env:ORACLE_ADMIN_RUN_INTEGRATION = '1'
    .\Scripts\Invoke-Gate.ps1 -Integration

    Runs the gate, then the integration tier.

.NOTES
    Copyright © TACE Data Management Inc.
    **Invocation:** Standalone — self-contained; safe to run with `pwsh -File`. Runs from
    any working directory: every path is resolved from this script's location. Called
    by .githooks\pre-push before every push.
#>
[CmdletBinding()]
[OutputType([string])]
param(
    [Parameter()]
    [switch]$Integration
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Path $PSScriptRoot -Parent

$requiredAnalyzer = [version]'1.25.0'
$requiredGitleaks = '8.30.1'

$results = [System.Collections.Generic.List[object]]::new()

# Records one check. $Detail lines are printed under a failure.
function Add-Result {
    [OutputType([void])]
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [bool] $Passed,
        [Parameter(Mandatory)] [string] $Summary,
        [string[]] $Detail = @()
    )
    $results.Add([PSCustomObject]@{ Name = $Name; Passed = $Passed; Summary = $Summary; Detail = $Detail })
    $label = if ($Passed) { '[PASS]' } else { '[FAIL]' }
    Write-Output "$label $Name : $Summary"
    if (-not $Passed) { foreach ($line in $Detail) { Write-Output "       $line" } }
}

# Shows the first characters of a value and hides the rest.
function Get-Prefix {
    [OutputType([string])]
    param([Parameter(Mandatory)] [string] $Value)
    $Value.Substring(0, [Math]::Min(6, $Value.Length)) + '***'
}

# -- 1. tools ----------------------------------------------------------------

$analyzerModule = Get-Module -Name PSScriptAnalyzer -ListAvailable | Where-Object { $PSItem.Version -eq $requiredAnalyzer } | Select-Object -First 1
$pesterModule   = Get-Module -Name Pester -ListAvailable | Where-Object { $PSItem.Version.Major -ge 5 } | Select-Object -First 1
$gitleaks       = Get-Command -Name gitleaks -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$gitleaksVersion = if ($null -ne $gitleaks) { ((& $gitleaks.Source version) | Select-Object -First 1).Trim() } else { $null }
$git            = Get-Command -Name git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1

$toolProblems = @(
    if ($null -eq $analyzerModule) { "PSScriptAnalyzer $requiredAnalyzer is not installed: Install-PSResource PSScriptAnalyzer -Version $requiredAnalyzer" }
    if ($null -eq $pesterModule) { 'Pester 5 is not installed: Install-Module Pester -MinimumVersion 5.0' }
    if ($null -eq $gitleaks) { "gitleaks is not on PATH: winget install --id Gitleaks.Gitleaks --version $requiredGitleaks --exact" }
    elseif ($gitleaksVersion -ne $requiredGitleaks) { "gitleaks $gitleaksVersion found; $requiredGitleaks is required" }
    if ($null -eq $git) { 'git is not on PATH' }
)
Add-Result -Name 'tools' -Passed ($toolProblems.Count -eq 0) -Summary $(if ($toolProblems.Count -eq 0) { "PSScriptAnalyzer $requiredAnalyzer, gitleaks $requiredGitleaks, Pester $($pesterModule.Version), git" } else { "$($toolProblems.Count) missing or wrong version" }) -Detail $toolProblems

# -- 2. analyzer -------------------------------------------------------------

if ($null -eq $analyzerModule) {
    Add-Result -Name 'analyzer' -Passed $false -Summary 'not run: PSScriptAnalyzer is missing'
}
else {
    Import-Module -Name PSScriptAnalyzer -RequiredVersion $requiredAnalyzer
    $settings = Join-Path -Path $repoRoot -ChildPath 'Tests' -AdditionalChildPath 'Lint', 'PSScriptAnalyzerSettings.psd1'
    $covered  = @(
        Join-Path -Path $repoRoot -ChildPath 'Source'
        Join-Path -Path $repoRoot -ChildPath 'Scripts'
        Join-Path -Path $repoRoot -ChildPath 'Tests' -AdditionalChildPath 'Lint'
    )
    $files = @(Get-ChildItem -Path $covered -Include '*.ps1', '*.psm1', '*.psd1' -Recurse -File |
        Where-Object { $PSItem.Name -notlike '*.Tests.ps1' })

    # The settings load the custom rules by a path relative to the current directory.
    Push-Location -Path $repoRoot
    try {
        $findings = @(foreach ($file in $files) { Invoke-ScriptAnalyzer -Path $file.FullName -Settings $settings })
    }
    finally {
        Pop-Location
    }
    $detail = @($findings | ForEach-Object {
        $relative = [System.IO.Path]::GetRelativePath($repoRoot, $PSItem.ScriptPath)
        "${relative}:$($PSItem.Line) $($PSItem.RuleName): $($PSItem.Message)"
    })
    Add-Result -Name 'analyzer' -Passed ($findings.Count -eq 0) -Summary "$($findings.Count) finding(s) over $($files.Count) files" -Detail $detail
}

# -- 3. static ---------------------------------------------------------------

$staticScript = Join-Path -Path $PSScriptRoot -ChildPath 'Invoke-StaticTest.ps1'
$staticOutput = @(& pwsh -NoProfile -File $staticScript 2>&1 | ForEach-Object { "$PSItem" })
$staticExit   = $LASTEXITCODE
$staticLast   = @($staticOutput | Where-Object { $PSItem -match '^\[(PASS|FAIL)\] static' }) | Select-Object -Last 1
$staticFailed = @($staticOutput | Where-Object { $PSItem -match '^\s*\[-\]' } | ForEach-Object { $PSItem.Trim() })
Add-Result -Name 'static' -Passed ($staticExit -eq 0) -Summary $(if ($staticLast) { $staticLast -replace '^\[(PASS|FAIL)\] static: ', '' } else { "exit $staticExit" }) -Detail $staticFailed

# -- 4 to 6 need gitleaks and git --------------------------------------------

$gitleaksReady = $null -ne $gitleaks -and $gitleaksVersion -eq $requiredGitleaks
$config        = Join-Path -Path $repoRoot -ChildPath '.gitleaks.toml'

if (-not $gitleaksReady) {
    Add-Result -Name 'secrets' -Passed $false -Summary "not run: gitleaks $requiredGitleaks is missing"
}
else {
    $out = @(& $gitleaks.Source dir $repoRoot --config $config --redact --no-banner 2>&1 | ForEach-Object { "$PSItem" })
    $exit = $LASTEXITCODE
    Add-Result -Name 'secrets' -Passed ($exit -eq 0) -Summary $(if ($exit -eq 0) { 'no leaks in the working tree' } else { 'leaks found in the working tree' }) -Detail @($out | Where-Object { $PSItem -match 'Finding|File|Line|RuleID|leaks found' })
}

$unpushed = @()
if ($null -ne $git) {
    $unpushed = @(& $git.Source -C $repoRoot rev-list HEAD --not --remotes 2>$null)
    if ($LASTEXITCODE -ne 0) { $unpushed = $null }
}

if ($null -eq $git -or $null -eq $unpushed) {
    Add-Result -Name 'commits' -Passed $false -Summary 'not run: this is not a git checkout'
    Add-Result -Name 'messages' -Passed $false -Summary 'not run: this is not a git checkout'
}
elseif ($unpushed.Count -eq 0) {
    Add-Result -Name 'commits' -Passed $true -Summary 'no unpushed commits'
    Add-Result -Name 'messages' -Passed $true -Summary 'no unpushed commits'
}
else {
    if (-not $gitleaksReady) {
        Add-Result -Name 'commits' -Passed $false -Summary "not run: gitleaks $requiredGitleaks is missing"
    }
    else {
        $out = @(& $gitleaks.Source git $repoRoot --config $config --redact --no-banner --log-opts 'HEAD --not --remotes' 2>&1 | ForEach-Object { "$PSItem" })
        $exit = $LASTEXITCODE
        Add-Result -Name 'commits' -Passed ($exit -eq 0) -Summary $(if ($exit -eq 0) { "no leaks in $($unpushed.Count) unpushed commit(s)" } else { 'leaks found in unpushed commits' }) -Detail @($out | Where-Object { $PSItem -match 'Finding|File|Commit|RuleID|leaks found' })
    }

    $patternFile = Join-Path -Path $repoRoot -ChildPath 'Tests' -AdditionalChildPath 'Lint', 'PublicRepoPatterns.psd1'
    $patterns    = @((Import-PowerShellDataFile -LiteralPath $patternFile).Patterns)
    $problems    = [System.Collections.Generic.List[string]]::new()

    foreach ($commit in $unpushed) {
        $short   = $commit.Substring(0, 7)
        $message = (& $git.Source -C $repoRoot log -1 --format=%B $commit) -join "`n"

        foreach ($pattern in $patterns) {
            foreach ($match in [regex]::Matches($message, $pattern.Pattern)) {
                if ($pattern.Allow -and $match.Value -match $pattern.Allow) { continue }
                $problems.Add("commit ${short}: $($pattern.Id) $($pattern.Title): $(Get-Prefix -Value $match.Value)")
            }
        }

        if ($gitleaksReady) {
            $null = $message | & $gitleaks.Source stdin --config $config --redact --no-banner 2>&1
            if ($LASTEXITCODE -ne 0) { $problems.Add("commit ${short}: gitleaks found a secret in the message") }
        }
    }
    if (-not $gitleaksReady) { $problems.Add("gitleaks $requiredGitleaks is missing, so messages were checked against the S-16 patterns only") }

    Add-Result -Name 'messages' -Passed ($problems.Count -eq 0) -Summary "$($unpushed.Count) unpushed commit message(s), $($problems.Count) problem(s)" -Detail @($problems)
}

# -- 7. integration, only with -Integration ----------------------------------

if ($Integration) {
    $integrationScript = Join-Path -Path $PSScriptRoot -ChildPath 'Invoke-IntegrationTest.ps1'
    $integrationOutput = @(& pwsh -NoProfile -File $integrationScript 2>&1 | ForEach-Object { "$PSItem" })
    $integrationExit   = $LASTEXITCODE
    $integrationLast   = @($integrationOutput | Where-Object { $PSItem -match '^\[(PASS|FAIL)\] integration' }) | Select-Object -Last 1
    $integrationFailed = @($integrationOutput | Where-Object { $PSItem -match '^\s*\[-\]' } | ForEach-Object { $PSItem.Trim() })
    $summary = if ($integrationLast) { $integrationLast -replace '^\[(PASS|FAIL)\] integration: ', '' } else { "exit $integrationExit" }
    Add-Result -Name 'integration' -Passed ($integrationExit -eq 0) -Summary $summary -Detail $integrationFailed
}

# -- Summary -----------------------------------------------------------------

$failed = @($results | Where-Object { -not $PSItem.Passed })
if ($failed.Count -gt 0) {
    Write-Output "[FAIL] gate: $($failed.Count) of $($results.Count) checks failed: $(($failed.Name) -join ', ')"
    exit 1
}

Write-Output "[PASS] gate: all $($results.Count) checks passed"
exit 0
