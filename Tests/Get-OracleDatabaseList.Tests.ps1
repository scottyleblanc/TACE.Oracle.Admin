#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'OracleAdmin.psd1') -Force
}

Describe 'Get-OracleDatabaseList' {

    Context 'Parameter Validation' {

        It 'Accepts no parameters' {
            { Get-OracleDatabaseList } | Should -Not -Throw
        }

        It 'Does not accept positional arguments' {
            { Get-OracleDatabaseList 'ORCL' } | Should -Throw
        }
    }

    Context 'Implementation — services found' {

        BeforeEach {
            Mock Get-Service {
                @(
                    [PSCustomObject]@{ Name = 'OracleServiceORCL'; Status = 'Running' }
                    [PSCustomObject]@{ Name = 'OracleServiceCDB1'; Status = 'Stopped' }
                )
            } -ModuleName OracleAdmin
        }

        It 'Returns Success = $true' {
            $result = Get-OracleDatabaseList
            $result.Success | Should -BeTrue
        }

        It 'Returns correct SID values' {
            $result = Get-OracleDatabaseList
            $result.Data.SID | Should -Contain 'ORCL'
            $result.Data.SID | Should -Contain 'CDB1'
        }

        It 'Returns correct Status values' {
            $result = Get-OracleDatabaseList
            ($result.Data | Where-Object SID -EQ 'ORCL').Status | Should -Be 'Running'
            ($result.Data | Where-Object SID -EQ 'CDB1').Status | Should -Be 'Stopped'
        }

        It 'Returns correct ServiceName values' {
            $result = Get-OracleDatabaseList
            ($result.Data | Where-Object SID -EQ 'ORCL').ServiceName | Should -Be 'OracleServiceORCL'
        }

        It 'Returns Data as an array' {
            $result = Get-OracleDatabaseList
            $result.Data | Should -BeOfType [PSCustomObject]
            @($result.Data).Count | Should -Be 2
        }

        It 'Message contains instance count' {
            $result = Get-OracleDatabaseList
            $result.Message | Should -Match '2'
        }
    }

    Context 'Implementation — no services found' {

        BeforeEach {
            Mock Get-Service { @() } -ModuleName OracleAdmin
        }

        It 'Returns Success = $true with empty Data' {
            $result = Get-OracleDatabaseList
            $result.Success | Should -BeTrue
            @($result.Data).Count | Should -Be 0
        }

        It 'Returns a descriptive message' {
            $result = Get-OracleDatabaseList
            $result.Message | Should -Match 'No Oracle'
        }
    }

    Context 'Implementation — Get-Service throws' {

        BeforeEach {
            Mock Get-Service { throw 'Access denied' } -ModuleName OracleAdmin
        }

        It 'Returns Success = $false' {
            $result = Get-OracleDatabaseList
            $result.Success | Should -BeFalse
        }

        It 'Returns Data = $null' {
            $result = Get-OracleDatabaseList
            $result.Data | Should -BeNullOrEmpty
        }

        It 'Message contains exception text' {
            $result = Get-OracleDatabaseList
            $result.Message | Should -Match 'Access denied'
        }
    }

    Context 'Return object shape' {

        BeforeEach {
            Mock Get-Service { @() } -ModuleName OracleAdmin
        }

        It 'Has Success property' {
            $result = Get-OracleDatabaseList
            $result.PSObject.Properties.Name | Should -Contain 'Success'
        }

        It 'Has Data property' {
            $result = Get-OracleDatabaseList
            $result.PSObject.Properties.Name | Should -Contain 'Data'
        }

        It 'Has Message property' {
            $result = Get-OracleDatabaseList
            $result.PSObject.Properties.Name | Should -Contain 'Message'
        }

        It 'Message is always a non-null string' {
            $result = Get-OracleDatabaseList
            $result.Message | Should -BeOfType [string]
            $result.Message | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Security' {

        BeforeEach {
            Mock Get-Service { @() } -ModuleName OracleAdmin
        }

        It 'Message contains no credential fragments' {
            $result = Get-OracleDatabaseList
            $result.Message | Should -Not -Match 'password|credential|secret|pwd'
        }
    }
}
