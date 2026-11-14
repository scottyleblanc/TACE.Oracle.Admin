<#
.SECURITY
    Scope  : Remove-RmanObsoleteBackup (public)
    Touches: No filesystem paths. No real Oracle instance.
             All RMAN process calls mocked via Invoke-RmanProcess mock.
    Does NOT touch: Real RMAN binary, Oracle instance, network, registry,
                    or current session environment variables.

    Security assertions in this file:
    - ShouldProcess is the sole confirmation gate — RMAN never invoked on WhatIf
    - ORACLE_SID not set on current session after function call
    - No credential fragments in RMAN script passed to Invoke-RmanProcess
    - NOPROMPT present in RMAN script — no interactive prompt bypass possible
    - Message property contains no credential fragments
#>

#Requires -Version 7.0

Describe 'Remove-RmanObsoleteBackup' {

    BeforeAll {
        $modulePath = Join-Path $PSScriptRoot '..' 'TACE.Oracle.Admin.psd1'
        $modulePath = [System.IO.Path]::GetFullPath($modulePath)

        $testConfigPath = Join-Path $TestDrive 'OracleBackup.json'
        $env:ORACLE_BACKUP_CONFIG_PATH = $testConfigPath

        [PSCustomObject]@{
            BackupBasePath       = (Join-Path $TestDrive 'backup')
            FastRecoveryArea     = (Join-Path $TestDrive 'fra')
            LogBasePath          = (Join-Path $TestDrive 'logs')
            LogRetentionHotDays  = 15
            LogRetentionWarmDays = 90
            OracleHome           = (Join-Path $TestDrive 'oracle')
        } | ConvertTo-Json -Depth 5 |
            Set-Content -Path $testConfigPath -Encoding UTF8

        $script:fakeRmanPath   = Join-Path $TestDrive 'oracle' 'bin' 'rman.exe'
        New-Item -Path (Split-Path $script:fakeRmanPath) -ItemType Directory -Force | Out-Null
        New-Item -Path $script:fakeRmanPath -ItemType File -Force | Out-Null

        Remove-Module TACE.Oracle.Admin -Force -ErrorAction SilentlyContinue
        Import-Module $modulePath -Force

        Mock -CommandName Assert-OracleEnvironment -ModuleName TACE.Oracle.Admin -MockWith {
            return $script:fakeRmanPath
        }
        Mock -CommandName Invoke-RmanProcess -ModuleName TACE.Oracle.Admin -MockWith {
            return [PSCustomObject]@{
                ExitCode = 0
                StdOut   = "deleted backup piece`ndeleted backup piece"
                StdErr   = ''
                Success  = $true
            }
        }
    }

    AfterAll {
        Remove-Module TACE.Oracle.Admin -Force -ErrorAction SilentlyContinue
        $env:ORACLE_BACKUP_CONFIG_PATH = $null
    }

    # ── Parameter validation ──────────────────────────────────────────────────

    Context 'Parameter validation' {

        It 'DatabaseName is mandatory' {
            $param = (Get-Command Remove-RmanObsoleteBackup).Parameters['DatabaseName']
            $isMandatory = $param.Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory }
            $isMandatory | Should -Not -BeNullOrEmpty
        }

        It 'Supports WhatIf' {
            $cmd = Get-Command Remove-RmanObsoleteBackup
            $cmd.Parameters.ContainsKey('WhatIf') | Should -Be $true
        }

        It 'Supports Confirm' {
            $cmd = Get-Command Remove-RmanObsoleteBackup
            $cmd.Parameters.ContainsKey('Confirm') | Should -Be $true
        }
    }

    # ── Implementation ────────────────────────────────────────────────────────

    Context 'Implementation' {

        It 'Should return Success=$true when RMAN succeeds' {
            $result = Remove-RmanObsoleteBackup -DatabaseName 'ORCL' -Confirm:$false
            $result.Success | Should -Be $true
        }

        It 'Should return Success=$false when RMAN fails' {
            Mock -CommandName Invoke-RmanProcess -ModuleName TACE.Oracle.Admin -MockWith {
                return [PSCustomObject]@{ ExitCode = 1; StdOut = 'RMAN-03002: failure'; StdErr = ''; Success = $false }
            }
            $result = Remove-RmanObsoleteBackup -DatabaseName 'ORCL' -Confirm:$false
            $result.Success | Should -Be $false
        }

        It 'Should count deleted pieces from RMAN output' {
            Mock -CommandName Invoke-RmanProcess -ModuleName TACE.Oracle.Admin -MockWith {
                return [PSCustomObject]@{
                    ExitCode = 0
                    StdOut   = "deleted backup piece`ndeleted backup piece`ndeleted backup piece"
                    StdErr   = ''
                    Success  = $true
                }
            }
            $result = Remove-RmanObsoleteBackup -DatabaseName 'ORCL' -Confirm:$false
            $result.Data.DeletedCount | Should -Be 3
        }

        It 'Should not invoke RMAN on WhatIf' {
            $script:rmanCalled = $false
            Mock -CommandName Invoke-RmanProcess -ModuleName TACE.Oracle.Admin -MockWith {
                $script:rmanCalled = $true
                return [PSCustomObject]@{ ExitCode = 0; StdOut = ''; StdErr = ''; Success = $true }
            }
            Remove-RmanObsoleteBackup -DatabaseName 'ORCL' -WhatIf
            $script:rmanCalled | Should -Be $false
        }
    }

    # ── Security ──────────────────────────────────────────────────────────────

    Context 'Security' {

        It 'RMAN script must contain NOPROMPT' {
            $script:capturedScript = $null
            Mock -CommandName Invoke-RmanProcess -ModuleName TACE.Oracle.Admin -MockWith {
                $script:capturedScript = $RmanScript
                return [PSCustomObject]@{ ExitCode = 0; StdOut = ''; StdErr = ''; Success = $true }
            }
            Remove-RmanObsoleteBackup -DatabaseName 'ORCL' -Confirm:$false | Out-Null
            $script:capturedScript | Should -Match 'NOPROMPT'
        }

        It 'RMAN must not be invoked on WhatIf — ShouldProcess is the sole gate' {
            $script:rmanCalled = $false
            Mock -CommandName Invoke-RmanProcess -ModuleName TACE.Oracle.Admin -MockWith {
                $script:rmanCalled = $true
                return [PSCustomObject]@{ ExitCode = 0; StdOut = ''; StdErr = ''; Success = $true }
            }
            Remove-RmanObsoleteBackup -DatabaseName 'ORCL' -WhatIf
            $script:rmanCalled | Should -Be $false
        }

        It 'ORACLE_SID should not be set on current session' {
            $before = $env:ORACLE_SID
            Remove-RmanObsoleteBackup -DatabaseName 'ORCL' -Confirm:$false | Out-Null
            $env:ORACLE_SID | Should -Be $before
        }

        It 'RMAN script should not contain credential fragments' {
            $script:capturedScript = $null
            Mock -CommandName Invoke-RmanProcess -ModuleName TACE.Oracle.Admin -MockWith {
                $script:capturedScript = $RmanScript
                return [PSCustomObject]@{ ExitCode = 0; StdOut = ''; StdErr = ''; Success = $true }
            }
            Remove-RmanObsoleteBackup -DatabaseName 'ORCL' -Confirm:$false | Out-Null
            $script:capturedScript | Should -Not -Match '\w+/\w+@\w+'
            $script:capturedScript | Should -Not -Match 'password'
        }

        It 'Message should not contain credential fragments' {
            Mock -CommandName Invoke-RmanProcess -ModuleName TACE.Oracle.Admin -MockWith {
                return [PSCustomObject]@{ ExitCode = 0; StdOut = 'deleted backup piece'; StdErr = ''; Success = $true }
            }
            $result = Remove-RmanObsoleteBackup -DatabaseName 'ORCL' -Confirm:$false
            $result.Message | Should -Not -Match '\w+/\w+@\w+'
            $result.Message | Should -Not -Match 'password'
        }

        It 'Should return Success=$false and safe Message when binary integrity check fails' {
            Mock -CommandName Assert-OracleEnvironment -ModuleName TACE.Oracle.Admin -MockWith {
                throw 'RMAN binary integrity check failed: Authenticode signature status is NotSigned'
            }
            $result = Remove-RmanObsoleteBackup -DatabaseName 'ORCL' -Confirm:$false
            $result.Success | Should -Be $false
            $result.Message | Should -Not -Match '\w+/\w+@\w+'
            $result.Message | Should -Not -Match 'password'
        }
    }

    # ── WalletAuth ────────────────────────────────────────────────────────────

    Context 'WalletAuth' {

        BeforeAll {
            Mock -CommandName Invoke-RmanProcess -ModuleName TACE.Oracle.Admin -MockWith {
                return [PSCustomObject]@{
                    ExitCode = 0
                    StdOut   = "deleted backup piece`ndeleted backup piece"
                    StdErr   = ''
                    Success  = $true
                }
            }
        }

        It 'Returns Success=$true when WalletAlias is specified' {
            $result = Remove-RmanObsoleteBackup -DatabaseName 'ORCL' -WalletAlias 'CDB1' -Confirm:$false
            $result.Success | Should -Be $true
        }

        It 'Data.AuthMode is WalletAuth when WalletAlias is specified' {
            $result = Remove-RmanObsoleteBackup -DatabaseName 'ORCL' -WalletAlias 'CDB1' -Confirm:$false
            $result.Data.AuthMode | Should -Be 'WalletAuth'
        }

        It 'Returns Success=$false when both WalletAlias and Credential are specified' {
            $cred = New-Object System.Management.Automation.PSCredential('user', (ConvertTo-SecureString 'pass' -AsPlainText -Force))
            $result = Remove-RmanObsoleteBackup -DatabaseName 'ORCL' -WalletAlias 'CDB1' -Credential $cred -Confirm:$false
            $result.Success | Should -Be $false
            $result.Message | Should -Match 'cannot both be specified'
        }

        It 'Returns Success=$true when Credential is specified (NamedCredential mode)' {
            $cred = New-Object System.Management.Automation.PSCredential('user', (ConvertTo-SecureString 'pass' -AsPlainText -Force))
            $result = Remove-RmanObsoleteBackup -DatabaseName 'ORCL' -Credential $cred -Confirm:$false
            $result.Success | Should -Be $true
        }

        It 'Data.AuthMode is NamedCredential when Credential is specified' {
            $cred = New-Object System.Management.Automation.PSCredential('user', (ConvertTo-SecureString 'pass' -AsPlainText -Force))
            $result = Remove-RmanObsoleteBackup -DatabaseName 'ORCL' -Credential $cred -Confirm:$false
            $result.Data.AuthMode | Should -Be 'NamedCredential'
        }

        It '[SEC] Message does not contain credential fragments when WalletAlias is used' {
            $result = Remove-RmanObsoleteBackup -DatabaseName 'ORCL' -WalletAlias 'CDB1' -Confirm:$false
            $result.Message | Should -Not -Match '\w+/\w+@\w+'
            $result.Message | Should -Not -Match 'password'
        }

        It 'Data.AuthMode is OSAuth when neither WalletAlias nor Credential is specified' {
            $result = Remove-RmanObsoleteBackup -DatabaseName 'ORCL' -Confirm:$false
            $result.Data.AuthMode | Should -Be 'OSAuth'
        }
    }
}
