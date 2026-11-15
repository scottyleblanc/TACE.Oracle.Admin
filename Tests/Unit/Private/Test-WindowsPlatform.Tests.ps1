<#
.SECURITY
    Scope  : Test-WindowsPlatform (private)
    Touches: Nothing. Reads the $IsWindows automatic variable only.
#>

#Requires -Version 7.6

Describe 'Test-WindowsPlatform' {

    BeforeAll {
        $modulePath = [System.IO.Path]::GetFullPath((& (Join-Path $PSScriptRoot '..' 'Get-BuiltModulePath.ps1')))
        Remove-Module TACE.Oracle.Admin -Force -ErrorAction SilentlyContinue
        Import-Module $modulePath -Force
    }

    AfterAll {
        Remove-Module TACE.Oracle.Admin -Force -ErrorAction SilentlyContinue
    }

    Context 'Parameter validation' {

        It 'Accepts no parameters' {
            $cmd = InModuleScope TACE.Oracle.Admin { Get-Command Test-WindowsPlatform }
            $common = [System.Management.Automation.PSCmdlet]::CommonParameters
            @($cmd.Parameters.Keys | Where-Object { $PSItem -notin $common }) | Should -BeNullOrEmpty
        }
    }

    Context 'Implementation' {

        It 'R1 returns the value of IsWindows' {
            $result = InModuleScope TACE.Oracle.Admin { Test-WindowsPlatform }
            $result | Should -BeOfType [bool]
            $result | Should -Be ([bool]$IsWindows)
        }
    }

    Context 'Security' {

        It 'Is not exported as a public command' {
            (Get-Module TACE.Oracle.Admin).ExportedCommands.Keys | Should -Not -Contain 'Test-WindowsPlatform'
        }
    }
}
