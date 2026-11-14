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

    $callParams = @{}
    if ($PSBoundParameters.ContainsKey('SID'))     { $callParams['SID']     = $SID  }
    if ($PSBoundParameters.ContainsKey('Verbose')) { $callParams['Verbose'] = $true }

    $result = Set-OracleEnv @callParams
    if ($result -and -not $result.Success) {
        Write-Host "[ERROR] $($result.Message)"
    }
}
