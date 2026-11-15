#Requires -Version 7.6

function Measure-C05OutputTypeDeclared {
    <#
    .SYNOPSIS
        Rule C-05: every function declares its output type.

    .DESCRIPTION
        Reports a function whose param block has no [OutputType()] attribute, or that has
        no param block at all. Custom PSScriptAnalyzer rule (decision 26).

    .PARAMETER ScriptBlockAst
        The script block PSScriptAnalyzer passes in. The rule runs once per file, on the
        root script block, and ignores the nested ones it is also called for.

    .EXAMPLE
        Invoke-ScriptAnalyzer -Path .\Source -Recurse -CustomRulePath .\Tests\Lint\PSScriptAnalyzerRules\*.psm1

    .OUTPUTS
        Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord, one per
        function without [OutputType()].

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

    $functions = @($ScriptBlockAst.FindAll({
        param([System.Management.Automation.Language.Ast]$Node)
        $Node -is [System.Management.Automation.Language.FunctionDefinitionAst]
    }, $true))

    foreach ($function in $functions) {
        $paramBlock = $function.Body.ParamBlock
        $declared = $null -ne $paramBlock -and @($paramBlock.Attributes | Where-Object {
            ($PSItem.TypeName.Name -split '\.')[-1] -in @('OutputType', 'OutputTypeAttribute')
        }).Count -gt 0

        if (-not $declared) {
            [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
                Message  = "[C-05] Function '$($function.Name)' does not declare its output type. Add [OutputType()] below [CmdletBinding()]."
                Extent   = $function.Extent
                RuleName = 'Measure-C05OutputTypeDeclared'
                Severity = 'Warning'
            }
        }
    }
}

Export-ModuleMember -Function 'Measure-C05OutputTypeDeclared'
