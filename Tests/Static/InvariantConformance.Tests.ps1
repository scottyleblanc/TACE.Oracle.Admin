#Requires -Version 7.0

# Static tier. Reads source text only; it does not import the module or run a function.
# The linter (scripts\Invoke-InvariantLint.ps1) holds the rules. This file turns its
# result into pass or fail.

BeforeAll {
    $script:repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $lintScript      = Join-Path -Path $script:repoRoot -ChildPath 'scripts' -AdditionalChildPath 'Invoke-InvariantLint.ps1'
    $script:lint     = & $lintScript -RepoRoot $script:repoRoot
}

Describe 'Invariant blocks' -Tag 'Static' {

    It 'the linter ran' {
        $script:lint.Data | Should -Not -BeNullOrEmpty -Because $script:lint.Message
    }

    It 'I-01: every function in Public and Private has an INVARIANTS block' {
        $missing = @($script:lint.Data.MissingBlock)
        ($missing -join ', ') | Should -BeNullOrEmpty -Because 'every function states its invariants'
    }

    It 'I-03, I-05, I-06: every entry is well formed' {
        $found = @($script:lint.Data.Defects | ForEach-Object {
                "$($PSItem.File):$($PSItem.Line) $($PSItem.Function) $($PSItem.Id) $($PSItem.Reason)"
            })
        ($found -join "`n") | Should -BeNullOrEmpty -Because 'blocks follow Docs\standards\invariants.md'
    }

    It 'the committed index matches the code' {
        # The index is generated. To fix a failure, run:
        #   .\scripts\Invoke-InvariantLint.ps1 -IndexPath .\Docs\standards\invariants-index.md
        $indexPath = Join-Path -Path $script:repoRoot -ChildPath 'Docs' -AdditionalChildPath 'standards', 'invariants-index.md'
        (Test-Path -LiteralPath $indexPath) | Should -BeTrue -Because 'the generated index is committed'

        $committed = ((Get-Content -LiteralPath $indexPath -Raw) -replace "`r`n", "`n").TrimEnd()
        $fresh     = ($script:lint.Data.IndexMarkdown -replace "`r`n", "`n").TrimEnd()
        $fresh | Should -Be $committed -Because 'a block changed without the index being regenerated'
    }
}
