#Requires -Version 7.0
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
    param(
        [Parameter(Mandatory)] [string]$TnspingPath,
        [Parameter(Mandatory)] [string]$WalletAlias,
        [Parameter(Mandatory)] [string]$OracleHome
    )

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName               = $TnspingPath
    $psi.Arguments              = $WalletAlias
    $psi.UseShellExecute        = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.CreateNoWindow         = $true
    $psi.EnvironmentVariables['ORACLE_HOME'] = $OracleHome
    $psi.EnvironmentVariables['PATH']        = "$OracleHome\bin;$($psi.EnvironmentVariables['PATH'])"

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $proc = $null
    try {
        $proc = [System.Diagnostics.Process]::new()
        $proc.StartInfo = $psi
        $null = $proc.Start()
        $stdout = $proc.StandardOutput.ReadToEnd()
        $stderr = $proc.StandardError.ReadToEnd()
        $null   = $proc.WaitForExit(30000)
        return [PSCustomObject]@{
            ExitCode = $proc.ExitCode
            StdOut   = $stdout
            StdErr   = $stderr
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
                throw 'OracleHome is not configured. Set it via Set-OracleBackupConfig -OracleHome <path>.'
            }
        }

        # Validate OracleHome path exists on disk
        if (-not (Test-Path -Path $resolvedHome -PathType Container)) {
            throw "OracleHome path does not exist on disk: '$resolvedHome'"
        }

        # Resolve binary path explicitly from OracleHome\bin — never from PATH
        $binaryPath = Join-Path $resolvedHome 'bin' $Binary

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

            $tnspingPath = Join-Path $resolvedHome 'bin' 'tnsping.exe'
            if (-not (Test-Path -Path $tnspingPath -PathType Leaf)) {
                throw "tnsping.exe not found at expected path: '$tnspingPath'. Cannot validate wallet alias '$WalletAlias'."
            }

            $tnsResult = Invoke-TnspingProcess `
                -TnspingPath $tnspingPath `
                -WalletAlias $WalletAlias `
                -OracleHome  $resolvedHome

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
