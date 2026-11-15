#Requires -Version 7.6

# Static tier. Reads source text only; it does not import the module or run a function.
#
# Rule S-16: this repository is public, so no credential, account identifier or
# infrastructure detail is committed. This file checks the patterns that can be checked
# without knowing the real values: account IDs, ARNs, access keys, literal S3 targets,
# email addresses and private keys, in every file git tracks or would add. The patterns
# live in Tests\Lint\PublicRepoPatterns.psd1, which Scripts\Invoke-Gate.ps1 also applies
# to unpushed commit messages.
#
# It cannot catch a real resource name that matches no pattern; that is left to the
# review half of S-16. A cross-check against a private identifier list is deferred until
# its design is decided across all public repositories (TODO.md, Stack 2).
#
# A failure message shows only the first characters of a match: test output can be
# published, so it must not repeat the value it found.

BeforeDiscovery {
    $patternFile = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Lint' -AdditionalChildPath 'PublicRepoPatterns.psd1'
    $script:patterns = @((Import-PowerShellDataFile -LiteralPath $patternFile).Patterns)
}

BeforeAll {
    $script:repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent

    # Tracked files plus untracked files that are not ignored: what the next commit
    # could contain.
    $listed = @(& git -C $script:repoRoot ls-files --cached --others --exclude-standard)
    if ($LASTEXITCODE -ne 0) {
        throw "git ls-files failed (exit $LASTEXITCODE): this check needs a git checkout."
    }

    $script:files = @(foreach ($relative in $listed) {
            $full = Join-Path -Path $script:repoRoot -ChildPath $relative
            if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }
            $text = [System.IO.File]::ReadAllText($full)
            if ($text.Contains([char]0)) { continue }   # binary file
            [PSCustomObject]@{ Path = $relative; Lines = $text -split "`r?`n" }
        })

    # Returns 'path:line value-prefix***' for every match of $Pattern, skipping values
    # that match $Allow.
    function Find-PatternHit {
        param(
            [Parameter(Mandatory)] [string] $Pattern,
            [Parameter()] [string] $Allow = ''
        )
        foreach ($file in $script:files) {
            for ($i = 0; $i -lt $file.Lines.Count; $i++) {
                foreach ($match in [regex]::Matches($file.Lines[$i], $Pattern)) {
                    if ($Allow -and $match.Value -match $Allow) { continue }
                    $prefix = $match.Value.Substring(0, [Math]::Min(6, $match.Value.Length))
                    "$($file.Path):$($i + 1) $prefix***"
                }
            }
        }
    }
}

Describe 'Public repository hygiene' -Tag 'Static', 'SEC' {

    It 'found files to check' {
        $script:files.Count | Should -BeGreaterThan 0 -Because 'git lists the files of this repository'
    }

    It '<Id>: <Title>' -ForEach $script:patterns {
        $hits = @(Find-PatternHit -Pattern $Pattern -Allow $Allow)
        ($hits -join "`n") | Should -BeNullOrEmpty -Because $Because
    }
}
