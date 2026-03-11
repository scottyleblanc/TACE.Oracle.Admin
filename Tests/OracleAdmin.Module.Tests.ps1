#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'OracleAdmin.psd1') -Force
}

Describe 'OracleAdmin module' {

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

        It 'Invoke-OraEnv is a recognized command' {
            Get-Command -Name 'Invoke-OraEnv' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'oraset is exported by the module' {
            (Get-Module OracleAdmin).ExportedAliases.Keys | Should -Contain 'oraset'
        }

        It 'oraenv is exported by the module' {
            (Get-Module OracleAdmin).ExportedAliases.Keys | Should -Contain 'oraenv'
        }
    }
}
