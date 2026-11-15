<#
.SECURITY
    Scope  : ConvertFrom-RmanListBackup (private)
    Touches: Strings only. No process, file, network or environment access.

    Security assertions in this file: none. The function reads RawLog and nothing
    else (S1, a static property, not tested here).
#>

#Requires -Version 7.6

Describe 'ConvertFrom-RmanListBackup' {

    BeforeAll {
        Remove-Module TACE.Oracle.Admin -Force -ErrorAction SilentlyContinue
        Import-Module (& (Join-Path $PSScriptRoot '..' 'Get-BuiltModulePath.ps1')) -Force

        # LIST BACKUP SUMMARY as RMAN prints it with NLS_DATE_FORMAT = YYYY-MM-DD HH24:MI:SS.
        # Every row keeps the column positions of the separator line.
        $script:header    = 'Key     TY LV S Device Type Completion Time     #Pieces #Copies Compressed Tag'
        $script:separator = '------- -- -- - ----------- ------------------- ------- ------- ---------- ---'

        # Wraps data rows in the text RMAN prints around the table.
        function New-RmanListing {
            param([string[]] $Row = @(), [string] $Separator = $script:separator)
            @(
                'RMAN> list backup summary;'
                ''
                'List of Backups'
                '==============='
                ''
                $script:header
                $Separator
                $Row
                ''
                'Recovery Manager complete.'
            ) -join "`n"
        }

        # Runs the private function inside the module.
        function Invoke-Parse {
            param([AllowEmptyString()] [string] $RawLog)
            InModuleScope TACE.Oracle.Admin -Parameters @{ Text = $RawLog } {
                param([string] $Text)
                @(ConvertFrom-RmanListBackup -RawLog $Text)
            }
        }
    }

    AfterAll {
        Remove-Module TACE.Oracle.Admin -Force -ErrorAction SilentlyContinue
    }

    Context 'Parameter validation' {

        It 'P1 RawLog is mandatory and accepts an empty string' {
            $param = InModuleScope TACE.Oracle.Admin { (Get-Command ConvertFrom-RmanListBackup).Parameters['RawLog'] }
            @($param.Attributes | Where-Object { $PSItem -is [System.Management.Automation.ParameterAttribute] -and $PSItem.Mandatory }) |
                Should -Not -BeNullOrEmpty
            @($param.Attributes | Where-Object { $PSItem -is [System.Management.Automation.AllowEmptyStringAttribute] }) |
                Should -Not -BeNullOrEmpty
        }
    }

    Context 'Implementation' {

        It 'R3 returns one record per backup set row with every documented property' {
            $rows = @(
                '     91 B  F  A DISK        2026-02-01 02:00:00  1       1       NO         TAG20260201T020000'
                '     95 B  F  X DISK        2026-02-02 03:00:00  2       1       YES        TAG20260202T030000'
            )
            $records = Invoke-Parse -RawLog (New-RmanListing -Row $rows)
            $records | Should -HaveCount 2
            @($records[0].PSObject.Properties.Name) | Should -Be @(
                'Key', 'Level', 'Status', 'DeviceType', 'CompletionTime', 'BackupTime',
                'PieceCount', 'CopyCount', 'Compressed', 'Tag')
            $records[0].Key            | Should -Be 91
            $records[0].DeviceType     | Should -Be 'DISK'
            $records[0].CompletionTime | Should -Be ([datetime]'2026-02-01 02:00:00')
            $records[0].Compressed     | Should -BeFalse
            $records[1].PieceCount     | Should -Be 2
            $records[1].CopyCount      | Should -Be 1
            $records[1].Compressed     | Should -BeTrue
            $records[1].Tag            | Should -Be 'TAG20260202T030000'
        }

        It 'R3 maps the level and status codes' {
            $rows = @(
                '     91 B  F  A DISK        2026-02-01 02:00:00  1       1       NO         TAG20260201T020000'
                '     92 B  A  X DISK        2026-02-01 03:00:00  1       1       NO         TAG20260201T030000'
                '     93 B  0  D DISK        2026-02-02 02:00:00  1       1       NO         TAG20260202T020000'
                '     94 B  1  U DISK        2026-02-03 02:00:00  1       1       NO         TAG20260203T020000'
            )
            $records = Invoke-Parse -RawLog (New-RmanListing -Row $rows)
            @($records.Level)  | Should -Be @('Full', 'Archivelog', 'Incremental0', 'Incremental1')
            @($records.Status) | Should -Be @('Available', 'Expired', 'Deleted', 'Unavailable')
        }

        It 'R4 maps a level or status code it does not know to Unknown' {
            $row = '     96 B  Z  Q DISK        2026-02-04 02:00:00  1       1       NO         TAG20260204T020000'
            $records = Invoke-Parse -RawLog (New-RmanListing -Row $row)
            $records[0].Level  | Should -Be 'Unknown'
            $records[0].Status | Should -Be 'Unknown'
        }

        It 'R5 reads BackupTime from a tag of the form TAGyyyyMMddTHHmmss' {
            $row = '     91 B  F  A DISK        2026-02-01 02:00:00  1       1       NO         TAG20260201T020000'
            (Invoke-Parse -RawLog (New-RmanListing -Row $row))[0].BackupTime | Should -Be ([datetime]'2026-02-01 02:00:00')
        }

        It 'R5 gives a null BackupTime for <Case>' -ForEach @(
            @{ Case = 'a custom tag';                 Tag = 'CUSTOMTAG_NODATE' }
            @{ Case = 'a tag-shaped invalid date';    Tag = 'TAG20261399T999999' }
        ) {
            $row = '     91 B  F  A DISK        2026-02-01 02:00:00  1       1       NO         ' + $Tag
            (Invoke-Parse -RawLog (New-RmanListing -Row $row))[0].BackupTime | Should -BeNullOrEmpty
        }

        It 'R1, P2 gives a null CompletionTime for a completion time in another format, without throwing' {
            $row = '     99 B  F  A DISK        01-MAR-26            1       1       NO         CUSTOMTAG_NODATE'
            $records = Invoke-Parse -RawLog (New-RmanListing -Row $row)
            $records                   | Should -HaveCount 1
            $records[0].CompletionTime | Should -BeNullOrEmpty
        }

        It 'L2 skips a row whose Key is not a positive integer' {
            $rows = @(
                '    abc B  F  A DISK        2026-02-01 02:00:00  1       1       NO         TAG20260201T020000'
                '      0 B  F  A DISK        2026-02-01 02:00:00  1       1       NO         TAG20260201T020000'
                '     91 B  F  A DISK        2026-02-01 02:00:00  1       1       NO         TAG20260201T020000'
            )
            @((Invoke-Parse -RawLog (New-RmanListing -Row $rows)).Key) | Should -Be @(91)
        }

        It 'R2 returns no records for <Case>' -ForEach @(
            @{ Case = 'empty input';               Text = '' }
            @{ Case = 'whitespace only';           Text = "  `n  " }
            @{ Case = 'output with no table';      Text = "RMAN> list backup summary;`nspecification does not match any backup in the repository" }
            @{ Case = 'a table with no rows';      Text = 'TABLE_NO_ROWS' }
            @{ Case = 'fewer than ten columns';    Text = 'FEW_COLUMNS' }
        ) {
            $raw = switch ($Text) {
                'TABLE_NO_ROWS' { New-RmanListing }
                # Eight dash groups: recognised as a separator, but under ten columns.
                'FEW_COLUMNS'   { New-RmanListing -Separator '------- -- -- -- ----------- ------------------- ------- -------' -Row '     91 B  F  A DISK        2026-02-01 02:00:00  1       1' }
                default         { $Text }
            }
            Invoke-Parse -RawLog $raw | Should -HaveCount 0
        }

        It 'R1 does not throw on text it cannot parse' {
            $garbage = "-------------------------------------------`n" + ('x' * 500) + "`n`u{0000}`t|||"
            { Invoke-Parse -RawLog $garbage } | Should -Not -Throw
        }
    }
}
