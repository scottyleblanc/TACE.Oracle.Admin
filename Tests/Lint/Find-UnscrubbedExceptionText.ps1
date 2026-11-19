#Requires -Version 7.6
<#
.SYNOPSIS
    Finds exception text that leaves a function without passing through the scrub.

.DESCRIPTION
    Dot-sourced by the static tier. Defines Find-UnscrubbedExceptionText, which returns
    every `.Exception.Message` read in the given syntax tree that is not an argument of
    an Invoke-CredentialScrub call (rule S-07). Each hit is 'line N: text'.

    It sees `.Exception.Message` only. Exception text reached another way, such as
    "$PSItem" or $PSItem.ToString(), is not matched and is left to review.

.NOTES
    Copyright © TACE Data Management Inc.
    **Invocation:** lib helper — dot-sourced by Tests\Static\ExceptionScrub.Tests.ps1
    and Tests\Static\SourceInvariants.Tests.ps1.
#>

function Find-UnscrubbedExceptionText {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.Ast]$Ast
    )
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $reads = @($Ast.FindAll({
                param([System.Management.Automation.Language.Ast]$node)
                $node -is [System.Management.Automation.Language.MemberExpressionAst] -and
                $node.Member.Extent.Text -eq 'Message' -and
                $node.Expression -is [System.Management.Automation.Language.MemberExpressionAst] -and
                $node.Expression.Member.Extent.Text -eq 'Exception'
            }, $true))

    foreach ($read in $reads) {
        $scrubbed = $false
        $parent = $read.Parent
        while ($null -ne $parent) {
            if ($parent -is [System.Management.Automation.Language.CommandAst] -and
                $parent.GetCommandName() -eq 'Invoke-CredentialScrub') {
                $scrubbed = $true
                break
            }
            $parent = $parent.Parent
        }
        if (-not $scrubbed) { "line $($read.Extent.StartLineNumber): $($read.Extent.Text)" }
    }
}
