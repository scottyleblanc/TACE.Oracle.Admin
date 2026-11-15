#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Remove-Module 'TACE.Oracle.Admin' -Force -ErrorAction SilentlyContinue
    Import-Module (& (Join-Path $PSScriptRoot '..' 'Get-BuiltModulePath.ps1')) -Force
}

Describe 'TACE.Oracle.Admin module' {

    Context 'Aliases' {

        It 'oraset alias exists' {
            Get-Alias -Name 'oraset' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'oraenv alias exists' {
            Get-Alias -Name 'oraenv' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'oraset resolves to Invoke-OraEnv' {
            (Get-Alias -Name 'oraset').Definition | Should -Be 'Invoke-OraEnv'
        }

        It 'oraenv resolves to Invoke-OraEnv' {
            (Get-Alias -Name 'oraenv').Definition | Should -Be 'Invoke-OraEnv'
        }

        It 'oraset is exported by the module' {
            (Get-Module 'TACE.Oracle.Admin').ExportedAliases.Keys | Should -Contain 'oraset'
        }

        It 'oraenv is exported by the module' {
            (Get-Module 'TACE.Oracle.Admin').ExportedAliases.Keys | Should -Contain 'oraenv'
        }

        It 'Invoke-OraEnv is callable (alias target is reachable from outside the module)' {
            { Get-Command -Name 'Invoke-OraEnv' -ErrorAction Stop } | Should -Not -Throw
        }
    }
}
