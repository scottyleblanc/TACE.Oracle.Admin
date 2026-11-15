#Requires -Version 7.6

function Measure-C33ShouldProcessGate {
    <#
    .SYNOPSIS
        Rule C-33: in Source\, a call to a command that honours -WhatIf decides what a
        preview does with it.

    .DESCRIPTION
        Applies to files under a Source\ folder. Reports a call to a command that has a
        -WhatIf parameter unless one of these holds:
          - Gated: it is inside the body of an if whose condition is
            $PSCmdlet.ShouldProcess(...), or a variable assigned from it in the same
            function.
          - After an early return: an earlier if in the same function returns or throws
            when $PSCmdlet.ShouldProcess(...) is declined.
          - Explicit: the call passes -WhatIf itself, such as -WhatIf:$false for work
            that must happen even during a preview.
        Without one of these, a caller's -WhatIf reaches the call as $WhatIfPreference
        and silently skips it, or the call runs when the caller meant to preview.
        Whether a command has -WhatIf is asked of PowerShell when the rule runs. Only
        compiled cmdlets are checked (Set-Content, New-Item, Remove-Item, Set-Acl, ...),
        so the result is the same on every machine; ForEach-Object is excluded because it
        accepts -WhatIf but changes nothing itself. Custom PSScriptAnalyzer rule
        (decision 27).

    .PARAMETER ScriptBlockAst
        The script block PSScriptAnalyzer passes in. The rule runs once per file, on the
        root script block, and ignores the nested ones it is also called for.

    .EXAMPLE
        Invoke-ScriptAnalyzer -Path .\Source -Recurse -CustomRulePath .\Tests\Lint\PSScriptAnalyzerRules\*.psm1

    .OUTPUTS
        Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord, one per
        call that a preview would skip without a decision.

    .NOTES
        Copyright © TACE Data Management Inc.
        Returns diagnostic records, not the Success/Data/Message object: this is the
        contract PSScriptAnalyzer requires of a rule.
        Limitation: .NET calls ([System.IO.File]::WriteAllText, Process.Start) and
        $env: assignments never honour -WhatIf, so they are not checked; review covers
        them. A function, from this module or any other, is not checked: one that
        supports ShouldProcess makes its own preview decision, and one that does not
        cannot be told apart reliably. "After an early return" is read from source
        order, not from control flow.
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

    $file = $ScriptBlockAst.Extent.File
    if ([string]::IsNullOrEmpty($file) -or $file -notmatch '[\\/]Source[\\/]') { return }

    $shouldProcess    = '\$PSCmdlet\.ShouldProcess\('
    $supportsWhatIf   = @{}
    $notStateChanging = @('ForEach-Object')

    $commands = @($ScriptBlockAst.FindAll({
        param([System.Management.Automation.Language.Ast]$Node)
        $Node -is [System.Management.Automation.Language.CommandAst]
    }, $true))

    foreach ($command in $commands) {
        $name = $command.GetCommandName()
        if ([string]::IsNullOrEmpty($name)) { continue }

        if (-not $supportsWhatIf.ContainsKey($name)) {
            $resolved = Get-Command -Name $name -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($null -ne $resolved -and $resolved.CommandType -eq 'Alias') { $resolved = $resolved.ResolvedCommand }
            # Compiled cmdlets only, so the result does not depend on which modules happen
            # to be installed. ForEach-Object accepts -WhatIf but changes nothing itself.
            $supportsWhatIf[$name] = $null -ne $resolved -and
                $resolved.CommandType -eq 'Cmdlet' -and
                $resolved.Name -notin $notStateChanging -and
                $resolved.Parameters.ContainsKey('WhatIf')
        }
        if (-not $supportsWhatIf[$name]) { continue }

        # Explicit: the call passes -WhatIf itself.
        $explicit = @($command.CommandElements | Where-Object {
            $PSItem -is [System.Management.Automation.Language.CommandParameterAst] -and
            $PSItem.ParameterName -eq 'WhatIf'
        }).Count -gt 0
        if ($explicit) { continue }

        # The enclosing function, if any.
        $function = $command.Parent
        while ($null -ne $function -and $function -isnot [System.Management.Automation.Language.FunctionDefinitionAst]) {
            $function = $function.Parent
        }
        $scope = if ($null -ne $function) { $function.Body } else { $ScriptBlockAst }

        # Variables assigned from ShouldProcess in this scope: $applied = $PSCmdlet.ShouldProcess(...)
        $gateVariables = @($scope.FindAll({
            param([System.Management.Automation.Language.Ast]$Node)
            $Node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $Node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
                $Node.Right.Extent.Text -match '^\$PSCmdlet\.ShouldProcess\('
        }, $true) | ForEach-Object { $PSItem.Left.VariablePath.UserPath })

        # Gated: inside the body of an if clause whose condition is the gate.
        $gated = $false
        $child = $command
        $parent = $command.Parent
        while ($null -ne $parent -and $parent -ne $scope.Parent) {
            if ($parent -is [System.Management.Automation.Language.IfStatementAst]) {
                foreach ($clause in $parent.Clauses) {
                    if ($clause.Item2 -ne $child) { continue }
                    $condition = $clause.Item1.Extent.Text.Trim()
                    $isGate = ($condition -match "^$shouldProcess") -or
                        @($gateVariables | Where-Object { $condition -eq "`$$PSItem" }).Count -gt 0
                    if ($isGate) { $gated = $true }
                }
            }
            $child = $parent
            $parent = $parent.Parent
        }
        if ($gated) { continue }

        # After an early return: an earlier if that returns or throws when the gate declines.
        $start = $command.Extent.StartOffset
        $earlyReturn = @($scope.FindAll({
            param([System.Management.Automation.Language.Ast]$Node)
            $Node -is [System.Management.Automation.Language.IfStatementAst] -and
                $Node.Extent.EndOffset -lt $start
        }, $true) | Where-Object {
            $condition = $PSItem.Clauses[0].Item1.Extent.Text.Trim()
            $declined = ($condition -match "^(-not\s*|!\s*)\(?\s*$shouldProcess") -or
                @($gateVariables | Where-Object { $condition -match "^(-not\s*|!\s*)\`$$PSItem$" }).Count -gt 0
            $leaves = @($PSItem.Clauses[0].Item2.FindAll({
                param([System.Management.Automation.Language.Ast]$Node)
                $Node -is [System.Management.Automation.Language.ReturnStatementAst] -or
                    $Node -is [System.Management.Automation.Language.ThrowStatementAst]
            }, $true)).Count -gt 0
            $declined -and $leaves
        }).Count -gt 0
        if ($earlyReturn) { continue }

        [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
            Message  = "[C-33] '$name' honours -WhatIf but no ShouldProcess decision covers it. Gate it with `$PSCmdlet.ShouldProcess, return early when ShouldProcess declines, or pass -WhatIf:`$false if it must run during a preview."
            Extent   = $command.Extent
            RuleName = 'Measure-C33ShouldProcessGate'
            Severity = 'Warning'
        }
    }
}

Export-ModuleMember -Function 'Measure-C33ShouldProcessGate'
