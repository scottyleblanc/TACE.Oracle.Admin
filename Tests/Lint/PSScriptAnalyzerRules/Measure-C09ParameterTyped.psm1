#Requires -Version 7.6

function Measure-C09ParameterTyped {
    <#
    .SYNOPSIS
        Rule C-09: every parameter has an explicit type.

    .DESCRIPTION
        Reports a parameter with no type constraint. Function, script and script block
        parameters are all checked. Custom PSScriptAnalyzer rule (decision 26).

    .PARAMETER ScriptBlockAst
        The script block PSScriptAnalyzer passes in. The rule runs once per file, on the
        root script block, and ignores the nested ones it is also called for.

    .EXAMPLE
        Invoke-ScriptAnalyzer -Path .\Source -Recurse -CustomRulePath .\Tests\Lint\PSScriptAnalyzerRules\*.psm1

    .OUTPUTS
        Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord, one per
        untyped parameter.

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

    $parameters = @($ScriptBlockAst.FindAll({
        param([System.Management.Automation.Language.Ast]$Node)
        $Node -is [System.Management.Automation.Language.ParameterAst]
    }, $true))

    foreach ($parameter in $parameters) {
        $typed = @($parameter.Attributes | Where-Object {
            $PSItem -is [System.Management.Automation.Language.TypeConstraintAst]
        }).Count -gt 0

        if (-not $typed) {
            [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
                Message  = "[C-09] Parameter '$($parameter.Name.VariablePath.UserPath)' has no explicit type."
                Extent   = $parameter.Extent
                RuleName = 'Measure-C09ParameterTyped'
                Severity = 'Warning'
            }
        }
    }
}

Export-ModuleMember -Function 'Measure-C09ParameterTyped'
