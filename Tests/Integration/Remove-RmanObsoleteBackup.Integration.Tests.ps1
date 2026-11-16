#Requires -Version 7.6
<#
.SYNOPSIS
    Integration tests for Remove-RmanObsoleteBackup against a real Oracle database.

.DESCRIPTION
    Takes two control file backups into the test folder. Under RMAN's retention policy
    the first becomes obsolete once the second exists. Then:
      - with -WhatIf, nothing is deleted;
      - without it, DELETE OBSOLETE removes the first backup's pieces.

    Touches: the integration database named in IntegrationConfig.local.ps1, through
    rman.exe with OS authentication. DELETE OBSOLETE acts on the whole database, not just
    the test folder: any backup RMAN considers obsolete is deleted. Only run on a database
    that may lose backups. Writes backup pieces to TestBackupDestination and deletes
    every backup tagged INTEGRATION_TEST at the end.
    Does NOT touch: the module's real config file (a TestDrive config is used), any
    credential, or the session environment.

    The five guards in IntegrationTestHelpers.ps1 run first. A failed guard fails the
    file; nothing touches the database.

.NOTES
    Copyright © TACE Data Management Inc.
    **Invocation:** Run by Scripts\Invoke-IntegrationTest.ps1.
    Assumes a redundancy-based retention policy (RMAN's default, REDUNDANCY 1), under
    which a second control file backup makes the first obsolete.
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
    $script:first  = New-IntegrationBackup -Config $script:config -Prefix 'A'
    $script:second = New-IntegrationBackup -Config $script:config -Prefix 'B'
}

AfterAll {
    # Only clean up when the guards passed: otherwise nothing here may touch a database.
    if ($script:guardPassed) {
        Remove-IntegrationBackup -Config $script:config
        Clear-IntegrationConfigOverride
    }
    Remove-Module TACE.Oracle.Admin -Force -ErrorAction SilentlyContinue
}

Describe 'Remove-RmanObsoleteBackup integration' -Tag 'Integration' {

    Context 'WhatIf' {

        BeforeAll {
            $script:preview = Remove-RmanObsoleteBackup -DatabaseName $script:config.TestDatabaseName -WhatIf
        }

        It 'returns a successful preview with Applied false' {
            $script:preview.Success      | Should -BeTrue -Because $script:preview.Message
            $script:preview.Data.Applied | Should -BeFalse
            $script:preview.Message      | Should -BeLike 'WhatIf:*'
        }

        It 'deletes nothing: the obsolete backup is still on disk' {
            foreach ($piece in $script:first) {
                Test-Path -LiteralPath $piece.FullName | Should -BeTrue -Because "$($piece.Name) must survive -WhatIf"
            }
        }
    }

    Context 'Implementation' {

        BeforeAll {
            $sentinel = & (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'Unit', 'Set-EnvironmentSentinel.ps1')
            try {
                $script:result = Remove-RmanObsoleteBackup -DatabaseName $script:config.TestDatabaseName -Confirm:$false
            }
            finally {
                $script:changed = & (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'Unit', 'Compare-EnvironmentSentinel.ps1') -Snapshot $sentinel
            }
        }

        It 'returns Success with Applied true and a count of deleted pieces' {
            $script:result.Success           | Should -BeTrue -Because $script:result.Message
            $script:result.Data.Applied      | Should -BeTrue
            $script:result.Data.DeletedCount | Should -BeGreaterOrEqual 1
        }

        It 'deletes the obsolete first backup from disk' {
            foreach ($piece in $script:first) {
                Test-Path -LiteralPath $piece.FullName | Should -BeFalse -Because "$($piece.Name) was obsolete"
            }
        }

        It 'leaves the database with a current backup' {
            $status = Get-RmanBackupStatus -DatabaseName $script:config.TestDatabaseName
            $status.Success     | Should -BeTrue -Because $status.Message
            $status.Data.Status | Should -Be 'Available'
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
