#Requires -Version 7.0

function Get-OracleDatabaseList {
    <#
    .SYNOPSIS
        Returns a list of Oracle database instances on the local host.

    .DESCRIPTION
        Discovers Oracle databases using platform-appropriate discovery:

        Windows: queries Win32_Service (WMI) for OracleService* services.
          ORACLE_HOME and ORACLE_BASE are derived from the service executable path.

        Linux: parses /etc/oratab. ORACLE_HOME comes directly from the file;
          ORACLE_BASE is derived from ORACLE_HOME. Instance status is determined
          by checking for an ora_pmon_<SID> process. ServiceName is $null on Linux.

        Returns both running and stopped instances. Does not require a live
        database connection or ORACLE_HOME to be set.

    .PARAMETER Platform
        Platform to use for discovery. Defaults to automatic detection via
        $IsWindows / $IsLinux. Accepted values: Windows, Linux.
        Pass explicitly to override auto-detection (useful in tests).

    .OUTPUTS
        PSCustomObject { Success [bool], Data [PSCustomObject[]], Message [string] }
        Data entries: { SID [string], Status [string], ServiceName [string], OracleHome [string], OracleBase [string] }
        ServiceName is $null on Linux. OracleHome and OracleBase are $null if they
        cannot be determined.

    .EXAMPLE
        $result = Get-OracleDatabaseList
        if ($result.Success) { $result.Data | Format-Table }

    .NOTES
        Copyright © TACE Data Management Inc.
        Module  : TACE.OracleAdmin
        Version : 0.1.4
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $Platform = $(if ($IsWindows) { 'Windows' } elseif ($IsLinux) { 'Linux' } else { 'Unsupported' })
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    try {
        Write-Verbose "[Get-OracleDatabaseList] Querying Oracle instances on $Platform at $(Get-Date -Format u)"

        $databases = @()

        if ($Platform -eq 'Windows') {

            $services = @(Get-CimInstance -ClassName Win32_Service -Filter "Name LIKE 'OracleService%'" -ErrorAction SilentlyContinue)

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

        }
        elseif ($Platform -eq 'Linux') {

            $oratabPath = '/etc/oratab'

            if (-not (Test-Path -Path $oratabPath)) {
                return [PSCustomObject]@{
                    Success = $true
                    Data    = @()
                    Message = 'No Oracle database services found on this host.'
                }
            }

            $lines = @(Get-Content -Path $oratabPath -ErrorAction Stop)

            $databases = @($lines | ForEach-Object {
                # Skip blank lines and comments
                if ([string]::IsNullOrWhiteSpace($_) -or $_ -match '^\s*#') { return }

                $parts = $_ -split ':'
                if ($parts.Count -lt 2) { return }

                $sid        = $parts[0].Trim()
                $oracleHome = $parts[1].Trim()

                # Skip blank or wildcard SID entries
                if ([string]::IsNullOrWhiteSpace($sid) -or $sid -eq '*') { return }

                # Status: check for ora_pmon_<SID> process
                $pmon   = @(Get-Process -Name "ora_pmon_$sid" -ErrorAction SilentlyContinue)
                $status = if ($pmon.Count -gt 0) { 'Running' } else { 'Stopped' }

                $oracleHomeVal = if ([string]::IsNullOrWhiteSpace($oracleHome)) { $null } else { $oracleHome }

                # ORACLE_BASE is three levels above ORACLE_HOME: strip /{home}/{version}/product
                # Use string split on '/' to preserve Linux path separators on all platforms
                $oracleBase = if ($null -ne $oracleHomeVal) {
                    $parts = $oracleHomeVal.TrimEnd('/') -split '/'
                    if ($parts.Count -gt 3) { ($parts[0..($parts.Count - 4)]) -join '/' } else { $null }
                } else {
                    $null
                }

                [PSCustomObject]@{
                    SID         = $sid
                    Status      = $status
                    ServiceName = $null
                    OracleHome  = $oracleHomeVal
                    OracleBase  = $oracleBase
                }
            })

        }
        else {
            return [PSCustomObject]@{
                Success = $false
                Data    = $null
                Message = "Oracle instance discovery is not supported on platform '$Platform'."
            }
        }

        if ($databases.Count -eq 0) {
            return [PSCustomObject]@{
                Success = $true
                Data    = @()
                Message = 'No Oracle database services found on this host.'
            }
        }

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
