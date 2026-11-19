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
        automatically. If several instances exist, it returns Success = $false with
        a Message that lists them; pass -SID to choose one. It never prompts and never
        writes to the host, so it is safe in scripts and automation. Invoke-OraEnv is
        the interactive wrapper: it shows a menu and reports the result at the terminal.

        If a SID is supplied, it is validated against discovered instances.
        If the matching service is not running, a warning is issued but the
        SID is still set.

        If ORACLE_HOME or ORACLE_BASE cannot be determined from the service executable
        path, a warning is issued for each but ORACLE_SID is still set.
        PATH is not modified — that is managed by the profile.
        This function is session-only; nothing is written to disk.

    .PARAMETER SID
        The Oracle SID to activate. Must match a SID discovered via OracleService*
        Windows services on this host. Required when more than one instance exists.

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
        # Uses the only instance on this host. With several, returns Success = $false
        # and lists them.

    .NOTES
        Copyright © TACE Data Management Inc.
        Module  : TACE.Oracle.Admin
        Version : 0.2.8
        For the interactive menu use Invoke-OraEnv (aliases oraset, oraenv).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
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
    #   P2 A supplied SID matches an instance discovered on this host.
    #       Guard: the match check returns Success = $false when there is none.
    #       Test: 'P2 Message lists valid SIDs'.
    #
    # SECURITY INVARIANTS
    #   [SEC] S1 The list of valid SIDs always comes from live discovery, never from a
    #       stored list.
    #       Guard: the Get-OracleDatabaseList call at the start of every run.
    #       Test: 'S1 every call discovers the instances afresh; nothing is remembered'.
    #   [SEC] S2 Only ORACLE_SID, ORACLE_HOME and ORACLE_BASE of the current session are
    #       changed. Nothing is written to disk, the registry or another process.
    #       Static: 'Set-OracleEnv S2 changes only ORACLE_SID, ORACLE_HOME and ORACLE_BASE, and writes nothing to disk, the registry or another process'.
    #   [SEC] S3 The catch block scrubs the exception message before it is placed in
    #       Message (rule S-07).
    #       Guard: Invoke-CredentialScrub in the catch block.
    #       Static: 'Set-OracleEnv S3 reads exception text only through Invoke-CredentialScrub'.
    #
    # POST-CONDITIONS
    #   R1 Returns Success, Data and Message on every path, and never throws.
    #       Test: 'R1 returns exactly Success, Data and Message, without throwing, when <Path>'.
    #   R2 On success Data has SID, OracleHome, OracleBase and Applied.
    #       Test: 'R2 Data.SID is a non-empty string on success',
    #       'R2 Data.Applied is true when the variables are set'.
    #   R3 ORACLE_HOME and ORACLE_BASE are left unset when they cannot be determined, and
    #       a warning is written for each.
    #       Test: 'R3 does not set $env:ORACLE_HOME when OracleHome is null',
    #       'R3 does not set $env:ORACLE_BASE when OracleBase is null',
    #       'R3 emits warnings when OracleHome and OracleBase are null'.
    #   R4 A stopped service does not prevent the SID being set. A warning is written.
    #       Test: 'R4 sets $env:ORACLE_SID despite stopped service',
    #       'R4 emits a warning for a stopped service'.
    #   R5 On a failure path ORACLE_SID is not changed.
    #       Test: 'R5 does not set $env:ORACLE_SID'.
    #   R6 Under -WhatIf, or a declined -Confirm, no variable is set and the return is a
    #       preview: Success = $true, Data.Applied = $false, and a Message that starts
    #       with 'WhatIf:' (rule C-27).
    #       Test: 'R6 WhatIf sets no variable and returns a preview'.
    #   R7 With no SID and more than one instance it sets nothing and returns
    #       Success = $false, with a Message that names every SID found and asks for -SID.
    #       Test: 'R7 several instances and no SID set nothing and list every SID'.
    #
    # EXECUTION INVARIANTS
    #   L3 It never prompts and never writes to the host: no Read-Host, no Write-Host.
    #       L1 (the Read-Host menu) and L2 (host output) are retired; both moved to
    #       Invoke-OraEnv.
    #       Static: 'Set-OracleEnv L3 calls neither Read-Host nor Write-Host'.
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
                Write-Verbose "[Set-OracleEnv] One instance found. Using SID '$SID'."
            }
            else {
                # R7: no prompt. Invoke-OraEnv shows the menu and calls back with -SID.
                $validList = ($databases | ForEach-Object { $PSItem.SID }) -join ', '
                return [PSCustomObject]@{
                    Success = $false
                    Data    = $null
                    Message = "$($databases.Count) Oracle instances found on this host: $validList. Pass -SID to choose one."
                }
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

            if ($null -ne $resolved[0].OracleHome) {
                $env:ORACLE_HOME = $resolved[0].OracleHome
                Write-Verbose "[Set-OracleEnv] ORACLE_HOME set to '$($resolved[0].OracleHome)' at $(Get-Date -Format u)"
            }

            if ($null -ne $resolved[0].OracleBase) {
                $env:ORACLE_BASE = $resolved[0].OracleBase
                Write-Verbose "[Set-OracleEnv] ORACLE_BASE set to '$($resolved[0].OracleBase)' at $(Get-Date -Format u)"
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
        $safeMessage = Invoke-CredentialScrub -Content $PSItem.Exception.Message
        return [PSCustomObject]@{
            Success = $false
            Data    = $null
            Message = "Set-OracleEnv failed: $safeMessage"
        }
    }
}
