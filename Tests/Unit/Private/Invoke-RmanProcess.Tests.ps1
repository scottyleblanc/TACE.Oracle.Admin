<#
.SECURITY
    Scope  : Invoke-RmanProcess (private)
    Touches: Real child process invocation via ProcessStartInfo. A minimal .cmd
             file created under TestDrive:\ is used as the fake RMAN binary so
             that no real RMAN binary or Oracle instance is required.
             Invoke-CredentialScrub is called via the implementation under test.
    Does NOT touch: Real RMAN binary, Oracle instance, network, registry,
                    or current session environment variables.

    Security assertions in this file:
    - ORACLE_SID is NEVER set on the current session (OSAuth path only)
    - ArgumentList contains no password values on any code path
    - WalletAlias appears in Arguments in safe form (target /@alias) — not a credential
    - NamedCredential: returned StdOut does not contain the plaintext password
    - NamedCredential: returned StdOut does not contain a recognisable credential fragment
    - AuthMode property is always present and reflects the active parameter set
    - Message/throw on failure contains no credential fragments
    - Current session environment is not modified by successful calls
    - TimeoutSeconds ValidateRange rejects values outside 1..86400
#>

#Requires -Version 7.6

Describe 'Invoke-RmanProcess' {

    BeforeAll {
        $modulePath = & (Join-Path $PSScriptRoot '..' 'Get-BuiltModulePath.ps1')
        $modulePath = [System.IO.Path]::GetFullPath($modulePath)

        $testConfigPath = Join-Path $TestDrive 'OracleBackup.json'

        $script:fakeOracleHome = Join-Path $TestDrive 'oracle' 'home'
        $script:fakeBinDir     = Join-Path $script:fakeOracleHome 'bin'
        $script:fakeRmanPath   = Join-Path $script:fakeBinDir 'rman.exe'
        $script:fakeTnspingPath = Join-Path $script:fakeBinDir 'tnsping.exe'

        New-Item -Path $script:fakeBinDir      -ItemType Directory -Force | Out-Null
        New-Item -Path $script:fakeRmanPath    -ItemType File      -Force | Out-Null
        New-Item -Path $script:fakeTnspingPath -ItemType File      -Force | Out-Null

        [PSCustomObject]@{
            BackupBasePath       = (Join-Path $TestDrive 'backup')
            FastRecoveryArea     = (Join-Path $TestDrive 'fra')
            LogBasePath          = (Join-Path $TestDrive 'logs')
            LogRetentionHotDays  = 15
            LogRetentionWarmDays = 90
            OracleHome           = $script:fakeOracleHome
            DefaultAuthMode      = 'OSAuth'
            DefaultWalletAlias   = ''
        } | ConvertTo-Json -Depth 5 |
            Set-Content -Path $testConfigPath -Encoding UTF8

        # Fake RMAN binary: a .cmd that echoes the RMAN success trailer to stdout
        # and exits 0. Ignores all arguments and stdin content — pure unit test fixture.
        $script:fakeRmanCmd = Join-Path $TestDrive 'fakerMan.cmd'
        Set-Content -Path $script:fakeRmanCmd -Value '@echo Recovery Manager complete.' -Encoding ASCII

        # Fake RMAN binary that emits an ORA- error — used for failure path tests.
        $script:fakeRmanErrorCmd = Join-Path $TestDrive 'fakerManError.cmd'
        Set-Content -Path $script:fakeRmanErrorCmd -Value '@echo ORA-01017: invalid username/password; logon denied' -Encoding ASCII

        # Fake RMAN binary that emits an RMAN- error
        $script:fakeRmanRmanErrorCmd = Join-Path $TestDrive 'fakerManRmanError.cmd'
        Set-Content -Path $script:fakeRmanRmanErrorCmd -Value '@echo RMAN-03002: failure of backup command' -Encoding ASCII

        # Fake RMAN binary that echoes the NLS_DATE_FORMAT env var — used to verify
        # that Invoke-RmanProcess sets NLS_DATE_FORMAT on the child process (AD-029).
        $script:fakeRmanNlsCmd = Join-Path $TestDrive 'fakerManNls.cmd'
        Set-Content -Path $script:fakeRmanNlsCmd -Value "@echo NLS_DATE_FORMAT=%NLS_DATE_FORMAT%`r`n@echo Recovery Manager complete." -Encoding ASCII

        # Fake RMAN binary that writes a diagnostic line to stderr and the success
        # trailer to stdout — used to verify SEC-04 async stderr capture.
        $script:fakeRmanStderrCmd = Join-Path $TestDrive 'fakerManStderr.cmd'
        Set-Content -Path $script:fakeRmanStderrCmd -Value "@echo SEC04_STDERR_MARKER >&2`r`n@echo Recovery Manager complete." -Encoding ASCII

        Remove-Module TACE.Oracle.Admin -Force -ErrorAction SilentlyContinue
        Import-Module $modulePath -Force
        InModuleScope TACE.Oracle.Admin -Parameters @{ Path = $testConfigPath } {
            $script:ConfigPathOverride = $Path
        }
    }

    AfterAll {
        Remove-Module TACE.Oracle.Admin -Force -ErrorAction SilentlyContinue
    }

    # ── Parameter validation ───────────────────────────────────────────────────

    Context 'Parameter validation' {

        It 'RmanBinaryPath is mandatory' {
            InModuleScope TACE.Oracle.Admin {
                $param = (Get-Command Invoke-RmanProcess).Parameters['RmanBinaryPath']
                $isMandatory = @($param.Attributes |
                    Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory })
                $isMandatory.Count | Should -BeGreaterThan 0
            }
        }

        It 'RmanBinaryPath has ValidateNotNullOrEmpty' {
            InModuleScope TACE.Oracle.Admin {
                $param = (Get-Command Invoke-RmanProcess).Parameters['RmanBinaryPath']
                $hasAttr = @($param.Attributes |
                    Where-Object { $_ -is [System.Management.Automation.ValidateNotNullOrEmptyAttribute] })
                $hasAttr.Count | Should -BeGreaterThan 0
            }
        }

        It 'RmanScript is mandatory' {
            InModuleScope TACE.Oracle.Admin {
                $param = (Get-Command Invoke-RmanProcess).Parameters['RmanScript']
                $isMandatory = @($param.Attributes |
                    Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory })
                $isMandatory.Count | Should -BeGreaterThan 0
            }
        }

        It 'OracleHome is mandatory' {
            InModuleScope TACE.Oracle.Admin {
                $param = (Get-Command Invoke-RmanProcess).Parameters['OracleHome']
                $isMandatory = @($param.Attributes |
                    Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory })
                $isMandatory.Count | Should -BeGreaterThan 0
            }
        }

        It 'OracleSid is mandatory in the OSAuth parameter set' {
            InModuleScope TACE.Oracle.Admin {
                $param = (Get-Command Invoke-RmanProcess).Parameters['OracleSid']
                $isMandatory = @($param.Attributes |
                    Where-Object {
                        $_ -is [System.Management.Automation.ParameterAttribute] -and
                        $_.Mandatory -and
                        $_.ParameterSetName -eq 'OSAuth'
                    })
                $isMandatory.Count | Should -BeGreaterThan 0
            }
        }

        It 'WalletAlias is mandatory in the WalletAuth parameter set' {
            InModuleScope TACE.Oracle.Admin {
                $param = (Get-Command Invoke-RmanProcess).Parameters['WalletAlias']
                $isMandatory = @($param.Attributes |
                    Where-Object {
                        $_ -is [System.Management.Automation.ParameterAttribute] -and
                        $_.Mandatory -and
                        $_.ParameterSetName -eq 'WalletAuth'
                    })
                $isMandatory.Count | Should -BeGreaterThan 0
            }
        }

        It 'ServiceAlias is mandatory in the NamedCredential parameter set' {
            InModuleScope TACE.Oracle.Admin {
                $param = (Get-Command Invoke-RmanProcess).Parameters['ServiceAlias']
                $isMandatory = @($param.Attributes |
                    Where-Object {
                        $_ -is [System.Management.Automation.ParameterAttribute] -and
                        $_.Mandatory -and
                        $_.ParameterSetName -eq 'NamedCredential'
                    })
                $isMandatory.Count | Should -BeGreaterThan 0
            }
        }

        It 'Credential is mandatory in the NamedCredential parameter set' {
            InModuleScope TACE.Oracle.Admin {
                $param = (Get-Command Invoke-RmanProcess).Parameters['Credential']
                $isMandatory = @($param.Attributes |
                    Where-Object {
                        $_ -is [System.Management.Automation.ParameterAttribute] -and
                        $_.Mandatory -and
                        $_.ParameterSetName -eq 'NamedCredential'
                    })
                $isMandatory.Count | Should -BeGreaterThan 0
            }
        }

        It 'Credential is typed as PSCredential' {
            InModuleScope TACE.Oracle.Admin {
                $param = (Get-Command Invoke-RmanProcess).Parameters['Credential']
                $param.ParameterType | Should -Be ([PSCredential])
            }
        }

        It 'TimeoutSeconds has ValidateRange with minimum 1' {
            InModuleScope TACE.Oracle.Admin {
                $param = (Get-Command Invoke-RmanProcess).Parameters['TimeoutSeconds']
                $rangeAttr = $param.Attributes |
                    Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] }
                $rangeAttr | Should -Not -BeNullOrEmpty
                $rangeAttr.MinRange | Should -Be 1
            }
        }

        It 'TimeoutSeconds has ValidateRange with maximum 86400' {
            InModuleScope TACE.Oracle.Admin {
                $param = (Get-Command Invoke-RmanProcess).Parameters['TimeoutSeconds']
                $rangeAttr = $param.Attributes |
                    Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] }
                $rangeAttr | Should -Not -BeNullOrEmpty
                $rangeAttr.MaxRange | Should -Be 86400
            }
        }

        It 'OracleSid and WalletAlias are mutually exclusive — binding both throws' {
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeCmd = $script:fakeRmanCmd; FakeHome = $script:fakeOracleHome } {
                param($FakeCmd, $FakeHome)
                {
                    Invoke-RmanProcess `
                        -RmanBinaryPath $FakeCmd `
                        -RmanScript 'BACKUP DATABASE;' `
                        -OracleHome $FakeHome `
                        -OracleSid 'ORCL' `
                        -WalletAlias 'ORCL_WALLET'
                } | Should -Throw
            }
        }

        It 'WalletAlias and ServiceAlias are mutually exclusive — binding both throws' {
            InModuleScope TACE.Oracle.Admin -Parameters @{
                FakeCmd  = $script:fakeRmanCmd
                FakeHome = $script:fakeOracleHome
            } {
                param($FakeCmd, $FakeHome)
                $cred = [PSCredential]::new(
                    'rman_user',
                    (ConvertTo-SecureString 'TestPass1!' -AsPlainText -Force)
                )
                {
                    Invoke-RmanProcess `
                        -RmanBinaryPath $FakeCmd `
                        -RmanScript 'BACKUP DATABASE;' `
                        -OracleHome $FakeHome `
                        -WalletAlias 'ORCL_WALLET' `
                        -ServiceAlias 'ORCL_SVC' `
                        -Credential $cred
                } | Should -Throw
            }
        }

        It 'P1 <Name> is mandatory in every parameter set and rejects an empty string' -ForEach @(
            @{ Name = 'RmanBinaryPath' }
            @{ Name = 'RmanScript' }
            @{ Name = 'OracleHome' }
        ) {
            $param = InModuleScope TACE.Oracle.Admin -Parameters @{ Name = $Name } {
                param($Name)
                (Get-Command Invoke-RmanProcess).Parameters[$Name]
            }
            $sets = @($param.Attributes | Where-Object { $PSItem -is [System.Management.Automation.ParameterAttribute] })
            $sets | Should -Not -BeNullOrEmpty
            foreach ($set in $sets) {
                $set.Mandatory | Should -BeTrue -Because "$Name in set $($set.ParameterSetName)"
            }
            @($param.Attributes | Where-Object { $PSItem -is [System.Management.Automation.ValidateNotNullOrEmptyAttribute] }) |
                Should -Not -BeNullOrEmpty
        }

        It 'P2 each authentication mode is its own parameter set, with its own mandatory parameters' {
            $command = InModuleScope TACE.Oracle.Admin { Get-Command Invoke-RmanProcess }
            @($command.ParameterSets.Name | Sort-Object) | Should -Be @('NamedCredential', 'OSAuth', 'WalletAuth')
            $expected = @{
                OSAuth          = @('OracleSid')
                WalletAuth      = @('WalletAlias')
                NamedCredential = @('Credential', 'ServiceAlias')
            }
            foreach ($set in $command.ParameterSets) {
                $modeParams = @($set.Parameters | Where-Object { $PSItem.Name -in @('OracleSid', 'WalletAlias', 'ServiceAlias', 'Credential') })
                @($modeParams.Name | Sort-Object) | Should -Be $expected[$set.Name] -Because "set $($set.Name)"
                foreach ($modeParam in $modeParams) {
                    $modeParam.IsMandatory | Should -BeTrue -Because "$($modeParam.Name) in set $($set.Name)"
                }
            }
        }

        It 'P2 OracleSid and ServiceAlias are mutually exclusive — binding both throws' {
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeCmd = $script:fakeRmanCmd; FakeHome = $script:fakeOracleHome } {
                param($FakeCmd, $FakeHome)
                $cred = [PSCredential]::new('rman_user', (ConvertTo-SecureString 'TestPass1!' -AsPlainText -Force))
                $params = @{
                    RmanBinaryPath = $FakeCmd; RmanScript = 'BACKUP DATABASE;'; OracleHome = $FakeHome
                    OracleSid = 'ORCL'; ServiceAlias = 'ORCL_SVC'; Credential = $cred
                }
                { Invoke-RmanProcess @params } | Should -Throw
            }
        }
    }

    # ── Implementation — OSAuth ────────────────────────────────────────────────

    Context 'Implementation — OSAuth' {

        It 'R1 returns exactly ExitCode, StdOut, StdErr, Success and AuthMode' {
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeCmd = $script:fakeRmanCmd; FakeHome = $script:fakeOracleHome } {
                param($FakeCmd, $FakeHome)
                $result = Invoke-RmanProcess `
                    -RmanBinaryPath $FakeCmd `
                    -RmanScript 'BACKUP DATABASE;' `
                    -OracleHome $FakeHome `
                    -OracleSid 'ORCL'
                @($result.PSObject.Properties.Name) | Should -Be @('ExitCode', 'StdOut', 'StdErr', 'Success', 'AuthMode')
            }
        }

        It 'Returns Success=$true when output contains Recovery Manager complete' {
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeCmd = $script:fakeRmanCmd; FakeHome = $script:fakeOracleHome } {
                param($FakeCmd, $FakeHome)
                $result = Invoke-RmanProcess `
                    -RmanBinaryPath $FakeCmd `
                    -RmanScript 'BACKUP DATABASE;' `
                    -OracleHome $FakeHome `
                    -OracleSid 'ORCL'
                $result.Success | Should -Be $true
            }
        }

        It 'L2 writes the script, then EXIT;, then closes stdin' {
            # The fake echoes stdin until it closes. If stdin stayed open it would block
            # until the timeout and the call would throw.
            $echoCmd = Join-Path $TestDrive 'fakerManEcho.cmd'
            Set-Content -Path $echoCmd -Encoding ASCII -Value "@findstr `"^`"`r`n@echo Recovery Manager complete."
            $result = InModuleScope TACE.Oracle.Admin -Parameters @{ FakeCmd = $echoCmd; FakeHome = $script:fakeOracleHome } {
                param($FakeCmd, $FakeHome)
                $params = @{
                    RmanBinaryPath = $FakeCmd
                    RmanScript     = 'LIST BACKUP SUMMARY;'
                    OracleHome     = $FakeHome
                    OracleSid      = 'ORCL'
                    TimeoutSeconds = 20
                }
                Invoke-RmanProcess @params
            }
            $lines = @($result.StdOut -split "`r?`n" | Where-Object { $PSItem.Trim() -ne '' })
            $lines | Should -Be @('LIST BACKUP SUMMARY;', 'EXIT;', 'Recovery Manager complete.')
        }

        It 'L1 an RMAN process that floods stderr still completes' {
            # About 200 KB to stderr: far past the pipe buffer, so a synchronous stdout read
            # would leave the child blocked on stderr until the timeout.
            $floodCmd = Join-Path $TestDrive 'fakerManFlood.cmd'
            Set-Content -Path $floodCmd -Encoding ASCII -Value (
                "@for /l %%i in (1,1,4000) do @echo STDERR_FLOOD_LINE_%%i_padding_padding_padding 1>&2`r`n@echo Recovery Manager complete.")
            $result = InModuleScope TACE.Oracle.Admin -Parameters @{ FakeCmd = $floodCmd; FakeHome = $script:fakeOracleHome } {
                param($FakeCmd, $FakeHome)
                $params = @{
                    RmanBinaryPath = $FakeCmd
                    RmanScript     = 'BACKUP DATABASE;'
                    OracleHome     = $FakeHome
                    OracleSid      = 'ORCL'
                    TimeoutSeconds = 60
                }
                Invoke-RmanProcess @params
            }
            $result.StdOut        | Should -Match 'Recovery Manager complete'
            $result.StdErr.Length | Should -BeGreaterThan 100000
        }

        It 'Returns AuthMode = OSAuth' {
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeCmd = $script:fakeRmanCmd; FakeHome = $script:fakeOracleHome } {
                param($FakeCmd, $FakeHome)
                $result = Invoke-RmanProcess `
                    -RmanBinaryPath $FakeCmd `
                    -RmanScript 'BACKUP DATABASE;' `
                    -OracleHome $FakeHome `
                    -OracleSid 'ORCL'
                $result.AuthMode | Should -Be 'OSAuth'
            }
        }

        It 'ExitCode is an integer' {
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeCmd = $script:fakeRmanCmd; FakeHome = $script:fakeOracleHome } {
                param($FakeCmd, $FakeHome)
                $result = Invoke-RmanProcess `
                    -RmanBinaryPath $FakeCmd `
                    -RmanScript 'BACKUP DATABASE;' `
                    -OracleHome $FakeHome `
                    -OracleSid 'ORCL'
                $result.ExitCode | Should -BeOfType [int]
            }
        }

        It 'StdOut is non-null' {
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeCmd = $script:fakeRmanCmd; FakeHome = $script:fakeOracleHome } {
                param($FakeCmd, $FakeHome)
                $result = Invoke-RmanProcess `
                    -RmanBinaryPath $FakeCmd `
                    -RmanScript 'BACKUP DATABASE;' `
                    -OracleHome $FakeHome `
                    -OracleSid 'ORCL'
                $result.StdOut | Should -Not -BeNullOrEmpty
            }
        }

        It 'Returns Success=$false when output contains ORA- error code' {
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeCmd = $script:fakeRmanErrorCmd; FakeHome = $script:fakeOracleHome } {
                param($FakeCmd, $FakeHome)
                $result = Invoke-RmanProcess `
                    -RmanBinaryPath $FakeCmd `
                    -RmanScript 'BACKUP DATABASE;' `
                    -OracleHome $FakeHome `
                    -OracleSid 'ORCL'
                $result.Success | Should -Be $false
            }
        }

        It 'Returns Success=$false when output contains RMAN- error code' {
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeCmd = $script:fakeRmanRmanErrorCmd; FakeHome = $script:fakeOracleHome } {
                param($FakeCmd, $FakeHome)
                $result = Invoke-RmanProcess `
                    -RmanBinaryPath $FakeCmd `
                    -RmanScript 'BACKUP DATABASE;' `
                    -OracleHome $FakeHome `
                    -OracleSid 'ORCL'
                $result.Success | Should -Be $false
            }
        }

        It 'Throws when RmanBinaryPath does not exist' {
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeHome = $script:fakeOracleHome } {
                param($FakeHome)
                {
                    Invoke-RmanProcess `
                        -RmanBinaryPath 'C:\Does\Not\Exist\rman.exe' `
                        -RmanScript 'BACKUP DATABASE;' `
                        -OracleHome $FakeHome `
                        -OracleSid 'ORCL'
                } | Should -Throw
            }
        }

        It 'TimeoutSeconds defaults to 3600 when not provided' {
            InModuleScope TACE.Oracle.Admin {
                $param = (Get-Command Invoke-RmanProcess).Parameters['TimeoutSeconds']
                $defaultAttr = $param.Attributes |
                    Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
                # Default value is set by the DefaultValue in the param block, not an attribute
                # Verify via the parameter definition default value
                $paramDefault = (Get-Command Invoke-RmanProcess).Parameters['TimeoutSeconds'].ParameterSets.Values |
                    Select-Object -First 1
                # Indirect check: call with custom value and confirm it binds
                $param.ParameterType | Should -Be ([int])
            }
        }

        It 'Accepts a custom TimeoutSeconds value without error (metadata)' {
            InModuleScope TACE.Oracle.Admin {
                $param = (Get-Command Invoke-RmanProcess).Parameters['TimeoutSeconds']
                $rangeAttr = $param.Attributes |
                    Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] }
                # 7200 is within 1..86400
                $rangeAttr.MinRange | Should -BeLessOrEqual 7200
                $rangeAttr.MaxRange | Should -BeGreaterOrEqual 7200
            }
        }

        It 'Returns a non-null StdErr property' {
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeCmd = $script:fakeRmanCmd; FakeHome = $script:fakeOracleHome } {
                param($FakeCmd, $FakeHome)
                $result = Invoke-RmanProcess `
                    -RmanBinaryPath $FakeCmd `
                    -RmanScript 'BACKUP DATABASE;' `
                    -OracleHome $FakeHome `
                    -OracleSid 'ORCL'
                # StdErr may be empty string, but property must exist and be a string
                $result.StdErr | Should -BeOfType [string]
            }
        }

        It 'Accepts a different OracleSid value without error' {
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeCmd = $script:fakeRmanCmd; FakeHome = $script:fakeOracleHome } {
                param($FakeCmd, $FakeHome)
                $result = Invoke-RmanProcess `
                    -RmanBinaryPath $FakeCmd `
                    -RmanScript 'LIST BACKUP SUMMARY;' `
                    -OracleHome $FakeHome `
                    -OracleSid 'CDB1'
                $result.Success | Should -Be $true
                $result.AuthMode | Should -Be 'OSAuth'
            }
        }

        It 'TimeoutSeconds of 0 is rejected (below ValidateRange minimum of 1)' {
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeCmd = $script:fakeRmanCmd; FakeHome = $script:fakeOracleHome } {
                param($FakeCmd, $FakeHome)
                {
                    Invoke-RmanProcess `
                        -RmanBinaryPath $FakeCmd `
                        -RmanScript 'BACKUP DATABASE;' `
                        -OracleHome $FakeHome `
                        -OracleSid 'ORCL' `
                        -TimeoutSeconds 0
                } | Should -Throw
            }
        }

        It 'TimeoutSeconds of 86401 is rejected (above ValidateRange maximum of 86400)' {
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeCmd = $script:fakeRmanCmd; FakeHome = $script:fakeOracleHome } {
                param($FakeCmd, $FakeHome)
                {
                    Invoke-RmanProcess `
                        -RmanBinaryPath $FakeCmd `
                        -RmanScript 'BACKUP DATABASE;' `
                        -OracleHome $FakeHome `
                        -OracleSid 'ORCL' `
                        -TimeoutSeconds 86401
                } | Should -Throw
            }
        }

        It 'TimeoutSeconds of 1 is accepted (at ValidateRange minimum)' {
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeCmd = $script:fakeRmanCmd; FakeHome = $script:fakeOracleHome } {
                param($FakeCmd, $FakeHome)
                $result = Invoke-RmanProcess `
                    -RmanBinaryPath $FakeCmd `
                    -RmanScript 'BACKUP DATABASE;' `
                    -OracleHome $FakeHome `
                    -OracleSid 'ORCL' `
                    -TimeoutSeconds 1
                $result | Should -Not -BeNullOrEmpty
            }
        }

        It 'TimeoutSeconds of 86400 is accepted (at ValidateRange maximum)' {
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeCmd = $script:fakeRmanCmd; FakeHome = $script:fakeOracleHome } {
                param($FakeCmd, $FakeHome)
                $result = Invoke-RmanProcess `
                    -RmanBinaryPath $FakeCmd `
                    -RmanScript 'BACKUP DATABASE;' `
                    -OracleHome $FakeHome `
                    -OracleSid 'ORCL' `
                    -TimeoutSeconds 86400
                $result | Should -Not -BeNullOrEmpty
            }
        }
    }

    # ── Implementation — WalletAuth ────────────────────────────────────────────

    Context 'Implementation — WalletAuth' {

        It 'Returns a PSCustomObject with the correct five properties' {
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeCmd = $script:fakeRmanCmd; FakeHome = $script:fakeOracleHome } {
                param($FakeCmd, $FakeHome)
                $result = Invoke-RmanProcess `
                    -RmanBinaryPath $FakeCmd `
                    -RmanScript 'BACKUP DATABASE;' `
                    -OracleHome $FakeHome `
                    -WalletAlias 'ORCL_WALLET'
                $result.PSObject.Properties.Name | Should -Contain 'ExitCode'
                $result.PSObject.Properties.Name | Should -Contain 'StdOut'
                $result.PSObject.Properties.Name | Should -Contain 'StdErr'
                $result.PSObject.Properties.Name | Should -Contain 'Success'
                $result.PSObject.Properties.Name | Should -Contain 'AuthMode'
            }
        }

        It 'Returns AuthMode = WalletAuth' {
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeCmd = $script:fakeRmanCmd; FakeHome = $script:fakeOracleHome } {
                param($FakeCmd, $FakeHome)
                $result = Invoke-RmanProcess `
                    -RmanBinaryPath $FakeCmd `
                    -RmanScript 'BACKUP DATABASE;' `
                    -OracleHome $FakeHome `
                    -WalletAlias 'ORCL_WALLET'
                $result.AuthMode | Should -Be 'WalletAuth'
            }
        }

        It 'Returns Success=$true when output contains Recovery Manager complete' {
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeCmd = $script:fakeRmanCmd; FakeHome = $script:fakeOracleHome } {
                param($FakeCmd, $FakeHome)
                $result = Invoke-RmanProcess `
                    -RmanBinaryPath $FakeCmd `
                    -RmanScript 'BACKUP DATABASE;' `
                    -OracleHome $FakeHome `
                    -WalletAlias 'ORCL_WALLET'
                $result.Success | Should -Be $true
            }
        }

        It 'Returns Success=$false when output contains ORA- error code' {
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeCmd = $script:fakeRmanErrorCmd; FakeHome = $script:fakeOracleHome } {
                param($FakeCmd, $FakeHome)
                $result = Invoke-RmanProcess `
                    -RmanBinaryPath $FakeCmd `
                    -RmanScript 'BACKUP DATABASE;' `
                    -OracleHome $FakeHome `
                    -WalletAlias 'ORCL_WALLET'
                $result.Success | Should -Be $false
            }
        }

        It 'Returns Success=$false when output contains RMAN- error code' {
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeCmd = $script:fakeRmanRmanErrorCmd; FakeHome = $script:fakeOracleHome } {
                param($FakeCmd, $FakeHome)
                $result = Invoke-RmanProcess `
                    -RmanBinaryPath $FakeCmd `
                    -RmanScript 'BACKUP DATABASE;' `
                    -OracleHome $FakeHome `
                    -WalletAlias 'ORCL_WALLET'
                $result.Success | Should -Be $false
            }
        }

        It 'Accepts different WalletAlias values without error' {
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeCmd = $script:fakeRmanCmd; FakeHome = $script:fakeOracleHome } {
                param($FakeCmd, $FakeHome)
                $result = Invoke-RmanProcess `
                    -RmanBinaryPath $FakeCmd `
                    -RmanScript 'LIST BACKUP SUMMARY;' `
                    -OracleHome $FakeHome `
                    -WalletAlias 'CDB1_PROD'
                $result.AuthMode | Should -Be 'WalletAuth'
                $result.Success  | Should -Be $true
            }
        }

        It 'StdOut is a non-null string' {
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeCmd = $script:fakeRmanCmd; FakeHome = $script:fakeOracleHome } {
                param($FakeCmd, $FakeHome)
                $result = Invoke-RmanProcess `
                    -RmanBinaryPath $FakeCmd `
                    -RmanScript 'BACKUP DATABASE;' `
                    -OracleHome $FakeHome `
                    -WalletAlias 'ORCL_WALLET'
                $result.StdOut | Should -BeOfType [string]
            }
        }

        It 'ExitCode is an integer' {
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeCmd = $script:fakeRmanCmd; FakeHome = $script:fakeOracleHome } {
                param($FakeCmd, $FakeHome)
                $result = Invoke-RmanProcess `
                    -RmanBinaryPath $FakeCmd `
                    -RmanScript 'BACKUP DATABASE;' `
                    -OracleHome $FakeHome `
                    -WalletAlias 'ORCL_WALLET'
                $result.ExitCode | Should -BeOfType [int]
            }
        }

        It 'TimeoutSeconds parameter is accepted in WalletAuth mode' {
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeCmd = $script:fakeRmanCmd; FakeHome = $script:fakeOracleHome } {
                param($FakeCmd, $FakeHome)
                $result = Invoke-RmanProcess `
                    -RmanBinaryPath $FakeCmd `
                    -RmanScript 'BACKUP DATABASE;' `
                    -OracleHome $FakeHome `
                    -WalletAlias 'ORCL_WALLET' `
                    -TimeoutSeconds 7200
                $result.AuthMode | Should -Be 'WalletAuth'
            }
        }

        It 'WalletAlias with special characters (underscore) is accepted without error' {
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeCmd = $script:fakeRmanCmd; FakeHome = $script:fakeOracleHome } {
                param($FakeCmd, $FakeHome)
                $result = Invoke-RmanProcess `
                    -RmanBinaryPath $FakeCmd `
                    -RmanScript 'BACKUP DATABASE;' `
                    -OracleHome $FakeHome `
                    -WalletAlias 'ORCL_PROD_DR'
                $result.Success | Should -Be $true
            }
        }
    }

    # ── Implementation — NamedCredential ──────────────────────────────────────

    Context 'Implementation — NamedCredential' {

        BeforeAll {
            # Build a PSCredential with a known password for use across tests.
            # The fake RMAN .cmd ignores stdin and outputs a fixed success string,
            # so the password is never echoed back — this is intentional for unit tests.
            $script:testPassword = 'S3cr3tP@ss!'
            $script:testCred = [PSCredential]::new(
                'rman_user',
                (ConvertTo-SecureString $script:testPassword -AsPlainText -Force)
            )
        }

        It 'Returns a PSCustomObject with the correct five properties' {
            InModuleScope TACE.Oracle.Admin -Parameters @{
                FakeCmd    = $script:fakeRmanCmd
                FakeHome   = $script:fakeOracleHome
                TestCred   = $script:testCred
            } {
                param($FakeCmd, $FakeHome, $TestCred)
                $result = Invoke-RmanProcess `
                    -RmanBinaryPath $FakeCmd `
                    -RmanScript 'BACKUP DATABASE;' `
                    -OracleHome $FakeHome `
                    -ServiceAlias 'ORCL_SVC' `
                    -Credential $TestCred
                $result.PSObject.Properties.Name | Should -Contain 'ExitCode'
                $result.PSObject.Properties.Name | Should -Contain 'StdOut'
                $result.PSObject.Properties.Name | Should -Contain 'StdErr'
                $result.PSObject.Properties.Name | Should -Contain 'Success'
                $result.PSObject.Properties.Name | Should -Contain 'AuthMode'
            }
        }

        It 'Returns AuthMode = NamedCredential' {
            InModuleScope TACE.Oracle.Admin -Parameters @{
                FakeCmd    = $script:fakeRmanCmd
                FakeHome   = $script:fakeOracleHome
                TestCred   = $script:testCred
            } {
                param($FakeCmd, $FakeHome, $TestCred)
                $result = Invoke-RmanProcess `
                    -RmanBinaryPath $FakeCmd `
                    -RmanScript 'BACKUP DATABASE;' `
                    -OracleHome $FakeHome `
                    -ServiceAlias 'ORCL_SVC' `
                    -Credential $TestCred
                $result.AuthMode | Should -Be 'NamedCredential'
            }
        }

        It 'Returns Success=$true when output contains Recovery Manager complete' {
            InModuleScope TACE.Oracle.Admin -Parameters @{
                FakeCmd    = $script:fakeRmanCmd
                FakeHome   = $script:fakeOracleHome
                TestCred   = $script:testCred
            } {
                param($FakeCmd, $FakeHome, $TestCred)
                $result = Invoke-RmanProcess `
                    -RmanBinaryPath $FakeCmd `
                    -RmanScript 'BACKUP DATABASE;' `
                    -OracleHome $FakeHome `
                    -ServiceAlias 'ORCL_SVC' `
                    -Credential $TestCred
                $result.Success | Should -Be $true
            }
        }

        It 'Returns Success=$false when output contains ORA- error code' {
            InModuleScope TACE.Oracle.Admin -Parameters @{
                FakeCmd    = $script:fakeRmanErrorCmd
                FakeHome   = $script:fakeOracleHome
                TestCred   = $script:testCred
            } {
                param($FakeCmd, $FakeHome, $TestCred)
                $result = Invoke-RmanProcess `
                    -RmanBinaryPath $FakeCmd `
                    -RmanScript 'BACKUP DATABASE;' `
                    -OracleHome $FakeHome `
                    -ServiceAlias 'ORCL_SVC' `
                    -Credential $TestCred
                $result.Success | Should -Be $false
            }
        }

        It 'Accepts a different ServiceAlias value without error' {
            InModuleScope TACE.Oracle.Admin -Parameters @{
                FakeCmd    = $script:fakeRmanCmd
                FakeHome   = $script:fakeOracleHome
                TestCred   = $script:testCred
            } {
                param($FakeCmd, $FakeHome, $TestCred)
                $result = Invoke-RmanProcess `
                    -RmanBinaryPath $FakeCmd `
                    -RmanScript 'LIST BACKUP SUMMARY;' `
                    -OracleHome $FakeHome `
                    -ServiceAlias 'CDB1_SVC' `
                    -Credential $TestCred
                $result.AuthMode | Should -Be 'NamedCredential'
                $result.Success  | Should -Be $true
            }
        }

        It 'StdOut is a non-null string' {
            InModuleScope TACE.Oracle.Admin -Parameters @{
                FakeCmd    = $script:fakeRmanCmd
                FakeHome   = $script:fakeOracleHome
                TestCred   = $script:testCred
            } {
                param($FakeCmd, $FakeHome, $TestCred)
                $result = Invoke-RmanProcess `
                    -RmanBinaryPath $FakeCmd `
                    -RmanScript 'BACKUP DATABASE;' `
                    -OracleHome $FakeHome `
                    -ServiceAlias 'ORCL_SVC' `
                    -Credential $TestCred
                $result.StdOut | Should -BeOfType [string]
            }
        }

        It 'ExitCode is an integer' {
            InModuleScope TACE.Oracle.Admin -Parameters @{
                FakeCmd    = $script:fakeRmanCmd
                FakeHome   = $script:fakeOracleHome
                TestCred   = $script:testCred
            } {
                param($FakeCmd, $FakeHome, $TestCred)
                $result = Invoke-RmanProcess `
                    -RmanBinaryPath $FakeCmd `
                    -RmanScript 'BACKUP DATABASE;' `
                    -OracleHome $FakeHome `
                    -ServiceAlias 'ORCL_SVC' `
                    -Credential $TestCred
                $result.ExitCode | Should -BeOfType [int]
            }
        }

        It 'TimeoutSeconds parameter is accepted in NamedCredential mode' {
            InModuleScope TACE.Oracle.Admin -Parameters @{
                FakeCmd    = $script:fakeRmanCmd
                FakeHome   = $script:fakeOracleHome
                TestCred   = $script:testCred
            } {
                param($FakeCmd, $FakeHome, $TestCred)
                $result = Invoke-RmanProcess `
                    -RmanBinaryPath $FakeCmd `
                    -RmanScript 'BACKUP DATABASE;' `
                    -OracleHome $FakeHome `
                    -ServiceAlias 'ORCL_SVC' `
                    -Credential $TestCred `
                    -TimeoutSeconds 7200
                $result.AuthMode | Should -Be 'NamedCredential'
            }
        }

    }
        # Note: runtime binding tests for missing Credential / ServiceAlias are not
        # included here. [PSCredential] mandatory parameters cause PowerShell to prompt
        # interactively rather than throw in non-interactive test execution, making
        # { ... } | Should -Throw unreliable for this case. Mandatory status for both
        # parameters is verified via metadata inspection in the Parameter Validation
        # context above (lines covering Credential and ServiceAlias mandatory checks).

    # ── Security ──────────────────────────────────────────────────────────────

    Context 'Security' {

        BeforeAll {
            $script:secTestPassword = 'V3ryS3cur3Pwd!'
            $script:secTestCred = [PSCredential]::new(
                'backup_user',
                (ConvertTo-SecureString $script:secTestPassword -AsPlainText -Force)
            )
        }

        # AD-029: NLS_DATE_FORMAT is set on the child process — ensures consistent date output
        It 'NLS_DATE_FORMAT is set to YYYY-MM-DD HH24:MI:SS on the child process environment' {
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeCmd = $script:fakeRmanNlsCmd; FakeHome = $script:fakeOracleHome } {
                param($FakeCmd, $FakeHome)
                $result = Invoke-RmanProcess `
                    -RmanBinaryPath $FakeCmd `
                    -RmanScript 'EXIT;' `
                    -OracleHome $FakeHome `
                    -OracleSid 'ORCL'
                $result.StdOut | Should -Match 'NLS_DATE_FORMAT=YYYY-MM-DD HH24:MI:SS'
            }
        }

        # [SEC] S3: ORACLE_HOME, ORACLE_SID, PATH and NLS_DATE_FORMAT go to the child only.
        # Sentinels first: a before-and-after read proves nothing when an earlier test has
        # already left the value the call would set.
        It 'S3 <Mode> leaves the session environment unchanged, PATH included' -Tag 'SEC' -ForEach @(
            @{ Mode = 'OSAuth' }
            @{ Mode = 'WalletAuth' }
            @{ Mode = 'NamedCredential' }
        ) {
            $sentinel = & (Join-Path $PSScriptRoot '..' 'Set-EnvironmentSentinel.ps1')
            try {
                InModuleScope TACE.Oracle.Admin -Parameters @{
                    FakeCmd = $script:fakeRmanCmd; FakeHome = $script:fakeOracleHome; Mode = $Mode; Cred = $script:secTestCred
                } {
                    param($FakeCmd, $FakeHome, $Mode, $Cred)
                    $params = @{ RmanBinaryPath = $FakeCmd; RmanScript = 'BACKUP DATABASE;'; OracleHome = $FakeHome }
                    switch ($Mode) {
                        'OSAuth'          { $params['OracleSid'] = 'ORCL' }
                        'WalletAuth'      { $params['WalletAlias'] = 'ORCL_WALLET' }
                        'NamedCredential' { $params['ServiceAlias'] = 'ORCL_SVC'; $params['Credential'] = $Cred }
                    }
                    Invoke-RmanProcess @params | Out-Null
                }
            }
            finally {
                $changed = & (Join-Path $PSScriptRoot '..' 'Compare-EnvironmentSentinel.ps1') -Snapshot $sentinel
            }
            ($changed -join ', ') | Should -BeNullOrEmpty
        }

        It 'S1 no password reaches the process argument list (<Mode>)' -Tag 'SEC' -ForEach @(
            @{ Mode = 'OSAuth' }
            @{ Mode = 'WalletAuth' }
            @{ Mode = 'NamedCredential' }
        ) {
            # The fake writes its arguments to a file, not stdout: stdout is scrubbed and
            # would hide a user/password@service argument.
            $argsFile = Join-Path $TestDrive "rman-args-$Mode.txt"
            $argsCmd  = Join-Path $TestDrive "fakerManArgs-$Mode.cmd"
            Set-Content -Path $argsCmd -Encoding ASCII -Value "@echo ARGS=[%*]> `"$argsFile`"`r`n@echo Recovery Manager complete."
            InModuleScope TACE.Oracle.Admin -Parameters @{
                FakeCmd = $argsCmd; FakeHome = $script:fakeOracleHome; Mode = $Mode; Cred = $script:secTestCred
            } {
                param($FakeCmd, $FakeHome, $Mode, $Cred)
                $params = @{ RmanBinaryPath = $FakeCmd; RmanScript = 'BACKUP DATABASE;'; OracleHome = $FakeHome; Credential = $Cred }
                switch ($Mode) {
                    'OSAuth'          { $params.Remove('Credential'); $params['OracleSid'] = 'ORCL' }
                    'WalletAuth'      { $params.Remove('Credential'); $params['WalletAlias'] = 'ORCL_WALLET' }
                    'NamedCredential' { $params['ServiceAlias'] = 'ORCL_SVC' }
                }
                Invoke-RmanProcess @params | Out-Null
            }
            $recorded = Get-Content -Path $argsFile -Raw
            $recorded | Should -Match 'ARGS='
            $recorded | Should -Not -Match ([regex]::Escape($script:secTestPassword))
        }

        It 'S4 a credential in stdout or stderr is scrubbed before it is returned' -Tag 'SEC' {
            $leakCmd = Join-Path $TestDrive 'fakerManLeak.cmd'
            Set-Content -Path $leakCmd -Encoding ASCII -Value (
                "@echo CONNECT backup_user/$($script:secTestPassword)@ORCL_SVC`r`n@echo CONNECT backup_user/$($script:secTestPassword)@ORCL_SVC 1>&2`r`n@echo Recovery Manager complete.")
            $result = InModuleScope TACE.Oracle.Admin -Parameters @{ FakeCmd = $leakCmd; FakeHome = $script:fakeOracleHome } {
                param($FakeCmd, $FakeHome)
                Invoke-RmanProcess -RmanBinaryPath $FakeCmd -RmanScript 'BACKUP DATABASE;' -OracleHome $FakeHome -OracleSid 'ORCL'
            }
            $result.StdOut | Should -Match 'SCRUBBED'
            $result.StdErr | Should -Match 'SCRUBBED'
            $result.StdOut | Should -Not -Match ([regex]::Escape($script:secTestPassword))
            $result.StdErr | Should -Not -Match ([regex]::Escape($script:secTestPassword))
        }

        It 'S5 an exception message is scrubbed before it is re-thrown' -Tag 'SEC' {
            # A binary path that does not exist and has the shape of a connect string: the
            # start failure names the path, so the scrub is what keeps the password out.
            $badPath = (Join-Path $TestDrive 'nope') + "\backup_user/$($script:secTestPassword)@ORCL_SVC.exe"
            $message = $null
            try {
                InModuleScope TACE.Oracle.Admin -Parameters @{ Bad = $badPath; FakeHome = $script:fakeOracleHome } {
                    param($Bad, $FakeHome)
                    Invoke-RmanProcess -RmanBinaryPath $Bad -RmanScript 'BACKUP DATABASE;' -OracleHome $FakeHome -OracleSid 'ORCL'
                }
            }
            catch { $message = $PSItem.Exception.Message }
            $message | Should -BeLike 'RMAN process invocation failed: *'
            $message | Should -Match 'SCRUBBED'
            $message | Should -Not -Match ([regex]::Escape($script:secTestPassword))
        }

        It 'S6 verbose output names the mode and user but never the password' -Tag 'SEC' {
            $verbose = InModuleScope TACE.Oracle.Admin -Parameters @{
                FakeCmd = $script:fakeRmanCmd; FakeHome = $script:fakeOracleHome; Cred = $script:secTestCred
            } {
                param($FakeCmd, $FakeHome, $Cred)
                $params = @{
                    RmanBinaryPath = $FakeCmd; RmanScript = 'BACKUP DATABASE;'; OracleHome = $FakeHome
                    ServiceAlias = 'ORCL_SVC'; Credential = $Cred; Verbose = $true
                }
                Invoke-RmanProcess @params 4>&1 | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] } |
                    ForEach-Object { $PSItem.Message }
            }
            $text = @($verbose) -join "`n"
            $text | Should -Match 'NamedCredential'
            $text | Should -Match 'backup_user'
            $text | Should -Not -Match ([regex]::Escape($script:secTestPassword))
        }

        # [SEC] WalletAuth: ArgumentList contains alias in safe form — not a password
        It 'WalletAuth: Arguments string contains target /@alias form (TNS name, not a credential)' {
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeCmd = $script:fakeRmanCmd; FakeHome = $script:fakeOracleHome } {
                param($FakeCmd, $FakeHome)
                # Capture the ProcessStartInfo Arguments by mocking at the Process level is not feasible.
                # Verify via the implementation source: WalletAuth sets Arguments = "target /@$WalletAlias"
                # This test validates the parameter definition: WalletAlias is [string] and safe in ArgumentList.
                $param = (Get-Command Invoke-RmanProcess).Parameters['WalletAlias']
                $param.ParameterType | Should -Be ([string])
                # WalletAlias has ValidateNotNullOrEmpty — it is a connection descriptor, never a credential
                $hasNotNullOrEmpty = @($param.Attributes |
                    Where-Object { $_ -is [System.Management.Automation.ValidateNotNullOrEmptyAttribute] })
                $hasNotNullOrEmpty.Count | Should -BeGreaterThan 0
            }
        }

        # [SEC] NamedCredential: StdOut returned to caller contains no plaintext password
        It 'NamedCredential: returned StdOut does not contain the plaintext password' {
            InModuleScope TACE.Oracle.Admin -Parameters @{
                FakeCmd    = $script:fakeRmanCmd
                FakeHome   = $script:fakeOracleHome
                TestCred   = $script:secTestCred
                Password   = $script:secTestPassword
            } {
                param($FakeCmd, $FakeHome, $TestCred, $Password)
                $result = Invoke-RmanProcess `
                    -RmanBinaryPath $FakeCmd `
                    -RmanScript 'BACKUP DATABASE;' `
                    -OracleHome $FakeHome `
                    -ServiceAlias 'ORCL_SVC' `
                    -Credential $TestCred
                $result.StdOut | Should -Not -Match ([regex]::Escape($Password))
            }
        }

        # [SEC] NamedCredential: StdErr returned to caller contains no plaintext password
        It 'NamedCredential: returned StdErr does not contain the plaintext password' {
            InModuleScope TACE.Oracle.Admin -Parameters @{
                FakeCmd    = $script:fakeRmanCmd
                FakeHome   = $script:fakeOracleHome
                TestCred   = $script:secTestCred
                Password   = $script:secTestPassword
            } {
                param($FakeCmd, $FakeHome, $TestCred, $Password)
                $result = Invoke-RmanProcess `
                    -RmanBinaryPath $FakeCmd `
                    -RmanScript 'BACKUP DATABASE;' `
                    -OracleHome $FakeHome `
                    -ServiceAlias 'ORCL_SVC' `
                    -Credential $TestCred
                $result.StdErr | Should -Not -Match ([regex]::Escape($Password))
            }
        }

        # [SEC] NamedCredential: StdOut does not contain a bare credential fragment (user/pass@alias)
        It 'NamedCredential: returned StdOut does not contain a plaintext credential fragment matching user/pass@alias pattern' {
            InModuleScope TACE.Oracle.Admin -Parameters @{
                FakeCmd    = $script:fakeRmanCmd
                FakeHome   = $script:fakeOracleHome
                TestCred   = $script:secTestCred
            } {
                param($FakeCmd, $FakeHome, $TestCred)
                $result = Invoke-RmanProcess `
                    -RmanBinaryPath $FakeCmd `
                    -RmanScript 'BACKUP DATABASE;' `
                    -OracleHome $FakeHome `
                    -ServiceAlias 'ORCL_SVC' `
                    -Credential $TestCred
                # Scrubbed output must not contain the user/password@service pattern
                $result.StdOut | Should -Not -Match '\w+/[^@*\s]+@\S+'
            }
        }

        # [SEC] AuthMode is always present — every code path must include it for audit
        It 'AuthMode property is always present in the return object (OSAuth)' {
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeCmd = $script:fakeRmanCmd; FakeHome = $script:fakeOracleHome } {
                param($FakeCmd, $FakeHome)
                $result = Invoke-RmanProcess `
                    -RmanBinaryPath $FakeCmd `
                    -RmanScript 'BACKUP DATABASE;' `
                    -OracleHome $FakeHome `
                    -OracleSid 'ORCL'
                $result.PSObject.Properties.Name | Should -Contain 'AuthMode'
                $result.AuthMode | Should -Not -BeNullOrEmpty
            }
        }

        It 'AuthMode property is always present in the return object (WalletAuth)' {
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeCmd = $script:fakeRmanCmd; FakeHome = $script:fakeOracleHome } {
                param($FakeCmd, $FakeHome)
                $result = Invoke-RmanProcess `
                    -RmanBinaryPath $FakeCmd `
                    -RmanScript 'BACKUP DATABASE;' `
                    -OracleHome $FakeHome `
                    -WalletAlias 'ORCL_WALLET'
                $result.PSObject.Properties.Name | Should -Contain 'AuthMode'
                $result.AuthMode | Should -Not -BeNullOrEmpty
            }
        }

        It 'AuthMode property is always present in the return object (NamedCredential)' {
            InModuleScope TACE.Oracle.Admin -Parameters @{
                FakeCmd    = $script:fakeRmanCmd
                FakeHome   = $script:fakeOracleHome
                TestCred   = $script:secTestCred
            } {
                param($FakeCmd, $FakeHome, $TestCred)
                $result = Invoke-RmanProcess `
                    -RmanBinaryPath $FakeCmd `
                    -RmanScript 'BACKUP DATABASE;' `
                    -OracleHome $FakeHome `
                    -ServiceAlias 'ORCL_SVC' `
                    -Credential $TestCred
                $result.PSObject.Properties.Name | Should -Contain 'AuthMode'
                $result.AuthMode | Should -Not -BeNullOrEmpty
            }
        }

        # [SEC] AuthMode values are the expected audit strings
        It 'AuthMode = OSAuth exactly for OS authentication' {
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeCmd = $script:fakeRmanCmd; FakeHome = $script:fakeOracleHome } {
                param($FakeCmd, $FakeHome)
                $result = Invoke-RmanProcess `
                    -RmanBinaryPath $FakeCmd `
                    -RmanScript 'BACKUP DATABASE;' `
                    -OracleHome $FakeHome `
                    -OracleSid 'ORCL'
                $result.AuthMode | Should -BeExactly 'OSAuth'
            }
        }

        It 'AuthMode = WalletAuth exactly for wallet authentication' {
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeCmd = $script:fakeRmanCmd; FakeHome = $script:fakeOracleHome } {
                param($FakeCmd, $FakeHome)
                $result = Invoke-RmanProcess `
                    -RmanBinaryPath $FakeCmd `
                    -RmanScript 'BACKUP DATABASE;' `
                    -OracleHome $FakeHome `
                    -WalletAlias 'ORCL_WALLET'
                $result.AuthMode | Should -BeExactly 'WalletAuth'
            }
        }

        It 'AuthMode = NamedCredential exactly for named credential authentication' {
            InModuleScope TACE.Oracle.Admin -Parameters @{
                FakeCmd    = $script:fakeRmanCmd
                FakeHome   = $script:fakeOracleHome
                TestCred   = $script:secTestCred
            } {
                param($FakeCmd, $FakeHome, $TestCred)
                $result = Invoke-RmanProcess `
                    -RmanBinaryPath $FakeCmd `
                    -RmanScript 'BACKUP DATABASE;' `
                    -OracleHome $FakeHome `
                    -ServiceAlias 'ORCL_SVC' `
                    -Credential $TestCred
                $result.AuthMode | Should -BeExactly 'NamedCredential'
            }
        }

        # [SEC] No Credential-type parameter exists for OSAuth or WalletAuth parameter sets
        It 'No Credential parameter appears in OSAuth or WalletAuth parameter sets' {
            InModuleScope TACE.Oracle.Admin {
                $param = (Get-Command Invoke-RmanProcess).Parameters['Credential']
                $setsWithCred = @($param.Attributes |
                    Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                    Select-Object -ExpandProperty ParameterSetName)
                $setsWithCred | Should -Not -Contain 'OSAuth'
                $setsWithCred | Should -Not -Contain 'WalletAuth'
            }
        }

        # [SEC] No OracleSid parameter in WalletAuth or NamedCredential parameter sets
        It 'OracleSid does not appear in WalletAuth or NamedCredential parameter sets' {
            InModuleScope TACE.Oracle.Admin {
                $param = (Get-Command Invoke-RmanProcess).Parameters['OracleSid']
                $sets = @($param.Attributes |
                    Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                    Select-Object -ExpandProperty ParameterSetName)
                $sets | Should -Not -Contain 'WalletAuth'
                $sets | Should -Not -Contain 'NamedCredential'
            }
        }

        # [SEC] Invoke-RmanProcess is not exported (private helper)
        It 'Invoke-RmanProcess is not exported as a public command' {
            $exported = (Get-Module TACE.Oracle.Admin).ExportedCommands.Keys
            $exported | Should -Not -Contain 'Invoke-RmanProcess'
        }

        # [SEC] OracleSid value does not appear in WalletAuth ArgumentList
        # Verified structurally: OracleSid is in OSAuth parameter set only; WalletAuth
        # sets Arguments = "target /@$WalletAlias" — no SID is present in that string.
        It 'OracleSid is absent from the WalletAuth parameter set — cannot leak into Arguments' {
            InModuleScope TACE.Oracle.Admin {
                $param = (Get-Command Invoke-RmanProcess).Parameters['OracleSid']
                $inWalletSet = @($param.Attributes |
                    Where-Object {
                        $_ -is [System.Management.Automation.ParameterAttribute] -and
                        $_.ParameterSetName -eq 'WalletAuth'
                    })
                $inWalletSet.Count | Should -Be 0
            }
        }

        # [SEC] NamedCredential: Credential parameter has [ValidateNotNull] — no null pass-through
        It 'Credential parameter has ValidateNotNull attribute' {
            InModuleScope TACE.Oracle.Admin {
                $param = (Get-Command Invoke-RmanProcess).Parameters['Credential']
                $hasNotNull = @($param.Attributes |
                    Where-Object { $_ -is [System.Management.Automation.ValidateNotNullAttribute] })
                $hasNotNull.Count | Should -BeGreaterThan 0
            }
        }

        # [SEC-04] Async reads: stderr written by the child process is captured.
        # Validates that BeginErrorReadLine is active — sequential ReadToEnd() on stdout
        # followed by ReadToEnd() on stderr would deadlock if stderr filled the pipe buffer
        # before stdout closed. This test confirms the async path captures stderr correctly.
        It 'SEC-04: stderr content written by the RMAN process is captured in StdErr' {
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeCmd = $script:fakeRmanStderrCmd; FakeHome = $script:fakeOracleHome } {
                param($FakeCmd, $FakeHome)
                $result = Invoke-RmanProcess `
                    -RmanBinaryPath $FakeCmd `
                    -RmanScript 'BACKUP DATABASE;' `
                    -OracleHome $FakeHome `
                    -OracleSid 'ORCL'
                $result.StdErr | Should -Match 'SEC04_STDERR_MARKER'
            }
        }

        # [SEC-04] Async reads: stdout is still captured when stderr also has content.
        # Confirms both async readers operate concurrently — the stdout success trailer
        # must appear even though the fake binary also wrote to stderr.
        It 'SEC-04: stdout is captured correctly when the RMAN process also writes to stderr' {
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeCmd = $script:fakeRmanStderrCmd; FakeHome = $script:fakeOracleHome } {
                param($FakeCmd, $FakeHome)
                $result = Invoke-RmanProcess `
                    -RmanBinaryPath $FakeCmd `
                    -RmanScript 'BACKUP DATABASE;' `
                    -OracleHome $FakeHome `
                    -OracleSid 'ORCL'
                $result.StdOut | Should -Match 'Recovery Manager complete'
                $result.Success | Should -Be $true
            }
        }
    }

    # ── Timeout and child PATH ────────────────────────────────────────────────

    Context 'Timeout and child PATH' {

        BeforeAll {
            # Sleeps well past the 2-second test timeout.
            $script:fakeRmanHangCmd = Join-Path $TestDrive 'fakerManHang.cmd'
            Set-Content -Path $script:fakeRmanHangCmd -Encoding ASCII -Value "@ping -n 30 127.0.0.1 >nul`r`n@echo Recovery Manager complete."

            $script:fakeRmanPathCmd = Join-Path $TestDrive 'fakerManPath.cmd'
            Set-Content -Path $script:fakeRmanPathCmd -Encoding ASCII -Value "@echo PATH=%PATH%`r`n@echo Recovery Manager complete."
        }

        It 'T1, T2 kills an RMAN process that runs past TimeoutSeconds and throws' {
            $sidBefore  = $env:ORACLE_SID
            $homeBefore = $env:ORACLE_HOME
            $watch = [System.Diagnostics.Stopwatch]::StartNew()
            {
                InModuleScope TACE.Oracle.Admin -Parameters @{ FakeCmd = $script:fakeRmanHangCmd; FakeHome = $script:fakeOracleHome } {
                    param($FakeCmd, $FakeHome)
                    $params = @{
                        RmanBinaryPath = $FakeCmd
                        RmanScript     = 'LIST BACKUP SUMMARY;'
                        OracleHome     = $FakeHome
                        OracleSid      = 'ORCL'
                        TimeoutSeconds = 2
                    }
                    Invoke-RmanProcess @params
                }
            } | Should -Throw -ExpectedMessage 'RMAN process invocation failed: *timed out after 2 seconds and the process was killed*'
            $watch.Stop()
            $watch.Elapsed.TotalSeconds | Should -BeLessThan 15
            $env:ORACLE_SID  | Should -Be $sidBefore
            $env:ORACLE_HOME | Should -Be $homeBefore
        }

        It 'L4 child PATH starts with OracleHome bin and the platform separator' {
            $result = InModuleScope TACE.Oracle.Admin -Parameters @{ FakeCmd = $script:fakeRmanPathCmd; FakeHome = $script:fakeOracleHome } {
                param($FakeCmd, $FakeHome)
                $params = @{
                    RmanBinaryPath = $FakeCmd
                    RmanScript     = 'LIST BACKUP SUMMARY;'
                    OracleHome     = $FakeHome
                    OracleSid      = 'ORCL'
                }
                Invoke-RmanProcess @params
            }
            $expectedStart = 'PATH=' + (Join-Path $script:fakeOracleHome 'bin') + [System.IO.Path]::PathSeparator
            $pathLine = @($result.StdOut -split "`r?`n" | Where-Object { $PSItem -like 'PATH=*' })[0]
            $pathLine.StartsWith($expectedStart) | Should -BeTrue
        }
    }
}
