#Requires -Version 7.6

function Invoke-OraEnv {
    <#
    .SYNOPSIS
        Interactive wrapper for Set-OracleEnv: shows an instance menu and reports the
        result at the terminal.

    .DESCRIPTION
        With -SID, calls Set-OracleEnv for that SID. Without it, discovers the instances
        on this host; when there is more than one it shows a numbered menu, reads the
        choice and calls Set-OracleEnv with the chosen SID. Set-OracleEnv validates the
        SID against a fresh discovery.

        On success it writes the Message from Set-OracleEnv to the host, and under
        -Verbose the ORACLE_HOME and ORACLE_BASE values that were set. On failure it
        writes one [ERROR] line. Nothing is written to the pipeline.

        Use Set-OracleEnv directly in scripts and automation: it never prompts and
        never writes to the host.

    .PARAMETER SID
        Passed through to Set-OracleEnv. If omitted and several instances exist, a
        numbered menu is shown.

    .EXAMPLE
        oraset
        # Shows a menu when several instances are found.

    .EXAMPLE
        Invoke-OraEnv -SID ORCL -Verbose

    .NOTES
        Copyright © TACE Data Management Inc.
        Module  : TACE.Oracle.Admin
        Version : 0.2.3
        Aliases : oraset, oraenv (declared by the [Alias()] attribute below; rule C-30)
    #>
    [CmdletBinding()]
    [OutputType([void])]
    [Alias('oraset', 'oraenv')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Interactive terminal wrapper: shows the instance menu and the result to the user (rule C-31).')]
    param(
        [Parameter(Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string] $SID
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    #--------------------------------------------------------------
    # INVARIANTS
    #
    # PRE-CONDITIONS
    #   P1 SID, when supplied, is a non-empty string.
    #       Type: ValidateNotNullOrEmpty.
    #       Test: 'P1 SID rejects an empty string'.
    #
    # SECURITY INVARIANTS
    #   [SEC] S2 It writes to the host only the instance menu, the Message returned by
    #       Set-OracleEnv, an [ERROR] line, and under -Verbose the ORACLE_HOME and
    #       ORACLE_BASE values that were set. S1 (only the Message) is retired: the menu
    #       moved here from Set-OracleEnv.
    #       Test: 'S2 writes only the menu, the Message and the verbose paths to the host'.
    #
    # POST-CONDITIONS
    #   R1 Nothing is written to the pipeline.
    #       Test: 'R1 does not write to the pipeline on success'.
    #   R2 When Set-OracleEnv fails, one [ERROR] line is written to the host.
    #       Test: 'R2 writes [ERROR] to host when Set-OracleEnv returns Success=$false'.
    #   R3 SID and -Verbose are passed through to Set-OracleEnv unchanged.
    #       Test: 'R3 calls Set-OracleEnv with the supplied SID',
    #       'R3 shows ORACLE_HOME and ORACLE_BASE on host when -Verbose is specified'.
    #   R4 With no SID and more than one instance it shows a numbered menu, reads the
    #       choice with Read-Host, and calls Set-OracleEnv with the chosen SID.
    #       Test: 'R4 several instances: shows a menu and calls Set-OracleEnv with the chosen SID'.
    #   R5 An invalid choice writes one [ERROR] line and does not call Set-OracleEnv.
    #       Test: 'R5 an invalid choice writes one [ERROR] line and sets nothing (<Choice>)'.
    #   R6 On success the Message returned by Set-OracleEnv is written to the host.
    #       Test: 'R6 on success writes the Message from Set-OracleEnv'.
    #   T1 An exception from Set-OracleEnv is not caught here.
    #       Limitation: Set-OracleEnv never throws (its R1), so none is expected.
    #
    # EXECUTION INVARIANTS
    #   L1 With no SID and more than one instance it prompts with Read-Host.
    #       Limitation: interactive by design. Use Set-OracleEnv -SID in automation.
    #--------------------------------------------------------------

    $callParams = @{}
    if ($PSBoundParameters.ContainsKey('SID')) {
        $callParams['SID'] = $SID
    }
    else {
        $list = Get-OracleDatabaseList
        # @() outside the if: an if statement returns an empty array as $null, and
        # .Count on $null throws under StrictMode.
        $instances = @(if ($list.Success) { $list.Data })
        if ($instances.Count -gt 1) {
            Write-Host '[Invoke-OraEnv] Oracle instances on this host:'
            for ($i = 0; $i -lt $instances.Count; $i++) {
                Write-Host "  [$($i + 1)] $($instances[$i].SID)"
            }
            $raw   = Read-Host "Enter selection (1-$($instances.Count))"
            $index = 0
            if (-not [int]::TryParse($raw, [ref]$index) -or $index -lt 1 -or $index -gt $instances.Count) {
                Write-Host "[ERROR] Invalid selection '$raw'. Enter a number between 1 and $($instances.Count)."
                return
            }
            $callParams['SID'] = $instances[$index - 1].SID
        }
        # One instance, none, or a failed discovery: Set-OracleEnv handles each and
        # returns the Message to show.
    }
    if ($PSBoundParameters.ContainsKey('Verbose')) { $callParams['Verbose'] = $true }

    $result = Set-OracleEnv @callParams
    if ($null -eq $result -or -not $result.Success) {
        $text = if ($null -eq $result) { 'Set-OracleEnv returned nothing.' } else { $result.Message }
        Write-Host "[ERROR] $text"
        return
    }

    Write-Host $result.Message
    if ($VerbosePreference -eq 'Continue' -and $null -ne $result.Data) {
        if ($null -ne $result.Data.OracleHome) { Write-Host "ORACLE_HOME set to '$($result.Data.OracleHome)'" }
        if ($null -ne $result.Data.OracleBase) { Write-Host "ORACLE_BASE set to '$($result.Data.OracleBase)'" }
    }
}
