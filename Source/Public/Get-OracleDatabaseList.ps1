#Requires -Version 7.6

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
        Module  : TACE.Oracle.Admin
        Version : 0.2.4
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('Measure-C14PathWithJoinPath', '',
        Justification = 'ORACLE_BASE is derived from a Linux ORACLE_HOME with -join ''/'' so the separator stays / on every platform; Join-Path would use \ on Windows, where the Linux branch is unit-tested (rule C-14).')]
    param(
        [Parameter()]
        [ValidateSet('Windows', 'Linux', 'Unsupported')]
        [string] $Platform =$(if ($IsWindows) { 'Windows' } elseif ($IsLinux) { 'Linux' } else { 'Unsupported' })
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    #--------------------------------------------------------------
    # INVARIANTS
    #
    # PRE-CONDITIONS
    #   P1 Platform is 'Windows', 'Linux' or 'Unsupported', the value detection gives on
    #       any other OS. Any other value is refused at the call; 'Unsupported' reaches
    #       the final else branch, which returns Success = $false (rule C-07).
    #       Type: ValidateSet('Windows', 'Linux', 'Unsupported').
    #       Test: 'P1 Platform accepts only Windows, Linux and Unsupported',
    #       'P1 throws a parameter error for an unknown platform value'.
    #
    # SECURITY INVARIANTS
    #   [SEC] S1 No Oracle connection is made and no credential is read.
    #       Static: 'Get-OracleDatabaseList S1 makes no Oracle connection and reads no credential'.
    #   [SEC] S2 The catch block places the raw exception message in Message.
    #       Limitation: not scrubbed. Accepted because nothing in this function
    #       handles a credential.
    #
    # POST-CONDITIONS
    #   R1 Returns Success, Data and Message on every path, and never throws.
    #       Test: 'R1 returns exactly Success, Data and Message, without throwing, on Windows when <Path>',
    #       'R1 returns exactly Success, Data and Message, without throwing, on <Platform> when <Path>'.
    #   R2 When no instance is found, Success is true and Data is an empty array.
    #       Test: 'R2 returns Success = $true with empty Data'.
    #   R3 Each Data entry has SID, Status, ServiceName, OracleHome and OracleBase.
    #       Test: 'R3 Data entries have SID property', 'R3 Data entries have Status property',
    #       'R3 Data entries have ServiceName property', 'R3 Data entries have OracleHome property',
    #       'R3 Data entries have OracleBase property'.
    #   R4 OracleHome and OracleBase are null when they cannot be derived.
    #       Test: 'R4 returns OracleHome as $null when PathName is empty',
    #       'R4 returns OracleBase as $null when PathName is empty'.
    #   R5 ServiceName is null on Linux.
    #       Test: 'R5 returns ServiceName as $null'.
    #
    # EXECUTION INVARIANTS
    #   L1 Read-only: it reads services, /etc/oratab and the process list, and changes
    #       nothing.
    #       Static: 'Get-OracleDatabaseList L1 is read-only: every command it calls only reads'.
    #   L2 On Windows any error from the service query, terminating or not, returns
    #       Success = $false. It is never read as no instances found.
    #       Test: 'L2 a non-terminating service query error returns Success false'.
    #--------------------------------------------------------------

    try {
        Write-Verbose "[Get-OracleDatabaseList] Querying Oracle instances on $Platform at $(Get-Date -Format u)"

        $databases = @()

        if ($Platform -eq 'Windows') {

            # L2: Stop, so a failed query (WMI stopped, access denied, RPC failure) reaches
            # the catch as Success = $false. A query that matches nothing raises no error
            # and still returns an empty result (R2).
            $services = @(Get-CimInstance -ClassName Win32_Service -Filter "Name LIKE 'OracleService%'" -ErrorAction Stop)

            $databases = @($services | ForEach-Object {
                # PathName may be quoted ("C:\...\bin\ORACLE.EXE" args) or unquoted
                $exePath = if ($PSItem.PathName -match '^"([^"]+)"') {
                    $Matches[1]
                } elseif (-not [string]::IsNullOrWhiteSpace($PSItem.PathName)) {
                    ($PSItem.PathName -split '\s+')[0]
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
                    SID         = $PSItem.Name -replace '^OracleService', ''
                    Status      = $PSItem.State
                    ServiceName = $PSItem.Name
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
                if ([string]::IsNullOrWhiteSpace($PSItem) -or $PSItem -match '^\s*#') { return }

                $parts = $PSItem -split ':'
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
            Message = "Failed to query Oracle database services: $($PSItem.Exception.Message)"
        }
    }
}
