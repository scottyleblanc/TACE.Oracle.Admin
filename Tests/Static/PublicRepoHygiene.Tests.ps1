#Requires -Version 7.6

# Static tier. Reads source text only; it does not import the module or run a function.
#
# Rule S-16: this repository is public, so no credential, account identifier or
# infrastructure detail is committed. This file checks the patterns that can be checked
# without knowing the real values: account IDs, ARNs, access keys, literal S3 targets,
# email addresses and private keys, in every file git tracks or would add.
#
# It cannot catch a real resource name that matches no pattern, and it does not read
# commit messages. Both are covered by the review half of S-16 and by the Stack 2
# cross-check against the private resource list.
#
# A failure message shows only the first characters of a match: test output can be
# published, so it must not repeat the value it found.

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
    # that $Allow accepts.
    function Find-PatternHit {
        param(
            [Parameter(Mandatory)] [string] $Pattern,
            [Parameter()] [scriptblock] $Allow = { $false }
        )
        foreach ($file in $script:files) {
            for ($i = 0; $i -lt $file.Lines.Count; $i++) {
                foreach ($match in [regex]::Matches($file.Lines[$i], $Pattern)) {
                    if (& $Allow $match.Value) { continue }
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

    It 'S-16: no AWS account ID' {
        # Twelve digits standing alone. A GUID's last segment is preceded by '-', so it
        # is not matched.
        $hits = @(Find-PatternHit -Pattern '(?<![\w.\-])\d{12}(?![\w.\-])')
        ($hits -join "`n") | Should -BeNullOrEmpty -Because 'an account ID is infrastructure detail (S-16)'
    }

    It 'S-16: no ARN' {
        $hits = @(Find-PatternHit -Pattern 'arn:aws[a-z\-]*:')
        ($hits -join "`n") | Should -BeNullOrEmpty -Because 'an ARN names a real resource (S-16)'
    }

    It 'S-16: no AWS access key ID' {
        $hits = @(Find-PatternHit -Pattern '\b(AKIA|ASIA)[A-Z0-9]{16}\b')
        ($hits -join "`n") | Should -BeNullOrEmpty -Because 'an access key ID is a credential (S-04, S-16)'
    }

    It 'S-16: no literal S3 target' {
        # s3:// followed by a real name. A variable ($S3Bucket) or a placeholder
        # (<staging-bucket>) does not start with a letter or digit, so it passes.
        $hits = @(Find-PatternHit -Pattern 's3://[a-z0-9]')
        ($hits -join "`n") | Should -BeNullOrEmpty -Because 'a bucket name is infrastructure detail; take it as a parameter (S-16)'
    }

    It 'S-16: no email address outside the reserved example domains' {
        $allowExample = { param($value) $value -match '@example\.(com|org|net)$' }
        $hits = @(Find-PatternHit -Pattern '[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}' -Allow $allowExample)
        ($hits -join "`n") | Should -BeNullOrEmpty -Because 'a real address identifies a person or an account (S-16)'
    }

    It 'S-04: no private key block' {
        $hits = @(Find-PatternHit -Pattern '-----BEGIN [A-Z ]*PRIVATE KEY-----')
        ($hits -join "`n") | Should -BeNullOrEmpty -Because 'a private key is a credential (S-04)'
    }
}
