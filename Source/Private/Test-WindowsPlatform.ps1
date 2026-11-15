#Requires -Version 7.6
<#
.SYNOPSIS
    Reports whether the module is running on Windows.

.DESCRIPTION
    Returns the value of $IsWindows. Functions that support only Windows call this
    for their platform check (rule C-07) instead of reading $IsWindows directly.

.OUTPUTS
    [bool] — $true on Windows, $false on every other platform.

.NOTES
    Exists so that unit tests can simulate another platform. $IsWindows is a
    read-only automatic variable and cannot be overridden in a test; this function
    can be mocked.
#>
function Test-WindowsPlatform {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    #--------------------------------------------------------------
    # INVARIANTS
    #
    # POST-CONDITIONS
    #   R1 Returns $IsWindows: $true on Windows and $false on every other platform.
    #       Test: 'R1 returns the value of IsWindows'.
    #--------------------------------------------------------------

    return [bool]$IsWindows
}
