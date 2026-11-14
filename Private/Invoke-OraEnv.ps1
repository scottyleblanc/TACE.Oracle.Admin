#Requires -Version 7.0

function Invoke-OraEnv {
    <#
    .SYNOPSIS
        Interactive wrapper for Set-OracleEnv — suppresses pipeline output.

    .DESCRIPTION
        Calls Set-OracleEnv and discards the return object for clean interactive
        terminal output. On failure, writes the error message to the host.

        Use Set-OracleEnv directly when the return object is needed in scripts
        or automation.

    .PARAMETER SID
        Passed through to Set-OracleEnv. If omitted, interactive menu is presented.

    .NOTES
        Copyright © TACE Data Management Inc.
        Module  : TACE.Oracle.Admin
        Version : 0.2.0
        Alias   : oraset
    #>
    [CmdletBinding()]
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
    #
    # SECURITY INVARIANTS
    #   [SEC] S1 The only text it writes is the Message returned by Set-OracleEnv.
    #       Test: none yet. The existing security test checks one fixed message for
    #       password words; it does not show that nothing else is written.
    #
    # POST-CONDITIONS
    #   R1 Nothing is written to the pipeline.
    #       Test: 'Does not write to the pipeline on success'.
    #   R2 When Set-OracleEnv fails, one [ERROR] line is written to the host.
    #       Test: 'Writes [ERROR] to host when Set-OracleEnv returns Success=$false'.
    #   R3 SID and -Verbose are passed through to Set-OracleEnv unchanged.
    #       Test: 'Calls Set-OracleEnv with the supplied SID',
    #       'Shows ORACLE_HOME and ORACLE_BASE on host when -Verbose is specified'.
    #   T1 An exception from Set-OracleEnv is not caught here.
    #       Limitation: Set-OracleEnv never throws (its R1), so none is expected.
    #--------------------------------------------------------------

    $callParams = @{}
    if ($PSBoundParameters.ContainsKey('SID'))     { $callParams['SID']     = $SID  }
    if ($PSBoundParameters.ContainsKey('Verbose')) { $callParams['Verbose'] = $true }

    $result = Set-OracleEnv @callParams
    if ($result -and -not $result.Success) {
        Write-Host "[ERROR] $($result.Message)"
    }
}
