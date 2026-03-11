#Requires -Version 7.0

function Set-OracleEnv {
    <#
    .SYNOPSIS
        Sets ORACLE_SID for the current PowerShell session.

    .DESCRIPTION
        Sets the ORACLE_SID environment variable in the current session to a
        validated Oracle instance discovered on this host via Windows services.

        If no SID is supplied and only one instance exists, it is selected
        automatically. If multiple instances exist, an interactive numbered
        menu is presented.

        If a SID is supplied, it is validated against discovered instances.
        If the matching service is not running, a warning is issued but the
        SID is still set.

        ORACLE_HOME and PATH are not modified — those are managed by the profile.
        This function is session-only; nothing is written to disk.

    .PARAMETER SID
        The Oracle SID to activate. Must match a SID discovered via OracleService*
        Windows services on this host. If omitted, the function prompts interactively.

    .OUTPUTS
        PSCustomObject { Success [bool], Data [PSCustomObject], Message [string] }
        Data on success: { SID [string] }

    .EXAMPLE
        Set-OracleEnv -SID ORCL

    .EXAMPLE
        Set-OracleEnv
        # Presents a menu when multiple instances are found.

    .NOTES
        Copyright © TACE Data Management Inc.
        Module  : TACE.OracleAdmin
        Version : 0.1.0
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

    try {
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

            if ($match[0].Status -ne 'Running') {
                Write-Warning "[Set-OracleEnv] OracleService$SID is $($match[0].Status). ORACLE_SID will be set but the database may not be available."
            }
        }

        # -- Apply ---------------------------------------------------------------

        if ($PSCmdlet.ShouldProcess('ORACLE_SID', "Set to '$SID'")) {
            $env:ORACLE_SID = $SID
            Write-Verbose "[Set-OracleEnv] ORACLE_SID set to '$SID' at $(Get-Date -Format u)"
            Write-Host "[Set-OracleEnv] ORACLE_SID = $SID"
        }

        return [PSCustomObject]@{
            Success = $true
            Data    = [PSCustomObject]@{ SID = $SID }
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
