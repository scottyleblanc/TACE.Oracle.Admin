#Requires -Version 7.6
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

.EXAMPLE
    Remove-RmanObsoleteBackup -DatabaseName 'CDB1' -WhatIf

    Shows what RMAN would delete without removing anything.

.EXAMPLE
    Remove-RmanObsoleteBackup -DatabaseName 'CDB1' -Confirm:$false

    Removes obsolete backups without interactive confirmation prompt.

.NOTES
    Copyright © TACE Data Management Inc.
    Module  : TACE.Oracle.Admin
    Version : 0.2.8

    [SEC] SupportsShouldProcess is mandatory — no silent deletion path.
    [SEC] ORACLE_SID set on child process only — never on current session.
    [SEC] The RMAN script is fixed text — no caller value is placed in it.
    Recovery catalog support is not offered until a catalog is in scope.
#>
function Remove-RmanObsoleteBackup {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
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
    #       Test: 'P1 DatabaseName is mandatory',
    #       'P1 DatabaseName rejects an empty string'.
    #   P2 WalletAlias and Credential are not both supplied.
    #       Guard: the check at the start of the body returns Success = $false.
    #       Test: 'P2 returns Success=$false when both WalletAlias and Credential are specified'.
    #   P3 It runs on Windows. On any other platform it returns Success = $false before
    #       the ShouldProcess gate, the config read or any process (rule C-07).
    #       Test: 'P3 returns Success false on a platform other than Windows'.
    #   P4 A crosscheck has been run, so expired pieces are already marked.
    #       Limitation: the operator's duty. Nothing here checks it.
    #
    # SECURITY INVARIANTS
    #   [SEC] S1 Nothing is deleted unless ShouldProcess approves, with ConfirmImpact High.
    #       Test: 'S1 RMAN must not be invoked on WhatIf — ShouldProcess is the sole gate',
    #       'S1 declares ConfirmImpact High, so it asks before deleting at the default preference'.
    #   [SEC] S2 RMAN is run with NOPROMPT, so ShouldProcess is the only confirmation.
    #       Test: 'S2 RMAN script must contain NOPROMPT'.
    #   [SEC] S3 ORACLE_SID is never set on the current session.
    #       Test: 'S3 the session environment is unchanged after the call'.
    #   [SEC] S4 Message holds no credential when RMAN succeeds.
    #       Test: 'S4, S5 no part of a named credential reaches Message or the RMAN script',
    #       'S4 Message should not contain credential fragments'.
    #   [SEC] S8 Exception text is scrubbed before it is placed in Message.
    #       Test: 'S8 exception text is scrubbed before it is placed in Message'.
    #   [SEC] S5 The RMAN script holds no credential.
    #       Test: 'S4, S5 no part of a named credential reaches Message or the RMAN script',
    #       'S5 RMAN script should not contain credential fragments'.
    #   [SEC] S9 The RMAN script is fixed text. No parameter value is placed in it, and
    #       there is no catalog parameter. S6 and S7 are retired with those parameters.
    #       Test: 'S9 RMAN script is fixed text and no catalog parameter exists'.
    #   [SEC] S10 WalletAlias holds only letters, digits, _, . and -, so it cannot add a
    #       line or a command to the CONNECT text written to RMAN's stdin, or an
    #       argument to tnsping.
    #       Type: ValidatePattern('^[A-Za-z0-9_.-]*\z'); the empty default passes.
    #       Test: 'S10 WalletAlias pattern accepts <Alias>',
    #       'S10 WalletAlias refuses <Case> at the call'.
    #
    # POST-CONDITIONS
    #   R1 Returns Success, Data and Message on every path, and never throws once its
    #       parameters are bound.
    #       Test: 'R1 should return Success=$false and safe Message when binary integrity check fails'.
    #   R2 On success Data has DatabaseName, StartTime, EndTime, DurationSec, DeletedCount,
    #       AuthMode, RawLog and Applied = $true.
    #       Test: 'R2 a real run returns the full Data with Applied true'.
    #   R3 When ShouldProcess declines, or under -WhatIf, RMAN is not run and the return
    #       is a preview: Success = $true, Data.Applied = $false, and a Message that
    #       starts with 'WhatIf:' (rule C-27).
    #       Test: 'R3 should not invoke RMAN on WhatIf',
    #       'R3 WhatIf returns a preview with Applied false'.
    #   R4 DeletedCount is the number of 'deleted backup piece' lines in the RMAN output.
    #       Test: 'R4 should count deleted pieces from RMAN output'.
    #
    # EXECUTION INVARIANTS
    #   L1 Nothing is read, written or started before the ShouldProcess gate approves:
    #       under -WhatIf the config store and the environment check are not called.
    #       Test: 'L1 WhatIf reads no config and runs no environment check'.
    #   L2 Invoke-RmanProcess receives the home that Assert-OracleEnvironment validated,
    #       including one found through the ORACLE_HOME fallback when the config has none.
    #       Test: 'L2 passes the validated home to RMAN when the config has none'.
    #--------------------------------------------------------------

    # ── Platform check (C-07) ─────────────────────────────────────────────────
    if (-not (Test-WindowsPlatform)) {
        return [PSCustomObject]@{
            Success = $false
            Data    = $null
            Message = 'Remove-RmanObsoleteBackup is Windows only. Linux support is not yet built.'
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
        # ── ShouldProcess gate — destructive operation ────────────────────
        # [SEC] This is the only confirmation gate — NOPROMPT in the RMAN
        # script suppresses RMAN's own prompt. Never bypass ShouldProcess.
        # It runs before anything is read, written or started (L1), so -WhatIf
        # has no side effects: no config file is created and tnsping is not run.
        if (-not $PSCmdlet.ShouldProcess($DatabaseName, 'Delete obsolete RMAN backup pieces')) {
            # A successful no-op preview (C-27): nothing deleted, Applied = $false.
            return [PSCustomObject]@{
                Success = $true
                Data    = [PSCustomObject]@{
                    DatabaseName = $DatabaseName
                    Applied      = $false
                }
                Message = "WhatIf: would delete obsolete RMAN backup pieces for '$DatabaseName'."
            }
        }

        # ── Environment validation ─────────────────────────────────────────
        $config   = Get-OracleBackupConfigStore
        $rmanPath = Assert-OracleEnvironment -OracleHome $config.OracleHome -WalletAlias $WalletAlias

        # The validated home, which may have come from the ORACLE_HOME fallback (L2).
        # Assert-OracleEnvironment always resolves the binary as <home>\bin\<binary>.
        $oracleHome = Split-Path -Path (Split-Path -Path $rmanPath -Parent) -Parent

        # ── Build RMAN delete script ───────────────────────────────────────
        # [SEC] Fixed text (S9) — no caller value is placed in the script.
        # NOPROMPT required — RMAN prompts interactively by default.
        # ShouldProcess above is the confirmation gate; RMAN must not prompt again.
        $deleteScript = 'DELETE NOPROMPT OBSOLETE;'

        $startTime = Get-Date
        Write-Verbose "[Remove-RmanObsoleteBackup] Starting DELETE OBSOLETE for '$DatabaseName' (AuthMode: $authMode)"

        $rmanInvokeParams = @{
            RmanBinaryPath = $rmanPath
            RmanScript     = $deleteScript
            OracleHome     = $oracleHome
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
                Applied      = $true
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
