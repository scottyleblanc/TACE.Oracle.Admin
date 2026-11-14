#Requires -Version 7.0

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
        Data on success: { SID [string], OracleHome [string], OracleBase [string] }
        OracleHome and OracleBase are $null if they could not be determined from the service.

    .EXAMPLE
        Set-OracleEnv -SID ORCL

    .EXAMPLE
        Set-OracleEnv
        # Presents a menu when multiple instances are found.

    .NOTES
        Copyright © TACE Data Management Inc.
        Module  : TACE.Oracle.Admin
        Version : 0.2.0
        Profile alias: oraset
    #>
    [CmdletBinding(SupportsShouldProcess)]
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
    #   P2 A supplied SID matches an instance discovered on this host.
    #       Guard: the match check returns Success = $false when there is none.
    #
    # SECURITY INVARIANTS
    #   [SEC] S1 The list of valid SIDs always comes from live discovery, never from a
    #       stored list.
    #       Guard: the Get-OracleDatabaseList call at the start of every run.
    #   [SEC] S2 Only ORACLE_SID, ORACLE_HOME and ORACLE_BASE of the current session are
    #       changed. Nothing is written to disk, the registry or another process.
    #       Static: none yet.
    #   [SEC] S3 The catch block places the raw exception message in Message.
    #       Limitation: not scrubbed. Accepted because nothing in this function
    #       handles a credential.
    #
    # POST-CONDITIONS
    #   R1 Returns Success, Data and Message on every path, and never throws.
    #       Test: 'Has Success property', 'Has Data property', 'Has Message property'.
    #   R2 On success Data has SID, OracleHome and OracleBase.
    #       Test: 'Data.SID is a non-empty string on success'.
    #   R3 ORACLE_HOME and ORACLE_BASE are left unset when they cannot be determined, and
    #       a warning is written for each.
    #       Test: 'Does not set $env:ORACLE_HOME when OracleHome is null',
    #       'Does not set $env:ORACLE_BASE when OracleBase is null'.
    #   R4 A stopped service does not prevent the SID being set. A warning is written.
    #       Test: 'Sets $env:ORACLE_SID despite stopped service'.
    #   R5 On a failure path ORACLE_SID is not changed.
    #       Test: 'Does not set $env:ORACLE_SID'.
    #   R6 Under -WhatIf no variable is set, but the return still reports Success with
    #       the message 'ORACLE_SID set to'.
    #       Limitation: the message is wrong under -WhatIf. Known defect.
    #
    # EXECUTION INVARIANTS
    #   L1 With no SID and more than one instance it prompts with Read-Host.
    #       Limitation: not suitable for unattended use. Pass -SID in automation.
    #   L2 User-facing lines are written with Write-Host, by design.
    #       Limitation: an interactive function. The analyzer rule is excluded for it.
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
            $match = @($databases | Where-Object { $_.SID -eq $SID })

            if ($match.Count -eq 0) {
                $validList = ($databases | ForEach-Object { $_.SID }) -join ', '
                return [PSCustomObject]@{
                    Success = $false
                    Data    = $null
                    Message = "SID '$SID' not found on this host. Valid options: $validList"
                }
            }
        }

        # Check service status, ORACLE_HOME, and ORACLE_BASE for the resolved SID
        $resolved = @($databases | Where-Object { $_.SID -eq $SID })
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

        if ($PSCmdlet.ShouldProcess('ORACLE_SID', "Set to '$SID'")) {
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

        return [PSCustomObject]@{
            Success = $true
            Data    = [PSCustomObject]@{
                SID        = $SID
                OracleHome = $resolved[0].OracleHome
                OracleBase = $resolved[0].OracleBase
            }
            Message = "ORACLE_SID set to '$SID'."
        }
    }
    catch {
        return [PSCustomObject]@{
            Success = $false
            Data    = $null
            Message = "Set-OracleEnv failed: $($_.Exception.Message)"
        }
    }
}
