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
    - NotSigned status does NOT cause failure (Oracle binaries are not signed)
    - HashMismatch status causes hard terminating failure (binary altered after signing)
    - TrustFailure status causes hard terminating failure (cert chain untrustworthy)
    - Non-Oracle signer subject causes hard terminating failure (binary substitution indicator)
    - File owner is NOT checked; domain-account-owned Oracle installs are normal
    - Exception from Get-AuthenticodeSignature propagates cleanly (no silent swallow)
    - No SkipSignatureCheck, Force, or SkipOwnerCheck bypass parameter exists
    - Error messages on integrity failure contain no credential fragments
    - Returned binary path is always rooted under the validated OracleHome
#>

#Requires -Version 7.6

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

        It 'P1 OracleHome is mandatory' {
            InModuleScope TACE.Oracle.Admin {
                $param = (Get-Command Assert-OracleEnvironment).Parameters['OracleHome']
                $isMandatory = @($param.Attributes |
                    Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory })
                $isMandatory.Count | Should -BeGreaterThan 0
            }
        }

        It 'P2 Binary must not be null or empty' {
            InModuleScope TACE.Oracle.Admin {
                $param = (Get-Command Assert-OracleEnvironment).Parameters['Binary']
                $notNullOrEmpty = @($param.Attributes |
                    Where-Object { $_ -is [System.Management.Automation.ValidateNotNullOrEmptyAttribute] })
                $notNullOrEmpty.Count | Should -BeGreaterThan 0
            }
        }

        It 'P2 Binary defaults to rman.exe — Get-AuthenticodeSignature called with rman.exe path when Binary is omitted' {
            $script:capturedPath = $null
            Mock -CommandName Get-AuthenticodeSignature -ModuleName TACE.Oracle.Admin -MockWith {
                $script:capturedPath = $FilePath
                [PSCustomObject]@{ Status = 'NotSigned'; SignerCertificate = $null }
            }
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeHome = $script:fakeOracleHome } {
                param($FakeHome)
                Assert-OracleEnvironment -OracleHome $FakeHome | Out-Null
            }
            $script:capturedPath | Should -Match 'rman\.exe$'
        }

        It 'P1 throws with a clear message when OracleHome is empty and env var is not set' {
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
            # Default mock: NotSigned, as every Oracle binary is — all checks pass
            Mock -CommandName Get-AuthenticodeSignature -ModuleName TACE.Oracle.Admin -MockWith {
                [PSCustomObject]@{ Status = 'NotSigned'; SignerCertificate = $null }
            }
        }

        # Case 1a: unsigned binary → returns binary path
        It 'R1 returns the binary path when all checks pass' {
            InModuleScope TACE.Oracle.Admin -Parameters @{
                FakeHome = $script:fakeOracleHome
                RmanPath = $script:fakeRmanPath
            } {
                param($FakeHome, $RmanPath)
                $result = Assert-OracleEnvironment -OracleHome $FakeHome
                $result | Should -Be $RmanPath
            }
        }

        # Case 1b: the other side of the signer check in S3 — a valid signature whose
        # subject contains 'Oracle' is not refused
        It 'Returns the binary path for a valid signature whose signer contains Oracle' {
            Mock -CommandName Get-AuthenticodeSignature -ModuleName TACE.Oracle.Admin -MockWith {
                [PSCustomObject]@{
                    Status            = 'Valid'
                    SignerCertificate = [PSCustomObject]@{ Subject = 'CN=Oracle America Inc' }
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
        It 'S3 throws when Authenticode status is TrustFailure' -Tag 'SEC' {
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
        It 'S3 throws when Authenticode status is HashMismatch' -Tag 'SEC' {
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
        It 'S3 throws when Authenticode signer subject does not contain Oracle' -Tag 'SEC' {
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

        # Case 5: user-owned file → passes; the owner is not checked
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

        It 'S1 throws when OracleHome does not exist on disk' -Tag 'SEC' {
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

    Context 'Throw prefix and ORACLE_HOME fallback' {

        BeforeAll {
            # A home with both binaries, for the tnsping failure path.
            $script:fullHome = Join-Path $TestDrive 'fullhome'
            $null = New-Item -Path (Join-Path $script:fullHome 'bin') -ItemType Directory -Force
            $null = New-Item -Path (Join-Path $script:fullHome 'bin' 'rman.exe') -ItemType File -Force
            $null = New-Item -Path (Join-Path $script:fullHome 'bin' 'tnsping.exe') -ItemType File -Force
        }

        BeforeEach {
            Mock -CommandName Get-AuthenticodeSignature -ModuleName TACE.Oracle.Admin -MockWith {
                [PSCustomObject]@{ Status = 'NotSigned'; SignerCertificate = $null }
            }
            Mock -CommandName Invoke-TnspingProcess -ModuleName TACE.Oracle.Admin -MockWith {
                [PSCustomObject]@{ ExitCode = 1; StdOut = 'TNS-03505: Failed to resolve name'; StdErr = '' }
            }
        }

        It 'T1 every throw starts with the validation prefix (<Case>)' -ForEach @(
            @{ Case = 'no home configured' }
            @{ Case = 'home does not exist' }
            @{ Case = 'binary missing' }
            @{ Case = 'signature HashMismatch' }
            @{ Case = 'tnsping fails' }
        ) {
            if ($Case -eq 'signature HashMismatch') {
                Mock -CommandName Get-AuthenticodeSignature -ModuleName TACE.Oracle.Admin -MockWith {
                    [PSCustomObject]@{ Status = 'HashMismatch'; SignerCertificate = [PSCustomObject]@{ Subject = 'CN=Oracle America Inc' } }
                }
            }
            $call = switch ($Case) {
                'no home configured'     { @{ OracleHome = '' } }
                'home does not exist'    { @{ OracleHome = (Join-Path $TestDrive 'missing-home') } }
                'binary missing'         { @{ OracleHome = $script:fakeOracleHome; Binary = 'absent.exe' } }
                'signature HashMismatch' { @{ OracleHome = $script:fakeOracleHome } }
                'tnsping fails'          { @{ OracleHome = $script:fullHome; WalletAlias = 'MY_ALIAS' } }
            }
            $saved = $env:ORACLE_HOME
            $env:ORACLE_HOME = ''
            try {
                $message = $null
                try {
                    InModuleScope TACE.Oracle.Admin -Parameters @{ Call = $call } {
                        param($Call)
                        Assert-OracleEnvironment @Call
                    }
                }
                catch { $message = $PSItem.Exception.Message }
            }
            finally {
                $env:ORACLE_HOME = $saved
            }
            $message | Should -BeLike 'Oracle environment validation failed: *'
        }

        It 'L1 an empty OracleHome falls back to ORACLE_HOME and returns the binary under its bin folder' {
            $saved = $env:ORACLE_HOME
            $env:ORACLE_HOME = $script:fakeOracleHome
            try {
                $result = InModuleScope TACE.Oracle.Admin { Assert-OracleEnvironment -OracleHome '' }
            }
            finally {
                $env:ORACLE_HOME = $saved
            }
            $result | Should -Be (Join-Path $script:fakeOracleHome 'bin' 'rman.exe')
        }
    }

    Context 'Security' {

        BeforeEach {
            Mock -CommandName Get-AuthenticodeSignature -ModuleName TACE.Oracle.Admin -MockWith {
                [PSCustomObject]@{ Status = 'NotSigned'; SignerCertificate = $null }
            }
        }

        It 'S2 returned binary path is rooted under the validated OracleHome — never from PATH' -Tag 'SEC' {
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

        It 'S5 no bypass parameter exists — SkipSignatureCheck, Force, and SkipOwnerCheck are absent' -Tag 'SEC' {
            InModuleScope TACE.Oracle.Admin {
                $keys = (Get-Command Assert-OracleEnvironment).Parameters.Keys
                $keys | Should -Not -Contain 'SkipSignatureCheck'
                $keys | Should -Not -Contain 'Force'
                $keys | Should -Not -Contain 'SkipOwnerCheck'
            }
        }

        It 'S8 the session environment is unchanged when all checks pass' -Tag 'SEC' {
            # Sentinels first: a before-and-after read proves nothing when an earlier test
            # has already left the value the call would set.
            $sentinel = & (Join-Path $PSScriptRoot '..' 'Set-EnvironmentSentinel.ps1')
            try {
                InModuleScope TACE.Oracle.Admin -Parameters @{ FakeHome = $script:fakeOracleHome } {
                    param($FakeHome)
                    Assert-OracleEnvironment -OracleHome $FakeHome | Out-Null
                }
            }
            finally {
                $changed = & (Join-Path $PSScriptRoot '..' 'Compare-EnvironmentSentinel.ps1') -Snapshot $sentinel
            }
            ($changed -join ', ') | Should -BeNullOrEmpty
        }
    }

    # ── WalletAlias tnsping validation ────────────────────────────────────────
    # Uses Mock -CommandName Invoke-TnspingProcess (private helper extracted in
    # Stage 9) — avoids Add-Type ConsoleApplication which is not supported on
    # .NET Core. All tnsping invocation behaviour is tested via the mock contract.

    Context 'WalletAlias tnsping validation' {

        BeforeAll {
            # Mock Get-AuthenticodeSignature — NotSigned, as every Oracle binary is; integrity checks pass
            Mock -CommandName Get-AuthenticodeSignature -ModuleName TACE.Oracle.Admin -MockWith {
                [PSCustomObject]@{ Status = 'NotSigned'; SignerCertificate = $null }
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
        It 'P3 returns binary path when WalletAlias is empty — tnsping not invoked' {
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
        It 'P3 treats whitespace-only WalletAlias as empty — tnsping not invoked' {
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
        It 'S6 throws when tnsping exits with a non-zero exit code' -Tag 'SEC' {
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
        It 'S6 throws when tnsping stdout contains a TNS-NNNNN error code' -Tag 'SEC' {
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
        It 'S7 a credential in tnsping stdout or stderr is scrubbed from the error message (<Stream>)' -Tag 'SEC' -ForEach @(
            @{ Stream = 'StdOut'; Out = 'TNS-12154: user/pass@service could not resolve'; Err = '' }
            @{ Stream = 'StdErr'; Out = ''; Err = 'TNS-12154: user/pass@service could not resolve' }
        ) {
            # The output must carry a TNS- code: only then is it placed in the message.
            $script:tnsOut = $Out
            $script:tnsErr = $Err
            Mock -CommandName Invoke-TnspingProcess -ModuleName TACE.Oracle.Admin -MockWith {
                [PSCustomObject]@{ ExitCode = 1; StdOut = $script:tnsOut; StdErr = $script:tnsErr }
            }
            InModuleScope TACE.Oracle.Admin -Parameters @{ FakeHome = $script:homeWithTnsping } {
                param($FakeHome)
                $msg = ''
                try { Assert-OracleEnvironment -OracleHome $FakeHome -WalletAlias 'MY_DB_ALIAS' }
                catch { $msg = $PSItem.Exception.Message }
                $msg | Should -Match 'TNS-12154'
                $msg | Should -Match 'SCRUBBED'
                $msg | Should -Not -Match 'user/pass@'
            }
        }

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
}
