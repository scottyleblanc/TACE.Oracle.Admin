#Requires -Version 7.0
<#
.SYNOPSIS
    Returns the status of the most recently completed RMAN backup.

.DESCRIPTION
    Runs RMAN LIST BACKUP SUMMARY and returns a single record representing
    the most recent backup. The record is augmented with two health-check
    fields: IsRecentDay and AgeHours.

    Most recent backup is determined by CompletionTime (the RMAN-reported
    completion timestamp) in descending order. If all records have a null
    CompletionTime, the record with the highest Key number is returned as
    the fallback.

    This is a read-only operation — no RMAN backup or restore is performed.
    Designed for monitoring checks and health-status dashboards.

.PARAMETER DatabaseName
    The Oracle database name (SID) to query.

.EXAMPLE
    Get-RmanBackupStatus -DatabaseName 'CDB1'

    Returns the most recent backup record with age information.

.EXAMPLE
    $s = Get-RmanBackupStatus -DatabaseName 'CDB1'
    if ($s.Success -and -not $s.Data.IsRecentDay) {
        Write-Warning "No backup in the last 24 hours for CDB1"
    }

    Monitoring check pattern — alerts when no recent backup is found.

.NOTES

    Data.IsRecentDay is $false if CompletionTime is $null (cannot confirm recency).
    Data.AgeHours is -1.0 if CompletionTime is $null (cannot compute age).

    [SEC] ORACLE_SID is set on the child process only — never on the
    current session environment.
    [SEC] No credential surface — OS authentication only at this stage.
    [SEC] Message property contains no sensitive path or credential fragments.
#>
function Get-RmanBackupStatus {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DatabaseName,

        [Parameter()]
        [string]$WalletAlias = '',

        [Parameter()]
        [PSCredential]$Credential = $null
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    # ── Auth mode resolution ──────────────────────────────────────────────────
    if (-not [string]::IsNullOrWhiteSpace($WalletAlias) -and $null -ne $Credential) {
        return [PSCustomObject]@{
            Success = $false
            Data    = $null
            Message = '-WalletAlias and -Credential cannot both be specified.'
        }
    }

    $authMode = if (-not [string]::IsNullOrWhiteSpace($WalletAlias)) { 'WalletAuth' }
                elseif ($null -ne $Credential) { 'NamedCredential' }
                else { 'OSAuth' }

    try {
        # ── Environment validation ─────────────────────────────────────────
        $config   = Get-OracleBackupConfigStore
        $rmanPath = Assert-OracleEnvironment -OracleHome $config.OracleHome -WalletAlias $WalletAlias

        # ── Build RMAN script ─────────────────────────────────────────────
        $listScript = 'LIST BACKUP SUMMARY;'

        # ── Invoke RMAN ───────────────────────────────────────────────────
        Write-Verbose "[Get-RmanBackupStatus] Querying most recent backup for '$DatabaseName' (AuthMode: $authMode)"

        $rmanInvokeParams = @{
            RmanBinaryPath = $rmanPath
            RmanScript     = $listScript
            OracleHome     = $config.OracleHome
        }
        switch ($authMode) {
            'WalletAuth'      { $rmanInvokeParams['WalletAlias'] = $WalletAlias }
            'NamedCredential' { $rmanInvokeParams['ServiceAlias'] = $DatabaseName; $rmanInvokeParams['Credential'] = $Credential }
            default           { $rmanInvokeParams['OracleSid'] = $DatabaseName }
        }
        $rmanResult = Invoke-RmanProcess @rmanInvokeParams

        if (-not $rmanResult.Success) {
            return [PSCustomObject]@{
                Success = $false
                Data    = $null
                Message = "LIST BACKUP SUMMARY failed for '$DatabaseName'. Review RMAN output for details."
            }
        }

        # ── Parse output ──────────────────────────────────────────────────
        $allRecords = @(ConvertFrom-RmanListBackup -RawLog $rmanResult.StdOut)

        if ($allRecords.Count -eq 0) {
            return [PSCustomObject]@{
                Success = $false
                Data    = $null
                Message = "No backup records found for '$DatabaseName'."
            }
        }

        # ── Select most recent record ─────────────────────────────────────
        # Primary sort: CompletionTime descending (nulls last).
        # Fallback: Key descending (higher key = more recent in control file).
        $mostRecent = $allRecords |
            Sort-Object -Property @(
                @{ Expression = { if ($null -ne $PSItem.CompletionTime) { 1 } else { 0 } }; Descending = $true },
                @{ Expression = { $PSItem.CompletionTime }; Descending = $true },
                @{ Expression = { $PSItem.Key            }; Descending = $true }
            ) |
            Select-Object -First 1

        # ── Compute health fields ─────────────────────────────────────────
        $now          = Get-Date
        $isRecentDay  = $false
        $ageHours     = [double]-1.0

        if ($null -ne $mostRecent.CompletionTime) {
            $isRecentDay = $mostRecent.CompletionTime -ge $now.AddHours(-24)
            $ageHours    = [Math]::Round(($now - $mostRecent.CompletionTime).TotalHours, 1)
        }

        Write-Verbose "[Get-RmanBackupStatus] Most recent: Key=$($mostRecent.Key) Level=$($mostRecent.Level) Status=$($mostRecent.Status) AgeHours=$ageHours"

        # ── Build message ─────────────────────────────────────────────────
        $message = if ($null -ne $mostRecent.CompletionTime) {
            "Most recent backup for '$DatabaseName': $($mostRecent.Level) ($($mostRecent.Status)), $($mostRecent.CompletionTime.ToString('yyyy-MM-dd HH:mm:ss')), ${ageHours}h ago."
        } else {
            "Most recent backup for '$DatabaseName' has no parseable CompletionTime. Tag: $($mostRecent.Tag)."
        }

        return [PSCustomObject]@{
            Success = $true
            Data    = [PSCustomObject]@{
                DatabaseName   = $DatabaseName
                Key            = $mostRecent.Key
                Level          = $mostRecent.Level
                Status         = $mostRecent.Status
                DeviceType     = $mostRecent.DeviceType
                CompletionTime = $mostRecent.CompletionTime
                BackupTime     = $mostRecent.BackupTime
                PieceCount     = $mostRecent.PieceCount
                CopyCount      = $mostRecent.CopyCount
                Compressed     = $mostRecent.Compressed
                Tag            = $mostRecent.Tag
                IsRecentDay    = $isRecentDay
                AgeHours       = $ageHours
                RawLog         = $rmanResult.StdOut
            }
            Message = $message
        }
    }
    catch {
        $safeMessage = Invoke-CredentialScrub -Content $PSItem.Exception.Message
        return [PSCustomObject]@{
            Success = $false
            Data    = $null
            Message = "Get-RmanBackupStatus failed: $safeMessage"
        }
    }
}
