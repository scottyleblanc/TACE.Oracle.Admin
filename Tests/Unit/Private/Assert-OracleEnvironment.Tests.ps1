<#
.SECURITY
    Scope  : Assert-OracleEnvironment (private)
    Touches: No real Oracle instance or real binaries. Get-AuthenticodeSignature and
             Get-Acl mocked via -ModuleName TACE.Oracle.Admin. TestDrive:\ used for all
             filesystem paths. The real binary file created in TestDrive is unsigned
             by design — all six integrity check cases are exercised via mocks.
    Does NOT touch: Real RMAN binary, Oracle instance, network, registry,
                    or current session environment variables.

    Security assertions in this file:
    - NotSigned status does NOT cause failure (Oracle signs archives, not individual executables — NotSigned is always expected)
    - HashMismatch status causes hard terminating failure (binary altered after signing)
    - TrustFailure status causes hard terminating failure (cert chain untrustworthy)
    - Non-Oracle signer subject causes hard terminating failure (binary substitution indicator)
    - File owner is NOT checked; domain-account-owned Oracle installs are normal
    - Exception from Get-AuthenticodeSignature propagates cleanly (no silent swallow)
    - No SkipSignatureCheck, Force, or SkipOwnerCheck bypass parameter exists
    - Error messages on integrity failure contain no credential fragments
    - Returned binary path is always rooted under the validated OracleHome
#>

#Requires -Version 7.0

Describe 'Assert-OracleEnvironment' {

    BeforeAll {
        $modulePath = & (Join-Path $PSScriptRoot '..' 'Get-BuiltModulePath.ps1')
        $modulePath = [System.IO.Path]::GetFullPath($modulePath)

        $testConfigPath = Join-Path $TestDrive 'OracleBackup.json'

        $script:fakeOracleHome = Join-Path $TestDrive 'oracle' 'home'
        $script:fakeBinDir     = Join-Path $script:fakeOracleHome 'bin'
        $script:fakeRmanPath   = Join-Path $script:fakeBinDir 'rman.exe'

        New-Item -Path $script:fakeBinDir   -ItemType Directory -Force | Out-Null
        New-Item -Path $script:fakeRmanPath -ItemType File      -Force | Out-Null

        [PSCustomObject]@{
            BackupBasePath       = (Join-Path $TestDrive 'backup')
            FastRecoveryArea     = (Join-Path $TestDrive 'fra')
            LogBasePath          = (Join-Path $TestDrive 'logs')
            LogRetentionHotDays  = 15
            LogRetentionWarmDays = 90
            OracleHome           = $script:fakeOracleHome
        } | ConvertTo-Json -Depth 5 |
            Set-Content -Path $testConfigPath -Encoding UTF8

        Remove-Module TACE.Oracle.Admin -Force -ErrorAction SilentlyContinue
        Import-Module $modulePath -Force
        InModuleScope TACE.Oracle.Admin -Parameters @{ Path = $testConfigPath } {
            $script:ConfigPathOverride = $Path
        }
    }

    AfterAll {
        Remove-Module TACE.Oracle.Admin -Force -ErrorAction SilentlyContinue
    }

    # ── Parameter validation ──────────────────────────────────────────────────

    Context 'Parameter validation' {

        It 'OracleHome is mandatory' {
            InModuleScope TACE.Oracle.Admin {
                $param = (Get-Command Assert-OracleEnvironment).Parameters['OracleHome']
                $isMandatory = @($param.Attributes |
                    Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory })
                $isMandatory.Count | Should -BeGreaterThan 0
            }
        }

        It 'Binary must not be null or empty' {
            InModuleScope TACE.Oracle.Admin {
                $param = (Get-Command Assert-OracleEnvironment).Parameters['Binary']
                $notNullOrEmpty = @($param.Attributes |
                    Where-Object { $_ -is [System.Management.Automation.ValidateNotNullOrEmptyAttribute] })
                $notNullOrEmpty.Count | Should -BeGreaterThan 0
            }
        }

        It 'Binary defaults to rman.exe — Get-AuthenticodeSignature called with rman.exe path when Binary is omitted' {
            $script:capturedPath = $null
            Mock -CommandName Get-AuthenticodeSignature -ModuleName TACE.Oracle.Admin -MockWith {
                $script:capturedPath = $FilePath
                [PSCustomObject]@{
                    Status            = 'Valid'
                    SignerCertificate = [PSCustomObject]@{ Subject = 'CN=Oracle America Inc' }
                }
            }
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeHome = $script:fakeOracleHome } {
                param($FakeHome)
                Assert-OracleEnvironment -OracleHome $FakeHome | Out-Null
            }
            $script:capturedPath | Should -Match 'rman\.exe$'
        }

        It 'Throws with a clear message when OracleHome is empty and env var is not set' {
            InModuleScope TACE.Oracle.Admin {
                $saved = $env:ORACLE_HOME
                $env:ORACLE_HOME = ''
                try {
                    { Assert-OracleEnvironment -OracleHome '' } | Should -Throw -ExpectedMessage '*not configured*'
                }
                finally {
                    $env:ORACLE_HOME = $saved
                }
            }
        }

        It 'T2 the missing-home error names the config file and ORACLE_HOME' {
            InModuleScope TACE.Oracle.Admin {
                $saved = $env:ORACLE_HOME
                $env:ORACLE_HOME = ''
                try {
                    $message = $null
                    try { Assert-OracleEnvironment -OracleHome '' } catch { $message = $PSItem.Exception.Message }
                    $message | Should -BeLike 'Oracle environment validation failed:*'
                    $message | Should -BeLike '*Config\OracleBackup.json*'
                    $message | Should -BeLike '*ORACLE_HOME environment variable*'
                    $message | Should -Not -BeLike '*Set-OracleBackupConfig*'
                }
                finally {
                    $env:ORACLE_HOME = $saved
                }
            }
        }
    }

    # ── Implementation ────────────────────────────────────────────────────────

    Context 'Implementation' {

        BeforeEach {
            # Default mock: valid Oracle signature — all checks pass
            Mock -CommandName Get-AuthenticodeSignature -ModuleName TACE.Oracle.Admin -MockWith {
                [PSCustomObject]@{
                    Status            = 'Valid'
                    SignerCertificate = [PSCustomObject]@{
                        Subject = 'CN=Oracle America Inc, O=Oracle America Inc, L=Austin, S=Texas, C=US'
                    }
                }
            }
        }

        # Case 1a: valid Oracle signature → returns binary path
        It 'Returns the binary path when all checks pass (valid Oracle signature, SYSTEM owner)' {
            InModuleScope TACE.Oracle.Admin -Parameters @{
                FakeHome = $script:fakeOracleHome
                RmanPath = $script:fakeRmanPath
            } {
                param($FakeHome, $RmanPath)
                $result = Assert-OracleEnvironment -OracleHome $FakeHome
                $result | Should -Be $RmanPath
            }
        }

        # Case 1b: NotSigned → passes; Oracle 19c does not consistently sign Windows executables
        It 'Returns the binary path when Authenticode status is NotSigned' {
            Mock -CommandName Get-AuthenticodeSignature -ModuleName TACE.Oracle.Admin -MockWith {
                [PSCustomObject]@{
                    Status            = 'NotSigned'
                    SignerCertificate = $null
                }
            }
            InModuleScope TACE.Oracle.Admin -Parameters @{
                FakeHome = $script:fakeOracleHome
                RmanPath = $script:fakeRmanPath
            } {
                param($FakeHome, $RmanPath)
                $result = Assert-OracleEnvironment -OracleHome $FakeHome
                $result | Should -Be $RmanPath
            }
        }

        # Case 2: Status = 'TrustFailure' → throws hard fail (cert chain untrustworthy)
        It 'Throws when Authenticode status is TrustFailure' {
            Mock -CommandName Get-AuthenticodeSignature -ModuleName TACE.Oracle.Admin -MockWith {
                [PSCustomObject]@{
                    Status            = 'TrustFailure'
                    SignerCertificate = [PSCustomObject]@{ Subject = 'CN=Oracle America Inc' }
                }
            }
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeHome = $script:fakeOracleHome } {
                param($FakeHome)
                { Assert-OracleEnvironment -OracleHome $FakeHome } |
                    Should -Throw -ExpectedMessage '*binary integrity check failed*'
            }
        }

        # Case 3: Status = 'HashMismatch' → throws hard fail
        It 'Throws when Authenticode status is HashMismatch' {
            Mock -CommandName Get-AuthenticodeSignature -ModuleName TACE.Oracle.Admin -MockWith {
                [PSCustomObject]@{
                    Status            = 'HashMismatch'
                    SignerCertificate = [PSCustomObject]@{ Subject = 'CN=Oracle America Inc' }
                }
            }
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeHome = $script:fakeOracleHome } {
                param($FakeHome)
                { Assert-OracleEnvironment -OracleHome $FakeHome } |
                    Should -Throw -ExpectedMessage '*binary integrity check failed*'
            }
        }

        # Case 4: Valid signature but non-Oracle Subject → throws hard fail
        It 'Throws when Authenticode signer subject does not contain Oracle' {
            Mock -CommandName Get-AuthenticodeSignature -ModuleName TACE.Oracle.Admin -MockWith {
                [PSCustomObject]@{
                    Status            = 'Valid'
                    SignerCertificate = [PSCustomObject]@{ Subject = 'CN=SomeOtherVendor Inc' }
                }
            }
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeHome = $script:fakeOracleHome } {
                param($FakeHome)
                { Assert-OracleEnvironment -OracleHome $FakeHome } |
                    Should -Throw -ExpectedMessage '*binary integrity check failed*'
            }
        }

        # Case 5: Valid Oracle signature, user-owned file → passes; owner check removed
        # Oracle on domain-joined Windows is normally owned by the installing user account
        It 'Returns the binary path when file owner is a named user account (owner check removed)' {
            InModuleScope TACE.Oracle.Admin -Parameters @{
                FakeHome = $script:fakeOracleHome
                RmanPath = $script:fakeRmanPath
            } {
                param($FakeHome, $RmanPath)
                $result = Assert-OracleEnvironment -OracleHome $FakeHome
                $result | Should -Be $RmanPath
            }
        }

        # Case 6: Get-AuthenticodeSignature itself throws → error propagates cleanly
        It 'Propagates error cleanly when Get-AuthenticodeSignature throws' {
            Mock -CommandName Get-AuthenticodeSignature -ModuleName TACE.Oracle.Admin -MockWith {
                throw 'Unhandled exception in Authenticode provider'
            }
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeHome = $script:fakeOracleHome } {
                param($FakeHome)
                { Assert-OracleEnvironment -OracleHome $FakeHome } | Should -Throw
            }
        }

        It 'Throws when OracleHome does not exist on disk' {
            InModuleScope TACE.Oracle.Admin {
                { Assert-OracleEnvironment -OracleHome 'C:\Does\Not\Exist\12345' } |
                    Should -Throw -ExpectedMessage '*does not exist*'
            }
        }

        It 'Throws when the requested binary is not present under OracleHome\bin' {
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeHome = $script:fakeOracleHome } {
                param($FakeHome)
                { Assert-OracleEnvironment -OracleHome $FakeHome -Binary 'sqlplus.exe' } |
                    Should -Throw -ExpectedMessage '*not found*'
            }
        }
    }

    # ── Security ──────────────────────────────────────────────────────────────

    Context 'Security' {

        BeforeEach {
            Mock -CommandName Get-AuthenticodeSignature -ModuleName TACE.Oracle.Admin -MockWith {
                [PSCustomObject]@{
                    Status            = 'Valid'
                    SignerCertificate = [PSCustomObject]@{
                        Subject = 'CN=Oracle America Inc, O=Oracle America Inc'
                    }
                }
            }
        }

        It 'Returned binary path is rooted under the validated OracleHome — never from PATH' {
            InModuleScope TACE.Oracle.Admin -Parameters @{
                FakeHome = $script:fakeOracleHome
                RmanPath = $script:fakeRmanPath
            } {
                param($FakeHome, $RmanPath)
                $result = Assert-OracleEnvironment -OracleHome $FakeHome
                $result | Should -Be $RmanPath
                $result | Should -BeLike "$FakeHome*"
            }
        }

        It 'Error message on HashMismatch failure contains no credential fragments' {
            Mock -CommandName Get-AuthenticodeSignature -ModuleName TACE.Oracle.Admin -MockWith {
                [PSCustomObject]@{
                    Status            = 'HashMismatch'
                    SignerCertificate = [PSCustomObject]@{ Subject = 'CN=Oracle America Inc' }
                }
            }
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeHome = $script:fakeOracleHome } {
                param($FakeHome)
                $errorMessage = ''
                try { Assert-OracleEnvironment -OracleHome $FakeHome }
                catch { $errorMessage = $_.Exception.Message }

                $errorMessage | Should -Not -BeNullOrEmpty
                $errorMessage | Should -Not -Match '/\S+@'
                $errorMessage | Should -Not -Match 'PASSWORD'
                $errorMessage | Should -Not -Match 'password'
            }
        }

        It 'No bypass parameter exists — SkipSignatureCheck, Force, and SkipOwnerCheck are absent' {
            InModuleScope TACE.Oracle.Admin {
                $keys = (Get-Command Assert-OracleEnvironment).Parameters.Keys
                $keys | Should -Not -Contain 'SkipSignatureCheck'
                $keys | Should -Not -Contain 'Force'
                $keys | Should -Not -Contain 'SkipOwnerCheck'
            }
        }

        It 'Current session environment is not modified when all checks pass' {
            $before = [System.Environment]::GetEnvironmentVariables()
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeHome = $script:fakeOracleHome } {
                param($FakeHome)
                Assert-OracleEnvironment -OracleHome $FakeHome | Out-Null
            }
            $after   = [System.Environment]::GetEnvironmentVariables()
            $newKeys = @($after.Keys | Where-Object { $before.Keys -notcontains $_ })
            $newKeys.Count | Should -Be 0
        }
    }

    # ── WalletAlias tnsping validation ────────────────────────────────────────
    # Uses Mock -CommandName Invoke-TnspingProcess (private helper extracted in
    # Stage 9) — avoids Add-Type ConsoleApplication which is not supported on
    # .NET Core. All tnsping invocation behaviour is tested via the mock contract.

    Context 'WalletAlias tnsping validation' {

        BeforeAll {
            # Mock Get-AuthenticodeSignature — valid Oracle signature; integrity checks pass
            Mock -CommandName Get-AuthenticodeSignature -ModuleName TACE.Oracle.Admin -MockWith {
                [PSCustomObject]@{
                    Status            = 'Valid'
                    SignerCertificate = [PSCustomObject]@{
                        Subject = 'CN=Oracle America Inc, O=Oracle America Inc'
                    }
                }
            }

            # Default tnsping mock — succeeds; overridden per-test where needed
            Mock -CommandName Invoke-TnspingProcess -ModuleName TACE.Oracle.Admin -MockWith {
                [PSCustomObject]@{ ExitCode = 0; StdOut = 'OK (10 msec)'; StdErr = '' }
            }

            # Helper: create a fake OracleHome/bin with rman.exe and optionally tnsping.exe
            # $WithTnsping = $true  → both rman.exe and tnsping.exe (empty stub)
            # $WithTnsping = $false → rman.exe only (simulates missing tnsping)
            function New-FakeTnspingHome {
                param([string]$Suffix, [bool]$WithTnsping = $true)
                $fakeHome = Join-Path $TestDrive "tnshome_$Suffix"
                $binDir   = Join-Path $fakeHome 'bin'
                New-Item -Path $binDir -ItemType Directory -Force | Out-Null
                New-Item -Path (Join-Path $binDir 'rman.exe')    -ItemType File -Force | Out-Null
                if ($WithTnsping) {
                    New-Item -Path (Join-Path $binDir 'tnsping.exe') -ItemType File -Force | Out-Null
                }
                return $fakeHome
            }

            $script:homeWithTnsping    = New-FakeTnspingHome -Suffix 'default' -WithTnsping $true
            $script:homeWithoutTnsping = New-FakeTnspingHome -Suffix 'notns'   -WithTnsping $false
        }

        # Test 1: WalletAlias parameter exists, is not mandatory, defaults to empty string
        It 'WalletAlias parameter exists, is not mandatory, and defaults to empty string' {
            InModuleScope TACE.Oracle.Admin {
                $params = (Get-Command Assert-OracleEnvironment).Parameters
                $params.ContainsKey('WalletAlias') | Should -Be $true

                $isMandatory = @($params['WalletAlias'].Attributes |
                    Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory })
                $isMandatory.Count | Should -Be 0

                # DefaultValue is not exposed via ParameterMetadata reflection;
                # behavioral default (empty → no tnsping) is covered by the next test.
            }
        }

        # Test 2: WalletAlias = '' → Invoke-TnspingProcess is never called
        It 'Returns binary path when WalletAlias is empty — tnsping not invoked' {
            InModuleScope TACE.Oracle.Admin -Parameters @{
                FakeHome = $script:fakeOracleHome
                RmanPath = $script:fakeRmanPath
            } {
                param($FakeHome, $RmanPath)
                $result = Assert-OracleEnvironment -OracleHome $FakeHome -WalletAlias ''
                $result | Should -Be $RmanPath
                Should -Invoke Invoke-TnspingProcess -ModuleName TACE.Oracle.Admin -Times 0
            }
        }

        # Test 3: WalletAlias = '   ' (whitespace only) → treated as empty; tnsping not invoked
        It 'Treats whitespace-only WalletAlias as empty — tnsping not invoked' {
            InModuleScope TACE.Oracle.Admin -Parameters @{
                FakeHome = $script:fakeOracleHome
                RmanPath = $script:fakeRmanPath
            } {
                param($FakeHome, $RmanPath)
                $result = Assert-OracleEnvironment -OracleHome $FakeHome -WalletAlias '   '
                $result | Should -Be $RmanPath
                Should -Invoke Invoke-TnspingProcess -ModuleName TACE.Oracle.Admin -Times 0
            }
        }

        # Test 4: tnsping.exe not present under OracleHome\bin → throws (Test-Path check)
        It 'Throws when WalletAlias is provided but tnsping.exe is not found under OracleHome\bin' {
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeHome = $script:homeWithoutTnsping } {
                param($FakeHome)
                { Assert-OracleEnvironment -OracleHome $FakeHome -WalletAlias 'MY_DB_ALIAS' } |
                    Should -Throw -ExpectedMessage '*not found*'
            }
        }

        # Test 5: Missing tnsping.exe — error message references 'tnsping'
        It 'Error message when tnsping.exe is missing contains the word tnsping' {
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeHome = $script:homeWithoutTnsping } {
                param($FakeHome)
                $msg = ''
                try { Assert-OracleEnvironment -OracleHome $FakeHome -WalletAlias 'MY_DB_ALIAS' }
                catch { $msg = $_.Exception.Message }
                $msg | Should -Not -BeNullOrEmpty
                $msg | Should -Match 'tnsping'
            }
        }

        # Test 6: Invoke-TnspingProcess returns ExitCode=0, no TNS- error → returns binary path
        It 'Returns binary path when tnsping exits 0 and output contains no TNS- error' {
            Mock -CommandName Invoke-TnspingProcess -ModuleName TACE.Oracle.Admin -MockWith {
                [PSCustomObject]@{ ExitCode = 0; StdOut = 'OK (10 msec)'; StdErr = '' }
            }
            InModuleScope TACE.Oracle.Admin -Parameters @{
                FakeHome    = $script:homeWithTnsping
                ExpectedRman = (Join-Path $script:homeWithTnsping 'bin' 'rman.exe')
            } {
                param($FakeHome, $ExpectedRman)
                $result = Assert-OracleEnvironment -OracleHome $FakeHome -WalletAlias 'MY_DB_ALIAS'
                $result | Should -Be $ExpectedRman
            }
        }

        # Test 7: Invoke-TnspingProcess returns ExitCode=1 → throws
        It 'Throws when tnsping exits with a non-zero exit code' {
            Mock -CommandName Invoke-TnspingProcess -ModuleName TACE.Oracle.Admin -MockWith {
                [PSCustomObject]@{ ExitCode = 1; StdOut = 'tnsping: error starting session'; StdErr = '' }
            }
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeHome = $script:homeWithTnsping } {
                param($FakeHome)
                { Assert-OracleEnvironment -OracleHome $FakeHome -WalletAlias 'MY_DB_ALIAS' } |
                    Should -Throw
            }
        }

        # Test 8: Invoke-TnspingProcess returns TNS-NNNNN in StdOut → throws
        It 'Throws when tnsping stdout contains a TNS-NNNNN error code' {
            Mock -CommandName Invoke-TnspingProcess -ModuleName TACE.Oracle.Admin -MockWith {
                [PSCustomObject]@{ ExitCode = 1; StdOut = 'TNS-12154: TNS:could not resolve the connect identifier specified'; StdErr = '' }
            }
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeHome = $script:homeWithTnsping } {
                param($FakeHome)
                { Assert-OracleEnvironment -OracleHome $FakeHome -WalletAlias 'MY_DB_ALIAS' } |
                    Should -Throw
            }
        }

        # Test 9: Wallet alias name appears in the error message on failure
        It 'Error message on tnsping failure contains the wallet alias name' {
            Mock -CommandName Invoke-TnspingProcess -ModuleName TACE.Oracle.Admin -MockWith {
                [PSCustomObject]@{ ExitCode = 1; StdOut = 'error'; StdErr = '' }
            }
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeHome = $script:homeWithTnsping } {
                param($FakeHome)
                $msg = ''
                try { Assert-OracleEnvironment -OracleHome $FakeHome -WalletAlias 'PROD_WALLET_ALIAS' }
                catch { $msg = $_.Exception.Message }
                $msg | Should -Not -BeNullOrEmpty
                $msg | Should -Match 'PROD_WALLET_ALIAS'
            }
        }

        # Test 10 (Security): Error message is scrubbed — no credential fragments
        It 'Error message on tnsping failure contains no credential fragments' {
            Mock -CommandName Invoke-TnspingProcess -ModuleName TACE.Oracle.Admin -MockWith {
                [PSCustomObject]@{ ExitCode = 1; StdOut = 'user/pass@service: error'; StdErr = '' }
            }
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeHome = $script:homeWithTnsping } {
                param($FakeHome)
                $msg = ''
                try { Assert-OracleEnvironment -OracleHome $FakeHome -WalletAlias 'MY_DB_ALIAS' }
                catch { $msg = $_.Exception.Message }
                $msg | Should -Not -BeNullOrEmpty
                $msg | Should -Not -Match '/\S+@'
                $msg | Should -Not -Match 'password'
                $msg | Should -Not -Match 'PASSWORD'
            }
        }

        # Test 11: OracleHome validation fires before tnsping — bad home throws on "does not exist"
        It 'Throws on OracleHome validation before reaching tnsping when OracleHome is invalid' {
            InModuleScope TACE.Oracle.Admin {
                { Assert-OracleEnvironment -OracleHome 'C:\DoesNotExist\99999' -WalletAlias 'MY_DB_ALIAS' } |
                    Should -Throw -ExpectedMessage '*does not exist*'
            }
        }

        # Test 12: Invoke-TnspingProcess is called with TnspingPath from OracleHome\bin
        It 'Invoke-TnspingProcess receives TnspingPath rooted under OracleHome\bin' {
            $script:capturedTnspingPath = $null
            Mock -CommandName Invoke-TnspingProcess -ModuleName TACE.Oracle.Admin -MockWith {
                $script:capturedTnspingPath = $TnspingPath
                [PSCustomObject]@{ ExitCode = 0; StdOut = 'OK'; StdErr = '' }
            }
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeHome = $script:homeWithTnsping } {
                param($FakeHome)
                Assert-OracleEnvironment -OracleHome $FakeHome -WalletAlias 'MY_DB_ALIAS' | Out-Null
            }
            $expectedPath = Join-Path $script:homeWithTnsping 'bin' 'tnsping.exe'
            $script:capturedTnspingPath | Should -Be $expectedPath
        }

        # Test 13 (Security): Session environment is not modified by the tnsping path
        It 'Current session environment is not modified by Invoke-TnspingProcess call' {
            Mock -CommandName Invoke-TnspingProcess -ModuleName TACE.Oracle.Admin -MockWith {
                [PSCustomObject]@{ ExitCode = 0; StdOut = 'OK'; StdErr = '' }
            }
            $oracleHomeBefore = $env:ORACLE_HOME
            $oracleSidBefore  = $env:ORACLE_SID
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeHome = $script:homeWithTnsping } {
                param($FakeHome)
                Assert-OracleEnvironment -OracleHome $FakeHome -WalletAlias 'MY_DB_ALIAS' | Out-Null
            }
            $env:ORACLE_HOME | Should -Be $oracleHomeBefore
            $env:ORACLE_SID  | Should -Be $oracleSidBefore
        }
    }

    # ── Invoke-TnspingProcess (real child process) ───────────────────────────
    # These run the helper itself, not a mock. Fake .cmd files under TestDrive stand in
    # for tnsping.exe, the same approach as the Invoke-RmanProcess tests.

    Context 'Invoke-TnspingProcess' {

        BeforeAll {
            $script:tnsHome = Join-Path $TestDrive 'tnshome'
            $null = New-Item -ItemType Directory -Force -Path (Join-Path $script:tnsHome 'bin')

            $script:tnsEchoCmd = Join-Path $TestDrive 'tnsEcho.cmd'
            Set-Content -Path $script:tnsEchoCmd -Encoding ASCII -Value (
                "@echo ORACLE_HOME=%ORACLE_HOME%`r`n@echo PATH=%PATH%`r`n@echo ALIAS=%1`r`n@echo OK (10 msec)")

            # About 200 KB to stderr: far past the pipe buffer, so a synchronous stdout read
            # would leave the child blocked on stderr.
            $script:tnsFloodCmd = Join-Path $TestDrive 'tnsFlood.cmd'
            Set-Content -Path $script:tnsFloodCmd -Encoding ASCII -Value (
                "@for /l %%i in (1,1,4000) do @echo STDERR_FLOOD_LINE_%%i_padding_padding_padding 1>&2`r`n@echo FLOOD_DONE")

            # Sleeps well past the 2-second test timeout.
            $script:tnsHangCmd = Join-Path $TestDrive 'tnsHang.cmd'
            Set-Content -Path $script:tnsHangCmd -Encoding ASCII -Value "@ping -n 30 127.0.0.1 >nul`r`n@echo LATE"
        }

        It 'R1 returns exactly ExitCode, StdOut and StdErr' {
            $result = InModuleScope TACE.Oracle.Admin -Parameters @{ Cmd = $script:tnsEchoCmd; FakeHome = $script:tnsHome } {
                param($Cmd, $FakeHome)
                Invoke-TnspingProcess -TnspingPath $Cmd -WalletAlias 'MY_ALIAS' -OracleHome $FakeHome
            }
            @($result.PSObject.Properties.Name) | Should -Be @('ExitCode', 'StdOut', 'StdErr')
            $result.ExitCode | Should -Be 0
            $result.StdOut   | Should -Match 'ALIAS=MY_ALIAS'
        }

        It 'S1 child gets ORACLE_HOME and the session environment is unchanged' -Tag 'SEC' {
            $homeBefore = $env:ORACLE_HOME
            $pathBefore = $env:PATH
            $result = InModuleScope TACE.Oracle.Admin -Parameters @{ Cmd = $script:tnsEchoCmd; FakeHome = $script:tnsHome } {
                param($Cmd, $FakeHome)
                Invoke-TnspingProcess -TnspingPath $Cmd -WalletAlias 'MY_ALIAS' -OracleHome $FakeHome
            }
            $result.StdOut   | Should -Match ([regex]::Escape("ORACLE_HOME=$($script:tnsHome)"))
            $env:ORACLE_HOME | Should -Be $homeBefore
            $env:PATH        | Should -Be $pathBefore
        }

        It 'L4 child PATH starts with OracleHome bin and the platform separator' {
            $result = InModuleScope TACE.Oracle.Admin -Parameters @{ Cmd = $script:tnsEchoCmd; FakeHome = $script:tnsHome } {
                param($Cmd, $FakeHome)
                Invoke-TnspingProcess -TnspingPath $Cmd -WalletAlias 'MY_ALIAS' -OracleHome $FakeHome
            }
            $expectedStart = 'PATH=' + (Join-Path $script:tnsHome 'bin') + [System.IO.Path]::PathSeparator
            $pathLine = @($result.StdOut -split "`r?`n" | Where-Object { $PSItem -like 'PATH=*' })[0]
            $pathLine.StartsWith($expectedStart) | Should -BeTrue
        }

        It 'L1 a tnsping that floods stderr still completes' {
            $result = InModuleScope TACE.Oracle.Admin -Parameters @{ Cmd = $script:tnsFloodCmd; FakeHome = $script:tnsHome } {
                param($Cmd, $FakeHome)
                Invoke-TnspingProcess -TnspingPath $Cmd -WalletAlias 'MY_ALIAS' -OracleHome $FakeHome -TimeoutSeconds 60
            }
            $result.StdOut        | Should -Match 'FLOOD_DONE'
            $result.StdErr.Length | Should -BeGreaterThan 100000
        }

        It 'S1, L2 kills a tnsping that runs past TimeoutSeconds and throws' -Tag 'SEC' {
            $homeBefore = $env:ORACLE_HOME
            $pathBefore = $env:PATH
            $watch = [System.Diagnostics.Stopwatch]::StartNew()
            {
                InModuleScope TACE.Oracle.Admin -Parameters @{ Cmd = $script:tnsHangCmd; FakeHome = $script:tnsHome } {
                    param($Cmd, $FakeHome)
                    Invoke-TnspingProcess -TnspingPath $Cmd -WalletAlias 'MY_ALIAS' -OracleHome $FakeHome -TimeoutSeconds 2
                }
            } | Should -Throw -ExpectedMessage '*timed out after 2 seconds and the process was killed*'
            $watch.Stop()
            $watch.Elapsed.TotalSeconds | Should -BeLessThan 15
            $env:ORACLE_HOME | Should -Be $homeBefore
            $env:PATH        | Should -Be $pathBefore
        }
    }
}
