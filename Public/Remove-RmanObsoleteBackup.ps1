#Requires -Version 7.0
<#
.SYNOPSIS
    Removes RMAN backup pieces marked obsolete per the configured retention policy.

.DESCRIPTION
    Executes RMAN DELETE OBSOLETE to remove backup pieces that no longer satisfy
    the configured retention policy. Uses RMAN's own retention policy evaluation
    (consistent with AD-009 — the module does not own RMAN configuration).

    Always run Invoke-RmanCrosscheck before Remove-RmanObsoleteBackup to ensure
    expired pieces are identified before deletion. This function requires
    ShouldProcess confirmation — it is a destructive operation.

    Supports -WhatIf to preview what RMAN would delete without removing anything.

.PARAMETER DatabaseName
    The Oracle database name (SID) to remove obsolete backups for.

.PARAMETER CatalogConnection
    Optional. RMAN catalog connection string (AD-008).

.PARAMETER CatalogCredential
    Optional. SecureString credential for the catalog connection.
    Required when CatalogConnection is supplied.

.EXAMPLE
    Remove-RmanObsoleteBackup -DatabaseName 'CDB1' -WhatIf

    Shows what RMAN would delete without removing anything.

.EXAMPLE
    Remove-RmanObsoleteBackup -DatabaseName 'CDB1' -Confirm:$false

    Removes obsolete backups without interactive confirmation prompt.

.NOTES

    [SEC] SupportsShouldProcess is mandatory — no silent deletion path.
    [SEC] ORACLE_SID set on child process only — never on current session.
    [SEC] CatalogCredential plaintext extracted inline at stdin boundary only.
#>
function Remove-RmanObsoleteBackup {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DatabaseName,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$CatalogConnection,

        [Parameter()]
        [SecureString]$CatalogCredential,

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

        # ── Build RMAN delete script ───────────────────────────────────────
        $catalogPrefix = if ($PSBoundParameters.ContainsKey('CatalogConnection')) {
            # TODO: [SEC] Inject CatalogCredential via stdin
            "CONNECT CATALOG $CatalogConnection;`n"
        } else {
            ''
        }

        # NOPROMPT required — RMAN prompts interactively by default.
        # ShouldProcess above is the confirmation gate; RMAN must not prompt again.
        $deleteScript = @"
${catalogPrefix}DELETE NOPROMPT OBSOLETE;
"@

        # ── ShouldProcess gate — destructive operation ────────────────────
        # [SEC] This is the only confirmation gate — NOPROMPT in the RMAN
        # script suppresses RMAN's own prompt. Never bypass ShouldProcess.
        if (-not $PSCmdlet.ShouldProcess($DatabaseName, 'Delete obsolete RMAN backup pieces')) {
            return [PSCustomObject]@{
                Success = $false
                Data    = $null
                Message = 'Delete obsolete skipped — WhatIf or user declined.'
            }
        }

        $startTime = Get-Date
        Write-Verbose "[Remove-RmanObsoleteBackup] Starting DELETE OBSOLETE for '$DatabaseName' (AuthMode: $authMode)"

        $rmanInvokeParams = @{
            RmanBinaryPath = $rmanPath
            RmanScript     = $deleteScript
            OracleHome     = $config.OracleHome
        }
        switch ($authMode) {
            'WalletAuth'      { $rmanInvokeParams['WalletAlias'] = $WalletAlias }
            'NamedCredential' { $rmanInvokeParams['ServiceAlias'] = $DatabaseName; $rmanInvokeParams['Credential'] = $Credential }
            default           { $rmanInvokeParams['OracleSid'] = $DatabaseName }
        }
        $rmanResult = Invoke-RmanProcess @rmanInvokeParams

        $endTime     = Get-Date
        $durationSec = [int]($endTime - $startTime).TotalSeconds

        # ── Parse deletion output ─────────────────────────────────────────
        # TODO: Parse deleted piece count from RMAN output.
        # RMAN emits: 'deleted backup piece' for each removed piece.
        $deletedCount = ([regex]::Matches($rmanResult.StdOut, 'deleted backup piece')).Count

        Write-Verbose "[Remove-RmanObsoleteBackup] Completed in ${durationSec}s. Deleted: $deletedCount piece(s)"

        if (-not $rmanResult.Success) {
            return [PSCustomObject]@{
                Success = $false
                Data    = $null
                Message = "DELETE OBSOLETE failed for '$DatabaseName'."
            }
        }

        return [PSCustomObject]@{
            Success = $true
            Data    = [PSCustomObject]@{
                DatabaseName = $DatabaseName
                StartTime    = $startTime
                EndTime      = $endTime
                DurationSec  = $durationSec
                DeletedCount = $deletedCount
                AuthMode     = $authMode
                RawLog       = $rmanResult.StdOut
            }
            Message = "DELETE OBSOLETE completed for '$DatabaseName'. Removed $deletedCount piece(s) in ${durationSec}s."
        }
    }
    catch {
        $safeMessage = Invoke-CredentialScrub -Content $PSItem.Exception.Message
        return [PSCustomObject]@{
            Success = $false
            Data    = $null
            Message = "Remove-RmanObsoleteBackup failed: $safeMessage"
        }
    }
}
