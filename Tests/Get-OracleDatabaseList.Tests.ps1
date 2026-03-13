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
            Mock Get-CimInstance {
                @(
                    [PSCustomObject]@{
                        Name     = 'OracleServiceORCL'
                        State    = 'Running'
                        PathName = 'C:\app\oracle\product\19.3\dbhome_1\bin\ORACLE.EXE ORCL'
                    }
                    [PSCustomObject]@{
                        Name     = 'OracleServiceCDB1'
                        State    = 'Stopped'
                        PathName = 'C:\app\oracle\product\19.3\dbhome_2\bin\ORACLE.EXE CDB1'
                    }
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

        It 'Returns correct OracleHome from unquoted PathName' {
            $result = Get-OracleDatabaseList
            ($result.Data | Where-Object SID -EQ 'ORCL').OracleHome | Should -Be 'C:\app\oracle\product\19.3\dbhome_1'
            ($result.Data | Where-Object SID -EQ 'CDB1').OracleHome | Should -Be 'C:\app\oracle\product\19.3\dbhome_2'
        }

        It 'Returns correct OracleBase from unquoted PathName' {
            $result = Get-OracleDatabaseList
            ($result.Data | Where-Object SID -EQ 'ORCL').OracleBase | Should -Be 'C:\app\oracle'
            ($result.Data | Where-Object SID -EQ 'CDB1').OracleBase | Should -Be 'C:\app\oracle'
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

    Context 'Implementation — OracleHome and OracleBase from quoted PathName' {

        BeforeEach {
            Mock Get-CimInstance {
                @(
                    [PSCustomObject]@{
                        Name     = 'OracleServiceORCL'
                        State    = 'Running'
                        PathName = '"C:\app\oracle\product\19.3\dbhome_1\bin\ORACLE.EXE" ORCL'
                    }
                )
            } -ModuleName OracleAdmin
        }

        It 'Extracts OracleHome correctly from a quoted PathName' {
            $result = Get-OracleDatabaseList
            ($result.Data | Where-Object SID -EQ 'ORCL').OracleHome | Should -Be 'C:\app\oracle\product\19.3\dbhome_1'
        }

        It 'Extracts OracleBase correctly from a quoted PathName' {
            $result = Get-OracleDatabaseList
            ($result.Data | Where-Object SID -EQ 'ORCL').OracleBase | Should -Be 'C:\app\oracle'
        }
    }

    Context 'Implementation — OracleHome and OracleBase when PathName is empty' {

        BeforeEach {
            Mock Get-CimInstance {
                @(
                    [PSCustomObject]@{
                        Name     = 'OracleServiceORCL'
                        State    = 'Running'
                        PathName = ''
                    }
                )
            } -ModuleName OracleAdmin
        }

        It 'Returns OracleHome as $null when PathName is empty' {
            $result = Get-OracleDatabaseList
            ($result.Data | Where-Object SID -EQ 'ORCL').OracleHome | Should -BeNullOrEmpty
        }

        It 'Returns OracleBase as $null when PathName is empty' {
            $result = Get-OracleDatabaseList
            ($result.Data | Where-Object SID -EQ 'ORCL').OracleBase | Should -BeNullOrEmpty
        }
    }

    Context 'Implementation — no services found' {

        BeforeEach {
            Mock Get-CimInstance { @() } -ModuleName OracleAdmin
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

    Context 'Implementation — Get-CimInstance throws' {

        BeforeEach {
            Mock Get-CimInstance { throw 'Access denied' } -ModuleName OracleAdmin
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
            Mock Get-CimInstance { @() } -ModuleName OracleAdmin
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

    Context 'Data entry shape' {

        BeforeEach {
            Mock Get-CimInstance {
                @(
                    [PSCustomObject]@{
                        Name     = 'OracleServiceORCL'
                        State    = 'Running'
                        PathName = 'C:\app\oracle\product\19.3\dbhome_1\bin\ORACLE.EXE ORCL'
                    }
                )
            } -ModuleName OracleAdmin
        }

        It 'Data entries have SID property' {
            $result = Get-OracleDatabaseList
            $result.Data[0].PSObject.Properties.Name | Should -Contain 'SID'
        }

        It 'Data entries have Status property' {
            $result = Get-OracleDatabaseList
            $result.Data[0].PSObject.Properties.Name | Should -Contain 'Status'
        }

        It 'Data entries have ServiceName property' {
            $result = Get-OracleDatabaseList
            $result.Data[0].PSObject.Properties.Name | Should -Contain 'ServiceName'
        }

        It 'Data entries have OracleHome property' {
            $result = Get-OracleDatabaseList
            $result.Data[0].PSObject.Properties.Name | Should -Contain 'OracleHome'
        }

        It 'Data entries have OracleBase property' {
            $result = Get-OracleDatabaseList
            $result.Data[0].PSObject.Properties.Name | Should -Contain 'OracleBase'
        }
    }

    Context 'Security' {

        BeforeEach {
            Mock Get-CimInstance { @() } -ModuleName OracleAdmin
        }

        It 'Message contains no credential fragments' {
            $result = Get-OracleDatabaseList
            $result.Message | Should -Not -Match 'password|credential|secret|pwd'
        }
    }
}
