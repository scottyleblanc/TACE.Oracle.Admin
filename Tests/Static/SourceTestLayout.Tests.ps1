#Requires -Version 7.6
<#
.SYNOPSIS
    Static tier: one function per source file, and one test file per function.

.DESCRIPTION
    Reads Source\ and Tests\Unit\ as text; runs no module code.
      - C-03: every file under Source\Classes, Source\Private and Source\Public defines
        exactly one top-level function, named for the file.
      - T-02: every such function has Tests\Unit\<Folder>\<Name>.Tests.ps1, in the folder
        that mirrors its source folder.
      - T-02: every test file in those folders belongs to a source file, so a renamed or
        removed function cannot leave a test file behind.
    Tests\Unit\Module\ holds module-level tests and is not checked against Source\.

.NOTES
    Copyright © TACE Data Management Inc.
#>

BeforeDiscovery {
    $repoRoot      = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $sourceFolders = @('Classes', 'Private', 'Public')

    $script:sourceCases = @(
        foreach ($folder in $sourceFolders) {
            $path = Join-Path -Path $repoRoot -ChildPath 'Source' -AdditionalChildPath $folder
            if (Test-Path -LiteralPath $path) {
                Get-ChildItem -LiteralPath $path -Filter '*.ps1' -File | Sort-Object -Property Name | ForEach-Object {
                    @{ Folder = $folder; Name = $PSItem.BaseName; Path = $PSItem.FullName; RepoRoot = $repoRoot }
                }
            }
        }
    )

    $script:testCases = @(
        foreach ($folder in $sourceFolders) {
            $path = Join-Path -Path $repoRoot -ChildPath 'Tests' -AdditionalChildPath 'Unit', $folder
            if (Test-Path -LiteralPath $path) {
                Get-ChildItem -LiteralPath $path -Filter '*.Tests.ps1' -File | Sort-Object -Property Name | ForEach-Object {
                    @{ Folder = $folder; Name = $PSItem.Name -replace '\.Tests\.ps1$', ''; RepoRoot = $repoRoot }
                }
            }
        }
    )
}

Describe 'Source and test layout' {

    # Discovery data is not visible when tests run, so the count is passed in as test data.
    It 'finds source files to check' -ForEach @(@{ Count = $script:sourceCases.Count }) {
        $Count | Should -BeGreaterThan 0
    }

    It 'C-03 Source\<Folder>\<Name>.ps1 defines exactly one function, <Name>' -ForEach $script:sourceCases {
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
        @($errors) | Should -HaveCount 0
        $names = @($ast.FindAll({
            param([System.Management.Automation.Language.Ast]$Node)
            $Node -is [System.Management.Automation.Language.FunctionDefinitionAst]
        }, $false) | ForEach-Object { $PSItem.Name })
        $names | Should -Be @($Name)
    }

    It 'T-02 Source\<Folder>\<Name>.ps1 has Tests\Unit\<Folder>\<Name>.Tests.ps1' -ForEach $script:sourceCases {
        $testFile = Join-Path -Path $RepoRoot -ChildPath 'Tests' -AdditionalChildPath 'Unit', $Folder, "$Name.Tests.ps1"
        Test-Path -LiteralPath $testFile -PathType Leaf | Should -BeTrue
    }

    It 'T-02 Tests\Unit\<Folder>\<Name>.Tests.ps1 belongs to Source\<Folder>\<Name>.ps1' -ForEach $script:testCases {
        $sourceFile = Join-Path -Path $RepoRoot -ChildPath 'Source' -AdditionalChildPath $Folder, "$Name.ps1"
        Test-Path -LiteralPath $sourceFile -PathType Leaf | Should -BeTrue
    }
}
