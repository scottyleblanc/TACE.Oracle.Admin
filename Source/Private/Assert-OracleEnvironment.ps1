#Requires -Version 7.6
<#
.SYNOPSIS
    Validates the Oracle environment before any RMAN operation is attempted.

.DESCRIPTION
    Validates that ORACLE_HOME is configured, that the resolved path exists on
    disk, and that the specified Oracle binary exists under ORACLE_HOME\bin.
    Also verifies the binary's Authenticode signature: hard-fails only on
    HashMismatch and TrustFailure (genuine tamper indicators). NotSigned is
    always expected — Oracle signs distribution archives, not individual
    executables.

    When -WalletAlias is specified, also validates that the alias can be
    resolved by tnsping.exe. tnsping is invoked via ProcessStartInfo (same
    pattern as RMAN). A non-zero exit code or a TNS- error in stdout is a
    hard failure (APSC-DV-002000).

    This helper is called by all public functions that invoke RMAN or any other
    Oracle binary. It throws a terminating error on any validation failure —
    callers cannot continue if the Oracle environment is invalid.

.PARAMETER OracleHome
    The ORACLE_HOME path to validate. Sourced from module config; treated as
    untrusted input and validated before use in path construction.

.PARAMETER Binary
    The Oracle binary name to verify under ORACLE_HOME\bin (e.g. 'rman.exe').
    Defaults to 'rman.exe'.

.PARAMETER WalletAlias
    Optional. When non-empty, tnsping.exe is invoked against this alias.
    A hard failure if the alias cannot be resolved or if tnsping.exe is not
    found under ORACLE_HOME\bin. tnsping stdout is scrubbed via
    Invoke-CredentialScrub before inclusion in any error message.

.OUTPUTS
    [string] — the fully resolved, validated binary path.

.NOTES

    [SEC] OracleHome is treated as untrusted input — validated before use in
    any path construction or process invocation.

    [SEC] Binary is resolved explicitly from OracleHome\bin — never from
    $env:PATH alone. The full resolved path is verified to exist on disk
    before being returned.

    [SEC] AD-023 — Authenticode signature checked via Get-AuthenticodeSignature.
    Hard failure on HashMismatch or TrustFailure — these indicate the binary was
    altered after signing and represent genuine tamper evidence. NotSigned is
    always expected; Oracle signs distribution archives (zip/jar), not individual
    executables. When Status is Valid the Subject must contain 'Oracle' — a valid
    cert from a different vendor indicates binary substitution.

    [SEC] AD-026 — WalletAlias validated by tnsping before RMAN invocation
    (APSC-DV-002000). tnsping stdout scrubbed via Invoke-CredentialScrub before
    any error message.

    [SEC] Environment variable $env:ORACLE_HOME is used only as a fallback
    default when OracleHome config value is empty. It is validated before use
    and never trusted without verification.
#>
# Private helper — extracted so unit tests can mock the tnsping invocation
# without needing real .exe files or .NET compiler support.
# Returns [PSCustomObject]@{ ExitCode; StdOut; StdErr }
function Invoke-TnspingProcess {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string]$TnspingPath,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string]$WalletAlias,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string]$OracleHome,
        [Parameter()] [ValidateRange(1, 300)] [int]$TimeoutSeconds = 30
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    #--------------------------------------------------------------
    # INVARIANTS
    #
    # PRE-CONDITIONS
    #   P1 TnspingPath, WalletAlias and OracleHome are non-empty strings.
    #       Type: Mandatory and ValidateNotNullOrEmpty.
    #   P2 TimeoutSeconds is between 1 and 300. It defaults to 30.
    #       Type: ValidateRange.
    #
    # SECURITY INVARIANTS
    #   [SEC] S1 ORACLE_HOME and PATH are set on the child process only. The current
    #       session environment is not changed, including after a timeout kill.
    #       Test: 'S1 child gets ORACLE_HOME and the session environment is unchanged',
    #       'S1, L2 kills a tnsping that runs past TimeoutSeconds and throws'.
    #   [SEC] S2 WalletAlias is passed as the process argument. It is a connection name,
    #       not a credential.
    #       Limitation: true by definition of a TNS alias. Nothing checks the value.
    #   [SEC] S3 Output is returned as captured, not scrubbed.
    #       Limitation: the caller scrubs it. See Assert-OracleEnvironment S7.
    #
    # POST-CONDITIONS
    #   R1 Returns an object with exactly ExitCode, StdOut and StdErr.
    #       Test: 'R1 returns exactly ExitCode, StdOut and StdErr'.
    #
    # EXECUTION INVARIANTS
    #   L1 Both output streams are read asynchronously before the wait, so a full stderr
    #       pipe cannot stall the process.
    #       Test: 'L1 a tnsping that floods stderr still completes'.
    #   L2 The wait is bounded by TimeoutSeconds. A tnsping still running then has its
    #       whole process tree killed, and the function throws 'timed out after N
    #       seconds and the process was killed'. A failed kill does not replace that error.
    #       Test: 'S1, L2 kills a tnsping that runs past TimeoutSeconds and throws'.
    #   L3 The process object is disposed on every path.
    #       Guard: the finally block.
    #   L4 The child PATH starts with OracleHome\bin, built with Join-Path and joined to
    #       the inherited PATH with [System.IO.Path]::PathSeparator.
    #       Test: 'L4 child PATH starts with OracleHome bin and the platform separator'.
    #--------------------------------------------------------------

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName               = $TnspingPath
    $psi.Arguments              = $WalletAlias
    $psi.UseShellExecute        = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.CreateNoWindow         = $true

    # [SEC] Child environment only (S1). The key is exactly 'PATH' — environment names
    # are case-sensitive off Windows (L4).
    $psi.EnvironmentVariables['ORACLE_HOME'] = $OracleHome
    $binDir    = Join-Path -Path $OracleHome -ChildPath 'bin'
    $childPath = $psi.EnvironmentVariables['PATH']
    $psi.EnvironmentVariables['PATH'] = if ([string]::IsNullOrEmpty($childPath)) { $binDir }
                                        else { $binDir + [System.IO.Path]::PathSeparator + $childPath }

    $proc = $null
    try {
        $proc = [System.Diagnostics.Process]::new()
        $proc.StartInfo = $psi
        $null = $proc.Start()

        # L1: drain both pipes before waiting. A synchronous ReadToEnd() on stdout blocks
        # until stdout closes, so a hung tnsping would never reach the timeout, and a full
        # stderr pipe would stall the child.
        $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
        $stderrTask = $proc.StandardError.ReadToEndAsync()

        if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
            # L2: kill the whole tree; a kill that fails because the process has just
            # exited must not replace the timeout error.
            try { $proc.Kill($true) } catch {
                Write-Verbose "[Invoke-TnspingProcess] KILL on tnsping failed at $([datetime]::UtcNow.ToString('o'))"
            }
            try { $null = $proc.WaitForExit(5000) } catch {
                Write-Verbose "[Invoke-TnspingProcess] WAIT on killed tnsping failed at $([datetime]::UtcNow.ToString('o'))"
            }
            throw "tnsping timed out after $TimeoutSeconds seconds and the process was killed"
        }

        # The untimed wait also waits for the redirected streams to finish.
        $null = $proc.WaitForExit()

        return [PSCustomObject]@{
            ExitCode = $proc.ExitCode
            StdOut   = $stdoutTask.GetAwaiter().GetResult()
            StdErr   = $stderrTask.GetAwaiter().GetResult()
        }
    }
    finally {
        if ($null -ne $proc) { $proc.Dispose() }
    }
}

function Assert-OracleEnvironment {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$OracleHome,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Binary = 'rman.exe',

        [Parameter()]
        [string]$WalletAlias = ''
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    #--------------------------------------------------------------
    # INVARIANTS
    #
    # PRE-CONDITIONS
    #   P1 OracleHome is a string, and may be empty.
    #       Type: Mandatory and AllowEmptyString.
    #   P2 Binary is a non-empty file name. It defaults to rman.exe.
    #       Type: ValidateNotNullOrEmpty.
    #   P3 An empty or blank WalletAlias means no alias check is made.
    #       Guard: the IsNullOrWhiteSpace check before the tnsping step.
    #
    # SECURITY INVARIANTS
    #   [SEC] S1 OracleHome, from the config or the environment, is checked to exist
    #       before it is used in a path.
    #       Test: 'Throws when OracleHome does not exist on disk'.
    #   [SEC] S2 The binary is resolved from OracleHome\bin, never from PATH.
    #       Test: 'Returned binary path is rooted under the validated OracleHome — never from PATH'.
    #   [SEC] S3 A signature status of HashMismatch or TrustFailure, or a valid signature
    #       that is not Oracle's, stops the call.
    #       Test: 'Throws when Authenticode status is HashMismatch',
    #       'Throws when Authenticode status is TrustFailure',
    #       'Throws when Authenticode signer subject does not contain Oracle'.
    #   [SEC] S4 An unsigned binary is accepted. Oracle does not sign individual
    #       executables, so the signature check cannot detect a replaced Oracle binary,
    #       whether the replacement came from a patch or from tampering.
    #       Limitation: accepted. Detecting replacement needs a recorded baseline, which
    #       is outside this module's current scope.
    #   [SEC] S5 No parameter turns the signature check off.
    #       Test: 'No bypass parameter exists — SkipSignatureCheck, Force, and SkipOwnerCheck are absent'.
    #   [SEC] S6 A WalletAlias is resolved with tnsping before the function returns.
    #       Test: 'Throws when tnsping exits with a non-zero exit code',
    #       'Throws when tnsping stdout contains a TNS-NNNNN error code'.
    #   [SEC] S7 tnsping output is scrubbed before it is placed in an error message.
    #       Test: 'Error message on tnsping failure contains no credential fragments'.
    #   [SEC] S8 The current session environment is not changed.
    #       Test: 'Current session environment is not modified when all checks pass'.
    #   [SEC] S9 tnsping.exe is checked to exist, but its signature is not checked.
    #       Limitation: accepted. tnsping.exe is unsigned like every Oracle binary (S4),
    #       so the same check would not detect a replacement.
    #
    # POST-CONDITIONS
    #   R1 Returns the full path of the validated binary.
    #       Test: 'Returns the binary path when all checks pass (valid Oracle signature, SYSTEM owner)'.
    #   T1 Every throw starts with 'Oracle environment validation failed:'.
    #       Test: none yet.
    #   T2 The error for a missing OracleHome names the two ways to set one: OracleHome in
    #       Config\OracleBackup.json, or the ORACLE_HOME environment variable.
    #       Test: 'T2 the missing-home error names the config file and ORACLE_HOME'.
    #
    # EXECUTION INVARIANTS
    #   L1 When OracleHome is empty it falls back to the ORACLE_HOME environment variable.
    #       It returns only the binary path, always <home>\bin\<binary> (S2), so a caller
    #       recovers the validated home from that path.
    #       Guard: callers derive the home from the returned path. See Get-RmanBackupStatus
    #       L3 and Remove-RmanObsoleteBackup L2.
    #--------------------------------------------------------------

    try {
        # Resolve OracleHome — use config value; fall back to environment variable
        # as untrusted input only if config is empty
        $resolvedHome = $OracleHome

        if ([string]::IsNullOrWhiteSpace($resolvedHome)) {
            Write-Verbose '[Assert-OracleEnvironment] OracleHome not in config — checking $env:ORACLE_HOME'

            # [SEC] $env:ORACLE_HOME is untrusted input — assigned here but not used
            # in any path construction until validated by Test-Path below.
            $resolvedHome = $env:ORACLE_HOME

            if ([string]::IsNullOrWhiteSpace($resolvedHome)) {
                throw 'OracleHome is not configured. Set OracleHome in Config\OracleBackup.json, or set the ORACLE_HOME environment variable.'
            }
        }

        # Validate OracleHome path exists on disk
        if (-not (Test-Path -Path $resolvedHome -PathType Container)) {
            throw "OracleHome path does not exist on disk: '$resolvedHome'"
        }

        # Resolve binary path explicitly from OracleHome\bin — never from PATH
        $binaryPath = Join-Path -Path $resolvedHome -ChildPath 'bin' -AdditionalChildPath $Binary

        if (-not (Test-Path -Path $binaryPath -PathType Leaf)) {
            throw "Oracle binary '$Binary' not found at expected path: '$binaryPath'"
        }

        # [SEC] AD-023 — Authenticode integrity check.
        # Hard-fail ONLY on statuses that indicate the binary was altered after signing.
        # NotSigned is always expected — Oracle signs distribution archives, not individual
        # executables. No bypass parameter exists.
        $sig = Get-AuthenticodeSignature -FilePath $binaryPath
        if ($sig.Status -in @('HashMismatch', 'TrustFailure')) {
            throw "RMAN binary integrity check failed: Authenticode signature status is '$($sig.Status)'. The binary may have been tampered with. Verify the Oracle installation is intact."
        }
        if ($sig.Status -eq 'Valid' -and $sig.SignerCertificate.Subject -notmatch 'Oracle') {
            throw "RMAN binary integrity check failed: Authenticode signer '$($sig.SignerCertificate.Subject)' does not contain 'Oracle'. Binary may have been replaced."
        }

        Write-Verbose "[Assert-OracleEnvironment] Oracle environment validated. Binary: $binaryPath"

        # [SEC] AD-026 — WalletAlias validation via tnsping.
        # When WalletAlias is provided, validate that the alias resolves before
        # RMAN is invoked. tnsping output is scrubbed before inclusion in any message.
        if (-not [string]::IsNullOrWhiteSpace($WalletAlias)) {
            Write-Verbose "[Assert-OracleEnvironment] Validating wallet alias '$WalletAlias' via tnsping"

            $tnspingPath = Join-Path -Path $resolvedHome -ChildPath 'bin' -AdditionalChildPath 'tnsping.exe'
            if (-not (Test-Path -Path $tnspingPath -PathType Leaf)) {
                throw "tnsping.exe not found at expected path: '$tnspingPath'. Cannot validate wallet alias '$WalletAlias'."
            }

            $tnspingParams = @{
                TnspingPath = $tnspingPath
                WalletAlias = $WalletAlias
                OracleHome  = $resolvedHome
            }
            $tnsResult = Invoke-TnspingProcess @tnspingParams

            # [SEC] Scrub tnsping output before inclusion in any error message
            $tnsOutScrubbed = Invoke-CredentialScrub -Content $tnsResult.StdOut
            $tnsErrScrubbed = Invoke-CredentialScrub -Content $tnsResult.StdErr

            if ($tnsResult.ExitCode -ne 0 -or
                $tnsResult.StdOut -match 'TNS-\d{5}' -or
                $tnsResult.StdErr -match 'TNS-\d{5}') {
                $detail = if ($tnsResult.StdOut -match 'TNS-\d{5}') { $tnsOutScrubbed.Trim() }
                          elseif ($tnsResult.StdErr -match 'TNS-\d{5}') { $tnsErrScrubbed.Trim() }
                          else { "tnsping exit code: $($tnsResult.ExitCode)" }
                throw "TNS alias '$WalletAlias' could not be resolved by tnsping: $detail"
            }

            Write-Verbose "[Assert-OracleEnvironment] Wallet alias '$WalletAlias' resolved successfully by tnsping"
        }

        return $binaryPath
    }
    catch {
        throw "Oracle environment validation failed: $($PSItem.Exception.Message)"
    }
}
