#Requires -Version 7.6
<#
.SYNOPSIS
    Parses raw RMAN LIST BACKUP SUMMARY output into structured backup records.

.DESCRIPTION
    Extracts one structured record per backup set from the tabular output of
    RMAN LIST BACKUP SUMMARY. The table is identified by its separator line
    (a row of dash groups); column positions are derived dynamically from that
    line so the parser tolerates minor width variations between Oracle versions.

    Parsing relies on NLS_DATE_FORMAT being set to 'YYYY-MM-DD HH24:MI:SS' on the
    RMAN child process (enforced by Invoke-RmanProcess, AD-029). CompletionTime is
    parsed as [datetime?] using that fixed format. BackupTime is also parsed from
    the Tag field (TAG<YYYYMMDD>T<HHmmss>) as a secondary reference.
    - Level and Status are derived from single-character RMAN codes (LV and S
      columns) — these are NLS-independent.

.PARAMETER RawLog
    The raw RMAN stdout string containing LIST BACKUP SUMMARY output.

.OUTPUTS
    [PSCustomObject[]] — zero or more records with the following properties:
        Key            [int]      Backup set key
        Level          [string]   Full / Archivelog / Incremental0 / Incremental1 / Unknown
        Status         [string]   Available / Expired / Deleted / Unavailable / Unknown
        DeviceType     [string]   DISK / SBT_TAPE / raw value from RMAN
        CompletionTime [datetime?] Parsed from RMAN output using 'yyyy-MM-dd HH:mm:ss';
                                   $null if parsing fails (unexpected NLS format)
        BackupTime     [datetime?] Parsed from Tag (TAG<YYYYMMDD>T<HHmmss>);
                                   $null if tag absent or not in standard Oracle format
        PieceCount     [int]
        CopyCount      [int]
        Compressed     [bool]
        Tag            [string]

.NOTES

    Column positions are derived from the separator line at runtime — not
    hardcoded — so the parser survives minor format changes between Oracle
    versions and NLS configurations.

    TY column (always 'B' for backup set) is extracted but not returned;
    it carries no information useful to callers at this stage.
#>
function ConvertFrom-RmanListBackup {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$RawLog
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    #--------------------------------------------------------------
    # INVARIANTS
    #
    # PRE-CONDITIONS
    #   P1 RawLog is a string, and may be empty.
    #       Type: Mandatory and AllowEmptyString.
    #   P2 Completion times in RawLog are in the form yyyy-MM-dd HH:mm:ss.
    #       Limitation: the caller's duty, met by Invoke-RmanProcess. Another format gives
    #       a null CompletionTime, not an error.
    #
    # SECURITY INVARIANTS
    #   [SEC] S1 It reads RawLog and nothing else: no file, no process, no credential.
    #       Static: none yet.
    #
    # POST-CONDITIONS
    #   R1 Returns an array of zero or more records, and does not throw on text it cannot
    #       parse.
    #       Test: none yet.
    #   R2 Empty input, no separator line, or fewer than ten columns gives an empty array.
    #       Test: none yet.
    #   R3 Each record has Key, Level, Status, DeviceType, CompletionTime, BackupTime,
    #       PieceCount, CopyCount, Compressed and Tag.
    #       Test: none yet.
    #   R4 A level or status code it does not know becomes 'Unknown'.
    #       Test: none yet.
    #   R5 BackupTime is null unless the tag has the form TAGyyyyMMddTHHmmss.
    #       Test: none yet.
    #
    # EXECUTION INVARIANTS
    #   L1 Column positions are taken from the separator line, not hard-coded.
    #       Guard: the column start scan.
    #   L2 A row whose Key is not a positive integer is skipped.
    #       Guard: the TryParse check at the start of the row loop.
    #--------------------------------------------------------------

    if ([string]::IsNullOrWhiteSpace($RawLog)) {
        return [PSCustomObject[]]@()
    }

    $lines = $RawLog -split '\r?\n'

    # ── Locate separator line ─────────────────────────────────────────────────
    # The separator is the first line that starts with dashes and contains at
    # least 8 dash groups (one per column in the LIST BACKUP SUMMARY table).
    $separatorIdx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $ln = $lines[$i]
        if ($ln -match '^-{3,}' -and ([regex]::Matches($ln, '-{2,}')).Count -ge 8) {
            $separatorIdx = $i
            break
        }
    }

    if ($separatorIdx -lt 0) {
        Write-Verbose "[ConvertFrom-RmanListBackup] No LIST BACKUP SUMMARY table found in RMAN output."
        return [PSCustomObject[]]@()
    }

    # ── Determine column start positions ─────────────────────────────────────
    # Each dash group in the separator marks the start of one column.
    $colStarts = [System.Collections.Generic.List[int]]::new()
    $inDash    = $false
    $separator = $lines[$separatorIdx]

    for ($ci = 0; $ci -lt $separator.Length; $ci++) {
        if ($separator[$ci] -eq '-' -and -not $inDash) {
            $colStarts.Add($ci)
            $inDash = $true
        } elseif ($separator[$ci] -ne '-') {
            $inDash = $false
        }
    }

    # LIST BACKUP SUMMARY has 10 columns: Key TY LV S DeviceType CompletionTime #Pieces #Copies Compressed Tag
    if ($colStarts.Count -lt 10) {
        Write-Verbose "[ConvertFrom-RmanListBackup] Separator has $($colStarts.Count) column(s) — expected >= 10. Cannot parse."
        return [PSCustomObject[]]@()
    }

    # ── Column extraction helper ──────────────────────────────────────────────
    # Extracts and trims the value of column $ci from line $ln.
    # For columns 0–8: extracts from colStarts[ci] to colStarts[ci+1]-1.
    # For column 9 (last): extracts from colStarts[9] to end of line.
    $getCell = {
        param([string]$ln, [int]$ci)
        $st = $colStarts[$ci]
        if ($st -ge $ln.Length) { return '' }
        $en  = if ($ci -lt ($colStarts.Count - 1)) { $colStarts[$ci + 1] - 1 } else { $ln.Length - 1 }
        $mx  = [Math]::Min($en - $st + 1, $ln.Length - $st)
        if ($mx -le 0) { return '' }
        $ln.Substring($st, $mx).Trim()
    }

    # ── Parse data rows ───────────────────────────────────────────────────────
    $records = [System.Collections.Generic.List[PSCustomObject]]::new()

    for ($ri = $separatorIdx + 1; $ri -lt $lines.Count; $ri++) {
        $line = $lines[$ri]
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        $rawKey = & $getCell $line 0

        # Key column must be a positive integer — non-data lines will not parse
        $key = 0
        if (-not [int]::TryParse($rawKey, [ref]$key) -or $key -le 0) { continue }

        $rawLv         = & $getCell $line 2
        $rawS          = & $getCell $line 3
        $rawDevice     = & $getCell $line 4
        $rawCompletion = & $getCell $line 5
        $rawPieces     = & $getCell $line 6
        $rawCopies     = & $getCell $line 7
        $rawCompressed = & $getCell $line 8
        $rawTag        = & $getCell $line 9

        # Map LV code → human-readable Level
        $level = switch ($rawLv) {
            'F'     { 'Full'         }
            'A'     { 'Archivelog'   }
            '0'     { 'Incremental0' }
            '1'     { 'Incremental1' }
            default { 'Unknown'      }
        }

        # Map S code → human-readable Status
        $status = switch ($rawS) {
            'A'     { 'Available'   }
            'X'     { 'Expired'     }
            'D'     { 'Deleted'     }
            'U'     { 'Unavailable' }
            default { 'Unknown'     }
        }

        $pieceCount = 0; [int]::TryParse($rawPieces, [ref]$pieceCount) | Out-Null
        $copyCount  = 0; [int]::TryParse($rawCopies,  [ref]$copyCount)  | Out-Null
        $compressed = $rawCompressed -eq 'YES'

        # Parse CompletionTime using the fixed NLS_DATE_FORMAT set on the RMAN child
        # process by Invoke-RmanProcess (AD-029): 'YYYY-MM-DD HH24:MI:SS'.
        $parsedCompletion = $null
        $dtRef = [datetime]::MinValue
        if ([datetime]::TryParseExact(
                $rawCompletion,
                'yyyy-MM-dd HH:mm:ss',
                [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::None,
                [ref]$dtRef)) {
            $parsedCompletion = $dtRef
        }

        # Parse BackupTime from the standard Oracle tag format TAG<YYYYMMDD>T<HHmmss>.
        # Secondary reference — CompletionTime is the primary date field.
        $backupTime = $null
        if ($rawTag -match '^TAG(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})$') {
            try {
                $backupTime = [datetime]::new(
                    [int]$Matches[1], [int]$Matches[2], [int]$Matches[3],
                    [int]$Matches[4], [int]$Matches[5], [int]$Matches[6]
                )
            } catch {
                $backupTime = $null
            }
        }

        $records.Add([PSCustomObject]@{
            Key            = $key
            Level          = $level
            Status         = $status
            DeviceType     = $rawDevice
            CompletionTime = $parsedCompletion
            BackupTime     = $backupTime
            PieceCount     = $pieceCount
            CopyCount      = $copyCount
            Compressed     = $compressed
            Tag            = $rawTag
        })
    }

    Write-Verbose "[ConvertFrom-RmanListBackup] Parsed $($records.Count) backup record(s)."
    return [PSCustomObject[]]$records.ToArray()
}
