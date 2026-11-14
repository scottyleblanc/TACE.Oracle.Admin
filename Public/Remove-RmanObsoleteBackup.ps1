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

    #--------------------------------------------------------------
    # INVARIANTS
    #
    # PRE-CONDITIONS
    #   P1 DatabaseName is a non-empty string.
    #       Type: Mandatory and ValidateNotNullOrEmpty.
    #   P2 WalletAlias and Credential are not both supplied.
    #       Guard: the check at the start of the body returns Success = $false.
    #   P3 It runs on Windows.
    #       Limitation: there is no platform check. Known finding against rule C-07.
    #   P4 A crosscheck has been run, so expired pieces are already marked.
    #       Limitation: the operator's duty. Nothing here checks it.
    #
    # SECURITY INVARIANTS
    #   [SEC] S1 Nothing is deleted unless ShouldProcess approves, with ConfirmImpact High.
    #       Test: 'RMAN must not be invoked on WhatIf — ShouldProcess is the sole gate'.
    #   [SEC] S2 RMAN is run with NOPROMPT, so ShouldProcess is the only confirmation.
    #       Test: 'RMAN script must contain NOPROMPT'.
    #   [SEC] S3 ORACLE_SID is never set on the current session.
    #       Test: 'ORACLE_SID should not be set on current session'.
    #   [SEC] S4 Message holds no credential when RMAN succeeds.
    #       Test: 'Message should not contain credential fragments'.
    #   [SEC] S8 Exception text is scrubbed before it is placed in Message.
    #       Test: none yet. No test raises an exception that carries a credential.
    #   [SEC] S5 The RMAN script holds no credential.
    #       Test: 'RMAN script should not contain credential fragments'.
    #   [SEC] S6 CatalogCredential is accepted and not used. The catalog connect line is
    #       written without a credential.
    #       Limitation: unfinished. Open [SEC] TODO in the body.
    #   [SEC] S7 CatalogConnection is placed in the RMAN script after a non-empty check
    #       only.
    #       Limitation: caller text reaches RMAN unvalidated. Finding against rule S-11.
    #
    # POST-CONDITIONS
    #   R1 Returns Success, Data and Message on every path, and never throws once its
    #       parameters are bound.
    #       Test: 'Should return Success=$false and safe Message when binary integrity check fails'.
    #   R2 On success Data has DatabaseName, StartTime, EndTime, DurationSec, DeletedCount,
    #       AuthMode and RawLog.
    #       Test: none yet.
    #   R3 When ShouldProcess declines, or under -WhatIf, RMAN is not run and Success is
    #       false.
    #       Test: 'Should not invoke RMAN on WhatIf'.
    #   R4 DeletedCount is the number of 'deleted backup piece' lines in the RMAN output.
    #       Test: 'Should count deleted pieces from RMAN output'.
    #
    # EXECUTION INVARIANTS
    #   L1 The environment check runs before the ShouldProcess gate.
    #       Limitation: under -WhatIf it can still create the config file and run tnsping.
    #   L2 The OracleHome from the config is passed to Invoke-RmanProcess even when it is
    #       empty and the environment variable was used to find RMAN.
    #       Limitation: suspected defect, not yet confirmed by a test.
    #--------------------------------------------------------------

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
