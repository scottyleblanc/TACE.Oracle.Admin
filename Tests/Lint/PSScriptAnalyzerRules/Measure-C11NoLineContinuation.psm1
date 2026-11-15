#Requires -Version 7.6

function Measure-C11NoLineContinuation {
    <#
    .SYNOPSIS
        Rule C-11: a call with several parameters uses splatting, never backtick line
        continuation.

    .DESCRIPTION
        Reports every backtick line continuation. A continuation is only ever used to
        spread a statement across lines, which splatting or a natural line break (after a
        pipe, an operator or an opening bracket) does without one. Custom PSScriptAnalyzer
        rule (decision 26).

    .PARAMETER Token
        The file's tokens, which PSScriptAnalyzer passes in once per file.

    .EXAMPLE
        Invoke-ScriptAnalyzer -Path .\Source -Recurse -CustomRulePath .\Tests\Lint\PSScriptAnalyzerRules\*.psm1

    .OUTPUTS
        Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord, one per
        line continuation.

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

    $continuations = @($Token | Where-Object {
        $PSItem.Kind -eq [System.Management.Automation.Language.TokenKind]::LineContinuation
    })

    foreach ($continuation in $continuations) {
        [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
            Message  = '[C-11] Backtick line continuation. Use splatting, or break the line after a pipe, operator or bracket.'
            Extent   = $continuation.Extent
            RuleName = 'Measure-C11NoLineContinuation'
            Severity = 'Warning'
        }
    }
}

Export-ModuleMember -Function 'Measure-C11NoLineContinuation'
