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
      7. version    Rule D-10. The manifest, Source\TACE.Oracle.Admin.psm1, every public
                    function's .NOTES and the newest CHANGELOG release name the same
                    version. With -Base, the tags too (below)

    "Not yet on a remote" means not reachable from any remote-tracking branch, as git
    last saw it. A branch never pushed has all its commits checked.

    In CI every commit is already on a remote, so "not yet on a remote" would check
    nothing. -Base names the branch a pull request merges into; with it, 'commits' and
    'messages' check the commits in Base..HEAD instead, 'version' also checks the tags,
    and three more checks run.

    The tag rule: the version is not lower than the latest v* tag; if it is already
    tagged, that tag is in HEAD's history and nothing under Source\ changed since Base.
    A change to the code under a released number fails until the version is bumped. A
    tag is made on the merge commit after the pull request merges, so a release's own
    pull request passes with its version not yet tagged.

      8. evidence   Rule T-14 (decision 30). When the commits since the merge base with
                    Base change Source\, Tests\Integration\LastRun.json at HEAD must
                    show a passing run on a clean tree (Evidence = true) of a commit
                    that HEAD contains, and nothing but that file may change between
                    that commit and HEAD. A change outside Source\ needs no evidence
      9. review     Decision 35. When the commits since the merge base with Base change
                    any file other than the two evidence files, Review\LastReview.json at
                    HEAD must show a completed review of a commit that HEAD contains and
                    Base does not (one this branch adds, so a record left by an earlier
                    pull request fails), from that merge base or an older one, and every
                    finding must have a Response
                    that starts with Fixed:, Rejected:, Accepted: or Deferred:
                    (Docs\REVIEW.md). Commits after the reviewed one are the author's
                    fixes. If git cannot list the changes, the check fails
     10. package    Builds the package (Scripts\Build-Module.ps1 -Package) and fails
                    unless it holds exactly the files the built manifest's FileList
                    names. Publish-PSResource packages the whole version folder and
                    ignores FileList, so this is what stops a stray file from shipping.
                    Nothing is published

    Found values are never printed in full: gitleaks runs with --redact, and a pattern
    match shows only its first characters.

    By default the gate holds only the checks that read source text, so the pre-push
    hook stays fast. Two switches add the test tiers that run module code:

      -Unit         'unit': the unit tier (Scripts\Invoke-UnitTest.ps1), coverage floor
                    included. Behaviour defects are caught here. CI passes this switch
      -Integration  'integration': the integration tier
                    (Scripts\Invoke-IntegrationTest.ps1) against the local Oracle
                    database. Its own guards decide whether it may run; a failed guard
                    fails the check

    They run after the checks above, unit first. The pre-push hook passes neither.

.PARAMETER Base
    The branch a pull request merges into, as a git revision (for example
    origin/master). Checks commits in Base..HEAD instead of the unpushed ones, adds the
    tag rule to 'version', and adds the 'evidence', 'review' and 'package' checks. CI
    passes it; the pre-push hook does not.

.PARAMETER Unit
    Also run the unit tier, with its coverage floor.

.PARAMETER Integration
    Also run the integration tier. Needs the local integration setup and the opt-in
    variable; see Scripts\Invoke-IntegrationTest.ps1.

.EXAMPLE
    .\Scripts\Invoke-Gate.ps1

    Runs the gate from any working directory. Exits 0 when every check passes.

.EXAMPLE
    .\Scripts\Invoke-Gate.ps1 -Unit

    Runs the gate, then the unit tier.

.EXAMPLE
    .\Scripts\Invoke-Gate.ps1 -Unit -Base origin/master

    Runs the gate over the commits a pull request adds to master, with the tag rule and
    the evidence, review and package checks, then the unit tier. This is what CI runs (.github\workflows\gate.yml).

.EXAMPLE
    $env:ORACLE_ADMIN_RUN_INTEGRATION = '1'
    .\Scripts\Invoke-Gate.ps1 -Unit -Integration

    Runs the gate, then the unit and integration tiers.

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
    [ValidatePattern('^[A-Za-z0-9_][A-Za-z0-9_./-]*$')]
    [string]$Base,

    [Parameter()]
    [switch]$Unit,

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

# Without -Base: commits not on any remote. With -Base: the commits a pull request adds.
$baseCommit = $null
$notReady   = $null
if ($null -eq $git) {
    $notReady = 'not run: git is not on PATH'
}
elseif ($Base) {
    $baseCommit = @(& $git.Source -C $repoRoot rev-parse --verify --quiet "$Base^{commit}" 2>$null) | Select-Object -First 1
    if ($LASTEXITCODE -ne 0 -or -not $baseCommit) { $notReady = "not run: base '$Base' is not a commit in this checkout" }
}

$rangeArgs  = if ($Base) { @('HEAD', '--not', $baseCommit) } else { @('HEAD', '--not', '--remotes') }
$rangeLabel = if ($Base) { "commit(s) since $Base" } else { 'unpushed commit(s)' }

$unpushed = @()
if ($null -eq $notReady) {
    $unpushed = @(& $git.Source -C $repoRoot rev-list @rangeArgs 2>$null)
    if ($LASTEXITCODE -ne 0) { $notReady = 'not run: this is not a git checkout' }
}

if ($null -ne $notReady) {
    Add-Result -Name 'commits' -Passed $false -Summary $notReady
    Add-Result -Name 'messages' -Passed $false -Summary $notReady
}
elseif ($unpushed.Count -eq 0) {
    Add-Result -Name 'commits' -Passed $true -Summary "no $rangeLabel"
    Add-Result -Name 'messages' -Passed $true -Summary "no $rangeLabel"
}
else {
    if (-not $gitleaksReady) {
        Add-Result -Name 'commits' -Passed $false -Summary "not run: gitleaks $requiredGitleaks is missing"
    }
    else {
        $out = @(& $gitleaks.Source git $repoRoot --config $config --redact --no-banner --log-opts ($rangeArgs -join ' ') 2>&1 | ForEach-Object { "$PSItem" })
        $exit = $LASTEXITCODE
        Add-Result -Name 'commits' -Passed ($exit -eq 0) -Summary $(if ($exit -eq 0) { "no leaks in $($unpushed.Count) $rangeLabel" } else { "leaks found in $rangeLabel" }) -Detail @($out | Where-Object { $PSItem -match 'Finding|File|Commit|RuleID|leaks found' })
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

    Add-Result -Name 'messages' -Passed ($problems.Count -eq 0) -Summary "messages of $($unpushed.Count) $rangeLabel, $($problems.Count) problem(s)" -Detail @($problems)
}

# -- 7. version --------------------------------------------------------------
# Rule D-10. Every run: the manifest, the root module, every public function's .NOTES
# and the newest CHANGELOG release name the same version. With -Base, also the tags:
# the version is not lower than the latest v* tag, and a version already tagged is in
# HEAD's history with no Source\ change since Base, so a released number never labels
# different code.

$versionProblems = [System.Collections.Generic.List[string]]::new()
$sourceRoot      = Join-Path -Path $repoRoot -ChildPath 'Source'
$moduleVersion   = [string](Import-PowerShellDataFile -LiteralPath (Join-Path -Path $sourceRoot -ChildPath 'TACE.Oracle.Admin.psd1')).ModuleVersion
$versionValid    = $moduleVersion -match '^\d+\.\d+\.\d+$'
if (-not $versionValid) { $versionProblems.Add("Source\TACE.Oracle.Admin.psd1: ModuleVersion '$moduleVersion' is not MAJOR.MINOR.PATCH") }

$notesFiles = @(
    Join-Path -Path $sourceRoot -ChildPath 'TACE.Oracle.Admin.psm1'
    Get-ChildItem -LiteralPath (Join-Path -Path $sourceRoot -ChildPath 'Public') -Filter '*.ps1' -File | Sort-Object -Property Name | ForEach-Object { $PSItem.FullName }
)
foreach ($file in $notesFiles) {
    $relative = [System.IO.Path]::GetRelativePath($repoRoot, $file)
    $found    = [regex]::Match([System.IO.File]::ReadAllText($file), '(?m)^\s*Version\s*:\s*(\S+)\s*$')
    if (-not $found.Success) { $versionProblems.Add("${relative}: no 'Version :' line in .NOTES") }
    elseif ($found.Groups[1].Value -ne $moduleVersion) { $versionProblems.Add("${relative}: .NOTES Version $($found.Groups[1].Value)") }
}

$changelogPath = Join-Path -Path $repoRoot -ChildPath 'Docs' -AdditionalChildPath 'CHANGELOG.md'
$newest        = [regex]::Match([System.IO.File]::ReadAllText($changelogPath), '(?m)^## \[(\d+\.\d+\.\d+)\]')
if (-not $newest.Success) { $versionProblems.Add('Docs\CHANGELOG.md: no release heading') }
elseif ($newest.Groups[1].Value -ne $moduleVersion) { $versionProblems.Add("Docs\CHANGELOG.md: newest release $($newest.Groups[1].Value)") }

$tagNote = ''
if ($Base) {
    if ($null -ne $notReady) {
        $versionProblems.Add("tags $notReady")
    }
    elseif ($versionValid) {
        $tagOut  = @(& $git.Source -C $repoRoot tag --list 'v*' 2>$null)
        $tagExit = $LASTEXITCODE
        $tagged  = @($tagOut | ForEach-Object { if ($PSItem -match '^v(\d+\.\d+\.\d+)$') { [version]$Matches[1] } })
        $current = [version]$moduleVersion
        $latest  = $tagged | Sort-Object -Descending | Select-Object -First 1
        if ($tagExit -ne 0) {
            # Fail closed: a check that cannot see the tags does not pass them.
            $versionProblems.Add('git could not list the tags')
        }
        elseif ($null -ne $latest -and $current -lt $latest) {
            $versionProblems.Add("version $moduleVersion is lower than the latest tag v$latest")
        }
        elseif ($tagged -contains $current) {
            $null = & $git.Source -C $repoRoot merge-base --is-ancestor "refs/tags/v$moduleVersion" HEAD 2>$null
            if ($LASTEXITCODE -ne 0) { $versionProblems.Add("v$moduleVersion is tagged on a commit this branch does not contain") }
            $changedOut = @(& $git.Source -C $repoRoot diff --name-only "$baseCommit...HEAD" 2>$null)
            if ($LASTEXITCODE -ne 0) {
                $versionProblems.Add("git could not list the files changed since $Base")
            }
            elseif (@($changedOut | Where-Object { $PSItem -like 'Source/*' }).Count -gt 0) {
                $versionProblems.Add("Source\ changed since $Base but v$moduleVersion is already released: bump the version in the manifest, the .NOTES blocks and the CHANGELOG")
            }
            $tagNote = "; v$moduleVersion already tagged"
        }
        else {
            $tagNote = if ($null -ne $latest) { "; not yet tagged, latest tag v$latest" } else { '; no tags yet' }
        }
    }
}
$versionSummary = if ($versionProblems.Count -eq 0) {
    "$moduleVersion in the manifest, $($notesFiles.Count) .NOTES blocks and the CHANGELOG$tagNote"
}
else {
    "version $moduleVersion does not agree everywhere (rule D-10)"
}
Add-Result -Name 'version' -Passed ($versionProblems.Count -eq 0) -Summary $versionSummary -Detail @($versionProblems)

# -- 8. evidence, only with -Base --------------------------------------------

if ($Base) {
    $evidencePath = 'Tests/Integration/LastRun.json'
    if ($null -ne $notReady) {
        Add-Result -Name 'evidence' -Passed $false -Summary $notReady
    }
    else {
        $changed       = @(& $git.Source -C $repoRoot diff --name-only "$baseCommit...HEAD" 2>$null)
        $changedExit   = $LASTEXITCODE
        $sourceChanged = @($changed | Where-Object { $PSItem -like 'Source/*' })
        if ($changedExit -ne 0) {
            # Fail closed: a check that cannot see the change does not pass it.
            Add-Result -Name 'evidence' -Passed $false -Summary "not run: git could not list the files changed since $Base"
        }
        elseif ($sourceChanged.Count -eq 0) {
            Add-Result -Name 'evidence' -Passed $true -Summary "Source\ not changed since $Base; no evidence needed"
        }
        else {
            $evidenceProblems = [System.Collections.Generic.List[string]]::new()
            $json = (& $git.Source -C $repoRoot show "HEAD:$evidencePath" 2>$null) -join "`n"
            $run  = $null
            if ($LASTEXITCODE -ne 0 -or -not $json) {
                $evidenceProblems.Add("$evidencePath is not in HEAD")
            }
            else {
                try { $run = $json | ConvertFrom-Json } catch { $evidenceProblems.Add("$evidencePath is not valid JSON") }
            }
            if ($null -ne $run) {
                $runCommit = if ($run.PSObject.Properties['Commit']) { "$($run.Commit)" } else { '' }
                if (-not ($run.PSObject.Properties['Evidence'] -and $run.Evidence -eq $true)) {
                    $evidenceProblems.Add("$evidencePath does not show Evidence = true: the run failed or the tree was not clean")
                }
                if ($runCommit -notmatch '^[0-9a-f]{40}$') {
                    $evidenceProblems.Add("$evidencePath names no commit")
                }
                else {
                    $null = & $git.Source -C $repoRoot merge-base --is-ancestor $runCommit HEAD 2>$null
                    if ($LASTEXITCODE -ne 0) {
                        $evidenceProblems.Add("the run's commit $($runCommit.Substring(0, 7)) is not in HEAD's history")
                    }
                    else {
                        $sinceOut = @(& $git.Source -C $repoRoot diff --name-only $runCommit HEAD 2>$null)
                        if ($LASTEXITCODE -ne 0) {
                            $evidenceProblems.Add("git could not list the files changed since the run's commit $($runCommit.Substring(0, 7))")
                        }
                        $since = @($sinceOut | Where-Object { $PSItem -and $PSItem -ne $evidencePath })
                        foreach ($path in $since) { $evidenceProblems.Add("changed after the run's commit $($runCommit.Substring(0, 7)): $path") }
                    }
                }
            }
            $summary = if ($evidenceProblems.Count -eq 0) {
                "Source\ changed; LastRun.json is current for $($run.Commit.Substring(0, 7))"
            }
            else {
                "Source\ changed; integration evidence is missing or stale (rule T-14)"
            }
            Add-Result -Name 'evidence' -Passed ($evidenceProblems.Count -eq 0) -Summary $summary -Detail @($evidenceProblems)
        }
    }
}

# -- 9. review, only with -Base ----------------------------------------------

if ($Base) {
    $reviewPath    = 'Review/LastReview.json'
    $evidenceFiles = @($reviewPath, 'Tests/Integration/LastRun.json')
    if ($null -ne $notReady) {
        Add-Result -Name 'review' -Passed $false -Summary $notReady
    }
    else {
        $mergeBase = @(& $git.Source -C $repoRoot merge-base $baseCommit HEAD 2>$null) | Select-Object -First 1
        $diffOut   = @(& $git.Source -C $repoRoot diff --name-only "$baseCommit...HEAD" 2>$null)
        $diffExit  = $LASTEXITCODE
        $reviewed  = @($diffOut | Where-Object { $PSItem -and $evidenceFiles -notcontains $PSItem })
        if ($diffExit -ne 0 -or -not $mergeBase) {
            # Fail closed: a check that cannot see the change does not pass it.
            Add-Result -Name 'review' -Passed $false -Summary "not run: git could not list the files changed since $Base"
        }
        elseif ($reviewed.Count -eq 0) {
            Add-Result -Name 'review' -Passed $true -Summary "no file changed since $Base; no review needed"
        }
        else {
            $reviewProblems = [System.Collections.Generic.List[string]]::new()
            $json   = (& $git.Source -C $repoRoot show "HEAD:$reviewPath" 2>$null) -join "`n"
            $record = $null
            if ($LASTEXITCODE -ne 0 -or -not $json) {
                $reviewProblems.Add("$reviewPath is not in HEAD: run Scripts\Invoke-ModelReview.ps1")
            }
            else {
                try { $record = $json | ConvertFrom-Json } catch { $reviewProblems.Add("$reviewPath is not valid JSON") }
            }
            if ($null -ne $record) {
                $names = @($record.PSObject.Properties.Name)
                if (-not ($names -contains 'SchemaVersion' -and $record.SchemaVersion -eq 1)) {
                    $reviewProblems.Add("$reviewPath is not schema version 1")
                }
                if (-not ($names -contains 'Completed' -and $record.Completed -eq $true)) {
                    $reviewProblems.Add("$reviewPath does not show a completed review")
                }
                $reviewCommit = if ($names -contains 'Commit') { "$($record.Commit)" } else { '' }
                $reviewBase   = if ($names -contains 'BaseCommit') { "$($record.BaseCommit)" } else { '' }
                # The review's base may be older than today's merge base: bringing the
                # branch up to date with Base moves the merge base forward, and the
                # review still covers every commit the branch adds.
                $baseCovered = $false
                if ($reviewBase -match '^[0-9a-f]{40}$') {
                    $null = & $git.Source -C $repoRoot merge-base --is-ancestor $reviewBase $mergeBase 2>$null
                    $baseCovered = $LASTEXITCODE -eq 0
                }
                if (-not $baseCovered) {
                    $reviewProblems.Add("the review's base is not the merge base with $Base or older: the review does not cover every commit since $Base")
                }
                if ($reviewCommit -notmatch '^[0-9a-f]{40}$') {
                    $reviewProblems.Add("$reviewPath names no commit")
                }
                else {
                    $null = & $git.Source -C $repoRoot merge-base --is-ancestor $reviewCommit HEAD 2>$null
                    if ($LASTEXITCODE -ne 0) {
                        $reviewProblems.Add("the reviewed commit $($reviewCommit.Substring(0, 7)) is not in HEAD's history")
                    }
                    # The reviewed commit must be one this branch adds. A record left by an
                    # earlier pull request names a commit already in Base, and passes every
                    # other test here. Exit 1 means "not an ancestor"; 0 or an error fails.
                    $null = & $git.Source -C $repoRoot merge-base --is-ancestor $reviewCommit $mergeBase 2>$null
                    if ($LASTEXITCODE -ne 1) {
                        $reviewProblems.Add("the reviewed commit $($reviewCommit.Substring(0, 7)) is already in ${Base}: the record is from an earlier pull request, run Scripts\Invoke-ModelReview.ps1")
                    }
                }
                if ($names -notcontains 'Findings') {
                    $reviewProblems.Add("$reviewPath has no Findings list")
                }
                else {
                    foreach ($finding in @($record.Findings | Where-Object { $null -ne $PSItem })) {
                        $id       = if ($finding.PSObject.Properties['Id']) { "$($finding.Id)" } else { '?' }
                        $response = if ($finding.PSObject.Properties['Response']) { "$($finding.Response)" } else { '' }
                        if ($response -notmatch '^(Fixed|Rejected|Accepted|Deferred): \S') {
                            $reviewProblems.Add("finding $id is not answered: its Response must start with Fixed:, Rejected:, Accepted: or Deferred:")
                        }
                    }
                }
            }
            $summary = if ($reviewProblems.Count -eq 0) {
                "LastReview.json covers $($record.Commit.Substring(0, 7)); $(@($record.Findings | Where-Object { $null -ne $PSItem }).Count) finding(s), all answered"
            }
            else {
                'the review is missing, incomplete or not answered (decision 35)'
            }
            Add-Result -Name 'review' -Passed ($reviewProblems.Count -eq 0) -Summary $summary -Detail @($reviewProblems)
        }
    }
}

# -- 10. package, only with -Base --------------------------------------------
# [SEC] Builds the package and fails unless it holds exactly the files FileList names
# (Scripts\Build-Module.ps1 -Package makes the comparison). Nothing is published.

if ($Base) {
    $buildScript  = Join-Path -Path $PSScriptRoot -ChildPath 'Build-Module.ps1'
    $buildOutput  = @(& pwsh -NoProfile -File $buildScript -Package 2>&1 | ForEach-Object { "$PSItem" })
    $buildExit    = $LASTEXITCODE
    $packageLine  = @($buildOutput | Where-Object { $PSItem -match '^\[Build-Module\] Package check : ' }) | Select-Object -Last 1
    # A mismatch lists its files; any other failure shows the last lines of the build.
    $packageFault = @($buildOutput | Where-Object { $PSItem -match '^\s*(not in FileList|in FileList, not in the package): ' } | ForEach-Object { $PSItem.Trim() })
    if ($packageFault.Count -eq 0) { $packageFault = @($buildOutput | Select-Object -Last 3) }
    $summary      = if ($buildExit -eq 0 -and $packageLine) { $packageLine -replace '^\[Build-Module\] Package check : ', '' -replace ' \[OK\]$', '' } else { "the package build failed (exit $buildExit)" }
    Add-Result -Name 'package' -Passed ($buildExit -eq 0 -and [bool]$packageLine) -Summary $summary -Detail $packageFault
}

# -- 11. unit, only with -Unit -----------------------------------------------

if ($Unit) {
    $unitScript = Join-Path -Path $PSScriptRoot -ChildPath 'Invoke-UnitTest.ps1'
    $unitOutput = @(& pwsh -NoProfile -File $unitScript 2>&1 | ForEach-Object { "$PSItem" })
    $unitExit   = $LASTEXITCODE
    $unitLast   = @($unitOutput | Where-Object { $PSItem -match '^\[(PASS|FAIL)\] unit' }) | Select-Object -Last 1
    $coverage   = @($unitOutput | Where-Object { $PSItem -match '^\[(PASS|FAIL)\] coverage' }) | Select-Object -Last 1
    $unitFailed = @(
        $unitOutput | Where-Object { $PSItem -match '^\s*\[-\]' } | ForEach-Object { $PSItem.Trim() }
        if ($coverage -match '^\[FAIL\]') { $coverage }
        $unitOutput | Where-Object { $PSItem -match '^\[FAIL\] unit: build failed' }
    )
    $summary = if ($unitLast) { $unitLast -replace '^\[(PASS|FAIL)\] unit: ', '' -replace '\. Results: .*$', '' } else { "exit $unitExit" }
    if ($coverage -match 'coverage: (?<percent>[\d.]+%)') { $summary = "$summary; coverage $($Matches['percent'])" }
    Add-Result -Name 'unit' -Passed ($unitExit -eq 0) -Summary $summary -Detail $unitFailed
}

# -- 12. integration, only with -Integration ---------------------------------

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
