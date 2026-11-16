#Requires -Version 7.6
<#
.SYNOPSIS
    Runs tnsping for a wallet alias and returns its exit code and output.

.DESCRIPTION
    Private helper for Assert-OracleEnvironment, which uses it to check that a wallet
    alias resolves before RMAN is started. Runs tnsping as a child process with
    ORACLE_HOME and PATH set on the child only, reads both output streams
    asynchronously, and kills the process tree if it runs past TimeoutSeconds.
    Kept separate so the unit tests can mock the tnsping call.

.PARAMETER TnspingPath
    Full path to tnsping, already resolved under OracleHome\bin by the caller.

.PARAMETER WalletAlias
    The TNS alias to resolve. Passed as the process argument.

.PARAMETER OracleHome
    ORACLE_HOME for the child process. OracleHome\bin is put first on the child PATH.

.PARAMETER TimeoutSeconds
    How long to wait before the process tree is killed. 1 to 300; defaults to 30.

.EXAMPLE
    Invoke-TnspingProcess -TnspingPath $tnspingPath -WalletAlias 'PROD_DB' -OracleHome $oracleHome

.OUTPUTS
    PSCustomObject with ExitCode, StdOut and StdErr.

.NOTES
    Copyright © TACE Data Management Inc.
    [SEC] Output is returned unscrubbed; Assert-OracleEnvironment scrubs it before it
    is placed in any error message.
#>function Invoke-TnspingProcess {
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
    #       Test: none yet.
    #   P2 TimeoutSeconds is between 1 and 300. It defaults to 30.
    #       Type: ValidateRange.
    #       Test: none yet.
    #
    # SECURITY INVARIANTS
    #   [SEC] S1 ORACLE_HOME and PATH are set on the child process only. The current
    #       session environment is not changed, including after a timeout kill.
    #       Test: 'S1 child gets ORACLE_HOME and the session environment is unchanged',
    #       'S1, L2 kills a tnsping that runs past TimeoutSeconds and throws'.
    #   [SEC] S2 WalletAlias is passed as the process argument. It is a connection name,
    #       not a credential.
    #       Limitation: nothing here checks the value. The public callers restrict it to
    #       letters, digits, _, . and - (Get-RmanBackupStatus S6,
    #       Remove-RmanObsoleteBackup S10).
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
    #       Test: none yet.
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
