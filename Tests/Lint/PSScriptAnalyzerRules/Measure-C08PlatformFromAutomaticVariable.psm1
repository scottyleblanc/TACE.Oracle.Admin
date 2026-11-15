#Requires -Version 7.6

function Measure-C08PlatformFromAutomaticVariable {
    <#
    .SYNOPSIS
        Rule C-08: platform is detected with $IsWindows, $IsLinux or $IsMacOS, never from
        environment variables.

    .DESCRIPTION
        Reports a read of the OS environment variable, as $env:OS or through
        [Environment]::GetEnvironmentVariable('OS'). Custom PSScriptAnalyzer rule
        (decision 26).

    .PARAMETER ScriptBlockAst
        The script block PSScriptAnalyzer passes in. The rule runs once per file, on the
        root script block, and ignores the nested ones it is also called for.

    .EXAMPLE
        Invoke-ScriptAnalyzer -Path .\Source -Recurse -CustomRulePath .\Tests\Lint\PSScriptAnalyzerRules\*.psm1

    .OUTPUTS
        Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord, one per read
        of the OS variable.

    .NOTES
        Copyright © TACE Data Management Inc.
        Returns diagnostic records, not the Success/Data/Message object: this is the
        contract PSScriptAnalyzer requires of a rule.
        Limitation: only the OS variable is checked. It is the one used for platform
        detection; other variables that happen to differ by platform are not.
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
        if ($Node -is [System.Management.Automation.Language.VariableExpressionAst]) {
            return $Node.VariablePath.IsDriveQualified -and
                $Node.VariablePath.DriveName -eq 'env' -and
                $Node.VariablePath.UserPath -eq 'env:OS'
        }
        if ($Node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
            $Node.Static -and
            $Node.Expression -is [System.Management.Automation.Language.TypeExpressionAst] -and
            $Node.Expression.TypeName.Name -in @('Environment', 'System.Environment') -and
            $Node.Member -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
            $Node.Member.Value -eq 'GetEnvironmentVariable' -and
            @($Node.Arguments).Count -ge 1) {
            $first = @($Node.Arguments)[0]
            return $first -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
                $first.Value -eq 'OS'
        }
        return $false
    }, $true))

    foreach ($hit in $hits) {
        [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
            Message  = '[C-08] Platform read from the OS environment variable. Use $IsWindows, $IsLinux or $IsMacOS.'
            Extent   = $hit.Extent
            RuleName = 'Measure-C08PlatformFromAutomaticVariable'
            Severity = 'Warning'
        }
    }
}

Export-ModuleMember -Function 'Measure-C08PlatformFromAutomaticVariable'
