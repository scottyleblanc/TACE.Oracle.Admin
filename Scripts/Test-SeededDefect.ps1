#Requires -Version 7.6
<#
.SYNOPSIS
    Proves the gate fails on planted defects: a lint violation, a removed agent permission
    rule, a secret in a file and in a commit message, a behaviour defect, a version
    mismatch and a stray package file.

.DESCRIPTION
    Copies the files the next commit could contain (tracked, plus untracked files that
    are not ignored) into a new folder under the system temp folder, makes that copy a
    git repository with one commit, and runs Scripts\Invoke-Gate.ps1 there:

      control    the copy as it is, with -Unit       the gate passes, unit tier included
      lint       a $_ planted in a function          the gate fails on 'analyzer'
      instructions  a rule added to Docs\standards\  the gate fails on 'static' only:
                 without AGENTS.md regenerated       the agent would not be told it
      permission the 'git push' deny rule removed    the gate fails on 'static' only
                 from .claude\settings.json          (rule S-17)
      secret     a token committed in a file         the gate fails on 'secrets' and 'commits'
      message    a token in a commit message         the gate fails on 'messages'
      behaviour  Get-RmanBackupStatus picks the      the gate with -Unit fails on 'unit'
                 highest Key, not the latest         only: valid code that every static
                 CompletionTime (breaks its R3)      check passes
      ci no base a token in a commit message,    the gate passes: nothing is unpushed,
                 and that commit on a remote     which is why CI must pass -Base
      ci message the same, gate with -Base       the gate fails on 'messages'
      evidence   a Source\ change, a review      the gate with -Base passes
      current    naming it, then LastRun.json
                 naming the review commit
      evidence   one more Source\ change after   the gate with -Base fails on
      stale      the evidence commit             'evidence' only (rule T-14); a fix
                                                 after the review needs no new review
      version    the 'evidence current' branch,  the gate with -Base fails on
      released   its version tagged at the base  'version' only: code changed under a
                                                 released number (rule D-10)
      review     a docs change with no review    the gate with -Base fails on
      missing    record                          'review' only (decision 35)
      review     a review record naming it,      the gate with -Base passes
      current    its finding answered
      review     the same record with a base     the gate with -Base fails on
      wrong base other than the merge base, so    'review' only
                 it covers none of the commits
      review     the same record with the        the gate with -Base fails on
      unanswered finding's Response empty        'review' only
      review     a fix committed after the       the gate with -Base passes: a fix
      fixed      review, answered Fixed:         needs no new review
      review     that branch merged; the next    the gate with -Base fails on
      stale      one makes a docs change and     'review' only: the record names a
                 leaves the old record           commit already in the base
      version    the newest CHANGELOG release    the gate fails on 'version' only
      mismatch   renamed 9.9.9
      stray file the build writes a notes file   the gate with -Base fails on
                 into the version folder after   'package' only: FileList is right,
                 FileList is made                the package is not

    Each case starts from the clean copy. The planted token is generated at random in
    the GitHub token format, so it is no real credential; it is never printed. This
    repository is never changed. The copy is deleted at the end.

    The copy has no remote, so every commit in it counts as unpushed.

.PARAMETER KeepCopy
    Leaves the temporary copy in place for inspection. Its path is printed.

.EXAMPLE
    .\Scripts\Test-SeededDefect.ps1

    Runs the twenty cases. Exits 0 when every case behaves as expected, 1 otherwise.

.NOTES
    Copyright © TACE Data Management Inc.
    **Invocation:** Standalone — self-contained; safe to run with `pwsh -File`. Needs
    everything the gate needs (PREREQUISITES.md). Takes about 25 minutes: the gate,
    static tier included, runs twenty times, twice with the unit tier. Run it by hand
    when the gate changes; it is not part of the gate or CI. The review records it
    plants are made up; no model review runs.
#>
[CmdletBinding()]
[OutputType([string])]
param(
    [Parameter()]
    [switch] $KeepCopy
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$copy     = Join-Path -Path $tempRoot -ChildPath ('tace-gate-seed-' + [guid]::NewGuid().ToString('N'))

# Every write below goes inside the copy. This refuses anything else.
function Assert-InCopy {
    [OutputType([void])]
    param([Parameter(Mandatory)] [string] $Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith($copy + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "[Test-SeededDefect] Refusing to write outside the temporary copy: $full"
    }
}

# Runs git in the copy and throws on failure.
function Invoke-CopyGit {
    [OutputType([string])]
    param([Parameter(Mandatory)] [string[]] $Argument)
    $out = & git -C $copy @Argument 2>&1
    if ($LASTEXITCODE -ne 0) { throw "[Test-SeededDefect] git $($Argument -join ' ') failed: $out" }
    $out
}

# Runs the gate in the copy; returns its exit code and the names of the checks that failed.
# -Unit passes the gate's -Unit switch, adding the unit tier.
function Invoke-CopyGate {
    [OutputType([PSCustomObject])]
    param([switch] $Unit, [string] $Base)
    $gate     = Join-Path -Path $copy -ChildPath 'Scripts' -AdditionalChildPath 'Invoke-Gate.ps1'
    $gateArgs = @('-NoProfile', '-File', $gate)
    if ($Unit) { $gateArgs += '-Unit' }
    if ($Base) { $gateArgs += @('-Base', $Base) }
    $output = @(& pwsh @gateArgs 2>&1 | ForEach-Object { "$PSItem" })
    $exit   = $LASTEXITCODE
    $failed = @($output | ForEach-Object { if ($PSItem -match '^\[FAIL\] (\w+) :') { $Matches[1] } })
    [PSCustomObject]@{ ExitCode = $exit; Failed = $failed }
}

# A random value in the GitHub token format: matched by gitleaks, valid nowhere.
function Get-FakeToken {
    [OutputType([string])]
    param()
    $alphabet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'.ToCharArray()
    'ghp_' + -join (1..36 | ForEach-Object { $alphabet | Get-Random })
}

# Plants Review\LastReview.json in the copy: a completed review of $Commit from
# $BaseCommit with one finding, answered with $Response.
function Write-ReviewRecord {
    [OutputType([void])]
    param(
        [Parameter(Mandatory)] [string] $Commit,
        [Parameter(Mandatory)] [string] $BaseCommit,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Response
    )
    $path = Join-Path -Path $copy -ChildPath 'Review' -AdditionalChildPath 'LastReview.json'
    Assert-InCopy -Path $path
    $null = New-Item -Path (Split-Path -Path $path -Parent) -ItemType Directory -Force
    $record = [PSCustomObject]@{
        SchemaVersion = 1
        Commit        = $Commit
        BaseCommit    = $BaseCommit
        Base          = 'seeded'
        Completed     = $true
        Summary       = 'Seeded review record.'
        Findings      = @([PSCustomObject]@{ Id = 'F1'; Severity = 'Low'; Rule = 'none'; Title = 'Seeded finding.'; Response = $Response })
    }
    [System.IO.File]::WriteAllText($path, (ConvertTo-Json -InputObject $record -Depth 5) + "`n", [System.Text.UTF8Encoding]::new($false))
}

$cases = [System.Collections.Generic.List[object]]::new()

function Add-Case {
    [OutputType([void])]
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [PSCustomObject] $Result,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $ExpectFailed
    )
    # Exactly the expected checks fail: a defect caught by the wrong check, or a check
    # failing for an unrelated reason, does not count as caught.
    $expectedSet = @($ExpectFailed | Sort-Object -Unique)
    $actualSet   = @($Result.Failed | Sort-Object -Unique)
    $sameSet     = ($expectedSet -join ',') -eq ($actualSet -join ',')
    $passed = if ($ExpectFailed.Count -eq 0) {
        $Result.ExitCode -eq 0 -and $actualSet.Count -eq 0
    }
    else {
        $Result.ExitCode -eq 1 -and $sameSet
    }
    $cases.Add([PSCustomObject]@{ Name = $Name; Passed = $passed })
    $label    = if ($passed) { '[PASS]' } else { '[FAIL]' }
    $expected = if ($ExpectFailed.Count -eq 0) { 'gate passes' } else { "gate fails on $($ExpectFailed -join ', ')" }
    $got      = if ($Result.ExitCode -eq 0) { 'gate passed' } else { "gate failed on $(@($Result.Failed) -join ', ')" }
    Write-Output "$label $Name : expected $expected; $got"
}

try {
    # -- Build the copy --------------------------------------------------------
    $null = New-Item -Path $copy -ItemType Directory
    $listed = @(& git -C $repoRoot ls-files --cached --others --exclude-standard)
    if ($LASTEXITCODE -ne 0) { throw '[Test-SeededDefect] git ls-files failed: this needs a git checkout.' }
    foreach ($relative in $listed) {
        $source = Join-Path -Path $repoRoot -ChildPath $relative
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { continue }
        $target = Join-Path -Path $copy -ChildPath $relative
        Assert-InCopy -Path $target
        $null = New-Item -Path (Split-Path -Path $target -Parent) -ItemType Directory -Force
        Copy-Item -LiteralPath $source -Destination $target
    }
    $null = Invoke-CopyGit -Argument @('init', '--quiet')
    $null = Invoke-CopyGit -Argument @('config', 'user.name', 'Seeded Defect Test')
    $null = Invoke-CopyGit -Argument @('config', 'user.email', 'seeded@example.com')
    $null = Invoke-CopyGit -Argument @('config', 'core.autocrlf', 'false')
    $null = Invoke-CopyGit -Argument @('add', '--all')
    $null = Invoke-CopyGit -Argument @('commit', '--quiet', '--message', 'test: baseline copy')
    $baseline = (Invoke-CopyGit -Argument @('rev-parse', 'HEAD')) | Select-Object -First 1
    Write-Output "[INFO] copy: $($listed.Count) files"

    # -- control ---------------------------------------------------------------
    Add-Case -Name 'control' -Result (Invoke-CopyGate -Unit) -ExpectFailed @()

    # -- lint: a $_ planted in a function --------------------------------------
    $target = Join-Path -Path $copy -ChildPath 'Source' -AdditionalChildPath 'Private', 'Test-WindowsPlatform.ps1'
    Assert-InCopy -Path $target
    $text = [System.IO.File]::ReadAllText($target)
    $anchor = "    `$ErrorActionPreference = 'Stop'`n"
    if (-not $text.Contains($anchor)) { throw '[Test-SeededDefect] lint anchor not found in Test-WindowsPlatform.ps1' }
    $planted = $text.Replace($anchor, $anchor + "    `$null = @(1) | ForEach-Object { `$_ }`n")
    [System.IO.File]::WriteAllText($target, $planted, [System.Text.UTF8Encoding]::new($false))
    Add-Case -Name 'lint' -Result (Invoke-CopyGate) -ExpectFailed @('analyzer')
    $null = Invoke-CopyGit -Argument @('checkout', '--quiet', '--', 'Source/Private/Test-WindowsPlatform.ps1')

    # -- instructions: a standard changed, AGENTS.md not regenerated -------------
    $target = Join-Path -Path $copy -ChildPath 'Docs' -AdditionalChildPath 'standards', 'testing.md'
    Assert-InCopy -Path $target
    $rule = "- **T-99** — A seeded rule that AGENTS.md does not carry.`n  Example: none. *Review.*`n"
    [System.IO.File]::AppendAllText($target, $rule, [System.Text.UTF8Encoding]::new($false))
    Add-Case -Name 'instructions' -Result (Invoke-CopyGate) -ExpectFailed @('static')
    $null = Invoke-CopyGit -Argument @('checkout', '--quiet', '--', 'Docs/standards/testing.md')

    # -- permission: a deny rule removed from the agent settings ------------------
    # S-17: the documented list in Tests\Lint\AgentPermissions.psd1 is unchanged, so the
    # static tier fails.
    $target = Join-Path -Path $copy -ChildPath '.claude' -AdditionalChildPath 'settings.json'
    Assert-InCopy -Path $target
    $text = [System.IO.File]::ReadAllText($target)
    $anchor = "      `"Bash(git push *)`",`n"
    if (([regex]::Matches($text, [regex]::Escape($anchor))).Count -ne 1) { throw '[Test-SeededDefect] permission anchor not found exactly once in .claude/settings.json' }
    [System.IO.File]::WriteAllText($target, $text.Replace($anchor, ''), [System.Text.UTF8Encoding]::new($false))
    Add-Case -Name 'permission' -Result (Invoke-CopyGate) -ExpectFailed @('static')
    $null = Invoke-CopyGit -Argument @('checkout', '--quiet', '--', '.claude/settings.json')

    # -- secret: a token committed in a file -----------------------------------
    $target = Join-Path -Path $copy -ChildPath 'Docs' -AdditionalChildPath 'seeded-note.md'
    Assert-InCopy -Path $target
    [System.IO.File]::WriteAllText($target, "github_token = $(Get-FakeToken)`n", [System.Text.UTF8Encoding]::new($false))
    $null = Invoke-CopyGit -Argument @('add', '--', 'Docs/seeded-note.md')
    $null = Invoke-CopyGit -Argument @('commit', '--quiet', '--message', 'docs: add a note')
    Add-Case -Name 'secret' -Result (Invoke-CopyGate) -ExpectFailed @('secrets', 'commits')
    $null = Invoke-CopyGit -Argument @('reset', '--quiet', '--hard', $baseline)

    # -- message: a token in a commit message only -----------------------------
    $null = Invoke-CopyGit -Argument @('commit', '--quiet', '--allow-empty', '--message', "fix: rotate token $(Get-FakeToken)")
    Add-Case -Name 'message' -Result (Invoke-CopyGate) -ExpectFailed @('messages')
    $null = Invoke-CopyGit -Argument @('reset', '--quiet', '--hard', $baseline)

    # -- behaviour: the latest-backup rule broken, in valid code -------------------
    # A plausible simplification: drop the CompletionTime sort, so the highest Key wins.
    # Nothing static can see it; the R3 unit test can.
    $target = Join-Path -Path $copy -ChildPath 'Source' -AdditionalChildPath 'Public', 'Get-RmanBackupStatus.ps1'
    Assert-InCopy -Path $target
    $text = [System.IO.File]::ReadAllText($target)
    $anchor = "                @{ Expression = { `$PSItem.CompletionTime }; Descending = `$true },`n"
    if (([regex]::Matches($text, [regex]::Escape($anchor))).Count -ne 1) { throw '[Test-SeededDefect] behaviour anchor not found exactly once in Get-RmanBackupStatus.ps1' }
    [System.IO.File]::WriteAllText($target, $text.Replace($anchor, ''), [System.Text.UTF8Encoding]::new($false))
    Add-Case -Name 'behaviour' -Result (Invoke-CopyGate -Unit) -ExpectFailed @('unit')
    $null = Invoke-CopyGit -Argument @('checkout', '--quiet', '--', 'Source/Public/Get-RmanBackupStatus.ps1')

    # -- CI: every commit is on a remote ---------------------------------------
    # A token in a commit message, then a remote-tracking ref at HEAD, as in a CI
    # checkout. Without -Base the gate sees nothing unpushed; with -Base it checks the
    # pull request's commits and fails.
    $null = Invoke-CopyGit -Argument @('commit', '--quiet', '--allow-empty', '--message', "fix: rotate token $(Get-FakeToken)")
    $null = Invoke-CopyGit -Argument @('update-ref', 'refs/remotes/origin/pr', 'HEAD')
    Add-Case -Name 'ci no base' -Result (Invoke-CopyGate) -ExpectFailed @()
    Add-Case -Name 'ci message' -Result (Invoke-CopyGate -Base $baseline) -ExpectFailed @('messages')
    $null = Invoke-CopyGit -Argument @('update-ref', '-d', 'refs/remotes/origin/pr')
    $null = Invoke-CopyGit -Argument @('reset', '--quiet', '--hard', $baseline)

    # -- evidence: rule T-14 ---------------------------------------------------
    # A Source\ change, its review, then LastRun.json naming the review commit, in the
    # order Docs\REVIEW.md gives: current. One more Source\ change after the evidence
    # commit: the integration evidence is stale; the review still covers the branch.
    $sourceFile = Join-Path -Path $copy -ChildPath 'Source' -AdditionalChildPath 'Private', 'Test-WindowsPlatform.ps1'
    $evidence   = Join-Path -Path $copy -ChildPath 'Tests' -AdditionalChildPath 'Integration', 'LastRun.json'
    Assert-InCopy -Path $sourceFile
    Assert-InCopy -Path $evidence
    [System.IO.File]::AppendAllText($sourceFile, "# seeded change 1`n", [System.Text.UTF8Encoding]::new($false))
    $null = Invoke-CopyGit -Argument @('commit', '--quiet', '--all', '--message', 'fix: a source change')
    $sourceCommit = (Invoke-CopyGit -Argument @('rev-parse', 'HEAD')) | Select-Object -First 1
    Write-ReviewRecord -Commit $sourceCommit -BaseCommit $baseline -Response 'Rejected: seeded answer.'
    $null = Invoke-CopyGit -Argument @('add', '--all')
    $null = Invoke-CopyGit -Argument @('commit', '--quiet', '--message', 'docs: review record')
    $run = [System.IO.File]::ReadAllText($evidence) | ConvertFrom-Json
    $run.Commit = (Invoke-CopyGit -Argument @('rev-parse', 'HEAD')) | Select-Object -First 1
    [System.IO.File]::WriteAllText($evidence, (ConvertTo-Json -InputObject $run -Depth 5) + "`n", [System.Text.UTF8Encoding]::new($false))
    $null = Invoke-CopyGit -Argument @('commit', '--quiet', '--all', '--message', 'test: integration evidence')
    Add-Case -Name 'evidence current' -Result (Invoke-CopyGate -Base $baseline) -ExpectFailed @()

    # -- version released: the same branch, its version already tagged ------------
    # Everything else is in order; only the tag rule can see that the code changed
    # under a released number.
    $manifestFile = Join-Path -Path $copy -ChildPath 'Source' -AdditionalChildPath 'TACE.Oracle.Admin.psd1'
    $copyVersion  = [string](Import-PowerShellDataFile -LiteralPath $manifestFile).ModuleVersion
    $null = Invoke-CopyGit -Argument @('tag', "v$copyVersion", $baseline)
    Add-Case -Name 'version released' -Result (Invoke-CopyGate -Base $baseline) -ExpectFailed @('version')
    $null = Invoke-CopyGit -Argument @('tag', '--delete', "v$copyVersion")
    [System.IO.File]::AppendAllText($sourceFile, "# seeded change 2`n", [System.Text.UTF8Encoding]::new($false))
    $null = Invoke-CopyGit -Argument @('commit', '--quiet', '--all', '--message', 'fix: a later source change')
    Add-Case -Name 'evidence stale' -Result (Invoke-CopyGate -Base $baseline) -ExpectFailed @('evidence')
    $null = Invoke-CopyGit -Argument @('reset', '--quiet', '--hard', $baseline)

    # -- review: decision 35 ---------------------------------------------------
    # A docs change needs no integration evidence, so only 'review' can fail. Any
    # review record the copy holds names a commit outside its history; it is removed.
    $docFile = Join-Path -Path $copy -ChildPath 'Docs' -AdditionalChildPath 'REVIEW.md'
    Assert-InCopy -Path $docFile
    [System.IO.File]::AppendAllText($docFile, "`nSeeded docs change 1.`n", [System.Text.UTF8Encoding]::new($false))
    $recordRelative = 'Review/LastReview.json'
    if (Test-Path -LiteralPath (Join-Path -Path $copy -ChildPath $recordRelative)) {
        $null = Invoke-CopyGit -Argument @('rm', '--quiet', '--', $recordRelative)
    }
    $null = Invoke-CopyGit -Argument @('commit', '--quiet', '--all', '--message', 'docs: a docs change')
    $docCommit = (Invoke-CopyGit -Argument @('rev-parse', 'HEAD')) | Select-Object -First 1
    Add-Case -Name 'review missing' -Result (Invoke-CopyGate -Base $baseline) -ExpectFailed @('review')
    Write-ReviewRecord -Commit $docCommit -BaseCommit $baseline -Response 'Accepted: seeded answer.'
    $null = Invoke-CopyGit -Argument @('add', '--all')
    $null = Invoke-CopyGit -Argument @('commit', '--quiet', '--message', 'docs: review record')
    Add-Case -Name 'review current' -Result (Invoke-CopyGate -Base $baseline) -ExpectFailed @()
    Write-ReviewRecord -Commit $docCommit -BaseCommit $docCommit -Response 'Accepted: seeded answer.'
    $null = Invoke-CopyGit -Argument @('commit', '--quiet', '--all', '--message', 'docs: review record, wrong base')
    Add-Case -Name 'review wrong base' -Result (Invoke-CopyGate -Base $baseline) -ExpectFailed @('review')
    Write-ReviewRecord -Commit $docCommit -BaseCommit $baseline -Response ''
    $null = Invoke-CopyGit -Argument @('commit', '--quiet', '--all', '--message', 'docs: review record, unanswered')
    Add-Case -Name 'review unanswered' -Result (Invoke-CopyGate -Base $baseline) -ExpectFailed @('review')
    [System.IO.File]::AppendAllText($docFile, "Seeded fix for F1.`n", [System.Text.UTF8Encoding]::new($false))
    Write-ReviewRecord -Commit $docCommit -BaseCommit $baseline -Response 'Fixed: seeded fix commit.'
    $null = Invoke-CopyGit -Argument @('commit', '--quiet', '--all', '--message', 'docs: fix F1 after the review')
    Add-Case -Name 'review fixed' -Result (Invoke-CopyGate -Base $baseline) -ExpectFailed @()
    # That branch counts as merged: its HEAD is the next pull request's base. The next
    # pull request makes a docs change and no review, so the only record is the
    # earlier one, which names a commit already in the base.
    $merged = (Invoke-CopyGit -Argument @('rev-parse', 'HEAD')) | Select-Object -First 1
    [System.IO.File]::AppendAllText($docFile, "Seeded docs change 2.`n", [System.Text.UTF8Encoding]::new($false))
    $null = Invoke-CopyGit -Argument @('commit', '--quiet', '--all', '--message', 'docs: a change in the next pull request')
    Add-Case -Name 'review stale' -Result (Invoke-CopyGate -Base $merged) -ExpectFailed @('review')
    $null = Invoke-CopyGit -Argument @('reset', '--quiet', '--hard', $baseline)

    # -- version mismatch: the CHANGELOG names a different release --------------
    # The manifest and every .NOTES block still agree; only the CHANGELOG is off.
    $changelog = Join-Path -Path $copy -ChildPath 'Docs' -AdditionalChildPath 'CHANGELOG.md'
    Assert-InCopy -Path $changelog
    $text   = [System.IO.File]::ReadAllText($changelog)
    $anchor = [regex]::Match($text, '(?m)^## \[\d+\.\d+\.\d+\]')
    if (-not $anchor.Success) { throw '[Test-SeededDefect] version anchor not found in CHANGELOG.md' }
    $text = $text.Remove($anchor.Index, $anchor.Length).Insert($anchor.Index, '## [9.9.9]')
    [System.IO.File]::WriteAllText($changelog, $text, [System.Text.UTF8Encoding]::new($false))
    Add-Case -Name 'version mismatch' -Result (Invoke-CopyGate) -ExpectFailed @('version')
    $null = Invoke-CopyGit -Argument @('checkout', '--quiet', '--', 'Docs/CHANGELOG.md')

    # -- stray file: the build writes a file FileList does not name ---------------
    # A build-script edit after the file list is made: FileList stays correct, and
    # Publish-PSResource would still package the extra file. Left uncommitted, so no
    # review or evidence is due and only 'package' can fail.
    $buildFile = Join-Path -Path $copy -ChildPath 'Scripts' -AdditionalChildPath 'Build-Module.ps1'
    Assert-InCopy -Path $buildFile
    $text   = [System.IO.File]::ReadAllText($buildFile)
    $anchor = "New-ModuleManifest @manifestParams`n"
    if (([regex]::Matches($text, [regex]::Escape($anchor))).Count -ne 1) { throw '[Test-SeededDefect] stray-file anchor not found exactly once in Build-Module.ps1' }
    $stray = "Set-Content -LiteralPath (Join-Path -Path `$moduleDir -ChildPath 'build-notes.txt') -Value 'seeded' -Encoding UTF8`n"
    [System.IO.File]::WriteAllText($buildFile, $text.Replace($anchor, $anchor + $stray), [System.Text.UTF8Encoding]::new($false))
    Add-Case -Name 'stray file' -Result (Invoke-CopyGate -Base $baseline) -ExpectFailed @('package')
    $null = Invoke-CopyGit -Argument @('checkout', '--quiet', '--', 'Scripts/Build-Module.ps1')
}
finally {
    if ($KeepCopy) {
        Write-Output "[INFO] copy kept at $copy"
    }
    elseif (Test-Path -LiteralPath $copy) {
        $resolved = [System.IO.Path]::GetFullPath($copy)
        if (-not $resolved.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
            (Split-Path -Path $resolved -Leaf) -notlike 'tace-gate-seed-*') {
            throw "[Test-SeededDefect] Refusing to delete $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}

$failedCases = @($cases | Where-Object { -not $PSItem.Passed })
if ($failedCases.Count -gt 0 -or $cases.Count -ne 20) {
    Write-Output "[FAIL] seeded defects: $($failedCases.Count) of $($cases.Count) cases did not behave as expected"
    exit 1
}
Write-Output '[PASS] seeded defects: the gate passed the clean copy and failed each planted defect'
exit 0
