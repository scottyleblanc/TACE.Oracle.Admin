#Requires -Version 7.6
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Remove-Module 'TACE.Oracle.Admin' -Force -ErrorAction SilentlyContinue
    Import-Module (& (Join-Path $PSScriptRoot '..' 'Get-BuiltModulePath.ps1')) -Force
}

Describe 'Invoke-OraEnv' {

    Context 'Parameter Validation' {

        It 'SID parameter is optional' {
            $params = (Get-Command Invoke-OraEnv).Parameters['SID']
            $mandatory = $params.Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Select-Object -ExpandProperty Mandatory
            $mandatory | Should -BeFalse
        }

        It 'SID parameter is typed [string]' {
            $params = (Get-Command Invoke-OraEnv).Parameters['SID']
            $params.ParameterType | Should -Be ([string])
        }
    }

    Context 'Implementation - SID pass-through' {

        BeforeEach {
            Mock Set-OracleEnv {
                [PSCustomObject]@{ Success = $true; Data = $null; Message = 'ok' }
            } -ModuleName 'TACE.Oracle.Admin'
        }

        It 'Calls Set-OracleEnv without SID when SID is not supplied' {
            Invoke-OraEnv
            Should -Invoke Set-OracleEnv -ModuleName 'TACE.Oracle.Admin' -Times 1 -Exactly `
                -ParameterFilter { -not $PSBoundParameters.ContainsKey('SID') }
        }

        It 'Calls Set-OracleEnv with the supplied SID' {
            Invoke-OraEnv -SID 'ORCL'
            Should -Invoke Set-OracleEnv -ModuleName 'TACE.Oracle.Admin' -Times 1 -Exactly `
                -ParameterFilter { $SID -eq 'ORCL' }
        }
    }

    Context 'Implementation - Verbose pass-through' {

        # Tests the end-to-end behaviour: Invoke-OraEnv -Verbose causes ORACLE_HOME
        # and ORACLE_BASE to appear on host. Get-OracleDatabaseList is mocked to
        # avoid WMI; Set-OracleEnv runs for real to verify the full call chain.

        BeforeEach {
            Mock Get-OracleDatabaseList {
                [PSCustomObject]@{
                    Success = $true
                    Data    = @(
                        [PSCustomObject]@{ SID = 'ORCL'; Status = 'Running'; ServiceName = 'OracleServiceORCL'; OracleHome = 'C:\app\oracle\product\19.3\dbhome_1'; OracleBase = 'C:\app\oracle' }
                    )
                    Message = 'Found 1 Oracle database instance(s).'
                }
            } -ModuleName 'TACE.Oracle.Admin'
            Mock Write-Host {} -ModuleName 'TACE.Oracle.Admin'
            $env:ORACLE_SID  = $null
            $env:ORACLE_HOME = $null
            $env:ORACLE_BASE = $null
        }

        AfterEach {
            $env:ORACLE_SID  = $null
            $env:ORACLE_HOME = $null
            $env:ORACLE_BASE = $null
        }

        It 'Shows ORACLE_HOME and ORACLE_BASE on host when -Verbose is specified' {
            Invoke-OraEnv -Verbose 4>&1 | Out-Null
            Should -Invoke Write-Host -ModuleName 'TACE.Oracle.Admin' `
                -ParameterFilter { $Object -like 'ORACLE_HOME*' } -Times 1 -Exactly
            Should -Invoke Write-Host -ModuleName 'TACE.Oracle.Admin' `
                -ParameterFilter { $Object -like 'ORACLE_BASE*' } -Times 1 -Exactly
        }

        It 'Does not show ORACLE_HOME and ORACLE_BASE on host when -Verbose is not specified' {
            Invoke-OraEnv
            Should -Invoke Write-Host -ModuleName 'TACE.Oracle.Admin' `
                -ParameterFilter { $Object -like 'ORACLE_HOME*' } -Times 0 -Exactly
            Should -Invoke Write-Host -ModuleName 'TACE.Oracle.Admin' `
                -ParameterFilter { $Object -like 'ORACLE_BASE*' } -Times 0 -Exactly
        }
    }

    Context 'Implementation - output behaviour' {

        It 'Does not write to the pipeline on success' {
            Mock Set-OracleEnv {
                [PSCustomObject]@{ Success = $true; Data = $null; Message = 'ok' }
            } -ModuleName 'TACE.Oracle.Admin'

            $output = Invoke-OraEnv
            $output | Should -BeNullOrEmpty
        }

        It 'Writes [ERROR] to host when Set-OracleEnv returns Success=$false' {
            Mock Set-OracleEnv {
                [PSCustomObject]@{ Success = $false; Data = $null; Message = 'SID not found.' }
            } -ModuleName 'TACE.Oracle.Admin'
            Mock Write-Host {} -ModuleName 'TACE.Oracle.Admin'

            Invoke-OraEnv
            Should -Invoke Write-Host -ModuleName 'TACE.Oracle.Admin' -Times 1 -Exactly `
                -ParameterFilter { $Object -like '*[ERROR]*' }
        }

        It 'Does not write [ERROR] to host when Set-OracleEnv returns Success=$true' {
            Mock Set-OracleEnv {
                [PSCustomObject]@{ Success = $true; Data = $null; Message = 'ok' }
            } -ModuleName 'TACE.Oracle.Admin'
            Mock Write-Host {} -ModuleName 'TACE.Oracle.Admin'

            Invoke-OraEnv
            Should -Invoke Write-Host -ModuleName 'TACE.Oracle.Admin' `
                -ParameterFilter { $Object -like '*[ERROR]*' } -Times 0 -Exactly
        }
    }

    Context 'Security' {

        It '[ERROR] message contains no credential fragments' {
            Mock Set-OracleEnv {
                [PSCustomObject]@{ Success = $false; Data = $null; Message = 'SID not found.' }
            } -ModuleName 'TACE.Oracle.Admin'
            Mock Write-Host {} -ModuleName 'TACE.Oracle.Admin'

            Invoke-OraEnv
            Should -Invoke Write-Host -ModuleName 'TACE.Oracle.Admin' `
                -ParameterFilter { $Object -notmatch 'password|credential|secret|pwd' } -Times 1 -Exactly
        }
    }
}
