#Requires -Version 7.6
<#
.SYNOPSIS
    Runs the second-model review of the current branch and writes Review\LastReview.json.

.DESCRIPTION
    Reviews the commits HEAD adds to Base, once, in a new Claude Code session that did
    not write them (decision 35, Docs\REVIEW.md):

      1. Refuses to run unless every change is committed. The two evidence files,
         Review\LastReview.json and Tests\Integration\LastRun.json, do not count.
      2. Checks out HEAD into a new git worktree under the system temp folder, and
         writes three inputs into a .review-input folder inside it: the diff from the
         merge base with Base, the list of changed files and the branch's commit
         messages. The evidence files are left out of the diff.
      3. Runs claude -p in that worktree with Review\reviewer-prompt.md, and requires
         the answer to match Review\review-output.schema.json.
      4. Writes Review\LastReview.json: the commit and merge base reviewed, the
         reviewer's tool, version, model and effort, the SHA-256 of the prompt, and
         each finding with an empty Response for the author to answer.
      5. Removes the worktree.

    The review runs once per pull request. Fixes for its findings are later commits,
    answered Fixed: <commit>; they are not reviewed again.

    [SEC] The reviewer session is confined:
      - --restricted removes every tool that runs commands or code, and WebFetch; it
        ignores user, project and local settings files, and confines file tools to the
        worktree.
      - --tools Read,Grep,Glob: it can read, not write.
      - --safe-mode turns off CLAUDE.md, skills, hooks, plugins and MCP servers;
        --strict-mcp-config with no --mcp-config loads no MCP server.
      - --no-session-persistence: the session is not saved, and it cannot be resumed.
      - The worktree holds only committed files, so ignored local files (integration
        config, local instructions, credentials) are not in reach. It sits outside the
        repository and its parent folders; on Windows the temp folder is inside the
        user profile, and --safe-mode is what keeps the user's instruction files out.

    [SEC] The prompt names no absolute path. A record that quotes a local user-profile
    path fails the gate's S-16 hygiene check; the author removes it before committing.
    The reviewer is told never to quote a credential-like value; the gate's secret scan
    covers the file when it is committed.

.PARAMETER Base
    The branch the pull request merges into, as a git revision. Default: origin/master.

.PARAMETER Model
    The model the reviewer uses. Default: claude-opus-5-5.

.PARAMETER Effort
    The reviewer's effort level. Default: high.

.PARAMETER MaxBudgetUsd
    The most the review may spend, in US dollars. Default: 10.

.PARAMETER KeepWorktree
    Leaves the worktree in place for inspection. Its path is printed. Remove it with
    git worktree remove.

.EXAMPLE
    .\Scripts\Invoke-ModelReview.ps1

    Reviews the commits the branch adds to origin/master and writes
    Review\LastReview.json. Answer each finding, then commit the file.

.EXAMPLE
    .\Scripts\Invoke-ModelReview.ps1 -Model claude-sonnet-5-5 -Effort medium

    The same review with another model and effort level.

.NOTES
    Copyright © TACE Data Management Inc.
    **Invocation:** Standalone — self-contained; safe to run with `pwsh -File`. Needs git
    and Claude Code (claude) on PATH, signed in. Takes a few minutes.
#>
[CmdletBinding()]
[OutputType([string])]
param(
    [Parameter()]
    [ValidatePattern('^[A-Za-z0-9_][A-Za-z0-9_./-]*$')]
    [string]$Base = 'origin/master',

    [Parameter()]
    [ValidatePattern('^[a-z0-9][a-z0-9.-]*$')]
    [string]$Model = 'claude-opus-5-5',

    [Parameter()]
    [ValidateSet('low', 'medium', 'high', 'xhigh', 'max')]
    [string]$Effort = 'high',

    [Parameter()]
    [ValidateRange(0.5, 100)]
    [double]$MaxBudgetUsd = 10,

    [Parameter()]
    [switch]$KeepWorktree
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot      = Split-Path -Path $PSScriptRoot -Parent
$reviewDir     = Join-Path -Path $repoRoot -ChildPath 'Review'
$recordFile    = Join-Path -Path $reviewDir -ChildPath 'LastReview.json'
$promptFile    = Join-Path -Path $reviewDir -ChildPath 'reviewer-prompt.md'
$schemaFile    = Join-Path -Path $reviewDir -ChildPath 'review-output.schema.json'
$evidenceFiles = @('Review/LastReview.json', 'Tests/Integration/LastRun.json')

$tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$worktree = Join-Path -Path $tempRoot -ChildPath ('tace-review-' + [guid]::NewGuid().ToString('N'))
$inputDir = Join-Path -Path $worktree -ChildPath '.review-input'

# Runs git in the repository and throws on failure.
function Invoke-RepoGit {
    [OutputType([string])]
    param([Parameter(Mandatory)] [string[]] $Argument)
    $out = & git -C $repoRoot @Argument 2>&1
    if ($LASTEXITCODE -ne 0) { throw "[Invoke-ModelReview] git $($Argument[0]) failed: $out" }
    $out
}

# Refuses any path that is not this run's worktree.
function Assert-RunFolder {
    [OutputType([void])]
    param([Parameter(Mandatory)] [string] $Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    if (-not $full.Equals($worktree, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "[Invoke-ModelReview] Refusing to use $full"
    }
}

# -- Preconditions ---------------------------------------------------------------

$claude = Get-Command -Name claude -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $claude) { throw '[Invoke-ModelReview] claude is not on PATH. Install Claude Code and sign in.' }
foreach ($required in $promptFile, $schemaFile) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "[Invoke-ModelReview] Missing $required" }
}

$changes = @(Invoke-RepoGit -Argument @('status', '--porcelain', '--untracked-files=all') |
    Where-Object { $PSItem -and $evidenceFiles -notcontains $PSItem.Substring(3).Trim('"') })
if ($changes.Count -gt 0) {
    throw "[Invoke-ModelReview] The working tree has $($changes.Count) uncommitted change(s). Commit them first: the review covers commits only."
}

$headCommit = (Invoke-RepoGit -Argument @('rev-parse', 'HEAD')) | Select-Object -First 1
$baseTip    = (Invoke-RepoGit -Argument @('rev-parse', '--verify', "$Base^{commit}")) | Select-Object -First 1
$baseCommit = (Invoke-RepoGit -Argument @('merge-base', $baseTip, $headCommit)) | Select-Object -First 1

$exclude = @($evidenceFiles | ForEach-Object { ":(exclude)$PSItem" })
$changed = @(Invoke-RepoGit -Argument (@('diff', '--name-only', $baseCommit, $headCommit, '--', '.') + $exclude) | Where-Object { $PSItem })
if ($changed.Count -eq 0) {
    throw "[Invoke-ModelReview] HEAD changes no file since $Base (evidence files aside): nothing to review."
}

$toolVersion = ((& $claude.Source --version) | Select-Object -First 1) -replace '\s*\(Claude Code\)\s*$', ''
$promptHash  = (Get-FileHash -LiteralPath $promptFile -Algorithm SHA256).Hash.ToLowerInvariant()
$schemaText  = [System.IO.File]::ReadAllText($schemaFile) | ConvertFrom-Json -AsHashtable | ConvertTo-Json -Depth 10 -Compress

Write-Output "[INFO] review: $($changed.Count) file(s), $($baseCommit.Substring(0, 7))..$($headCommit.Substring(0, 7)), $Model at $Effort effort, Claude Code $toolVersion"

$startedUtc = [datetime]::UtcNow
$result     = $null
try {
    # -- Worktree and inputs ---------------------------------------------------------
    Assert-RunFolder -Path $worktree
    $null = Invoke-RepoGit -Argument @('worktree', 'add', '--quiet', '--detach', $worktree, $headCommit)
    $null = New-Item -Path $inputDir -ItemType Directory

    $diff = (Invoke-RepoGit -Argument (@('diff', '--no-color', $baseCommit, $headCommit, '--', '.') + $exclude)) -join "`n"
    [System.IO.File]::WriteAllText((Join-Path -Path $inputDir -ChildPath 'changes.diff'), $diff + "`n", [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText((Join-Path -Path $inputDir -ChildPath 'files.txt'), ($changed -join "`n") + "`n", [System.Text.UTF8Encoding]::new($false))
    # Messages only, oldest first: no author name or email.
    $messages = (Invoke-RepoGit -Argument @('log', '--reverse', '--format=commit %h%n%B', "$baseCommit..$headCommit")) -join "`n"
    [System.IO.File]::WriteAllText((Join-Path -Path $inputDir -ChildPath 'commits.txt'), $messages + "`n", [System.Text.UTF8Encoding]::new($false))

    $prompt = [System.IO.File]::ReadAllText($promptFile) + "`nInput folder: .review-input (in the working directory)`n"

    # -- The review session ----------------------------------------------------------
    $claudeArgs = @(
        '-p'
        '--model', $Model
        '--effort', $Effort
        '--restricted'
        '--safe-mode'
        '--strict-mcp-config'
        '--tools', 'Read,Grep,Glob'
        '--permission-mode', 'dontAsk'
        '--permission-prompts', 'none'
        '--no-session-persistence'
        '--output-format', 'json'
        '--json-schema', $schemaText
        '--max-budget-usd', $MaxBudgetUsd.ToString([System.Globalization.CultureInfo]::InvariantCulture)
    )
    Push-Location -Path $worktree
    try {
        $raw = @($prompt | & $claude.Source @claudeArgs 2>&1 | ForEach-Object { "$PSItem" })
        $claudeExit = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }

    $jsonLine = @($raw | Where-Object { $PSItem.TrimStart().StartsWith('{') }) | Select-Object -Last 1
    if ($null -eq $jsonLine) { throw "[Invoke-ModelReview] claude exited $claudeExit with no JSON result." }
    $result = $jsonLine | ConvertFrom-Json
    if ($result.is_error -or $result.subtype -ne 'success' -or $null -eq $result.structured_output) {
        throw "[Invoke-ModelReview] The review did not complete: exit $claudeExit, subtype '$($result.subtype)'. No record written."
    }
}
finally {
    if ($KeepWorktree) {
        Write-Output "[INFO] review: worktree kept at $worktree"
    }
    elseif (Test-Path -LiteralPath $worktree) {
        Assert-RunFolder -Path $worktree
        $null = & git -C $repoRoot worktree remove --force $worktree 2>&1
        if (Test-Path -LiteralPath $worktree) { Remove-Item -LiteralPath $worktree -Recurse -Force }
        $null = & git -C $repoRoot worktree prune 2>&1
    }
}

# -- The record ------------------------------------------------------------------

$index    = 0
$findings = @(foreach ($finding in @($result.structured_output.findings)) {
        $index++
        [PSCustomObject]@{
            Id       = "F$index"
            Severity = $finding.severity
            Step     = $finding.step
            Rule     = $finding.rule
            File     = "$($finding.file)" -replace '\\', '/'
            Line     = [int]$finding.line
            Title    = $finding.title
            Detail   = $finding.detail
            Response = ''
        }
    })

$record = [PSCustomObject]@{
    SchemaVersion     = 1
    Commit            = $headCommit
    BaseCommit        = $baseCommit
    Base              = $Base
    Completed         = $true
    RunAtUtc          = $startedUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')
    Reviewer          = [PSCustomObject]@{
        Tool    = 'Claude Code'
        Version = $toolVersion
        Model   = $Model
        Effort  = $Effort
    }
    PromptSha256      = $promptHash
    FilesReviewed     = $changed.Count
    Turns             = [int]$result.num_turns
    CostUsd           = [math]::Round([double]$result.total_cost_usd, 2)
    PermissionDenials = @($result.permission_denials).Count
    Summary           = $result.structured_output.summary
    Findings          = $findings
}

$json = (ConvertTo-Json -InputObject $record -Depth 6) -replace "`r`n", "`n"
[System.IO.File]::WriteAllText($recordFile, $json + "`n", [System.Text.UTF8Encoding]::new($false))

Write-Output "[INFO] review: $($findings.Count) finding(s), $($record.Turns) turns, US`$$($record.CostUsd)"
foreach ($finding in $findings) {
    Write-Output "  [$($finding.Severity.ToUpperInvariant())] $($finding.Id) $($finding.Rule) $($finding.File):$($finding.Line) $($finding.Title)"
}
Write-Output "[INFO] review: written to Review/LastReview.json. Answer each finding (Docs\REVIEW.md), then commit the file."
exit 0
