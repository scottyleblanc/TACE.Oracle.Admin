#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'OracleAdmin.psd1') -Force

    # Shared test data — accessible in BeforeEach/It blocks via $script: scope
    $script:twoInstances = @(
        [PSCustomObject]@{ SID = 'ORCL'; Status = 'Running'; ServiceName = 'OracleServiceORCL' }
        [PSCustomObject]@{ SID = 'CDB1'; Status = 'Stopped'; ServiceName = 'OracleServiceCDB1' }
    )

    $script:oneInstance = @(
        [PSCustomObject]@{ SID = 'ORCL'; Status = 'Running'; ServiceName = 'OracleServiceORCL' }
    )
}

Describe 'Set-OracleEnv' {

    Context 'Parameter Validation' {

        It 'SID parameter is optional' {
            $params = (Get-Command Set-OracleEnv).Parameters['SID']
            $mandatory = $params.Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Select-Object -ExpandProperty Mandatory
            $mandatory | Should -BeFalse
        }

        It 'SID parameter is typed [string]' {
            $params = (Get-Command Set-OracleEnv).Parameters['SID']
            $params.ParameterType | Should -Be ([string])
        }

        It 'Supports -WhatIf' {
            (Get-Command Set-OracleEnv).Parameters.ContainsKey('WhatIf') | Should -BeTrue
        }
    }

    Context 'Implementation - SID supplied, service Running' {

        BeforeEach {
            # Mock scriptblock must be self-contained — no test-scope helpers or variables
            Mock Get-OracleDatabaseList {
                [PSCustomObject]@{
                    Success = $true
                    Data    = @(
                        [PSCustomObject]@{ SID = 'ORCL'; Status = 'Running'; ServiceName = 'OracleServiceORCL' }
                        [PSCustomObject]@{ SID = 'CDB1'; Status = 'Stopped'; ServiceName = 'OracleServiceCDB1' }
                    )
                    Message = 'Found 2 Oracle database instance(s).'
                }
            } -ModuleName OracleAdmin
            $env:ORACLE_SID = $null
        }

        AfterEach { $env:ORACLE_SID = $null }

        It 'Returns Success = $true' {
            $result = Set-OracleEnv -SID 'ORCL'
            $result.Success | Should -BeTrue
        }

        It 'Sets $env:ORACLE_SID to the supplied SID' {
            Set-OracleEnv -SID 'ORCL' | Out-Null
            $env:ORACLE_SID | Should -Be 'ORCL'
        }

        It 'Returns Data.SID matching the supplied SID' {
            $result = Set-OracleEnv -SID 'ORCL'
            $result.Data.SID | Should -Be 'ORCL'
        }
    }

    Context 'Implementation - SID supplied, service Stopped' {

        BeforeEach {
            Mock Get-OracleDatabaseList {
                [PSCustomObject]@{
                    Success = $true
                    Data    = @(
                        [PSCustomObject]@{ SID = 'ORCL'; Status = 'Running'; ServiceName = 'OracleServiceORCL' }
                        [PSCustomObject]@{ SID = 'CDB1'; Status = 'Stopped'; ServiceName = 'OracleServiceCDB1' }
                    )
                    Message = 'Found 2 Oracle database instance(s).'
                }
            } -ModuleName OracleAdmin
            $env:ORACLE_SID = $null
        }

        AfterEach { $env:ORACLE_SID = $null }

        It 'Returns Success = $true despite stopped service' {
            $result = Set-OracleEnv -SID 'CDB1' -WarningAction SilentlyContinue
            $result.Success | Should -BeTrue
        }

        It 'Sets $env:ORACLE_SID despite stopped service' {
            Set-OracleEnv -SID 'CDB1' -WarningAction SilentlyContinue | Out-Null
            $env:ORACLE_SID | Should -Be 'CDB1'
        }

        It 'Emits a warning for a stopped service' {
            Set-OracleEnv -SID 'CDB1' -WarningVariable w 3>&1 | Out-Null
            $w | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Implementation - SID supplied, not found' {

        BeforeEach {
            Mock Get-OracleDatabaseList {
                [PSCustomObject]@{
                    Success = $true
                    Data    = @(
                        [PSCustomObject]@{ SID = 'ORCL'; Status = 'Running'; ServiceName = 'OracleServiceORCL' }
                        [PSCustomObject]@{ SID = 'CDB1'; Status = 'Stopped'; ServiceName = 'OracleServiceCDB1' }
                    )
                    Message = 'Found 2 Oracle database instance(s).'
                }
            } -ModuleName OracleAdmin
        }

        It 'Returns Success = $false' {
            $result = Set-OracleEnv -SID 'BOGUS'
            $result.Success | Should -BeFalse
        }

        It 'Does not set $env:ORACLE_SID' {
            $env:ORACLE_SID = $null
            Set-OracleEnv -SID 'BOGUS' | Out-Null
            $env:ORACLE_SID | Should -BeNullOrEmpty
        }

        It 'Message lists valid SIDs' {
            $result = Set-OracleEnv -SID 'BOGUS'
            $result.Message | Should -Match 'ORCL'
            $result.Message | Should -Match 'CDB1'
        }
    }

    Context 'Implementation - no SID supplied, single instance' {

        BeforeEach {
            Mock Get-OracleDatabaseList {
                [PSCustomObject]@{
                    Success = $true
                    Data    = @(
                        [PSCustomObject]@{ SID = 'ORCL'; Status = 'Running'; ServiceName = 'OracleServiceORCL' }
                    )
                    Message = 'Found 1 Oracle database instance(s).'
                }
            } -ModuleName OracleAdmin
            $env:ORACLE_SID = $null
        }

        AfterEach { $env:ORACLE_SID = $null }

        It 'Returns Success = $true' {
            $result = Set-OracleEnv
            $result.Success | Should -BeTrue
        }

        It 'Sets $env:ORACLE_SID automatically' {
            Set-OracleEnv | Out-Null
            $env:ORACLE_SID | Should -Be 'ORCL'
        }
    }

    Context 'Implementation - no SID supplied, multiple instances, valid selection' {

        BeforeEach {
            Mock Get-OracleDatabaseList {
                [PSCustomObject]@{
                    Success = $true
                    Data    = @(
                        [PSCustomObject]@{ SID = 'ORCL'; Status = 'Running'; ServiceName = 'OracleServiceORCL' }
                        [PSCustomObject]@{ SID = 'CDB1'; Status = 'Stopped'; ServiceName = 'OracleServiceCDB1' }
                    )
                    Message = 'Found 2 Oracle database instance(s).'
                }
            } -ModuleName OracleAdmin
            Mock Read-Host { '1' } -ModuleName OracleAdmin
            $env:ORACLE_SID = $null
        }

        AfterEach { $env:ORACLE_SID = $null }

        It 'Returns Success = $true' {
            $result = Set-OracleEnv
            $result.Success | Should -BeTrue
        }

        It 'Sets $env:ORACLE_SID to the selected instance' {
            Set-OracleEnv | Out-Null
            $env:ORACLE_SID | Should -Be 'ORCL'
        }
    }

    Context 'Implementation - no SID supplied, multiple instances, invalid selection' {

        BeforeEach {
            Mock Get-OracleDatabaseList {
                [PSCustomObject]@{
                    Success = $true
                    Data    = @(
                        [PSCustomObject]@{ SID = 'ORCL'; Status = 'Running'; ServiceName = 'OracleServiceORCL' }
                        [PSCustomObject]@{ SID = 'CDB1'; Status = 'Stopped'; ServiceName = 'OracleServiceCDB1' }
                    )
                    Message = 'Found 2 Oracle database instance(s).'
                }
            } -ModuleName OracleAdmin
            Mock Read-Host { 'x' } -ModuleName OracleAdmin
        }

        It 'Returns Success = $false' {
            $result = Set-OracleEnv
            $result.Success | Should -BeFalse
        }

        It 'Does not set $env:ORACLE_SID' {
            $env:ORACLE_SID = $null
            Set-OracleEnv | Out-Null
            $env:ORACLE_SID | Should -BeNullOrEmpty
        }
    }

    Context 'Implementation - no instances found' {

        BeforeEach {
            Mock Get-OracleDatabaseList {
                [PSCustomObject]@{ Success = $true; Data = @(); Message = 'No Oracle database services found.' }
            } -ModuleName OracleAdmin
        }

        It 'Returns Success = $false' {
            $result = Set-OracleEnv
            $result.Success | Should -BeFalse
        }

        It 'Message indicates no instances found' {
            $result = Set-OracleEnv
            $result.Message | Should -Match 'No Oracle'
        }
    }

    Context 'Implementation - Get-OracleDatabaseList fails' {

        BeforeEach {
            Mock Get-OracleDatabaseList {
                [PSCustomObject]@{ Success = $false; Data = $null; Message = 'Service query failed.' }
            } -ModuleName OracleAdmin
        }

        It 'Returns Success = $false' {
            $result = Set-OracleEnv
            $result.Success | Should -BeFalse
        }
    }

    Context 'Return object shape' {

        BeforeEach {
            Mock Get-OracleDatabaseList {
                [PSCustomObject]@{
                    Success = $true
                    Data    = @(
                        [PSCustomObject]@{ SID = 'ORCL'; Status = 'Running'; ServiceName = 'OracleServiceORCL' }
                    )
                    Message = 'Found 1 Oracle database instance(s).'
                }
            } -ModuleName OracleAdmin
            $env:ORACLE_SID = $null
        }

        AfterEach { $env:ORACLE_SID = $null }

        It 'Has Success property' {
            (Set-OracleEnv).PSObject.Properties.Name | Should -Contain 'Success'
        }

        It 'Has Data property' {
            (Set-OracleEnv).PSObject.Properties.Name | Should -Contain 'Data'
        }

        It 'Has Message property' {
            (Set-OracleEnv).PSObject.Properties.Name | Should -Contain 'Message'
        }

        It 'Data.SID is a non-empty string on success' {
            $result = Set-OracleEnv
            $result.Data.SID | Should -BeOfType [string]
            $result.Data.SID | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Security' {

        BeforeEach {
            Mock Get-OracleDatabaseList {
                [PSCustomObject]@{
                    Success = $true
                    Data    = @(
                        [PSCustomObject]@{ SID = 'ORCL'; Status = 'Running'; ServiceName = 'OracleServiceORCL' }
                    )
                    Message = 'Found 1 Oracle database instance(s).'
                }
            } -ModuleName OracleAdmin
            $env:ORACLE_SID = $null
        }

        AfterEach { $env:ORACLE_SID = $null }

        It 'Message contains no credential fragments' {
            $result = Set-OracleEnv
            $result.Message | Should -Not -Match 'password|credential|secret|pwd'
        }

        It 'ArgumentList is not used (env var set directly, not via child process)' {
            # Set-OracleEnv writes to $env:ORACLE_SID directly — no child process involved.
            Mock Start-Process { throw 'Start-Process must not be called' } -ModuleName OracleAdmin
            { Set-OracleEnv } | Should -Not -Throw
        }
    }
}
