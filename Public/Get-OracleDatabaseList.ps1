#Requires -Version 7.0

function Get-OracleDatabaseList {
    <#
    .SYNOPSIS
        Returns a list of Oracle database instances installed on the local Windows host.

    .DESCRIPTION
        Discovers Oracle databases by querying Windows services named OracleService<SID>.
        Returns both running and stopped instances. Does not require a live database
        connection or ORACLE_HOME to be set.

    .OUTPUTS
        PSCustomObject { Success [bool], Data [PSCustomObject[]], Message [string] }
        Data entries: { SID [string], Status [string], ServiceName [string] }

    .EXAMPLE
        $result = Get-OracleDatabaseList
        if ($result.Success) { $result.Data | Format-Table }

    .NOTES
        Copyright © TACE Data Management Inc.
        Module  : TACE.OracleAdmin
        Version : 0.1.0
    #>
    [CmdletBinding()]
    param()

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    try {
        Write-Verbose "[Get-OracleDatabaseList] Querying Windows services at $(Get-Date -Format u)"

        $services = @(Get-Service -Name 'OracleService*' -ErrorAction SilentlyContinue)

        if ($services.Count -eq 0) {
            return [PSCustomObject]@{
                Success = $true
                Data    = @()
                Message = 'No Oracle database services found on this host.'
            }
        }

        $databases = @($services | ForEach-Object {
            [PSCustomObject]@{
                SID         = $_.Name -replace '^OracleService', ''
                Status      = $_.Status.ToString()
                ServiceName = $_.Name
            }
        })

        Write-Verbose "[Get-OracleDatabaseList] Found $($databases.Count) instance(s)."

        return [PSCustomObject]@{
            Success = $true
            Data    = $databases
            Message = "Found $($databases.Count) Oracle database instance(s)."
        }
    }
    catch {
        return [PSCustomObject]@{
            Success = $false
            Data    = $null
            Message = "Failed to query Oracle database services: $($_.Exception.Message)"
        }
    }
}
