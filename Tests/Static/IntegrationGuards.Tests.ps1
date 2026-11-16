#Requires -Version 7.6
<#
.SYNOPSIS
    Static tests for the integration tier's five guards.

.DESCRIPTION
    Runs Assert-IntegrationTestAllowed from Tests\Integration\IntegrationTestHelpers.ps1
    against configurations built here, so each guard is shown to refuse a run without a
    database. TestDrive holds the test folder and a fake Oracle home.

    Touches: TestDrive only, and the opt-in environment variable of this process, which
    is restored after each test.

.NOTES
    Copyright © TACE Data Management Inc.
#>

BeforeAll {
    Import-Module Pester -MinimumVersion 5.0
    . (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'Integration', 'IntegrationTestHelpers.ps1')

    $script:optInName = 'ORACLE_ADMIN_RUN_INTEGRATION'

    # A configuration that passes every guard. Each test changes one setting.
    function New-GuardConfig {
        param([hashtable]$Change = @{})
        $oracleHome = Join-Path -Path $TestDrive -ChildPath 'home'
        $bin  = Join-Path -Path $oracleHome -ChildPath 'bin'
        $null = New-Item -ItemType Directory -Path $bin -Force
        $null = New-Item -ItemType File -Path (Join-Path -Path $bin -ChildPath 'rman.exe') -Force
        $destination = Join-Path -Path $TestDrive -ChildPath 'dest'
        $null = New-Item -ItemType Directory -Path $destination -Force
        $config = [ordered]@{
            AllowedHosts           = [string[]]@($env:COMPUTERNAME)
            OptInVariableName      = $script:optInName
            OptInVariableValue     = '1'
            OracleHome             = $oracleHome
            TestDatabaseName       = 'TESTDB'
            TestBackupDestination  = $destination
            DeniedDatabasePatterns = [string[]]@('PROD', 'PRD')
        }
        foreach ($key in $Change.Keys) { $config[$key] = $Change[$key] }
        [PSCustomObject]$config
    }
}

Describe 'Integration guards' -Tag 'Static' {

    BeforeEach {
        $script:savedOptIn = [System.Environment]::GetEnvironmentVariable($script:optInName)
        [System.Environment]::SetEnvironmentVariable($script:optInName, '1')
    }

    AfterEach {
        [System.Environment]::SetEnvironmentVariable($script:optInName, $script:savedOptIn)
    }

    It 'allow a run when every guard passes' {
        { Assert-IntegrationTestAllowed -Config (New-GuardConfig) } | Should -Not -Throw
    }

    It 'guard 1 refuses an empty host allowlist' {
        { Assert-IntegrationTestAllowed -Config (New-GuardConfig -Change @{ AllowedHosts = [string[]]@() }) } |
            Should -Throw -ExpectedMessage '*Guard 1*'
    }

    It 'guard 1 refuses a host that is not on the allowlist' {
        { Assert-IntegrationTestAllowed -Config (New-GuardConfig -Change @{ AllowedHosts = [string[]]@('SOME-OTHER-HOST') }) } |
            Should -Throw -ExpectedMessage '*Guard 1*'
    }

    It 'guard 2 refuses a run when the opt-in variable is not set' {
        [System.Environment]::SetEnvironmentVariable($script:optInName, $null)
        { Assert-IntegrationTestAllowed -Config (New-GuardConfig) } | Should -Throw -ExpectedMessage '*Guard 2*'
    }

    It 'guard 3 refuses a missing <Name>' -ForEach @(
        @{ Name = 'OracleHome' }
        @{ Name = 'TestDatabaseName' }
        @{ Name = 'TestBackupDestination' }
    ) {
        { Assert-IntegrationTestAllowed -Config (New-GuardConfig -Change @{ $Name = '' }) } |
            Should -Throw -ExpectedMessage "*Guard 3*$Name*"
    }

    It 'guard 3 refuses a database name that is not a SID' {
        { Assert-IntegrationTestAllowed -Config (New-GuardConfig -Change @{ TestDatabaseName = "XE'; DROP" }) } |
            Should -Throw -ExpectedMessage '*Guard 3*'
    }

    It 'guard 3 refuses a test folder whose path holds a quote' {
        $quoted = Join-Path -Path $TestDrive -ChildPath "it's"
        $null = New-Item -ItemType Directory -Path $quoted -Force
        { Assert-IntegrationTestAllowed -Config (New-GuardConfig -Change @{ TestBackupDestination = $quoted }) } |
            Should -Throw -ExpectedMessage '*Guard 3*quote*'
    }

    It 'guard 4 refuses a database name matching a denied pattern, in any case' {
        { Assert-IntegrationTestAllowed -Config (New-GuardConfig -Change @{ TestDatabaseName = 'crmprod' }) } |
            Should -Throw -ExpectedMessage '*Guard 4*'
    }

    It 'guard 5 refuses a test folder that does not exist' {
        $missing = Join-Path -Path $TestDrive -ChildPath 'missing'
        { Assert-IntegrationTestAllowed -Config (New-GuardConfig -Change @{ TestBackupDestination = $missing }) } |
            Should -Throw -ExpectedMessage '*Guard 5*'
    }

    It 'guard 5 refuses an Oracle home with no rman.exe' {
        $empty = Join-Path -Path $TestDrive -ChildPath 'emptyhome'
        $null = New-Item -ItemType Directory -Path $empty -Force
        { Assert-IntegrationTestAllowed -Config (New-GuardConfig -Change @{ OracleHome = $empty }) } |
            Should -Throw -ExpectedMessage '*Guard 5*rman.exe*'
    }

    It 'the committed shared config allows no host and names no database' {
        $shared = Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'Integration', 'IntegrationConfig.ps1'
        $text = Get-Content -LiteralPath $shared -Raw
        $text | Should -Match "AllowedHosts\s+=\s+\[string\[\]\]@\(\)"
        $text | Should -Match "TestDatabaseName\s+=\s+''"
    }
}
