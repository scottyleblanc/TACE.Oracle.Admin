#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Remove-Module 'TACE.Oracle.Admin' -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $PSScriptRoot '..' 'TACE.Oracle.Admin.psd1') -Force
}

Describe 'Get-OracleDatabaseList' {

    Context 'Parameter Validation' {

        It 'Accepts no parameters' {
            { Get-OracleDatabaseList } | Should -Not -Throw
        }

        It 'Returns a structured error for an unknown platform value' {
            $result = Get-OracleDatabaseList -Platform 'BOGUS'
            $result.Success | Should -BeFalse
            $result.PSObject.Properties.Name | Should -Contain 'Message'
        }
    }

    # -------------------------------------------------------------------------
    # Windows path
    # -------------------------------------------------------------------------

    Context 'Windows — services found' -Skip:(-not $IsWindows) {

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
            } -ModuleName 'TACE.Oracle.Admin'
        }

        It 'Returns Success = $true' {
            (Get-OracleDatabaseList -Platform Windows).Success | Should -BeTrue
        }

        It 'Returns correct SID values' {
            $result = Get-OracleDatabaseList -Platform Windows
            $result.Data.SID | Should -Contain 'ORCL'
            $result.Data.SID | Should -Contain 'CDB1'
        }

        It 'Returns correct Status values' {
            $result = Get-OracleDatabaseList -Platform Windows
            ($result.Data | Where-Object SID -EQ 'ORCL').Status | Should -Be 'Running'
            ($result.Data | Where-Object SID -EQ 'CDB1').Status | Should -Be 'Stopped'
        }

        It 'Returns correct ServiceName values' {
            $result = Get-OracleDatabaseList -Platform Windows
            ($result.Data | Where-Object SID -EQ 'ORCL').ServiceName | Should -Be 'OracleServiceORCL'
        }

        It 'Returns correct OracleHome from unquoted PathName' {
            $result = Get-OracleDatabaseList -Platform Windows
            ($result.Data | Where-Object SID -EQ 'ORCL').OracleHome | Should -Be 'C:\app\oracle\product\19.3\dbhome_1'
            ($result.Data | Where-Object SID -EQ 'CDB1').OracleHome | Should -Be 'C:\app\oracle\product\19.3\dbhome_2'
        }

        It 'Returns correct OracleBase from unquoted PathName' {
            $result = Get-OracleDatabaseList -Platform Windows
            ($result.Data | Where-Object SID -EQ 'ORCL').OracleBase | Should -Be 'C:\app\oracle'
            ($result.Data | Where-Object SID -EQ 'CDB1').OracleBase | Should -Be 'C:\app\oracle'
        }

        It 'Returns Data as an array' {
            $result = Get-OracleDatabaseList -Platform Windows
            $result.Data | Should -BeOfType [PSCustomObject]
            @($result.Data).Count | Should -Be 2
        }

        It 'Message contains instance count' {
            (Get-OracleDatabaseList -Platform Windows).Message | Should -Match '2'
        }
    }

    Context 'Windows — OracleHome and OracleBase from quoted PathName' -Skip:(-not $IsWindows) {

        BeforeEach {
            Mock Get-CimInstance {
                @(
                    [PSCustomObject]@{
                        Name     = 'OracleServiceORCL'
                        State    = 'Running'
                        PathName = '"C:\app\oracle\product\19.3\dbhome_1\bin\ORACLE.EXE" ORCL'
                    }
                )
            } -ModuleName 'TACE.Oracle.Admin'
        }

        It 'Extracts OracleHome correctly from a quoted PathName' {
            $result = Get-OracleDatabaseList -Platform Windows
            ($result.Data | Where-Object SID -EQ 'ORCL').OracleHome | Should -Be 'C:\app\oracle\product\19.3\dbhome_1'
        }

        It 'Extracts OracleBase correctly from a quoted PathName' {
            $result = Get-OracleDatabaseList -Platform Windows
            ($result.Data | Where-Object SID -EQ 'ORCL').OracleBase | Should -Be 'C:\app\oracle'
        }
    }

    Context 'Windows — OracleHome and OracleBase when PathName is empty' -Skip:(-not $IsWindows) {

        BeforeEach {
            Mock Get-CimInstance {
                @(
                    [PSCustomObject]@{
                        Name     = 'OracleServiceORCL'
                        State    = 'Running'
                        PathName = ''
                    }
                )
            } -ModuleName 'TACE.Oracle.Admin'
        }

        It 'Returns OracleHome as $null when PathName is empty' {
            ($result = Get-OracleDatabaseList -Platform Windows)
            ($result.Data | Where-Object SID -EQ 'ORCL').OracleHome | Should -BeNullOrEmpty
        }

        It 'Returns OracleBase as $null when PathName is empty' {
            $result = Get-OracleDatabaseList -Platform Windows
            ($result.Data | Where-Object SID -EQ 'ORCL').OracleBase | Should -BeNullOrEmpty
        }
    }

    Context 'Windows — no services found' -Skip:(-not $IsWindows) {

        BeforeEach {
            Mock Get-CimInstance { @() } -ModuleName 'TACE.Oracle.Admin'
        }

        It 'Returns Success = $true with empty Data' {
            $result = Get-OracleDatabaseList -Platform Windows
            $result.Success | Should -BeTrue
            @($result.Data).Count | Should -Be 0
        }

        It 'Returns a descriptive message' {
            (Get-OracleDatabaseList -Platform Windows).Message | Should -Match 'No Oracle'
        }
    }

    Context 'Windows — Get-CimInstance throws' -Skip:(-not $IsWindows) {

        BeforeEach {
            Mock Get-CimInstance { throw 'Access denied' } -ModuleName 'TACE.Oracle.Admin'
        }

        It 'Returns Success = $false' {
            (Get-OracleDatabaseList -Platform Windows).Success | Should -BeFalse
        }

        It 'Returns Data = $null' {
            (Get-OracleDatabaseList -Platform Windows).Data | Should -BeNullOrEmpty
        }

        It 'Message contains exception text' {
            (Get-OracleDatabaseList -Platform Windows).Message | Should -Match 'Access denied'
        }
    }

    # -------------------------------------------------------------------------
    # Linux path
    # -------------------------------------------------------------------------

    Context 'Linux — oratab found, instances running and stopped' {

        BeforeEach {
            Mock Test-Path { $true } -ModuleName 'TACE.Oracle.Admin'
            Mock Get-Content {
                @(
                    'ORCL:/u01/app/oracle/product/19.3.0/dbhome_1:Y'
                    'CDB1:/u01/app/oracle/product/19.3.0/dbhome_2:N'
                )
            } -ModuleName 'TACE.Oracle.Admin'
            Mock Get-Process { @([PSCustomObject]@{ Name = 'ora_pmon_ORCL' }) } `
                -ParameterFilter { $Name -eq 'ora_pmon_ORCL' } -ModuleName 'TACE.Oracle.Admin'
            Mock Get-Process { @() } `
                -ParameterFilter { $Name -eq 'ora_pmon_CDB1' } -ModuleName 'TACE.Oracle.Admin'
        }

        It 'Returns Success = $true' {
            (Get-OracleDatabaseList -Platform Linux).Success | Should -BeTrue
        }

        It 'Returns correct SID values' {
            $result = Get-OracleDatabaseList -Platform Linux
            $result.Data.SID | Should -Contain 'ORCL'
            $result.Data.SID | Should -Contain 'CDB1'
        }

        It 'Returns Running status for instance with pmon process' {
            $result = Get-OracleDatabaseList -Platform Linux
            ($result.Data | Where-Object SID -EQ 'ORCL').Status | Should -Be 'Running'
        }

        It 'Returns Stopped status for instance without pmon process' {
            $result = Get-OracleDatabaseList -Platform Linux
            ($result.Data | Where-Object SID -EQ 'CDB1').Status | Should -Be 'Stopped'
        }

        It 'Returns ServiceName as $null' {
            $result = Get-OracleDatabaseList -Platform Linux
            ($result.Data | Where-Object SID -EQ 'ORCL').ServiceName | Should -BeNullOrEmpty
            ($result.Data | Where-Object SID -EQ 'CDB1').ServiceName | Should -BeNullOrEmpty
        }

        It 'Returns correct OracleHome from oratab' {
            $result = Get-OracleDatabaseList -Platform Linux
            ($result.Data | Where-Object SID -EQ 'ORCL').OracleHome | Should -Be '/u01/app/oracle/product/19.3.0/dbhome_1'
            ($result.Data | Where-Object SID -EQ 'CDB1').OracleHome | Should -Be '/u01/app/oracle/product/19.3.0/dbhome_2'
        }

        It 'Returns correct OracleBase derived from OracleHome' {
            $result = Get-OracleDatabaseList -Platform Linux
            ($result.Data | Where-Object SID -EQ 'ORCL').OracleBase | Should -Be '/u01/app/oracle'
            ($result.Data | Where-Object SID -EQ 'CDB1').OracleBase | Should -Be '/u01/app/oracle'
        }

        It 'Message contains instance count' {
            (Get-OracleDatabaseList -Platform Linux).Message | Should -Match '2'
        }
    }

    Context 'Linux — oratab not found' {

        BeforeEach {
            Mock Test-Path { $false } -ModuleName 'TACE.Oracle.Admin'
        }

        It 'Returns Success = $true' {
            (Get-OracleDatabaseList -Platform Linux).Success | Should -BeTrue
        }

        It 'Returns empty Data' {
            @((Get-OracleDatabaseList -Platform Linux).Data).Count | Should -Be 0
        }

        It 'Returns a descriptive message' {
            (Get-OracleDatabaseList -Platform Linux).Message | Should -Match 'No Oracle'
        }
    }

    Context 'Linux — comment and blank lines are skipped' {

        BeforeEach {
            Mock Test-Path { $true } -ModuleName 'TACE.Oracle.Admin'
            Mock Get-Content {
                @(
                    '# This is a comment'
                    ''
                    'ORCL:/u01/app/oracle/product/19.3.0/dbhome_1:Y'
                    '   '
                    '# Another comment'
                )
            } -ModuleName 'TACE.Oracle.Admin'
            Mock Get-Process { @([PSCustomObject]@{ Name = 'ora_pmon_ORCL' }) } `
                -ParameterFilter { $Name -eq 'ora_pmon_ORCL' } -ModuleName 'TACE.Oracle.Admin'
        }

        It 'Returns only the valid instance' {
            $result = Get-OracleDatabaseList -Platform Linux
            @($result.Data).Count | Should -Be 1
            $result.Data[0].SID | Should -Be 'ORCL'
        }
    }

    Context 'Linux — malformed oratab lines are skipped' {

        BeforeEach {
            Mock Test-Path { $true } -ModuleName 'TACE.Oracle.Admin'
            Mock Get-Content {
                @(
                    'MALFORMED_LINE_NO_COLON'
                    'ORCL:/u01/app/oracle/product/19.3.0/dbhome_1:Y'
                )
            } -ModuleName 'TACE.Oracle.Admin'
            Mock Get-Process { @([PSCustomObject]@{ Name = 'ora_pmon_ORCL' }) } `
                -ParameterFilter { $Name -eq 'ora_pmon_ORCL' } -ModuleName 'TACE.Oracle.Admin'
        }

        It 'Skips lines with fewer than two colon-separated fields' {
            $result = Get-OracleDatabaseList -Platform Linux
            @($result.Data).Count | Should -Be 1
            $result.Data[0].SID | Should -Be 'ORCL'
        }
    }

    Context 'Linux — wildcard SID entry is skipped' {

        BeforeEach {
            Mock Test-Path { $true } -ModuleName 'TACE.Oracle.Admin'
            Mock Get-Content {
                @(
                    '*:/u01/app/oracle/product/19.3.0/dbhome_1:N'
                    'ORCL:/u01/app/oracle/product/19.3.0/dbhome_1:Y'
                )
            } -ModuleName 'TACE.Oracle.Admin'
            Mock Get-Process { @([PSCustomObject]@{ Name = 'ora_pmon_ORCL' }) } `
                -ParameterFilter { $Name -eq 'ora_pmon_ORCL' } -ModuleName 'TACE.Oracle.Admin'
        }

        It 'Skips the wildcard entry and returns only real SIDs' {
            $result = Get-OracleDatabaseList -Platform Linux
            @($result.Data).Count | Should -Be 1
            $result.Data[0].SID | Should -Be 'ORCL'
        }
    }

    Context 'Linux — Get-Content throws' {

        BeforeEach {
            Mock Test-Path { $true } -ModuleName 'TACE.Oracle.Admin'
            Mock Get-Content { throw 'Permission denied' } -ModuleName 'TACE.Oracle.Admin'
        }

        It 'Returns Success = $false' {
            (Get-OracleDatabaseList -Platform Linux).Success | Should -BeFalse
        }

        It 'Returns Data = $null' {
            (Get-OracleDatabaseList -Platform Linux).Data | Should -BeNullOrEmpty
        }

        It 'Message contains exception text' {
            (Get-OracleDatabaseList -Platform Linux).Message | Should -Match 'Permission denied'
        }
    }

    # -------------------------------------------------------------------------
    # Unsupported platform
    # -------------------------------------------------------------------------

    Context 'Unsupported platform' {

        It 'Returns Success = $false' {
            (Get-OracleDatabaseList -Platform Unsupported).Success | Should -BeFalse
        }

        It 'Returns Data = $null' {
            (Get-OracleDatabaseList -Platform Unsupported).Data | Should -BeNullOrEmpty
        }

        It 'Message identifies the platform' {
            (Get-OracleDatabaseList -Platform Unsupported).Message | Should -Match 'Unsupported'
        }
    }

    # -------------------------------------------------------------------------
    # Return object shape and data entry shape (platform-agnostic)
    # -------------------------------------------------------------------------

    Context 'Return object shape' -Skip:(-not $IsWindows) {

        BeforeEach {
            Mock Get-CimInstance { @() } -ModuleName 'TACE.Oracle.Admin'
        }

        It 'Has Success property' {
            (Get-OracleDatabaseList -Platform Windows).PSObject.Properties.Name | Should -Contain 'Success'
        }

        It 'Has Data property' {
            (Get-OracleDatabaseList -Platform Windows).PSObject.Properties.Name | Should -Contain 'Data'
        }

        It 'Has Message property' {
            (Get-OracleDatabaseList -Platform Windows).PSObject.Properties.Name | Should -Contain 'Message'
        }

        It 'Message is always a non-null string' {
            $result = Get-OracleDatabaseList -Platform Windows
            $result.Message | Should -BeOfType [string]
            $result.Message | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Data entry shape' -Skip:(-not $IsWindows) {

        BeforeEach {
            Mock Get-CimInstance {
                @(
                    [PSCustomObject]@{
                        Name     = 'OracleServiceORCL'
                        State    = 'Running'
                        PathName = 'C:\app\oracle\product\19.3\dbhome_1\bin\ORACLE.EXE ORCL'
                    }
                )
            } -ModuleName 'TACE.Oracle.Admin'
        }

        It 'Data entries have SID property' {
            (Get-OracleDatabaseList -Platform Windows).Data[0].PSObject.Properties.Name | Should -Contain 'SID'
        }

        It 'Data entries have Status property' {
            (Get-OracleDatabaseList -Platform Windows).Data[0].PSObject.Properties.Name | Should -Contain 'Status'
        }

        It 'Data entries have ServiceName property' {
            (Get-OracleDatabaseList -Platform Windows).Data[0].PSObject.Properties.Name | Should -Contain 'ServiceName'
        }

        It 'Data entries have OracleHome property' {
            (Get-OracleDatabaseList -Platform Windows).Data[0].PSObject.Properties.Name | Should -Contain 'OracleHome'
        }

        It 'Data entries have OracleBase property' {
            (Get-OracleDatabaseList -Platform Windows).Data[0].PSObject.Properties.Name | Should -Contain 'OracleBase'
        }
    }

    Context 'Security' -Skip:(-not $IsWindows) {

        BeforeEach {
            Mock Get-CimInstance { @() } -ModuleName 'TACE.Oracle.Admin'
        }

        It 'Message contains no credential fragments' {
            $result = Get-OracleDatabaseList -Platform Windows
            $result.Message | Should -Not -Match 'password|credential|secret|pwd'
        }
    }
}
