#Requires -Version 7.6
<#
.SYNOPSIS
    Proves the gate fails on planted defects: a lint violation, and a secret in a file
    and in a commit message.

.DESCRIPTION
    Copies the files the next commit could contain (tracked, plus untracked files that
    are not ignored) into a new folder under the system temp folder, makes that copy a
    git repository with one commit, and runs Scripts\Invoke-Gate.ps1 there:

      control   the copy as it is              the gate passes
      lint      a $_ planted in a function     the gate fails on 'analyzer'
      secret    a token committed in a file    the gate fails on 'secrets' and 'commits'
      message   a token in a commit message    the gate fails on 'messages'

    Each case starts from the clean copy. The planted token is generated at random in
    the GitHub token format, so it is no real credential; it is never printed. This
    repository is never changed. The copy is deleted at the end.

    The copy has no remote, so every commit in it counts as unpushed.

.PARAMETER KeepCopy
    Leaves the temporary copy in place for inspection. Its path is printed.

.EXAMPLE
    .\Scripts\Test-SeededDefect.ps1

    Runs the four cases. Exits 0 when every case behaves as expected, 1 otherwise.

.NOTES
    Copyright © TACE Data Management Inc.
    **Invocation:** Standalone — self-contained; safe to run with `pwsh -File`. Needs
    everything the gate needs (PREREQUISITES.md). Takes a few minutes: the gate, static
    tier included, runs four times.
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
function Invoke-CopyGate {
    [OutputType([PSCustomObject])]
    param()
    $gate   = Join-Path -Path $copy -ChildPath 'Scripts' -AdditionalChildPath 'Invoke-Gate.ps1'
    $output = @(& pwsh -NoProfile -File $gate 2>&1 | ForEach-Object { "$PSItem" })
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
    Add-Case -Name 'control' -Result (Invoke-CopyGate) -ExpectFailed @()

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
if ($failedCases.Count -gt 0 -or $cases.Count -ne 4) {
    Write-Output "[FAIL] seeded defects: $($failedCases.Count) of $($cases.Count) cases did not behave as expected"
    exit 1
}
Write-Output '[PASS] seeded defects: the gate passed the clean copy and failed each planted defect'
exit 0
