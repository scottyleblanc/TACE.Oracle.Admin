#Requires -Version 7.6
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Remove-Module 'TACE.Oracle.Admin' -Force -ErrorAction SilentlyContinue
    Import-Module (& (Join-Path $PSScriptRoot '..' 'Get-BuiltModulePath.ps1')) -Force

    $script:oneInstance = [PSCustomObject]@{
        Success = $true
        Data    = @(
            [PSCustomObject]@{ SID = 'ORCL'; Status = 'Running'; ServiceName = 'OracleServiceORCL'; OracleHome = 'C:\app\oracle\product\19.3\dbhome_1'; OracleBase = 'C:\app\oracle' }
        )
        Message = 'Found 1 Oracle database instance(s).'
    }
    $script:twoInstances = [PSCustomObject]@{
        Success = $true
        Data    = @(
            [PSCustomObject]@{ SID = 'ORCL'; Status = 'Running'; ServiceName = 'OracleServiceORCL'; OracleHome = 'C:\app\oracle\product\19.3\dbhome_1'; OracleBase = 'C:\app\oracle' }
            [PSCustomObject]@{ SID = 'CDB1'; Status = 'Stopped'; ServiceName = 'OracleServiceCDB1'; OracleHome = 'C:\app\oracle\product\19.3\dbhome_2'; OracleBase = 'C:\app\oracle' }
        )
        Message = 'Found 2 Oracle database instance(s).'
    }
}

AfterAll {
    Remove-Module 'TACE.Oracle.Admin' -Force -ErrorAction SilentlyContinue
}

Describe 'Invoke-OraEnv' {

    BeforeEach {
        # Discovery is always mocked: the real one would read this host's services.
        Mock Get-OracleDatabaseList { $script:oneInstance } -ModuleName 'TACE.Oracle.Admin'
        $script:hostLines = [System.Collections.Generic.List[string]]::new()
        Mock Write-Host { $script:hostLines.Add("$Object") } -ModuleName 'TACE.Oracle.Admin'
        $env:ORACLE_SID  = $null
        $env:ORACLE_HOME = $null
        $env:ORACLE_BASE = $null
    }

    AfterEach {
        $env:ORACLE_SID  = $null
        $env:ORACLE_HOME = $null
        $env:ORACLE_BASE = $null
    }

    Context 'Parameter Validation' {

        It 'SID parameter is optional' {
            $params = (Get-Command Invoke-OraEnv).Parameters['SID']
            $mandatory = $params.Attributes |
                Where-Object { $PSItem -is [System.Management.Automation.ParameterAttribute] } |
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

        It 'Calls Set-OracleEnv without SID when one instance is found' {
            Invoke-OraEnv
            Should -Invoke Set-OracleEnv -ModuleName 'TACE.Oracle.Admin' -Times 1 -Exactly -ParameterFilter {
                -not $PSBoundParameters.ContainsKey('SID')
            }
        }

        It 'Calls Set-OracleEnv with the supplied SID' {
            Invoke-OraEnv -SID 'ORCL'
            Should -Invoke Set-OracleEnv -ModuleName 'TACE.Oracle.Admin' -Times 1 -Exactly -ParameterFilter { $SID -eq 'ORCL' }
            Should -Invoke Get-OracleDatabaseList -ModuleName 'TACE.Oracle.Admin' -Times 0 -Exactly
        }
    }

    Context 'Implementation - instance menu' {

        BeforeEach {
            Mock Get-OracleDatabaseList { $script:twoInstances } -ModuleName 'TACE.Oracle.Admin'
            Mock Set-OracleEnv {
                [PSCustomObject]@{ Success = $true; Data = $null; Message = "ORACLE_SID set to '$SID'." }
            } -ModuleName 'TACE.Oracle.Admin'
        }

        It 'R4 several instances: shows a menu and calls Set-OracleEnv with the chosen SID' {
            Mock Read-Host { '2' } -ModuleName 'TACE.Oracle.Admin'
            Invoke-OraEnv
            $script:hostLines | Should -Contain '  [1] ORCL'
            $script:hostLines | Should -Contain '  [2] CDB1'
            Should -Invoke Read-Host -ModuleName 'TACE.Oracle.Admin' -Times 1 -Exactly
            Should -Invoke Set-OracleEnv -ModuleName 'TACE.Oracle.Admin' -Times 1 -Exactly -ParameterFilter { $SID -eq 'CDB1' }
        }

        It 'R5 an invalid choice writes one [ERROR] line and sets nothing (<Choice>)' -ForEach @(
            @{ Choice = '0' }
            @{ Choice = '3' }
            @{ Choice = 'x' }
        ) {
            $script:choice = $Choice
            Mock Read-Host { $script:choice } -ModuleName 'TACE.Oracle.Admin'
            Invoke-OraEnv
            @($script:hostLines | Where-Object { $PSItem -like '`[ERROR`]*' }).Count | Should -Be 1
            Should -Invoke Set-OracleEnv -ModuleName 'TACE.Oracle.Admin' -Times 0 -Exactly
        }

        It 'Does not show a menu when a SID is supplied' {
            Mock Read-Host { throw 'no prompt expected' } -ModuleName 'TACE.Oracle.Admin'
            Invoke-OraEnv -SID 'CDB1'
            Should -Invoke Read-Host -ModuleName 'TACE.Oracle.Admin' -Times 0 -Exactly
        }
    }

    Context 'Implementation - Verbose pass-through' {

        # Set-OracleEnv runs for real, with discovery mocked, to test the whole chain.

        It 'Shows ORACLE_HOME and ORACLE_BASE on host when -Verbose is specified' {
            Invoke-OraEnv -Verbose 4>&1 | Out-Null
            @($script:hostLines | Where-Object { $PSItem -like 'ORACLE_HOME*' }).Count | Should -Be 1
            @($script:hostLines | Where-Object { $PSItem -like 'ORACLE_BASE*' }).Count | Should -Be 1
        }

        It 'Does not show ORACLE_HOME and ORACLE_BASE on host when -Verbose is not specified' {
            Invoke-OraEnv
            @($script:hostLines | Where-Object { $PSItem -like 'ORACLE_HOME*' -or $PSItem -like 'ORACLE_BASE*' }) | Should -BeNullOrEmpty
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

        It 'R6 on success writes the Message from Set-OracleEnv' {
            Invoke-OraEnv
            $script:hostLines | Should -Contain "ORACLE_SID set to 'ORCL'."
        }

        It 'Writes [ERROR] to host when Set-OracleEnv returns Success=$false' {
            Mock Set-OracleEnv {
                [PSCustomObject]@{ Success = $false; Data = $null; Message = 'SID not found.' }
            } -ModuleName 'TACE.Oracle.Admin'
            Invoke-OraEnv
            @($script:hostLines | Where-Object { $PSItem -like '`[ERROR`]*' }) | Should -Be @('[ERROR] SID not found.')
        }

        It 'Does not write [ERROR] to host when Set-OracleEnv returns Success=$true' {
            Mock Set-OracleEnv {
                [PSCustomObject]@{ Success = $true; Data = $null; Message = 'ok' }
            } -ModuleName 'TACE.Oracle.Admin'
            Invoke-OraEnv
            @($script:hostLines | Where-Object { $PSItem -like '`[ERROR`]*' }) | Should -BeNullOrEmpty
        }
    }

    Context 'Security' {

        It 'S2 writes only the menu, the Message and the verbose paths to the host' -Tag 'SEC' {
            # The full path: menu, choice, real Set-OracleEnv, and -Verbose output.
            Mock Get-OracleDatabaseList { $script:twoInstances } -ModuleName 'TACE.Oracle.Admin'
            Mock Read-Host { '1' } -ModuleName 'TACE.Oracle.Admin'
            Invoke-OraEnv -Verbose 4>&1 | Out-Null

            $allowed = @(
                '[Invoke-OraEnv] Oracle instances on this host:'
                '  [1] ORCL'
                '  [2] CDB1'
                "ORACLE_SID set to 'ORCL'."
                "ORACLE_HOME set to 'C:\app\oracle\product\19.3\dbhome_1'"
                "ORACLE_BASE set to 'C:\app\oracle'"
            )
            $script:hostLines.Count | Should -Be $allowed.Count
            @($script:hostLines | Where-Object { $PSItem -notin $allowed }) | Should -BeNullOrEmpty
        }

        It '[ERROR] message contains no credential fragments' {
            Mock Set-OracleEnv {
                [PSCustomObject]@{ Success = $false; Data = $null; Message = 'SID not found.' }
            } -ModuleName 'TACE.Oracle.Admin'
            Invoke-OraEnv
            @($script:hostLines | Where-Object { $PSItem -match 'password|credential|secret|pwd' }) | Should -BeNullOrEmpty
        }
    }
}
