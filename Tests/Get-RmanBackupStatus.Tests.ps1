<#
.SECURITY
    Scope  : Get-RmanBackupStatus (public)
    Touches: No filesystem paths. No real Oracle instance.
             All RMAN process calls mocked via Invoke-RmanProcess mock.
    Does NOT touch: Real RMAN binary, Oracle instance, network, registry,
                    or current session environment variables.

    Security assertions in this file:
    - ORACLE_SID not set on current session after function call
    - Message property contains no credential or path fragments
    - Assert-OracleEnvironment binary integrity check failure returns safe result
#>

#Requires -Version 7.0

Describe 'Get-RmanBackupStatus' {

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

        $script:fakeRmanPath = Join-Path $TestDrive 'oracle' 'bin' 'rman.exe'
        New-Item -Path (Split-Path $script:fakeRmanPath) -ItemType Directory -Force | Out-Null
        New-Item -Path $script:fakeRmanPath -ItemType File -Force | Out-Null

        Remove-Module TACE.Oracle.Admin -Force -ErrorAction SilentlyContinue
        Import-Module $modulePath -Force

        Mock -CommandName Assert-OracleEnvironment -ModuleName TACE.Oracle.Admin -MockWith {
            return $script:fakeRmanPath
        }

        # Representative LIST BACKUP SUMMARY output — NLS_DATE_FORMAT = YYYY-MM-DD HH24:MI:SS
        # Most recent by CompletionTime: Key 94 (2026-02-03 02:00:00)
        # Most recent by Key:            Key 95 (Key=95, CompletionTime 2026-02-02 03:00:00)
        # CompletionTime-based selection should prefer Key 94 over Key 95.
        # February 2026 dates are used so IsRecentDay is always $false regardless of run date.
        $script:mockOutput = @"
RMAN> list backup summary;

List of Backups
===============

Key     TY LV S Device Type Completion Time     #Pieces #Copies Compressed Tag
------- -- -- - ----------- ------------------- ------- ------- ---------- ---
     91 B  F  A DISK        2026-02-01 02:00:00  1       1       NO         TAG20260201T020000
     92 B  A  A DISK        2026-02-01 03:00:00  1       1       NO         TAG20260201T030000
     93 B  0  A DISK        2026-02-02 02:00:00  1       1       NO         TAG20260202T020000
     94 B  1  A DISK        2026-02-03 02:00:00  1       1       NO         TAG20260203T020000
     95 B  F  X DISK        2026-02-02 03:00:00  1       1       YES        TAG20260202T030000

Recovery Manager complete.
"@

        Mock -CommandName Invoke-RmanProcess -ModuleName TACE.Oracle.Admin -MockWith {
            return [PSCustomObject]@{
                ExitCode = 0
                StdOut   = $script:mockOutput
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
            $param = (Get-Command Get-RmanBackupStatus).Parameters['DatabaseName']
            $isMandatory = $param.Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory }
            $isMandatory | Should -Not -BeNullOrEmpty
        }

        It 'DatabaseName has ValidateNotNullOrEmpty' {
            $param = (Get-Command Get-RmanBackupStatus).Parameters['DatabaseName']
            $hasAttr = $param.Attributes |
                Where-Object { $_ -is [System.Management.Automation.ValidateNotNullOrEmptyAttribute] }
            $hasAttr | Should -Not -BeNullOrEmpty
        }
    }

    # ── Implementation ────────────────────────────────────────────────────────

    Context 'Implementation' {

        BeforeAll {
            Mock -CommandName Invoke-RmanProcess -ModuleName TACE.Oracle.Admin -MockWith {
                return [PSCustomObject]@{
                    ExitCode = 0
                    StdOut   = $script:mockOutput
                    StdErr   = ''
                    Success  = $true
                }
            }
        }

        It 'Should return Success=$true on clean RMAN output' {
            $result = Get-RmanBackupStatus -DatabaseName 'ORCL'
            $result.Success | Should -Be $true
        }

        It 'Should return a non-null Data object' {
            $result = Get-RmanBackupStatus -DatabaseName 'ORCL'
            $result.Data | Should -Not -BeNullOrEmpty
        }

        It 'Data should be a single object, not an array' {
            $result = Get-RmanBackupStatus -DatabaseName 'ORCL'
            # Should not be an array — it is a single PSCustomObject
            ($result.Data -is [array]) | Should -Be $false
        }

        It 'Should select the most recent record by CompletionTime (Key 94 over Key 95)' {
            $result = Get-RmanBackupStatus -DatabaseName 'ORCL'
            $result.Data.Key | Should -Be 94
        }

        It 'Data should include the DatabaseName field' {
            $result = Get-RmanBackupStatus -DatabaseName 'CDB1'
            $result.Data.DatabaseName | Should -Be 'CDB1'
        }

        It 'Data.IsRecentDay should be $false for old mock data' {
            # All mock CompletionTimes are from 2026-02-01 to 2026-02-03 (February)
            # These dates are always more than 24 hours in the past so IsRecentDay is always $false
            $result = Get-RmanBackupStatus -DatabaseName 'ORCL'
            $result.Data.IsRecentDay | Should -Be $false
        }

        It 'Data.AgeHours should be a positive double' {
            $result = Get-RmanBackupStatus -DatabaseName 'ORCL'
            $result.Data.AgeHours | Should -BeOfType [double]
            $result.Data.AgeHours | Should -BeGreaterThan 0
        }

        It 'Data.RawLog should be populated' {
            $result = Get-RmanBackupStatus -DatabaseName 'ORCL'
            $result.Data.RawLog | Should -Not -BeNullOrEmpty
        }

        It 'Data has all expected properties' {
            $result = Get-RmanBackupStatus -DatabaseName 'ORCL'
            $d = $result.Data
            { $d.Key }            | Should -Not -Throw
            { $d.Level }          | Should -Not -Throw
            { $d.Status }         | Should -Not -Throw
            { $d.DeviceType }     | Should -Not -Throw
            { $d.CompletionTime } | Should -Not -Throw
            { $d.BackupTime }     | Should -Not -Throw
            { $d.PieceCount }     | Should -Not -Throw
            { $d.CopyCount }      | Should -Not -Throw
            { $d.Compressed }     | Should -Not -Throw
            { $d.Tag }            | Should -Not -Throw
            { $d.IsRecentDay }    | Should -Not -Throw
            { $d.AgeHours }       | Should -Not -Throw
            { $d.DatabaseName }   | Should -Not -Throw
            { $d.RawLog }         | Should -Not -Throw
        }

        It 'Should return Success=$false when RMAN output contains no backup records' {
            Mock -CommandName Invoke-RmanProcess -ModuleName TACE.Oracle.Admin -MockWith {
                return [PSCustomObject]@{
                    ExitCode = 0
                    StdOut   = "RMAN> list backup summary;`nno backups found`n"
                    StdErr   = ''
                    Success  = $true
                }
            }
            $result = Get-RmanBackupStatus -DatabaseName 'ORCL'
            $result.Success | Should -Be $false
            $result.Data    | Should -BeNullOrEmpty
            $result.Message | Should -Match 'No backup'
        }

        It 'Should return Success=$false when RMAN fails' {
            Mock -CommandName Invoke-RmanProcess -ModuleName TACE.Oracle.Admin -MockWith {
                return [PSCustomObject]@{ ExitCode = 1; StdOut = 'RMAN-03002: failure'; StdErr = ''; Success = $false }
            }
            $result = Get-RmanBackupStatus -DatabaseName 'ORCL'
            $result.Success | Should -Be $false
            $result.Data    | Should -BeNullOrEmpty
        }

        It 'Data.AgeHours should be -1 (sentinel) when CompletionTime is null' {
            # Output with an unparseable CompletionTime — not in YYYY-MM-DD HH24:MI:SS format.
            # CompletionTime will be $null; AgeHours and IsRecentDay fall back to sentinel values.
            $noParseOutput = @"
List of Backups
===============

Key     TY LV S Device Type Completion Time     #Pieces #Copies Compressed Tag
------- -- -- - ----------- ------------------- ------- ------- ---------- ---
     99 B  F  A DISK        01-MAR-26            1       1       NO         CUSTOMTAG_NODATE

Recovery Manager complete.
"@
            Mock -CommandName Invoke-RmanProcess -ModuleName TACE.Oracle.Admin -MockWith {
                return [PSCustomObject]@{ ExitCode = 0; StdOut = $noParseOutput; StdErr = ''; Success = $true }
            }
            $result = Get-RmanBackupStatus -DatabaseName 'ORCL'
            $result.Success                | Should -Be $true
            $result.Data.CompletionTime    | Should -BeNullOrEmpty
            $result.Data.AgeHours          | Should -Be -1
            $result.Data.IsRecentDay       | Should -Be $false
        }

        It 'Should include LIST BACKUP SUMMARY in the RMAN script' {
            $script:capturedScript = $null
            Mock -CommandName Invoke-RmanProcess -ModuleName TACE.Oracle.Admin -MockWith {
                $script:capturedScript = $RmanScript
                return [PSCustomObject]@{ ExitCode = 0; StdOut = $script:mockOutput; StdErr = ''; Success = $true }
            }
            Get-RmanBackupStatus -DatabaseName 'ORCL' | Out-Null
            $script:capturedScript | Should -Match 'LIST BACKUP SUMMARY'
        }
    }

    # ── Security ──────────────────────────────────────────────────────────────

    Context 'Security' {

        BeforeAll {
            Mock -CommandName Invoke-RmanProcess -ModuleName TACE.Oracle.Admin -MockWith {
                return [PSCustomObject]@{
                    ExitCode = 0
                    StdOut   = $script:mockOutput
                    StdErr   = ''
                    Success  = $true
                }
            }
        }

        It 'ORACLE_SID should not be set on current session after call' {
            $before = $env:ORACLE_SID
            Get-RmanBackupStatus -DatabaseName 'ORCL' | Out-Null
            $env:ORACLE_SID | Should -Be $before
        }

        It 'Message should not contain credential fragments' {
            $result = Get-RmanBackupStatus -DatabaseName 'ORCL'
            $result.Message | Should -Not -Match '\w+/\w+@\w+'
            $result.Message | Should -Not -Match 'password'
        }

        It 'Should return Success=$false and safe Message when binary integrity check fails' {
            Mock -CommandName Assert-OracleEnvironment -ModuleName TACE.Oracle.Admin -MockWith {
                throw 'RMAN binary integrity check failed: Authenticode signature status is NotSigned'
            }
            $result = Get-RmanBackupStatus -DatabaseName 'ORCL'
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
                    StdOut   = $script:mockOutput
                    StdErr   = ''
                    Success  = $true
                }
            }
        }

        It 'Returns Success=$true when WalletAlias is specified' {
            $result = Get-RmanBackupStatus -DatabaseName 'ORCL' -WalletAlias 'CDB1'
            $result.Success | Should -Be $true
        }

        It 'Returns a non-null Data object when WalletAlias is specified' {
            $result = Get-RmanBackupStatus -DatabaseName 'ORCL' -WalletAlias 'CDB1'
            $result.Data | Should -Not -BeNullOrEmpty
        }

        It 'Returns Success=$false when both WalletAlias and Credential are specified' {
            $cred = New-Object System.Management.Automation.PSCredential('user', (ConvertTo-SecureString 'pass' -AsPlainText -Force))
            $result = Get-RmanBackupStatus -DatabaseName 'ORCL' -WalletAlias 'CDB1' -Credential $cred
            $result.Success | Should -Be $false
            $result.Message | Should -Match 'cannot both be specified'
        }

        It 'Returns Success=$true when Credential is specified (NamedCredential mode)' {
            $cred = New-Object System.Management.Automation.PSCredential('user', (ConvertTo-SecureString 'pass' -AsPlainText -Force))
            $result = Get-RmanBackupStatus -DatabaseName 'ORCL' -Credential $cred
            $result.Success | Should -Be $true
        }

        It 'Returns a non-null Data object when Credential is specified (NamedCredential mode)' {
            $cred = New-Object System.Management.Automation.PSCredential('user', (ConvertTo-SecureString 'pass' -AsPlainText -Force))
            $result = Get-RmanBackupStatus -DatabaseName 'ORCL' -Credential $cred
            $result.Data | Should -Not -BeNullOrEmpty
        }

        It '[SEC] Message does not contain credential fragments when WalletAlias is used' {
            $result = Get-RmanBackupStatus -DatabaseName 'ORCL' -WalletAlias 'CDB1'
            $result.Message | Should -Not -Match '\w+/\w+@\w+'
            $result.Message | Should -Not -Match 'password'
        }

        It 'Returns Success=$true when neither WalletAlias nor Credential is specified (OSAuth)' {
            $result = Get-RmanBackupStatus -DatabaseName 'ORCL'
            $result.Success | Should -Be $true
        }
    }
}
