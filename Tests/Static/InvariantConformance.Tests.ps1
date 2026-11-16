#Requires -Version 7.6

# Static tier. Reads source text only; it does not import the module or run a function.
# The linter (Tests\Lint\Invoke-InvariantLint.ps1) holds the rules. This file turns its
# result into pass or fail.

BeforeAll {
    $script:repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $lintScript      = Join-Path -Path $script:repoRoot -ChildPath 'Tests' -AdditionalChildPath 'Lint', 'Invoke-InvariantLint.ps1'
    $script:lint     = & $lintScript -RepoRoot $script:repoRoot
}

Describe 'Invariant blocks' -Tag 'Static' {

    It 'the linter ran' {
        $script:lint.Data | Should -Not -BeNullOrEmpty -Because $script:lint.Message
    }

    It 'I-01: every function in Source\Public and Source\Private has an INVARIANTS block' {
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
        #   .\Tests\Lint\Invoke-InvariantLint.ps1 -IndexPath .\Docs\standards\invariants-index.md
        $indexPath = Join-Path -Path $script:repoRoot -ChildPath 'Docs' -AdditionalChildPath 'standards', 'invariants-index.md'
        (Test-Path -LiteralPath $indexPath) | Should -BeTrue -Because 'the generated index is committed'

        $committed = ((Get-Content -LiteralPath $indexPath -Raw) -replace "`r`n", "`n").TrimEnd()
        $fresh     = ($script:lint.Data.IndexMarkdown -replace "`r`n", "`n").TrimEnd()
        $fresh | Should -Be $committed -Because 'a block changed without the index being regenerated'
    }
}

Describe 'Invariant linter proof rules' -Tag 'Static' {

    BeforeAll {
        $script:lintPath = Join-Path -Path $script:repoRoot -ChildPath 'Tests' -AdditionalChildPath 'Lint', 'Invoke-InvariantLint.ps1'

        # Builds a one-function repository under TestDrive and lints it. $Block is the
        # INVARIANTS entry lines, without the leading '    #'.
        function Invoke-FixtureLint {
            param([string]$Name, [string[]]$Block, [string[]]$UnitTitles = @(), [string[]]$StaticTitles = @(), [string[]]$UnitLines = @())

            $root = Join-Path -Path $TestDrive -ChildPath $Name
            $null = New-Item -ItemType Directory -Path (Join-Path -Path $root -ChildPath 'Source' -AdditionalChildPath 'Public') -Force
            $null = New-Item -ItemType Directory -Path (Join-Path -Path $root -ChildPath 'Source' -AdditionalChildPath 'Private') -Force
            $null = New-Item -ItemType Directory -Path (Join-Path -Path $root -ChildPath 'Tests' -AdditionalChildPath 'Unit', 'Public') -Force
            $null = New-Item -ItemType Directory -Path (Join-Path -Path $root -ChildPath 'Tests' -AdditionalChildPath 'Static') -Force

            $source = @(
                'function Get-Thing {'
                '    param()'
                '    Set-StrictMode -Version Latest'
                "    `$ErrorActionPreference = 'Stop'"
                '    #--------------------------------------------------------------'
                '    # INVARIANTS'
                '    #'
                @($Block | ForEach-Object { "    #$PSItem" })
                '    #--------------------------------------------------------------'
                '}'
            ) -join "`n"
            Set-Content -LiteralPath (Join-Path -Path $root -ChildPath 'Source' -AdditionalChildPath 'Public', 'Get-Thing.ps1') -Value $source -Encoding UTF8

            # $UnitLines are whole It lines, for tests that need tags or -ForEach.
            $unit = @(@($UnitTitles | ForEach-Object { "It '$PSItem' { }" }) + $UnitLines) -join "`n"
            Set-Content -LiteralPath (Join-Path -Path $root -ChildPath 'Tests' -AdditionalChildPath 'Unit', 'Public', 'Get-Thing.Tests.ps1') -Value $unit -Encoding UTF8

            if ($StaticTitles.Count -gt 0) {
                $static = @($StaticTitles | ForEach-Object { "It '$PSItem' { }" }) -join "`n"
                Set-Content -LiteralPath (Join-Path -Path $root -ChildPath 'Tests' -AdditionalChildPath 'Static', 'SourceInvariants.Tests.ps1') -Value $static -Encoding UTF8
            }

            & $script:lintPath -RepoRoot $root
        }
    }

    It 'I-11 refuses a Type entry with no proof line' {
        $result = Invoke-FixtureLint -Name 'no-proof' -Block @(
            ' PRE-CONDITIONS'
            '   P1 Name is a non-empty string.'
            '       Type: ValidateNotNullOrEmpty.'
        )
        $result.Success | Should -BeFalse
        @($result.Data.Defects.Reason) | Should -Match 'rule I-11'
    }

    It 'I-11 accepts a Guard entry with a cited test and counts it as proven' {
        $result = Invoke-FixtureLint -Name 'guard-proof' -UnitTitles @('P1 refuses a missing name') -Block @(
            ' PRE-CONDITIONS'
            '   P1 Name is checked.'
            '       Guard: the check at the start of the body.'
            "       Test: 'P1 refuses a missing name'."
        )
        $result.Success | Should -BeTrue -Because $result.Message
        $result.Data.Proven | Should -Be 1
    }

    It 'I-11 counts a Type entry with Test: none yet as unproven, not as a defect' {
        $result = Invoke-FixtureLint -Name 'type-none-yet' -Block @(
            ' PRE-CONDITIONS'
            '   P1 Name is a non-empty string.'
            '       Type: ValidateNotNullOrEmpty.'
            '       Test: none yet.'
        )
        $result.Success | Should -BeTrue -Because $result.Message
        $result.Data.Unproven | Should -Be 1
    }

    It 'I-09 refuses a proof line that cites a test the test file does not hold' {
        $result = Invoke-FixtureLint -Name 'missing-test' -Block @(
            ' PRE-CONDITIONS'
            '   P1 Name is checked.'
            '       Guard: the check at the start of the body.'
            "       Test: 'P1 a test nobody wrote'."
        )
        $result.Success | Should -BeFalse
        @($result.Data.Defects.Reason) | Should -Match 'Cited test not found'
    }

    It 'I-09 refuses a cited test whose title two tests in the file share' {
        $result = Invoke-FixtureLint -Name 'shared-title' -UnitTitles @('P1 refuses a missing name', 'P1 refuses a missing name') -Block @(
            ' PRE-CONDITIONS'
            '   P1 Name is checked.'
            '       Guard: the check at the start of the body.'
            "       Test: 'P1 refuses a missing name'."
        )
        $result.Success | Should -BeFalse
        @($result.Data.Defects.Reason) | Should -Match 'shared by 2 tests'
    }

    It 'I-12 refuses a cited static check whose title two checks share' {
        $result = Invoke-FixtureLint -Name 'static-shared' -StaticTitles @('Get-Thing S1 opens no file', 'Get-Thing S1 opens no file') -Block @(
            ' SECURITY INVARIANTS'
            '   [SEC] S1 No file is opened.'
            "       Static: 'Get-Thing S1 opens no file'."
        )
        $result.Success | Should -BeFalse
        @($result.Data.Defects.Reason) | Should -Match 'shared by 2 tests'
    }

    It 'I-12 accepts a cited static check in SourceInvariants.Tests.ps1 named for the function' {
        $result = Invoke-FixtureLint -Name 'static-ok' -StaticTitles @('Get-Thing S1 opens no file') -Block @(
            ' SECURITY INVARIANTS'
            '   [SEC] S1 No file is opened.'
            "       Static: 'Get-Thing S1 opens no file'."
        )
        $result.Success | Should -BeTrue -Because $result.Message
        $result.Data.Proven | Should -Be 1
    }

    It 'I-12 refuses a cited static check that does not start with the function name' {
        $result = Invoke-FixtureLint -Name 'static-unnamed' -StaticTitles @('S1 opens no file') -Block @(
            ' SECURITY INVARIANTS'
            '   [SEC] S1 No file is opened.'
            "       Static: 'S1 opens no file'."
        )
        $result.Success | Should -BeFalse
        @($result.Data.Defects.Reason) | Should -Match 'rule I-12'
    }

    It 'I-12 refuses a cited static check that is not in SourceInvariants.Tests.ps1' {
        $result = Invoke-FixtureLint -Name 'static-missing' -Block @(
            ' SECURITY INVARIANTS'
            '   [SEC] S1 No file is opened.'
            "       Static: 'Get-Thing S1 opens no file'."
        )
        $result.Success | Should -BeFalse
        @($result.Data.Defects.Reason) | Should -Match 'Cited check not found'
    }

    It 'T-09 refuses a cited test whose title does not start with its ID' {
        $result = Invoke-FixtureLint -Name 't09-no-id' -UnitTitles @('refuses a missing name') -Block @(
            ' PRE-CONDITIONS'
            '   P1 Name is checked.'
            '       Guard: the check at the start of the body.'
            "       Test: 'refuses a missing name'."
        )
        $result.Success | Should -BeFalse
        @($result.Data.Defects.Reason) | Should -Match 'rule T-09'
    }

    It 'T-09 refuses a cited test whose title names an ID it is not cited for' {
        $result = Invoke-FixtureLint -Name 't09-extra-id' -UnitTitles @('P1, P2 refuses a missing name') -Block @(
            ' PRE-CONDITIONS'
            '   P1 Name is checked.'
            '       Guard: the check at the start of the body.'
            "       Test: 'P1, P2 refuses a missing name'."
        )
        $result.Success | Should -BeFalse
        @($result.Data.Defects.Reason) | Should -Match 'rule T-09'
    }

    It 'T-09 accepts a test cited by two entries when its title names both' {
        $result = Invoke-FixtureLint -Name 't09-two-ids' -UnitTitles @('P1, R1 refuses a missing name') -Block @(
            ' PRE-CONDITIONS'
            '   P1 Name is checked.'
            '       Guard: the check at the start of the body.'
            "       Test: 'P1, R1 refuses a missing name'."
            ' POST-CONDITIONS'
            '   R1 A missing name returns Success = $false.'
            "       Test: 'P1, R1 refuses a missing name'."
        )
        $result.Success | Should -BeTrue -Because $result.Message
    }

    It 'T-09 refuses a test cited for a security invariant that has no SEC tag' {
        $result = Invoke-FixtureLint -Name 't09-untagged' -UnitTitles @('S1 opens no file') -Block @(
            ' SECURITY INVARIANTS'
            '   [SEC] S1 No file is opened.'
            '       Guard: no file command in the body.'
            "       Test: 'S1 opens no file'."
        )
        $result.Success | Should -BeFalse
        @($result.Data.Defects.Reason) | Should -Match 'no SEC tag'
    }

    It 'T-09 accepts a security test tagged SEC, with -ForEach before the tag' {
        $result = Invoke-FixtureLint -Name 't09-tagged' -UnitLines @("It 'S1 opens no file (<Case>)' -ForEach @(@{ Case = 'a' }) -Tag 'SEC' { }") -Block @(
            ' SECURITY INVARIANTS'
            '   [SEC] S1 No file is opened.'
            '       Guard: no file command in the body.'
            "       Test: 'S1 opens no file (<Case>)'."
        )
        $result.Success | Should -BeTrue -Because $result.Message
    }
}
