#Requires -Version 7.6
<#
.SYNOPSIS
    Integration tests for Get-RmanBackupStatus against a real Oracle database.

.DESCRIPTION
    Takes a control file backup into the test folder, then runs Get-RmanBackupStatus
    with OS authentication and checks the record it returns against that backup.

    Touches: the integration database named in IntegrationConfig.local.ps1, through
    rman.exe with OS authentication. Writes one backup piece to TestBackupDestination
    and deletes it again, with every other backup tagged INTEGRATION_TEST.
    Does NOT touch: the module's real config file (a TestDrive config is used), any
    credential, or the session environment.

    The five guards in IntegrationTestHelpers.ps1 run first. A failed guard fails the
    file; nothing touches the database.

.NOTES
    Copyright © TACE Data Management Inc.
    **Invocation:** Run by Scripts\Invoke-IntegrationTest.ps1.
#>

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'IntegrationTestHelpers.ps1')
    $script:guardPassed = $false
    $script:config = & (Join-Path -Path $PSScriptRoot -ChildPath 'IntegrationConfig.ps1')
    Assert-IntegrationTestAllowed -Config $script:config
    $script:guardPassed = $true

    Remove-Module TACE.Oracle.Admin -Force -ErrorAction SilentlyContinue
    Import-Module (& (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'Unit', 'Get-BuiltModulePath.ps1')) -Force
    Set-IntegrationConfigOverride -Config $script:config -Path (Join-Path -Path $TestDrive -ChildPath 'config.json')

    Remove-IntegrationBackup -Config $script:config
    $script:startedAt = Get-Date
    $script:pieces    = New-IntegrationBackup -Config $script:config -Prefix 'S'

    $sentinel = & (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'Unit', 'Set-EnvironmentSentinel.ps1')
    try {
        $script:result = Get-RmanBackupStatus -DatabaseName $script:config.TestDatabaseName
    }
    finally {
        $script:changed = & (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'Unit', 'Compare-EnvironmentSentinel.ps1') -Snapshot $sentinel
    }
}

AfterAll {
    # Only clean up when the guards passed: otherwise nothing here may touch a database.
    if ($script:guardPassed) {
        Remove-IntegrationBackup -Config $script:config
        Clear-IntegrationConfigOverride
    }
    Remove-Module TACE.Oracle.Admin -Force -ErrorAction SilentlyContinue
}

Describe 'Get-RmanBackupStatus integration' -Tag 'Integration' {

    Context 'Implementation' {

        It 'returns Success with the newest backup, taken by this run' {
            $script:result.Success             | Should -BeTrue -Because $script:result.Message
            $script:result.Data.DatabaseName   | Should -Be $script:config.TestDatabaseName
            $script:result.Data.Key            | Should -BeGreaterThan 0
            $script:result.Data.Status         | Should -Be 'Available'
            $script:result.Data.CompletionTime | Should -BeGreaterOrEqual $script:startedAt.AddMinutes(-1)
        }

        It 'Data.RawLog is the LIST BACKUP SUMMARY output, and lists the test backup' {
            $script:result.Data.RawLog | Should -Match 'List of Backups'
            $script:result.Data.RawLog | Should -Match 'INTEGRATION_TEST'
        }

        It 'Message names the database' {
            $script:result.Message | Should -Match ([regex]::Escape($script:config.TestDatabaseName))
        }
    }

    Context 'Security' {

        It 'leaves the session environment unchanged, PATH included' -Tag 'SEC' {
            ($script:changed -join ', ') | Should -BeNullOrEmpty
        }

        It 'Message and RawLog hold no credential pattern' -Tag 'SEC' {
            $script:result.Message     | Should -Not -Match '\w+/\w+@\w+'
            $script:result.Message     | Should -Not -Match '(?i)password'
            $script:result.Data.RawLog | Should -Not -Match '(?i)password\s*='
        }
    }
}
