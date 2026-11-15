#Requires -Version 7.6

function Measure-C18NoEmoji {
    <#
    .SYNOPSIS
        Rule C-18: no emojis in code, scripts or output.

    .DESCRIPTION
        Reports a token, including a comment or a string, that contains an emoji or a
        pictographic symbol. The ranges checked are the emoji and pictograph blocks
        (U+1F000 to U+1FAFF), Miscellaneous Symbols and Dingbats (U+2600 to U+27BF, which
        hold the check and cross marks), Miscellaneous Symbols and Arrows (U+2B00 to
        U+2BFF), and the emoji presentation selector (U+FE0F). Box-drawing characters,
        dashes, arrows and the copyright sign are allowed. Custom PSScriptAnalyzer rule
        (decision 26).

    .PARAMETER Token
        The file's tokens, which PSScriptAnalyzer passes in once per file.

    .EXAMPLE
        Invoke-ScriptAnalyzer -Path .\Source -Recurse -CustomRulePath .\Tests\Lint\PSScriptAnalyzerRules\*.psm1

    .OUTPUTS
        Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord, one per
        token that contains an emoji.

    .NOTES
        Copyright © TACE Data Management Inc.
        Returns diagnostic records, not the Success/Data/Message object: this is the
        contract PSScriptAnalyzer requires of a rule.
    #>
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Management.Automation.Language.Token[]]$Token
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    foreach ($item in $Token) {
        $found = $null
        foreach ($rune in $item.Text.EnumerateRunes()) {
            $value = $rune.Value
            if (($value -ge 0x1F000 -and $value -le 0x1FAFF) -or
                ($value -ge 0x2600 -and $value -le 0x27BF) -or
                ($value -ge 0x2B00 -and $value -le 0x2BFF) -or
                $value -eq 0xFE0F) {
                $found = $value
                break
            }
        }

        if ($null -ne $found) {
            [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
                Message  = ('[C-18] Emoji or pictograph U+{0:X4}. Use a [LABEL] prefix instead.' -f $found)
                Extent   = $item.Extent
                RuleName = 'Measure-C18NoEmoji'
                Severity = 'Warning'
            }
        }
    }
}

Export-ModuleMember -Function 'Measure-C18NoEmoji'
