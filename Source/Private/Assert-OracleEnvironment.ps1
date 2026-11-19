#Requires -Version 7.6
<#
.SYNOPSIS
    Validates the Oracle environment before any RMAN operation is attempted.

.DESCRIPTION
    Validates that ORACLE_HOME is configured, that the resolved path exists on
    disk, and that the specified Oracle binary exists under ORACLE_HOME\bin.
    Also checks the binary's Authenticode signature. Oracle binaries are not
    signed, so NotSigned passes. The call stops on HashMismatch or TrustFailure,
    or on a valid signature whose signer is not Oracle.

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
    found under ORACLE_HOME\bin. tnsping output in an error message is scrubbed by
    the catch block, which passes every message through Invoke-CredentialScrub.

.OUTPUTS
    [string] — the fully resolved, validated binary path.

.NOTES

    [SEC] OracleHome is treated as untrusted input — validated before use in
    any path construction or process invocation.

    [SEC] Binary is resolved explicitly from OracleHome\bin — never from
    $env:PATH alone. The full resolved path is verified to exist on disk
    before being returned.

    [SEC] Authenticode signature checked via Get-AuthenticodeSignature. Oracle
    binaries are not signed, so NotSigned passes, and the check cannot detect a
    replaced unsigned binary. It stops the call on HashMismatch or TrustFailure,
    and on a valid signature whose subject does not contain 'Oracle'.

    [SEC] AD-026 — WalletAlias validated by tnsping before RMAN invocation
    (APSC-DV-002000). tnsping output reaches an error message only through the
    catch block's Invoke-CredentialScrub call.

    [SEC] Environment variable $env:ORACLE_HOME is used only as a fallback
    default when OracleHome config value is empty. It is validated before use
    and never trusted without verification.
#>
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
    #       Test: 'P1 OracleHome is mandatory',
    #       'P1 throws with a clear message when OracleHome is empty and env var is not set'.
    #   P2 Binary is a non-empty file name. It defaults to rman.exe.
    #       Type: ValidateNotNullOrEmpty.
    #       Test: 'P2 Binary must not be null or empty',
    #       'P2 Binary defaults to rman.exe — Get-AuthenticodeSignature called with rman.exe path when Binary is omitted'.
    #   P3 An empty or blank WalletAlias means no alias check is made.
    #       Guard: the IsNullOrWhiteSpace check before the tnsping step.
    #       Test: 'P3 returns binary path when WalletAlias is empty — tnsping not invoked',
    #       'P3 treats whitespace-only WalletAlias as empty — tnsping not invoked'.
    #
    # SECURITY INVARIANTS
    #   [SEC] S1 OracleHome, from the config or the environment, is checked to exist
    #       before it is used in a path.
    #       Test: 'S1 throws when OracleHome does not exist on disk'.
    #   [SEC] S2 The binary is resolved from OracleHome\bin, never from PATH.
    #       Test: 'S2 returned binary path is rooted under the validated OracleHome — never from PATH'.
    #   [SEC] S3 A signature status of HashMismatch or TrustFailure, or a valid signature
    #       that is not Oracle's, stops the call.
    #       Test: 'S3 throws when Authenticode status is HashMismatch',
    #       'S3 throws when Authenticode status is TrustFailure',
    #       'S3 throws when Authenticode signer subject does not contain Oracle'.
    #   [SEC] S4 An unsigned binary is accepted. Oracle binaries are not signed, so the
    #       signature check cannot detect a replaced Oracle binary, whether the
    #       replacement came from a patch or from tampering.
    #       Limitation: accepted. Detecting replacement needs a recorded baseline, which
    #       is outside this module's current scope.
    #   [SEC] S5 No parameter turns the signature check off.
    #       Test: 'S5 no bypass parameter exists — SkipSignatureCheck, Force, and SkipOwnerCheck are absent'.
    #   [SEC] S6 A WalletAlias is resolved with tnsping before the function returns.
    #       Test: 'S6 throws when tnsping exits with a non-zero exit code',
    #       'S6 throws when tnsping stdout contains a TNS-NNNNN error code'.
    #   [SEC] S7 tnsping output placed in an error message is scrubbed: it reaches the caller
    #       only through the catch block, which scrubs every message (S10).
    #       Test: 'S7 a credential in tnsping stdout or stderr is scrubbed from the error message (<Stream>)'.
    #   [SEC] S8 The current session environment is not changed.
    #       Test: 'S8 the session environment is unchanged when all checks pass'.
    #   [SEC] S9 tnsping.exe is checked to exist, but its signature is not checked.
    #       Limitation: accepted. tnsping.exe is unsigned like every Oracle binary (S4),
    #       so the same check would not detect a replacement.
    #   [SEC] S10 The catch block scrubs the exception message before it is re-thrown
    #       (rule S-07).
    #       Guard: Invoke-CredentialScrub in the catch block.
    #       Static: 'Assert-OracleEnvironment S10 reads exception text only through Invoke-CredentialScrub'.
    #
    # POST-CONDITIONS
    #   R1 Returns the full path of the validated binary.
    #       Test: 'R1 returns the binary path when all checks pass'.
    #   T1 Every throw starts with 'Oracle environment validation failed:'.
    #       Test: 'T1 every throw starts with the validation prefix (<Case>)'.
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
    #       Test: 'L1 an empty OracleHome falls back to ORACLE_HOME and returns the binary under its bin folder'.
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

        # [SEC] Authenticode check (S3, S4). Oracle binaries are not signed, so NotSigned
        # passes. Stop on a broken signature, or on a valid one from another signer.
        # No bypass parameter exists (S5).
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
        # RMAN is invoked. The catch block scrubs tnsping output in the error (S7).
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

            if ($tnsResult.ExitCode -ne 0 -or
                $tnsResult.StdOut -match 'TNS-\d{5}' -or
                $tnsResult.StdErr -match 'TNS-\d{5}') {
                $detail = if ($tnsResult.StdOut -match 'TNS-\d{5}') { $tnsResult.StdOut.Trim() }
                          elseif ($tnsResult.StdErr -match 'TNS-\d{5}') { $tnsResult.StdErr.Trim() }
                          else { "tnsping exit code: $($tnsResult.ExitCode)" }
                throw "TNS alias '$WalletAlias' could not be resolved by tnsping: $detail"
            }

            Write-Verbose "[Assert-OracleEnvironment] Wallet alias '$WalletAlias' resolved successfully by tnsping"
        }

        return $binaryPath
    }
    catch {
        $safeMessage = Invoke-CredentialScrub -Content $PSItem.Exception.Message
        throw "Oracle environment validation failed: $safeMessage"
    }
}
