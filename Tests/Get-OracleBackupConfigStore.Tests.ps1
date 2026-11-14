<#
.SECURITY
    Scope  : Get-OracleBackupConfigStore (private)
    Touches: TestDrive only. The module's own Config folder is never read or written:
             file reads are mocked when the fixed path is in play.
    Does NOT touch: Real Oracle instance, network, registry, or the current session
                    environment beyond one variable that is set and then removed.

    Security assertions in this file:
    - ORACLE_BACKUP_CONFIG_PATH does not change the config path (S4)
#>

#Requires -Version 7.0

Describe 'Get-OracleBackupConfigStore' {

    BeforeAll {
        $modulePath = Join-Path $PSScriptRoot '..' 'TACE.Oracle.Admin.psd1'
        $modulePath = [System.IO.Path]::GetFullPath($modulePath)

        $script:defaultConfigPath = [System.IO.Path]::GetFullPath(
            (Join-Path $PSScriptRoot '..' 'Config' 'OracleBackup.json'))

        $script:fullConfigJson = [PSCustomObject]@{
            BackupBasePath       = 'C:\app\oracle\backup'
            FastRecoveryArea     = 'C:\app\oracle\fast_recovery_area'
            LogBasePath          = 'C:\app\oracle\backup\logs'
            LogRetentionHotDays  = 15
            LogRetentionWarmDays = 90
            OracleHome           = ''
            DefaultAuthMode      = 'OSAuth'
            DefaultWalletAlias   = ''
        } | ConvertTo-Json -Depth 5

        Remove-Module TACE.Oracle.Admin -Force -ErrorAction SilentlyContinue
        Import-Module $modulePath -Force
    }

    AfterAll {
        Remove-Module TACE.Oracle.Admin -Force -ErrorAction SilentlyContinue
    }

    # ── Parameter validation ──────────────────────────────────────────────────

    Context 'Parameter validation' {

        It 'Accepts no parameters' {
            $cmd = InModuleScope TACE.Oracle.Admin { Get-Command Get-OracleBackupConfigStore }
            $common = [System.Management.Automation.PSCmdlet]::CommonParameters
            @($cmd.Parameters.Keys | Where-Object { $PSItem -notin $common }) | Should -BeNullOrEmpty
        }
    }

    # ── Implementation ────────────────────────────────────────────────────────

    Context 'Implementation' {

        It 'R1 a setting missing from the file takes its default' {
            $target = Join-Path $TestDrive 'r1' 'OracleBackup.json'
            $null = New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent)
            [PSCustomObject]@{ OracleHome = 'C:\oracle\home1'; LogRetentionHotDays = 7 } |
                ConvertTo-Json | Set-Content -Path $target -Encoding UTF8
            InModuleScope TACE.Oracle.Admin -Parameters @{ Path = $target } {
                $script:ConfigPathOverride = $Path
            }
            try {
                $result = InModuleScope TACE.Oracle.Admin { Get-OracleBackupConfigStore }
                $result.OracleHome           | Should -Be 'C:\oracle\home1'
                $result.LogRetentionHotDays  | Should -Be 7
                $result.LogRetentionWarmDays | Should -Be 90
                $result.DefaultAuthMode      | Should -Be 'OSAuth'
                @($result.PSObject.Properties).Count | Should -Be 8
            }
            finally {
                InModuleScope TACE.Oracle.Admin { $script:ConfigPathOverride = $null }
            }
        }

        It 'R2 writes the defaults to the override path when the file is absent' {
            $target = Join-Path $TestDrive 'r2' 'OracleBackup.json'
            InModuleScope TACE.Oracle.Admin -Parameters @{ Path = $target } {
                $script:ConfigPathOverride = $Path
            }
            try {
                $result = InModuleScope TACE.Oracle.Admin { Get-OracleBackupConfigStore }
                Test-Path -Path $target | Should -Be $true
                $result.LogRetentionHotDays | Should -Be 15
                $result.DefaultAuthMode | Should -Be 'OSAuth'
            }
            finally {
                InModuleScope TACE.Oracle.Admin { $script:ConfigPathOverride = $null }
            }
        }
    }

    # ── Security ──────────────────────────────────────────────────────────────

    Context 'Security' {

        It 'S4 ORACLE_BACKUP_CONFIG_PATH does not change the config path' -Tag 'SEC' {
            $redirect = Join-Path $TestDrive 'redirected.json'
            $env:ORACLE_BACKUP_CONFIG_PATH = $redirect
            try {
                InModuleScope TACE.Oracle.Admin { $script:ConfigPathOverride = $null }
                Mock -CommandName Test-Path -ModuleName TACE.Oracle.Admin -MockWith { $true }
                Mock -CommandName Get-Content -ModuleName TACE.Oracle.Admin -MockWith { $script:fullConfigJson }

                InModuleScope TACE.Oracle.Admin { Get-OracleBackupConfigStore } | Out-Null

                Should -Invoke -CommandName Get-Content -ModuleName TACE.Oracle.Admin -Times 1 -Exactly -ParameterFilter {
                    $Path -eq $script:defaultConfigPath
                }
                Should -Invoke -CommandName Get-Content -ModuleName TACE.Oracle.Admin -Times 0 -Exactly -ParameterFilter {
                    $Path -eq $redirect
                }
                Test-Path -Path $redirect | Should -Be $false
            }
            finally {
                Remove-Item -Path Env:\ORACLE_BACKUP_CONFIG_PATH -ErrorAction SilentlyContinue
            }
        }
    }
}
