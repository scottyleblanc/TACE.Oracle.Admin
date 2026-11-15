#Requires -Version 7.6
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
        [ValidatePattern('^[A-Za-z0-9_.-]*\z')]
        [string]$WalletAlias = '',

        [Parameter()]
        [PSCredential]$Credential = $null
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    #--------------------------------------------------------------
    # INVARIANTS
    #
    # PRE-CONDITIONS
    #   P1 DatabaseName is a non-empty string.
    #       Type: Mandatory and ValidateNotNullOrEmpty.
    #   P2 WalletAlias and Credential are not both supplied.
    #       Guard: the check at the start of the body returns Success = $false.
    #   P3 It runs on Windows. On any other platform it returns Success = $false before
    #       it reads the config or starts a process (rule C-07).
    #       Test: 'P3 returns Success false on a platform other than Windows'.
    #
    # SECURITY INVARIANTS
    #   [SEC] S1 ORACLE_SID is never set on the current session.
    #       Test: 'ORACLE_SID should not be set on current session after call'.
    #   [SEC] S2 Message holds no credential when RMAN succeeds.
    #       Test: 'Message should not contain credential fragments',
    #       '[SEC] Message does not contain credential fragments when WalletAlias is used'.
    #   [SEC] S5 Exception text is scrubbed before it is placed in Message.
    #       Test: none yet. No test raises an exception that carries a credential.
    #   [SEC] S3 Credential is handed to Invoke-RmanProcess and to nothing else. It is
    #       never logged or returned.
    #       Static: none yet.
    #   [SEC] S4 Data.RawLog holds RMAN output as scrubbed by Invoke-RmanProcess.
    #       Limitation: it is only as clean as that scrub. See Invoke-CredentialScrub S2.
    #   [SEC] S6 WalletAlias holds only letters, digits, _, . and -, so it cannot add a
    #       line or a command to the CONNECT text written to RMAN's stdin, or an
    #       argument to tnsping.
    #       Type: ValidatePattern('^[A-Za-z0-9_.-]*\z'); the empty default passes.
    #
    # POST-CONDITIONS
    #   R1 Returns Success, Data and Message on every path, and never throws once its
    #       parameters are bound.
    #       Test: 'Should return Success=$false and safe Message when binary integrity check fails'.
    #   R2 On success Data is one record, not an array.
    #       Test: 'Data should be a single object, not an array'.
    #   R3 The record chosen has the latest CompletionTime. A record with no
    #       CompletionTime is chosen only when none has one, by highest Key.
    #       Test: 'Should select the most recent record by CompletionTime (Key 94 over Key 95)'.
    #   R4 When CompletionTime is null, IsRecentDay is false and AgeHours is -1.
    #       Test: 'Data.AgeHours should be -1 (sentinel) when CompletionTime is null'.
    #   R5 No backup records, or an RMAN failure, gives Success = $false.
    #       Test: 'Should return Success=$false when RMAN output contains no backup records',
    #       'Should return Success=$false when RMAN fails'.
    #
    # EXECUTION INVARIANTS
    #   L1 Read-only: the only RMAN command sent is LIST BACKUP SUMMARY.
    #       Test: 'Should include LIST BACKUP SUMMARY in the RMAN script'.
    #   L2 The first call can create the config file on disk.
    #       Limitation: see Get-OracleBackupConfigStore L1.
    #   L3 Invoke-RmanProcess receives the home that Assert-OracleEnvironment validated,
    #       including one found through the ORACLE_HOME fallback when the config has none.
    #       Test: 'L3 passes the validated home to RMAN when the config has none'.
    #--------------------------------------------------------------

    # ── Platform check (C-07) ─────────────────────────────────────────────────
    if (-not (Test-WindowsPlatform)) {
        return [PSCustomObject]@{
            Success = $false
            Data    = $null
            Message = 'Get-RmanBackupStatus is Windows only. Linux support is not yet built.'
        }
    }

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

        # The validated home, which may have come from the ORACLE_HOME fallback (L3).
        # Assert-OracleEnvironment always resolves the binary as <home>\bin\<binary>.
        $oracleHome = Split-Path -Path (Split-Path -Path $rmanPath -Parent) -Parent

        # ── Build RMAN script ─────────────────────────────────────────────
        $listScript = 'LIST BACKUP SUMMARY;'

        # ── Invoke RMAN ───────────────────────────────────────────────────
        Write-Verbose "[Get-RmanBackupStatus] Querying most recent backup for '$DatabaseName' (AuthMode: $authMode)"

        $rmanInvokeParams = @{
            RmanBinaryPath = $rmanPath
            RmanScript     = $listScript
            OracleHome     = $oracleHome
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
