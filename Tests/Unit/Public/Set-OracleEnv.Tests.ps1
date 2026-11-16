#Requires -Version 7.6
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Remove-Module 'TACE.Oracle.Admin' -Force -ErrorAction SilentlyContinue
    Import-Module (& (Join-Path $PSScriptRoot '..' 'Get-BuiltModulePath.ps1')) -Force

    # Shared test data — accessible in BeforeEach/It blocks via $script: scope
    $script:twoInstances = @(
        [PSCustomObject]@{ SID = 'ORCL'; Status = 'Running'; ServiceName = 'OracleServiceORCL'; OracleHome = 'C:\app\oracle\product\19.3\dbhome_1'; OracleBase = 'C:\app\oracle' }
        [PSCustomObject]@{ SID = 'CDB1'; Status = 'Stopped'; ServiceName = 'OracleServiceCDB1'; OracleHome = 'C:\app\oracle\product\19.3\dbhome_2'; OracleBase = 'C:\app\oracle' }
    )

    $script:oneInstance = @(
        [PSCustomObject]@{ SID = 'ORCL'; Status = 'Running'; ServiceName = 'OracleServiceORCL'; OracleHome = 'C:\app\oracle\product\19.3\dbhome_1'; OracleBase = 'C:\app\oracle' }
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

        It 'P1 SID rejects an empty string' {
            $param = (Get-Command Set-OracleEnv).Parameters['SID']
            @($param.Attributes | Where-Object { $PSItem -is [System.Management.Automation.ValidateNotNullOrEmptyAttribute] }) |
                Should -Not -BeNullOrEmpty
        }

        It 'Supports -WhatIf' {
            (Get-Command Set-OracleEnv).Parameters.ContainsKey('WhatIf') | Should -BeTrue
        }
    }

    Context 'Implementation - SID supplied, service Running' {

        BeforeEach {
            Mock Get-OracleDatabaseList {
                [PSCustomObject]@{
                    Success = $true
                    Data    = @(
                        [PSCustomObject]@{ SID = 'ORCL'; Status = 'Running'; ServiceName = 'OracleServiceORCL'; OracleHome = 'C:\app\oracle\product\19.3\dbhome_1'; OracleBase = 'C:\app\oracle' }
                        [PSCustomObject]@{ SID = 'CDB1'; Status = 'Stopped'; ServiceName = 'OracleServiceCDB1'; OracleHome = 'C:\app\oracle\product\19.3\dbhome_2'; OracleBase = 'C:\app\oracle' }
                    )
                    Message = 'Found 2 Oracle database instance(s).'
                }
            } -ModuleName 'TACE.Oracle.Admin'
            $env:ORACLE_SID  = $null
            $env:ORACLE_HOME = $null
            $env:ORACLE_BASE = $null
        }

        AfterEach {
            $env:ORACLE_SID  = $null
            $env:ORACLE_HOME = $null
            $env:ORACLE_BASE = $null
        }

        It 'Returns Success = $true' {
            $result = Set-OracleEnv -SID 'ORCL'
            $result.Success | Should -BeTrue
        }

        It 'Sets $env:ORACLE_SID to the supplied SID' {
            Set-OracleEnv -SID 'ORCL' | Out-Null
            $env:ORACLE_SID | Should -Be 'ORCL'
        }

        It 'Sets $env:ORACLE_HOME from the service executable path' {
            Set-OracleEnv -SID 'ORCL' | Out-Null
            $env:ORACLE_HOME | Should -Be 'C:\app\oracle\product\19.3\dbhome_1'
        }

        It 'Sets $env:ORACLE_BASE from the service executable path' {
            Set-OracleEnv -SID 'ORCL' | Out-Null
            $env:ORACLE_BASE | Should -Be 'C:\app\oracle'
        }

        It 'Returns Data.SID matching the supplied SID' {
            $result = Set-OracleEnv -SID 'ORCL'
            $result.Data.SID | Should -Be 'ORCL'
        }

        It 'Returns Data.OracleHome matching the service executable path' {
            $result = Set-OracleEnv -SID 'ORCL'
            $result.Data.OracleHome | Should -Be 'C:\app\oracle\product\19.3\dbhome_1'
        }

        It 'Returns Data.OracleBase matching the service executable path' {
            $result = Set-OracleEnv -SID 'ORCL'
            $result.Data.OracleBase | Should -Be 'C:\app\oracle'
        }
    }

    Context 'Implementation - SID supplied, service Stopped' {

        BeforeEach {
            Mock Get-OracleDatabaseList {
                [PSCustomObject]@{
                    Success = $true
                    Data    = @(
                        [PSCustomObject]@{ SID = 'ORCL'; Status = 'Running'; ServiceName = 'OracleServiceORCL'; OracleHome = 'C:\app\oracle\product\19.3\dbhome_1'; OracleBase = 'C:\app\oracle' }
                        [PSCustomObject]@{ SID = 'CDB1'; Status = 'Stopped'; ServiceName = 'OracleServiceCDB1'; OracleHome = 'C:\app\oracle\product\19.3\dbhome_2'; OracleBase = 'C:\app\oracle' }
                    )
                    Message = 'Found 2 Oracle database instance(s).'
                }
            } -ModuleName 'TACE.Oracle.Admin'
            $env:ORACLE_SID  = $null
            $env:ORACLE_HOME = $null
            $env:ORACLE_BASE = $null
        }

        AfterEach {
            $env:ORACLE_SID  = $null
            $env:ORACLE_HOME = $null
            $env:ORACLE_BASE = $null
        }

        It 'Returns Success = $true despite stopped service' {
            $result = Set-OracleEnv -SID 'CDB1' -WarningAction SilentlyContinue
            $result.Success | Should -BeTrue
        }

        It 'R4 sets $env:ORACLE_SID despite stopped service' {
            Set-OracleEnv -SID 'CDB1' -WarningAction SilentlyContinue | Out-Null
            $env:ORACLE_SID | Should -Be 'CDB1'
        }

        It 'Sets $env:ORACLE_HOME despite stopped service' {
            Set-OracleEnv -SID 'CDB1' -WarningAction SilentlyContinue | Out-Null
            $env:ORACLE_HOME | Should -Be 'C:\app\oracle\product\19.3\dbhome_2'
        }

        It 'Sets $env:ORACLE_BASE despite stopped service' {
            Set-OracleEnv -SID 'CDB1' -WarningAction SilentlyContinue | Out-Null
            $env:ORACLE_BASE | Should -Be 'C:\app\oracle'
        }

        It 'R4 emits a warning for a stopped service' {
            Set-OracleEnv -SID 'CDB1' -WarningVariable w 3>&1 | Out-Null
            $w | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Implementation - SID supplied, OracleHome and OracleBase are null' {

        BeforeEach {
            Mock Get-OracleDatabaseList {
                [PSCustomObject]@{
                    Success = $true
                    Data    = @(
                        [PSCustomObject]@{ SID = 'ORCL'; Status = 'Running'; ServiceName = 'OracleServiceORCL'; OracleHome = $null; OracleBase = $null }
                    )
                    Message = 'Found 1 Oracle database instance(s).'
                }
            } -ModuleName 'TACE.Oracle.Admin'
            $env:ORACLE_SID  = $null
            $env:ORACLE_HOME = $null
            $env:ORACLE_BASE = $null
        }

        AfterEach {
            $env:ORACLE_SID  = $null
            $env:ORACLE_HOME = $null
            $env:ORACLE_BASE = $null
        }

        It 'Returns Success = $true despite null OracleHome and OracleBase' {
            $result = Set-OracleEnv -SID 'ORCL' -WarningAction SilentlyContinue
            $result.Success | Should -BeTrue
        }

        It 'Sets $env:ORACLE_SID despite null OracleHome and OracleBase' {
            Set-OracleEnv -SID 'ORCL' -WarningAction SilentlyContinue | Out-Null
            $env:ORACLE_SID | Should -Be 'ORCL'
        }

        It 'R3 does not set $env:ORACLE_HOME when OracleHome is null' {
            Set-OracleEnv -SID 'ORCL' -WarningAction SilentlyContinue | Out-Null
            $env:ORACLE_HOME | Should -BeNullOrEmpty
        }

        It 'R3 does not set $env:ORACLE_BASE when OracleBase is null' {
            Set-OracleEnv -SID 'ORCL' -WarningAction SilentlyContinue | Out-Null
            $env:ORACLE_BASE | Should -BeNullOrEmpty
        }

        It 'R3 emits warnings when OracleHome and OracleBase are null' {
            Set-OracleEnv -SID 'ORCL' -WarningVariable w 3>&1 | Out-Null
            @($w).Count | Should -Be 2
        }

        It 'Returns Data.OracleHome as $null' {
            $result = Set-OracleEnv -SID 'ORCL' -WarningAction SilentlyContinue
            $result.Data.OracleHome | Should -BeNullOrEmpty
        }

        It 'Returns Data.OracleBase as $null' {
            $result = Set-OracleEnv -SID 'ORCL' -WarningAction SilentlyContinue
            $result.Data.OracleBase | Should -BeNullOrEmpty
        }
    }

    Context 'Implementation - SID supplied, not found' {

        BeforeEach {
            Mock Get-OracleDatabaseList {
                [PSCustomObject]@{
                    Success = $true
                    Data    = @(
                        [PSCustomObject]@{ SID = 'ORCL'; Status = 'Running'; ServiceName = 'OracleServiceORCL'; OracleHome = 'C:\app\oracle\product\19.3\dbhome_1'; OracleBase = 'C:\app\oracle' }
                        [PSCustomObject]@{ SID = 'CDB1'; Status = 'Stopped'; ServiceName = 'OracleServiceCDB1'; OracleHome = 'C:\app\oracle\product\19.3\dbhome_2'; OracleBase = 'C:\app\oracle' }
                    )
                    Message = 'Found 2 Oracle database instance(s).'
                }
            } -ModuleName 'TACE.Oracle.Admin'
        }

        It 'Returns Success = $false' {
            $result = Set-OracleEnv -SID 'BOGUS'
            $result.Success | Should -BeFalse
        }

        It 'R5 does not set $env:ORACLE_SID' {
            $env:ORACLE_SID = $null
            Set-OracleEnv -SID 'BOGUS' | Out-Null
            $env:ORACLE_SID | Should -BeNullOrEmpty
        }

        It 'P2 Message lists valid SIDs' {
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
                        [PSCustomObject]@{ SID = 'ORCL'; Status = 'Running'; ServiceName = 'OracleServiceORCL'; OracleHome = 'C:\app\oracle\product\19.3\dbhome_1'; OracleBase = 'C:\app\oracle' }
                    )
                    Message = 'Found 1 Oracle database instance(s).'
                }
            } -ModuleName 'TACE.Oracle.Admin'
            $env:ORACLE_SID  = $null
            $env:ORACLE_HOME = $null
            $env:ORACLE_BASE = $null
        }

        AfterEach {
            $env:ORACLE_SID  = $null
            $env:ORACLE_HOME = $null
            $env:ORACLE_BASE = $null
        }

        It 'Returns Success = $true' {
            $result = Set-OracleEnv
            $result.Success | Should -BeTrue
        }

        It 'Sets $env:ORACLE_SID automatically' {
            Set-OracleEnv | Out-Null
            $env:ORACLE_SID | Should -Be 'ORCL'
        }

        It 'Sets $env:ORACLE_HOME automatically' {
            Set-OracleEnv | Out-Null
            $env:ORACLE_HOME | Should -Be 'C:\app\oracle\product\19.3\dbhome_1'
        }

        It 'Sets $env:ORACLE_BASE automatically' {
            Set-OracleEnv | Out-Null
            $env:ORACLE_BASE | Should -Be 'C:\app\oracle'
        }
    }

    Context 'Implementation - no SID supplied, multiple instances' {

        BeforeEach {
            Mock Get-OracleDatabaseList {
                [PSCustomObject]@{
                    Success = $true
                    Data    = @(
                        [PSCustomObject]@{ SID = 'ORCL'; Status = 'Running'; ServiceName = 'OracleServiceORCL'; OracleHome = 'C:\app\oracle\product\19.3\dbhome_1'; OracleBase = 'C:\app\oracle' }
                        [PSCustomObject]@{ SID = 'CDB1'; Status = 'Stopped'; ServiceName = 'OracleServiceCDB1'; OracleHome = 'C:\app\oracle\product\19.3\dbhome_2'; OracleBase = 'C:\app\oracle' }
                    )
                    Message = 'Found 2 Oracle database instance(s).'
                }
            } -ModuleName 'TACE.Oracle.Admin'
            Mock Read-Host { throw 'Set-OracleEnv must not prompt' } -ModuleName 'TACE.Oracle.Admin'
            Mock Write-Host { } -ModuleName 'TACE.Oracle.Admin'
            $env:ORACLE_SID = $null
        }

        AfterEach {
            $env:ORACLE_SID = $null
        }

        It 'R7 several instances and no SID set nothing and list every SID' {
            $result = Set-OracleEnv
            $result.Success | Should -BeFalse
            $result.Message | Should -Match 'ORCL'
            $result.Message | Should -Match 'CDB1'
            $result.Message | Should -Match '-SID'
            $env:ORACLE_SID | Should -BeNullOrEmpty
            Should -Invoke Read-Host -ModuleName 'TACE.Oracle.Admin' -Times 0 -Exactly
            Should -Invoke Write-Host -ModuleName 'TACE.Oracle.Admin' -Times 0 -Exactly
        }
    }

    Context 'Implementation - no instances found' {

        BeforeEach {
            Mock Get-OracleDatabaseList {
                [PSCustomObject]@{ Success = $true; Data = @(); Message = 'No Oracle database services found.' }
            } -ModuleName 'TACE.Oracle.Admin'
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
            } -ModuleName 'TACE.Oracle.Admin'
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
                        [PSCustomObject]@{ SID = 'ORCL'; Status = 'Running'; ServiceName = 'OracleServiceORCL'; OracleHome = 'C:\app\oracle\product\19.3\dbhome_1'; OracleBase = 'C:\app\oracle' }
                    )
                    Message = 'Found 1 Oracle database instance(s).'
                }
            } -ModuleName 'TACE.Oracle.Admin'
            $env:ORACLE_SID  = $null
            $env:ORACLE_HOME = $null
            $env:ORACLE_BASE = $null
        }

        AfterEach {
            $env:ORACLE_SID  = $null
            $env:ORACLE_HOME = $null
            $env:ORACLE_BASE = $null
        }

        # R1 is "on every path", so each path is tested. The context mock gives one instance.
        It 'R1 returns exactly Success, Data and Message, without throwing, when <Path>' -ForEach @(
            @{ Path = 'one instance is found and no SID is given' }
            @{ Path = 'the given SID is found' }
            @{ Path = 'the given SID is not found' }
            @{ Path = 'several instances are found and no SID is given' }
            @{ Path = 'no instance is found' }
            @{ Path = 'discovery fails' }
            @{ Path = 'the call runs under -WhatIf' }
        ) {
            $script:twoInstances = [PSCustomObject]@{
                Success = $true
                Data    = @(
                    [PSCustomObject]@{ SID = 'ORCL'; Status = 'Running'; ServiceName = 'OracleServiceORCL'; OracleHome = 'C:\app\oracle\product\19.3\dbhome_1'; OracleBase = 'C:\app\oracle' }
                    [PSCustomObject]@{ SID = 'CDB1'; Status = 'Stopped'; ServiceName = 'OracleServiceCDB1'; OracleHome = 'C:\app\oracle\product\19.3\dbhome_2'; OracleBase = 'C:\app\oracle' }
                )
                Message = 'Found 2 Oracle database instance(s).'
            }
            $call = @{}
            switch ($Path) {
                'the given SID is found'     { $call['SID'] = 'ORCL' }
                'the given SID is not found' { $call['SID'] = 'BOGUS' }
                'several instances are found and no SID is given' {
                    Mock Get-OracleDatabaseList { $script:twoInstances } -ModuleName 'TACE.Oracle.Admin'
                }
                'no instance is found' {
                    Mock Get-OracleDatabaseList {
                        [PSCustomObject]@{ Success = $true; Data = @(); Message = 'No Oracle database services found.' }
                    } -ModuleName 'TACE.Oracle.Admin'
                }
                'discovery fails' {
                    Mock Get-OracleDatabaseList {
                        [PSCustomObject]@{ Success = $false; Data = $null; Message = 'Service query failed.' }
                    } -ModuleName 'TACE.Oracle.Admin'
                }
                'the call runs under -WhatIf' { $call['WhatIf'] = $true }
            }
            $result = Set-OracleEnv @call
            @($result.PSObject.Properties.Name) | Should -Be @('Success', 'Data', 'Message')
            $result.Message | Should -BeOfType [string]
        }

        It 'R2 Data.SID is a non-empty string on success' {
            $result = Set-OracleEnv
            $result.Data.SID | Should -BeOfType [string]
            $result.Data.SID | Should -Not -BeNullOrEmpty
        }

        It 'R2 Data.Applied is true when the variables are set' {
            $result = Set-OracleEnv
            $result.Data.Applied | Should -BeTrue
            $result.Message      | Should -Not -BeLike 'WhatIf:*'
        }

        It 'Data.OracleHome is a non-empty string when path is available' {
            $result = Set-OracleEnv
            $result.Data.OracleHome | Should -BeOfType [string]
            $result.Data.OracleHome | Should -Not -BeNullOrEmpty
        }

        It 'Data.OracleBase is a non-empty string when path is available' {
            $result = Set-OracleEnv
            $result.Data.OracleBase | Should -BeOfType [string]
            $result.Data.OracleBase | Should -Not -BeNullOrEmpty
        }
    }

    Context 'WhatIf support' {

        BeforeAll {
            $script:savedEnv = @{
                ORACLE_SID  = $env:ORACLE_SID
                ORACLE_HOME = $env:ORACLE_HOME
                ORACLE_BASE = $env:ORACLE_BASE
            }
        }

        AfterAll {
            $env:ORACLE_SID  = $script:savedEnv.ORACLE_SID
            $env:ORACLE_HOME = $script:savedEnv.ORACLE_HOME
            $env:ORACLE_BASE = $script:savedEnv.ORACLE_BASE
        }

        BeforeEach {
            Mock Get-OracleDatabaseList {
                [PSCustomObject]@{
                    Success = $true
                    Data    = $script:oneInstance
                    Message = 'Found 1 Oracle database instance(s).'
                }
            } -ModuleName 'TACE.Oracle.Admin'
            $env:ORACLE_SID  = 'BEFORE_SID'
            $env:ORACLE_HOME = 'C:\before\home'
            $env:ORACLE_BASE = 'C:\before'
        }

        It 'R6 WhatIf sets no variable and returns a preview' {
            $result = Set-OracleEnv -SID 'ORCL' -WhatIf
            $env:ORACLE_SID  | Should -Be 'BEFORE_SID'
            $env:ORACLE_HOME | Should -Be 'C:\before\home'
            $env:ORACLE_BASE | Should -Be 'C:\before'
            $result.Success      | Should -BeTrue
            $result.Data.SID     | Should -Be 'ORCL'
            $result.Data.Applied | Should -BeFalse
            $result.Message      | Should -BeLike 'WhatIf:*'
            $result.Message      | Should -Not -BeLike '*set to*'
        }
    }

    Context 'Security' {

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
            $env:ORACLE_SID  = $null
            $env:ORACLE_HOME = $null
            $env:ORACLE_BASE = $null
        }

        AfterEach {
            $env:ORACLE_SID  = $null
            $env:ORACLE_HOME = $null
            $env:ORACLE_BASE = $null
        }

        It 'S1 every call discovers the instances afresh; nothing is remembered' -Tag 'SEC' {
            Set-OracleEnv -SID 'ORCL' | Select-Object -ExpandProperty Success | Should -BeTrue

            # The host now has only CDB1. A stored list would still accept ORCL.
            Mock Get-OracleDatabaseList {
                [PSCustomObject]@{
                    Success = $true
                    Data    = @([PSCustomObject]@{ SID = 'CDB1'; Status = 'Running'; ServiceName = 'OracleServiceCDB1'; OracleHome = 'C:\app\oracle\product\19.3\dbhome_2'; OracleBase = 'C:\app\oracle' })
                    Message = 'Found 1 Oracle database instance(s).'
                }
            } -ModuleName 'TACE.Oracle.Admin'
            $second = Set-OracleEnv -SID 'ORCL'
            $second.Success | Should -BeFalse
            $second.Message | Should -Match 'CDB1'
        }

        It 'Message contains no credential fragments' {
            $result = Set-OracleEnv
            $result.Message | Should -Not -Match 'password|credential|secret|pwd'
        }

        It 'ArgumentList is not used (env var set directly, not via child process)' {
            # Set-OracleEnv writes to $env:ORACLE_SID directly — no child process involved.
            Mock Start-Process { throw 'Start-Process must not be called' } -ModuleName 'TACE.Oracle.Admin'
            { Set-OracleEnv } | Should -Not -Throw
        }
    }
}
