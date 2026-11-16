#Requires -Version 7.6

function Set-OracleEnv {
    <#
    .SYNOPSIS
        Sets ORACLE_SID, ORACLE_HOME, and ORACLE_BASE for the current PowerShell session.

    .DESCRIPTION
        Sets ORACLE_SID, ORACLE_HOME, and ORACLE_BASE in the current session to values
        derived from the Oracle instance discovered on this host via Win32_Service (WMI).
        ORACLE_HOME and ORACLE_BASE are derived from the service executable path.

        If no SID is supplied and only one instance exists, it is selected
        automatically. If multiple instances exist, an interactive numbered
        menu is presented.

        If a SID is supplied, it is validated against discovered instances.
        If the matching service is not running, a warning is issued but the
        SID is still set.

        If ORACLE_HOME or ORACLE_BASE cannot be determined from the service executable
        path, a warning is issued for each but ORACLE_SID is still set.
        PATH is not modified — that is managed by the profile.
        This function is session-only; nothing is written to disk.

    .PARAMETER SID
        The Oracle SID to activate. Must match a SID discovered via OracleService*
        Windows services on this host. If omitted, the function prompts interactively.

    .OUTPUTS
        PSCustomObject { Success [bool], Data [PSCustomObject], Message [string] }
        Data on success: { SID [string], OracleHome [string], OracleBase [string], Applied [bool] }
        OracleHome and OracleBase are $null if they could not be determined from the service.
        Applied is $false under -WhatIf or a declined -Confirm: nothing was set, and the
        Message starts with 'WhatIf:'.

    .EXAMPLE
        Set-OracleEnv -SID ORCL

    .EXAMPLE
        Set-OracleEnv
        # Presents a menu when multiple instances are found.

    .NOTES
        Copyright © TACE Data Management Inc.
        Module  : TACE.Oracle.Admin
        Version : 0.2.2
        Profile alias: oraset
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Interactive: presents an instance menu and confirms the change at the terminal (rule C-31).')]
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
    #       Test: none yet.
    #   P2 A supplied SID matches an instance discovered on this host.
    #       Guard: the match check returns Success = $false when there is none.
    #       Test: 'Message lists valid SIDs'.
    #
    # SECURITY INVARIANTS
    #   [SEC] S1 The list of valid SIDs always comes from live discovery, never from a
    #       stored list.
    #       Guard: the Get-OracleDatabaseList call at the start of every run.
    #       Test: none yet.
    #   [SEC] S2 Only ORACLE_SID, ORACLE_HOME and ORACLE_BASE of the current session are
    #       changed. Nothing is written to disk, the registry or another process.
    #       Static: none yet.
    #   [SEC] S3 The catch block places the raw exception message in Message.
    #       Limitation: not scrubbed. Accepted because nothing in this function
    #       handles a credential.
    #
    # POST-CONDITIONS
    #   R1 Returns Success, Data and Message on every path, and never throws.
    #       Test: 'R1 returns exactly Success, Data and Message, without throwing, when <Path>'.
    #   R2 On success Data has SID, OracleHome, OracleBase and Applied.
    #       Test: 'Data.SID is a non-empty string on success',
    #       'Data.Applied is true when the variables are set'.
    #   R3 ORACLE_HOME and ORACLE_BASE are left unset when they cannot be determined, and
    #       a warning is written for each.
    #       Test: 'Does not set $env:ORACLE_HOME when OracleHome is null',
    #       'Does not set $env:ORACLE_BASE when OracleBase is null',
    #       'Emits warnings when OracleHome and OracleBase are null'.
    #   R4 A stopped service does not prevent the SID being set. A warning is written.
    #       Test: 'Sets $env:ORACLE_SID despite stopped service',
    #       'Emits a warning for a stopped service'.
    #   R5 On a failure path ORACLE_SID is not changed.
    #       Test: 'Does not set $env:ORACLE_SID'.
    #   R6 Under -WhatIf, or a declined -Confirm, no variable is set and the return is a
    #       preview: Success = $true, Data.Applied = $false, and a Message that starts
    #       with 'WhatIf:' (rule C-27).
    #       Test: 'R6 WhatIf sets no variable and returns a preview'.
    #
    # EXECUTION INVARIANTS
    #   L1 With no SID and more than one instance it prompts with Read-Host.
    #       Limitation: not suitable for unattended use. Pass -SID in automation.
    #   L2 User-facing lines are written with Write-Host, by design, even when called from
    #       a script.
    #       Limitation: an interactive function; the analyzer rule is suppressed on this
    #       function only (C-31). Moving the host output and menu into Invoke-OraEnv is
    #       recorded for Stack 3.
    #--------------------------------------------------------------

    try {
        $serviceWarning    = $null
        $oracleHomeWarning = $null
        $oracleBaseWarning = $null
        Write-Verbose "[Set-OracleEnv] Querying available Oracle instances at $(Get-Date -Format u)"

        $listResult = Get-OracleDatabaseList
        if (-not $listResult.Success) {
            return [PSCustomObject]@{
                Success = $false
                Data    = $null
                Message = "Unable to retrieve Oracle instance list: $($listResult.Message)"
            }
        }

        $databases = $listResult.Data

        if ($databases.Count -eq 0) {
            return [PSCustomObject]@{
                Success = $false
                Data    = $null
                Message = 'No Oracle database services found on this host. Cannot set ORACLE_SID.'
            }
        }

        # -- Resolve target SID --------------------------------------------------

        if (-not $PSBoundParameters.ContainsKey('SID')) {

            if ($databases.Count -eq 1) {
                $SID = $databases[0].SID
                Write-Host "[Set-OracleEnv] One instance found. Using SID: $SID"
            }
            else {
                Write-Host '[Set-OracleEnv] Available Oracle instances:'
                for ($i = 0; $i -lt $databases.Count; $i++) {
                    Write-Host "  [$($i + 1)] $($databases[$i].SID)"
                }

                $raw = Read-Host "Enter selection (1-$($databases.Count))"
                $index = 0
                if (-not [int]::TryParse($raw, [ref]$index) -or $index -lt 1 -or $index -gt $databases.Count) {
                    return [PSCustomObject]@{
                        Success = $false
                        Data    = $null
                        Message = "Invalid selection '$raw'. Enter a number between 1 and $($databases.Count)."
                    }
                }

                $SID = $databases[$index - 1].SID
            }
        }
        else {
            # Validate the supplied SID against discovered instances
            $match = @($databases | Where-Object { $PSItem.SID -eq $SID })

            if ($match.Count -eq 0) {
                $validList = ($databases | ForEach-Object { $PSItem.SID }) -join ', '
                return [PSCustomObject]@{
                    Success = $false
                    Data    = $null
                    Message = "SID '$SID' not found on this host. Valid options: $validList"
                }
            }
        }

        # Check service status, ORACLE_HOME, and ORACLE_BASE for the resolved SID
        $resolved = @($databases | Where-Object { $PSItem.SID -eq $SID })
        if ($resolved.Count -gt 0 -and $resolved[0].Status -ne 'Running') {
            $serviceWarning = "[Set-OracleEnv] OracleService$SID is $($resolved[0].Status)."
        }
        if ($resolved.Count -gt 0 -and $null -eq $resolved[0].OracleHome) {
            $oracleHomeWarning = "[Set-OracleEnv] ORACLE_HOME could not be determined for SID '$SID' — set it manually."
        }
        if ($resolved.Count -gt 0 -and $null -eq $resolved[0].OracleBase) {
            $oracleBaseWarning = "[Set-OracleEnv] ORACLE_BASE could not be determined for SID '$SID' — set it manually."
        }

        # -- Apply ---------------------------------------------------------------

        # One ShouldProcess call, so -Confirm prompts once. Its answer decides both the
        # writes below and which result is returned (C-27).
        $applied = $PSCmdlet.ShouldProcess('ORACLE_SID', "Set to '$SID'")
        if ($applied) {
            $env:ORACLE_SID = $SID
            Write-Verbose "[Set-OracleEnv] ORACLE_SID set to '$SID' at $(Get-Date -Format u)"
            Write-Host "ORACLE_SID set to '$SID'"

            if ($null -ne $resolved[0].OracleHome) {
                $env:ORACLE_HOME = $resolved[0].OracleHome
                Write-Verbose "[Set-OracleEnv] ORACLE_HOME set to '$($resolved[0].OracleHome)' at $(Get-Date -Format u)"
                if ($VerbosePreference -eq 'Continue') {
                    Write-Host "ORACLE_HOME set to '$($resolved[0].OracleHome)'"
                }
            }

            if ($null -ne $resolved[0].OracleBase) {
                $env:ORACLE_BASE = $resolved[0].OracleBase
                Write-Verbose "[Set-OracleEnv] ORACLE_BASE set to '$($resolved[0].OracleBase)' at $(Get-Date -Format u)"
                if ($VerbosePreference -eq 'Continue') {
                    Write-Host "ORACLE_BASE set to '$($resolved[0].OracleBase)'"
                }
            }

            if ($serviceWarning)    { Write-Warning $serviceWarning }
            if ($oracleHomeWarning) { Write-Warning $oracleHomeWarning }
            if ($oracleBaseWarning) { Write-Warning $oracleBaseWarning }
        }

        $message = if ($applied) { "ORACLE_SID set to '$SID'." }
                   else          { "WhatIf: would set ORACLE_SID to '$SID'." }

        return [PSCustomObject]@{
            Success = $true
            Data    = [PSCustomObject]@{
                SID        = $SID
                OracleHome = $resolved[0].OracleHome
                OracleBase = $resolved[0].OracleBase
                Applied    = $applied
            }
            Message = $message
        }
    }
    catch {
        return [PSCustomObject]@{
            Success = $false
            Data    = $null
            Message = "Set-OracleEnv failed: $($PSItem.Exception.Message)"
        }
    }
}
