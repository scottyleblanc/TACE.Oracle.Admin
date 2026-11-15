#Requires -Version 7.6

function Measure-C17UsePSItem {
    <#
    .SYNOPSIS
        Rule C-17: the current pipeline item is written $PSItem, never $_.

    .DESCRIPTION
        Reports every use of $_, including inside double-quoted strings. Custom
        PSScriptAnalyzer rule (decision 26).

    .PARAMETER ScriptBlockAst
        The script block PSScriptAnalyzer passes in. The rule runs once per file, on the
        root script block, and ignores the nested ones it is also called for.

    .EXAMPLE
        Invoke-ScriptAnalyzer -Path .\Source -Recurse -CustomRulePath .\Tests\Lint\PSScriptAnalyzerRules\*.psm1

    .OUTPUTS
        Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord, one per use
        of $_.

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
        [System.Management.Automation.Language.ScriptBlockAst]$ScriptBlockAst
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if ($null -ne $ScriptBlockAst.Parent) { return }

    $hits = @($ScriptBlockAst.FindAll({
        param([System.Management.Automation.Language.Ast]$Node)
        $Node -is [System.Management.Automation.Language.VariableExpressionAst] -and
            -not $Node.VariablePath.IsDriveQualified -and
            $Node.VariablePath.UserPath -eq '_'
    }, $true))

    foreach ($hit in $hits) {
        [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
            Message  = '[C-17] $_ used. Write $PSItem.'
            Extent   = $hit.Extent
            RuleName = 'Measure-C17UsePSItem'
            Severity = 'Warning'
        }
    }
}

Export-ModuleMember -Function 'Measure-C17UsePSItem'
