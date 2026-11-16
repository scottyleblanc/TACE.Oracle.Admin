#Requires -Version 7.6

# Static tier. AGENTS.md is generated from Docs\standards\ by
# Scripts\Export-AgentInstruction.ps1, so the agent is told the same rules the gate
# enforces. This file fails when the committed copy has drifted from the standards.

BeforeAll {
    $script:repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $exportScript    = Join-Path -Path $script:repoRoot -ChildPath 'Scripts' -AdditionalChildPath 'Export-AgentInstruction.ps1'
    $script:export   = & $exportScript -RepoRoot $script:repoRoot
}

Describe 'Agent instructions' -Tag 'Static' {

    It 'the generator ran' {
        $script:export.Success | Should -BeTrue -Because $script:export.Message
    }

    It 'every rule in the standards is carried' {
        $standardsDir = Join-Path -Path $script:repoRoot -ChildPath 'Docs' -AdditionalChildPath 'standards'
        $expected = 0
        foreach ($name in $script:export.Data.Sources) {
            $text = Get-Content -LiteralPath (Join-Path -Path $standardsDir -ChildPath $name) -Raw
            $expected += @([regex]::Matches($text, '(?m)^- \*\*[A-Z]-\d+\*\* — ')).Count
        }
        $script:export.Data.RuleCount | Should -Be $expected
    }

    It 'the committed AGENTS.md matches Docs\standards' {
        # AGENTS.md is generated. To fix a failure, run:
        #   .\Scripts\Export-AgentInstruction.ps1 -Path .\AGENTS.md
        $agentsPath = Join-Path -Path $script:repoRoot -ChildPath 'AGENTS.md'
        (Test-Path -LiteralPath $agentsPath) | Should -BeTrue -Because 'the generated instructions are committed'

        $committed = ((Get-Content -LiteralPath $agentsPath -Raw) -replace "`r`n", "`n").TrimEnd()
        $fresh     = ($script:export.Data.Markdown -replace "`r`n", "`n").TrimEnd()
        $fresh | Should -Be $committed -Because 'a standard changed without AGENTS.md being regenerated'
    }
}
