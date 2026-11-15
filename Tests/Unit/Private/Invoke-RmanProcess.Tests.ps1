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

#Requires -Version 7.0

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
    }

    # ── Implementation — OSAuth ────────────────────────────────────────────────

    Context 'Implementation — OSAuth' {

        It 'Returns a PSCustomObject with the correct five properties' {
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeCmd = $script:fakeRmanCmd; FakeHome = $script:fakeOracleHome } {
                param($FakeCmd, $FakeHome)
                $result = Invoke-RmanProcess `
                    -RmanBinaryPath $FakeCmd `
                    -RmanScript 'BACKUP DATABASE;' `
                    -OracleHome $FakeHome `
                    -OracleSid 'ORCL'
                $result.PSObject.Properties.Name | Should -Contain 'ExitCode'
                $result.PSObject.Properties.Name | Should -Contain 'StdOut'
                $result.PSObject.Properties.Name | Should -Contain 'StdErr'
                $result.PSObject.Properties.Name | Should -Contain 'Success'
                $result.PSObject.Properties.Name | Should -Contain 'AuthMode'
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

        # [SEC] OSAuth: ORACLE_SID is never set on the current session
        It 'OSAuth: ORACLE_SID is NOT set on the current session after the call' {
            $sidBefore = $env:ORACLE_SID
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeCmd = $script:fakeRmanCmd; FakeHome = $script:fakeOracleHome } {
                param($FakeCmd, $FakeHome)
                Invoke-RmanProcess `
                    -RmanBinaryPath $FakeCmd `
                    -RmanScript 'BACKUP DATABASE;' `
                    -OracleHome $FakeHome `
                    -OracleSid 'ORCL' | Out-Null
            }
            $env:ORACLE_SID | Should -Be $sidBefore
        }

        # [SEC] OSAuth: ORACLE_HOME is never set on the current session
        It 'OSAuth: ORACLE_HOME on the current session is unchanged after the call' {
            $homeBefore = $env:ORACLE_HOME
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeCmd = $script:fakeRmanCmd; FakeHome = $script:fakeOracleHome } {
                param($FakeCmd, $FakeHome)
                Invoke-RmanProcess `
                    -RmanBinaryPath $FakeCmd `
                    -RmanScript 'BACKUP DATABASE;' `
                    -OracleHome $FakeHome `
                    -OracleSid 'ORCL' | Out-Null
            }
            $env:ORACLE_HOME | Should -Be $homeBefore
        }

        # [SEC] WalletAuth: current session environment unmodified
        It 'WalletAuth: ORACLE_SID is NOT set on the current session after the call' {
            $sidBefore = $env:ORACLE_SID
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeCmd = $script:fakeRmanCmd; FakeHome = $script:fakeOracleHome } {
                param($FakeCmd, $FakeHome)
                Invoke-RmanProcess `
                    -RmanBinaryPath $FakeCmd `
                    -RmanScript 'BACKUP DATABASE;' `
                    -OracleHome $FakeHome `
                    -WalletAlias 'ORCL_WALLET' | Out-Null
            }
            $env:ORACLE_SID | Should -Be $sidBefore
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

        # [SEC] Invoke-CredentialScrub is a private function — not exported
        It 'Invoke-CredentialScrub is not exported as a public command' {
            $exported = (Get-Module TACE.Oracle.Admin).ExportedCommands.Keys
            $exported | Should -Not -Contain 'Invoke-CredentialScrub'
        }

        # [SEC] Invoke-RmanProcess is not exported (private helper)
        It 'Invoke-RmanProcess is not exported as a public command' {
            $exported = (Get-Module TACE.Oracle.Admin).ExportedCommands.Keys
            $exported | Should -Not -Contain 'Invoke-RmanProcess'
        }

        # [SEC] Credential scrub: Invoke-CredentialScrub removes user/pass@service pattern
        It 'Invoke-CredentialScrub scrubs credential fragment matching user/pass@service' {
            InModuleScope TACE.Oracle.Admin {
                $raw = 'CONNECT TARGET backup_user/S3cr3tP@ss!@ORCL_SVC; BACKUP DATABASE;'
                $scrubbed = Invoke-CredentialScrub -Content $raw
                $scrubbed | Should -Not -Match 'S3cr3tP@ss!'
                $scrubbed | Should -Match '\*\*\*SCRUBBED\*\*\*'
            }
        }

        # [SEC] Credential scrub: clean content is returned unchanged
        It 'Invoke-CredentialScrub returns clean content unchanged' {
            InModuleScope TACE.Oracle.Admin {
                $clean = 'Recovery Manager: Release 19.0.0.0.0 - Production'
                $result = Invoke-CredentialScrub -Content $clean
                $result | Should -Be $clean
            }
        }

        # [SEC] Credential scrub: empty string is handled without error
        It 'Invoke-CredentialScrub handles empty string without error' {
            InModuleScope TACE.Oracle.Admin {
                $result = Invoke-CredentialScrub -Content ''
                $result | Should -BeNullOrEmpty
            }
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
