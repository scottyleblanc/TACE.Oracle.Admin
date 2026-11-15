#Requires -Version 7.6
<#
.SYNOPSIS
    Invokes the RMAN executable with the supplied script content and returns
    captured stdout, stderr, and exit code.

.DESCRIPTION
    Core RMAN process invocation helper. Uses ProcessStartInfo with redirected
    stdin, stdout, and stderr. The RMAN script is written to the process stdin
    stream after start — credentials are never passed via ArgumentList.

    Three authentication modes are supported via parameter sets:

    OSAuth (default)
        rman target / — OS authentication. ORACLE_SID is set on the child
        process EnvironmentVariables collection only. No credentials are
        required or supplied.

    WalletAuth
        rman target /@<alias> — wallet authentication. The TNS alias is a
        connection descriptor, not a credential; it is safe to include in
        ArgumentList (AD-024). No ORACLE_SID is set.

    NamedCredential
        RMAN is started with no target argument. The CONNECT TARGET statement
        (including username, password, and service) is injected as the first
        stdin line. Plaintext extraction happens inline at the
        StandardInput.WriteLine boundary using ConvertFrom-SecureStringToPlaintext
        — it is never assigned to a named variable (AD-025, APSC-DV-000160).

    stdout and stderr are scrubbed for credential fragments before being
    returned or written to any output stream.

.PARAMETER RmanBinaryPath
    Fully resolved, validated path to the RMAN executable.
    Must be provided by Assert-OracleEnvironment — never resolved internally.

.PARAMETER RmanScript
    The RMAN script content to write to stdin. Must not contain plaintext
    passwords — OS auth and wallet auth produce no credential material here.

.PARAMETER OracleHome
    The ORACLE_HOME value to set on the child process environment.

.PARAMETER OracleSid
    [OSAuth] The ORACLE_SID value to set on the child process environment.
    Never set on the current session.

.PARAMETER WalletAlias
    [WalletAuth] The TNS alias used in the rman target /@<alias> argument.
    This is a connection descriptor, not a credential — safe in ArgumentList
    (AD-024, AD-011).

.PARAMETER ServiceAlias
    [NamedCredential] The TNS service alias for the CONNECT TARGET statement.

.PARAMETER Credential
    [NamedCredential] The PSCredential supplying username and password for
    the CONNECT TARGET statement. Plaintext is extracted inline at the
    StandardInput.WriteLine boundary — never assigned to a variable.

.PARAMETER TimeoutSeconds
    Maximum seconds to wait for the RMAN process to complete.
    Default: 3600 (1 hour).

.OUTPUTS
    [PSCustomObject]@{
        ExitCode  [int]    — process exit code (not reliable for RMAN; check stdout)
        StdOut    [string] — scrubbed stdout content
        StdErr    [string] — scrubbed stderr content
        Success   [bool]   — $true if no ORA- or RMAN- errors found in stdout
        AuthMode  [string] — 'OSAuth' | 'WalletAuth' | 'NamedCredential'
    }

.NOTES

    [SEC] Credentials are never passed via ArgumentList — stdin only.
    [SEC] ORACLE_SID set on child process EnvironmentVariables only (OSAuth) — never $env:
    [SEC] WalletAlias is a TNS name, not a credential — safe in ArgumentList (AD-024).
    [SEC] NamedCredential password extracted inline at stdin write boundary — never a variable (AD-025).
    [SEC] stdout and stderr scrubbed for credential fragments before return.
    [SEC] Exception messages scrubbed before rethrow.
    [SEC] RmanBinaryPath must be pre-validated by Assert-OracleEnvironment.
    NLS_DATE_FORMAT set to 'YYYY-MM-DD HH24:MI:SS' on child process — ensures consistent
    date output in all RMAN sessions regardless of database NLS settings (AD-029).
#>
function Invoke-RmanProcess {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RmanBinaryPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RmanScript,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$OracleHome,

        # OSAuth — existing default: rman target / with ORACLE_SID on child env
        [Parameter(Mandatory, ParameterSetName = 'OSAuth')]
        [ValidateNotNullOrEmpty()]
        [string]$OracleSid,

        # WalletAuth — rman target /@alias; alias is a TNS name, not a credential
        [Parameter(Mandatory, ParameterSetName = 'WalletAuth')]
        [ValidateNotNullOrEmpty()]
        [string]$WalletAlias,

        # NamedCredential — CONNECT TARGET injected as first stdin line
        [Parameter(Mandatory, ParameterSetName = 'NamedCredential')]
        [ValidateNotNullOrEmpty()]
        [string]$ServiceAlias,

        [Parameter(Mandatory, ParameterSetName = 'NamedCredential')]
        [ValidateNotNull()]
        [PSCredential]$Credential,

        [Parameter()]
        [ValidateRange(1, 86400)]
        [int]$TimeoutSeconds = 3600
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    #--------------------------------------------------------------
    # INVARIANTS
    #
    # PRE-CONDITIONS
    #   P1 RmanBinaryPath, RmanScript and OracleHome are non-empty strings.
    #       Type: Mandatory and ValidateNotNullOrEmpty.
    #   P2 Exactly one authentication mode is chosen: OracleSid (OSAuth), WalletAlias
    #       (WalletAuth), or ServiceAlias with Credential (NamedCredential).
    #       Type: parameter sets.
    #   P3 TimeoutSeconds is between 1 and 86400.
    #       Type: ValidateRange.
    #   P4 RmanBinaryPath was validated by Assert-OracleEnvironment before this call.
    #       Limitation: the caller's duty. This function does not check the path again.
    #   P5 RmanScript holds no password.
    #       Limitation: cannot be checked here. Each caller builds its own script.
    #
    # SECURITY INVARIANTS
    #   [SEC] S1 No password is placed in the process argument list, in any mode.
    #       Test: none yet.
    #   [SEC] S2 In NamedCredential mode the password is extracted inline at the stdin
    #       write and is never assigned to a variable.
    #       Static: none yet.
    #   [SEC] S3 ORACLE_HOME, ORACLE_SID, PATH and NLS_DATE_FORMAT are set on the child
    #       process only. The current session environment is not changed.
    #       Test: 'OSAuth: ORACLE_SID is NOT set on the current session after the call',
    #       'OSAuth: ORACLE_HOME on the current session is unchanged after the call',
    #       'WalletAuth: ORACLE_SID is NOT set on the current session after the call',
    #       'NLS_DATE_FORMAT is set to YYYY-MM-DD HH24:MI:SS on the child process environment'.
    #   [SEC] S4 Stdout and stderr are scrubbed before they are returned.
    #       Test: none yet. The existing 'does not contain the plaintext password' tests
    #       run a fake RMAN that never echoes its input, so they pass without the scrub.
    #   [SEC] S5 An exception message is scrubbed before it is re-thrown.
    #       Test: none yet.
    #   [SEC] S6 Verbose output names the mode and the SID, alias or user name. It never
    #       holds a password.
    #       Test: none yet.
    #   [SEC] S7 The WalletAlias placed in the argument list is a connection name, not a
    #       credential.
    #       Limitation: true by definition of a TNS alias. Nothing checks the value.
    #
    # POST-CONDITIONS
    #   R1 Returns an object with exactly ExitCode, StdOut, StdErr, Success and AuthMode.
    #       Test: 'Returns a PSCustomObject with the correct five properties'.
    #   R2 Success is false when stdout or stderr holds an RMAN-nnnnn or ORA-nnnnn code.
    #       The exit code does not decide Success.
    #       Test: 'Returns Success=$false when output contains ORA- error code',
    #       'Returns Success=$false when output contains RMAN- error code'.
    #   R3 AuthMode is the name of the parameter set that was used.
    #       Test: 'AuthMode = OSAuth exactly for OS authentication',
    #       'AuthMode = WalletAuth exactly for wallet authentication',
    #       'AuthMode = NamedCredential exactly for named credential authentication'.
    #   T1 When RMAN runs past TimeoutSeconds the process is killed and the function throws
    #       'timed out after N seconds and the process was killed'.
    #       Test: 'T1, T2 kills an RMAN process that runs past TimeoutSeconds and throws'.
    #   T2 Every throw starts with 'RMAN process invocation failed:'.
    #       Test: 'T1, T2 kills an RMAN process that runs past TimeoutSeconds and throws'.
    #
    # EXECUTION INVARIANTS
    #   L1 Both output streams are read asynchronously before stdin is written, so a full
    #       stderr pipe cannot stall the process.
    #       Test: 'SEC-04: stderr content written by the RMAN process is captured in StdErr',
    #       'SEC-04: stdout is captured correctly when the RMAN process also writes to stderr'.
    #   L2 EXIT; is written after the script, and stdin is then closed.
    #       Guard: the three StandardInput calls that follow the script write.
    #   L3 The process object is disposed on every path.
    #       Guard: the finally block.
    #   L4 The child PATH starts with OracleHome\bin, built with Join-Path and joined to
    #       the inherited PATH with [System.IO.Path]::PathSeparator.
    #       Test: 'L4 child PATH starts with OracleHome bin and the platform separator'.
    #   L5 A timeout kills the whole process tree. A failed kill does not replace the
    #       timeout error, and the killed process is given 5 seconds to exit.
    #       Guard: the try blocks around Kill and WaitForExit in the timeout branch.
    #--------------------------------------------------------------

    $process = $null

    try {
        $authMode = $PSCmdlet.ParameterSetName

        Write-Verbose "[Invoke-RmanProcess] Starting RMAN (AuthMode: $authMode) at $(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ' -AsUTC)"

        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName               = $RmanBinaryPath
        $psi.UseShellExecute        = $false
        $psi.RedirectStandardInput  = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $psi.CreateNoWindow         = $true

        # [SEC] Set Oracle environment on child process only — never on current session
        $psi.EnvironmentVariables['ORACLE_HOME']     = $OracleHome
        # L4: OracleHome\bin first on the child PATH, joined with the platform separator.
        # The key is exactly 'PATH' — environment names are case-sensitive off Windows.
        $binDir    = Join-Path -Path $OracleHome -ChildPath 'bin'
        $childPath = $psi.EnvironmentVariables['PATH']
        $psi.EnvironmentVariables['PATH'] = if ([string]::IsNullOrEmpty($childPath)) { $binDir }
                                            else { $binDir + [System.IO.Path]::PathSeparator + $childPath }
        # AD-029: fix NLS_DATE_FORMAT on child process so all RMAN date output is
        # YYYY-MM-DD HH24:MI:SS — independent of database or session NLS settings.
        $psi.EnvironmentVariables['NLS_DATE_FORMAT'] = 'YYYY-MM-DD HH24:MI:SS'

        switch ($authMode) {
            'OSAuth' {
                # [SEC] ORACLE_SID set on child process only — never $env:ORACLE_SID
                $psi.EnvironmentVariables['ORACLE_SID'] = $OracleSid
                $psi.Arguments = 'target /'
                Write-Verbose "[Invoke-RmanProcess] OSAuth: SID='$OracleSid'"
            }
            'WalletAuth' {
                # [SEC] AD-024: WalletAlias is a TNS name (connection descriptor),
                # not a credential — safe to include in ArgumentList.
                # No ORACLE_SID is set — wallet provides the connection target.
                $psi.Arguments = "target /@$WalletAlias"
                Write-Verbose "[Invoke-RmanProcess] WalletAuth: alias='$WalletAlias'"
            }
            'NamedCredential' {
                # [SEC] AD-025: No target on command line. CONNECT TARGET is injected
                # as first stdin line. Plaintext extracted inline at the write boundary
                # via ConvertFrom-SecureStringToPlaintext — never assigned to a variable.
                $psi.Arguments = ''
                Write-Verbose "[Invoke-RmanProcess] NamedCredential: user='$($Credential.UserName)' service='$ServiceAlias'"
            }
        }

        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $psi

        $null = $process.Start()

        # [SEC-04] Start async reads of BOTH stdout and stderr before writing to stdin so
        # both pipes drain concurrently in the background. Sequential ReadToEnd() on stdout
        # blocks until stdout closes; if RMAN emits high-volume stderr (e.g. ORA-600 trace
        # dump) the stderr pipe buffer fills, the process blocks on stderr, stdout never
        # closes, and both sides wait until TimeoutSeconds kills the process. ReadToEndAsync()
        # runs on .NET thread pool threads — no PowerShell runspace is needed, eliminating
        # the runspace-in-thread-pool error that affects script block event handlers.
        # (APSC-DV-002000)
        $stdOutTask = $process.StandardOutput.ReadToEndAsync()
        $stdErrTask = $process.StandardError.ReadToEndAsync()

        # NamedCredential: inject CONNECT TARGET as first stdin line.
        # [SEC] Plaintext extracted inline at the StandardInput.WriteLine boundary —
        # ConvertFrom-SecureStringToPlaintext is called inline, never assigned to a variable.
        if ($authMode -eq 'NamedCredential') {
            $process.StandardInput.WriteLine(
                "CONNECT TARGET $($Credential.UserName)/$(ConvertFrom-SecureStringToPlaintext -SecureString $Credential.Password)@$ServiceAlias;"
            )
        }

        # Write RMAN script to stdin and close the stream
        $process.StandardInput.WriteLine($RmanScript)
        $process.StandardInput.WriteLine('EXIT;')
        $process.StandardInput.Close()

        $completed = $process.WaitForExit($TimeoutSeconds * 1000)

        if (-not $completed) {
            # T1, L5: kill the whole process tree, so no child keeps a pipe open. The
            # process can exit between the timeout and the kill, and Kill() then throws;
            # that must not replace the timeout error. Then allow it a moment to exit.
            try { $process.Kill($true) } catch {
                Write-Verbose "[Invoke-RmanProcess] KILL on rman failed at $([datetime]::UtcNow.ToString('o'))"
            }
            try { $null = $process.WaitForExit(5000) } catch {
                Write-Verbose "[Invoke-RmanProcess] WAIT on killed rman failed at $([datetime]::UtcNow.ToString('o'))"
            }
            throw "RMAN process timed out after $TimeoutSeconds seconds and the process was killed"
        }

        # A timed WaitForExit can return before the redirected streams are fully read;
        # the untimed call waits for that too.
        $null = $process.WaitForExit()

        $exitCode = $process.ExitCode

        # Collect async read results. Both tasks complete once the process closes its
        # output streams, which happens at exit. GetAwaiter().GetResult() returns
        # immediately here since WaitForExit() has already confirmed the process is done.
        $stdOut = $stdOutTask.GetAwaiter().GetResult()
        $stdErr = $stdErrTask.GetAwaiter().GetResult()

        # [SEC] Scrub stdout and stderr for credential fragments before storing or returning
        $stdOut = Invoke-CredentialScrub -Content $stdOut
        $stdErr = Invoke-CredentialScrub -Content $stdErr

        # Determine success by scanning for RMAN/ORA error codes in output
        # Exit code is not reliable for RMAN — output inspection is the correct approach
        $hasErrors = ($stdOut -match 'RMAN-\d{5}|ORA-\d{5}') -or
                     ($stdErr -match 'RMAN-\d{5}|ORA-\d{5}')

        Write-Verbose "[Invoke-RmanProcess] RMAN completed at $(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ' -AsUTC). ExitCode: $exitCode HasErrors: $hasErrors"

        return [PSCustomObject]@{
            ExitCode = $exitCode
            StdOut   = $stdOut
            StdErr   = $stdErr
            Success  = -not $hasErrors
            AuthMode = $authMode
        }
    }
    catch {
        # [SEC] Scrub exception message before rethrowing
        $safeMessage = Invoke-CredentialScrub -Content $PSItem.Exception.Message
        throw "RMAN process invocation failed: $safeMessage"
    }
    finally {
        if ($null -ne $process) {
            $process.Dispose()
        }
    }
}

<#
.SYNOPSIS
    Scrubs potential credential fragments from a string.

.DESCRIPTION
    Private helper called by Invoke-RmanProcess to sanitise stdout, stderr,
    and exception messages before they are stored, returned, or logged.

    Patterns scrubbed:
    - RMAN connection strings containing '/' (user/password@alias)
    - Sequences that look like passwords adjacent to @ or / delimiters

.NOTES
    [SEC] This is a best-effort scrub — not a guarantee. The primary defence
    is never placing credentials in command-line arguments in the first place.

    TODO: [SEC] Expand scrub patterns as new credential formats are encountered
    during integration testing against real RMAN output.
#>
function Invoke-CredentialScrub {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Content
    )

    #--------------------------------------------------------------
    # INVARIANTS
    #
    # PRE-CONDITIONS
    #   P1 Content is a string, and may be empty.
    #       Type: Mandatory and AllowEmptyString.
    #
    # SECURITY INVARIANTS
    #   [SEC] S1 The password in every user/password@service pattern is replaced with
    #       ***SCRUBBED***. The user name and the service name are kept.
    #       Test: 'Invoke-CredentialScrub scrubs credential fragment matching user/pass@service'.
    #   [SEC] S2 A credential in any other format passes through unchanged.
    #       Limitation: one pattern only. The main defence is that a credential is never
    #       placed where it could be echoed.
    #
    # POST-CONDITIONS
    #   R1 Empty content is returned unchanged.
    #       Test: 'Invoke-CredentialScrub handles empty string without error'.
    #   R2 Content with no matching pattern is returned unchanged.
    #       Test: 'Invoke-CredentialScrub returns clean content unchanged'.
    #--------------------------------------------------------------

    if ([string]::IsNullOrEmpty($Content)) { return $Content }

    # Scrub patterns: RMAN catalog connect strings (user/password@service)
    # Requires @service suffix to be present — avoids matching dates (02/27),
    # OS error labels (O/S), version strings, and Windows path separators.
    $scrubbed = $Content -replace '(\w+)/([^@\s]+)@(\S+)', '$1/***SCRUBBED***@$3'

    return $scrubbed
}
