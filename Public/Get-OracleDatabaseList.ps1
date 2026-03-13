#Requires -Version 7.0

function Get-OracleDatabaseList {
    <#
    .SYNOPSIS
        Returns a list of Oracle database instances installed on the local Windows host.

    .DESCRIPTION
        Discovers Oracle databases by querying Windows services named OracleService<SID>.
        Derives ORACLE_HOME and ORACLE_BASE for each instance from the service executable
        path (PathName property of Win32_Service). Returns both running and stopped
        instances. Does not require a live database connection or ORACLE_HOME to be set.

    .OUTPUTS
        PSCustomObject { Success [bool], Data [PSCustomObject[]], Message [string] }
        Data entries: { SID [string], Status [string], ServiceName [string], OracleHome [string], OracleBase [string] }
        OracleHome and OracleBase are $null if the service PathName cannot be parsed.

    .EXAMPLE
        $result = Get-OracleDatabaseList
        if ($result.Success) { $result.Data | Format-Table }

    .NOTES
        Copyright © TACE Data Management Inc.
        Module  : TACE.OracleAdmin
        Version : 0.1.3
    #>
    [CmdletBinding()]
    param()

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    try {
        Write-Verbose "[Get-OracleDatabaseList] Querying Windows services at $(Get-Date -Format u)"

        $services = @(Get-CimInstance -ClassName Win32_Service -Filter "Name LIKE 'OracleService%'" -ErrorAction SilentlyContinue)

        if ($services.Count -eq 0) {
            return [PSCustomObject]@{
                Success = $true
                Data    = @()
                Message = 'No Oracle database services found on this host.'
            }
        }

        $databases = @($services | ForEach-Object {
            # PathName may be quoted ("C:\...\bin\ORACLE.EXE" args) or unquoted
            $exePath = if ($_.PathName -match '^"([^"]+)"') {
                $Matches[1]
            } elseif (-not [string]::IsNullOrWhiteSpace($_.PathName)) {
                ($_.PathName -split '\s+')[0]
            } else {
                $null
            }

            # ORACLE_HOME is two levels above the executable: strip \bin\ORACLE.EXE
            $oracleHome = if ($null -ne $exePath) {
                $binDir = Split-Path -Parent $exePath
                if ($null -ne $binDir) { Split-Path -Parent $binDir } else { $null }
            } else {
                $null
            }

            # ORACLE_BASE is three levels above ORACLE_HOME: strip \product\{version}\{home}
            $oracleBase = if ($null -ne $oracleHome) {
                $p = Split-Path -Parent $oracleHome   # strip home name
                $p = Split-Path -Parent $p             # strip version
                if ($null -ne $p) { Split-Path -Parent $p } else { $null }  # strip 'product'
            } else {
                $null
            }

            [PSCustomObject]@{
                SID         = $_.Name -replace '^OracleService', ''
                Status      = $_.State
                ServiceName = $_.Name
                OracleHome  = $oracleHome
                OracleBase  = $oracleBase
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
