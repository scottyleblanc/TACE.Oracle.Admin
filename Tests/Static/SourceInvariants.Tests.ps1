#Requires -Version 7.6

# Static tier. Proves invariants that a unit test cannot reach, by reading the source.
# Each title starts with the function name and the identifiers it proves (rule I-12), and
# is cited on a Static: line in that function's INVARIANTS block. It parses files only; it
# does not import the module or run a function. Every check reads the syntax tree, so
# comments and help text never count.

BeforeAll {
    $script:repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent

    # Types whose use means a file, process, registry, network or environment change.
    $script:sideEffectTypes = 'IO\.File$|IO\.Directory$|IO\.StreamWriter$|IO\.FileStream$|Diagnostics\.Process|^System\.Environment$|^Environment$|Microsoft\.Win32|Registry|^System\.Net\.|^Net\.'
    # Methods that write or start something.
    $script:writeMembers = '^(Write|WriteAll\w*|WriteLine|AppendAll\w*|Create|CreateText|Delete|Move|Copy|SetValue|Kill|Start|SetEnvironmentVariable)$'
    # Methods that turn a secure value into plaintext.
    $script:plaintextMembers = @(
        'SecureStringToGlobalAllocUnicode', 'SecureStringToGlobalAllocAnsi', 'SecureStringToBSTR'
        'SecureStringToCoTaskMemUnicode', 'SecureStringToCoTaskMemAnsi'
        'PtrToStringUni', 'PtrToStringAnsi', 'PtrToStringAuto', 'PtrToStringBSTR', 'GetNetworkCredential'
    )

    function Get-SourcePath {
        param([string]$Folder, [string]$Name)
        Join-Path -Path 'Source' -ChildPath $Folder -AdditionalChildPath "$Name.ps1"
    }

    # Returns the function definition named $Name from a file under Source\.
    function Get-SourceFunction {
        param([string]$RelativePath, [string]$Name)
        $path = Join-Path -Path $script:repoRoot -ChildPath $RelativePath
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
        $ast.Find({
                param([System.Management.Automation.Language.Ast]$node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
            }, $true)
    }

    # Every function defined in Source\Public and Source\Private.
    function Get-AllSourceFunction {
        foreach ($folder in @('Public', 'Private')) {
            $dir = Join-Path -Path $script:repoRoot -ChildPath 'Source' -AdditionalChildPath $folder
            foreach ($file in @(Get-ChildItem -LiteralPath $dir -Filter '*.ps1' -File)) {
                $tokens = $null
                $errors = $null
                $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
                $ast.FindAll({
                        param([System.Management.Automation.Language.Ast]$node)
                        $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
                    }, $false)
            }
        }
    }

    function Find-Node {
        param([System.Management.Automation.Language.Ast]$Ast, [type]$Type)
        @($Ast.FindAll({ param($node) $node -is $Type }.GetNewClosure(), $true))
    }

    # Names of the commands called. A call through a variable (& $block) has no name.
    function Get-CommandName {
        param([System.Management.Automation.Language.Ast]$Ast)
        @(Find-Node -Ast $Ast -Type ([System.Management.Automation.Language.CommandAst]) |
            ForEach-Object { $PSItem.GetCommandName() } | Where-Object { $PSItem } | Sort-Object -Unique)
    }

    # Names of the environment variables read or, with -Assigned, written.
    function Get-EnvironmentVariableName {
        param([System.Management.Automation.Language.Ast]$Ast, [switch]$Assigned)
        $variables = @(Find-Node -Ast $Ast -Type ([System.Management.Automation.Language.VariableExpressionAst]) |
            Where-Object { $PSItem.VariablePath.DriveName -eq 'env' })
        if ($Assigned) { $variables = @($variables | Where-Object { Test-IsAssignmentTarget -Ast $PSItem }) }
        @($variables | ForEach-Object { $PSItem.VariablePath.UserPath -replace '^env:', '' } | Sort-Object -Unique)
    }

    # Full names of the types named, in casts, static calls and type literals.
    function Get-TypeName {
        param([System.Management.Automation.Language.Ast]$Ast)
        $expressions = @(Find-Node -Ast $Ast -Type ([System.Management.Automation.Language.TypeExpressionAst]) | ForEach-Object { $PSItem.TypeName.FullName })
        $constraints = @(Find-Node -Ast $Ast -Type ([System.Management.Automation.Language.TypeConstraintAst]) | ForEach-Object { $PSItem.TypeName.FullName })
        @($expressions + $constraints | Sort-Object -Unique)
    }

    # Names of the methods called, instance and static.
    function Get-MemberName {
        param([System.Management.Automation.Language.Ast]$Ast)
        @(Find-Node -Ast $Ast -Type ([System.Management.Automation.Language.InvokeMemberExpressionAst]) |
            ForEach-Object { $PSItem.Member.Extent.Text } | Sort-Object -Unique)
    }

    # Variables assigned in the env:, global: or script: scope.
    function Get-AssignedScope {
        param([System.Management.Automation.Language.Ast]$Ast)
        @(Find-Node -Ast $Ast -Type ([System.Management.Automation.Language.VariableExpressionAst]) |
            Where-Object { $PSItem.VariablePath.DriveName -in @('env', 'global', 'script') -or $PSItem.VariablePath.IsGlobal -or $PSItem.VariablePath.IsScript } |
            Where-Object { Test-IsAssignmentTarget -Ast $PSItem } |
            ForEach-Object { $PSItem.VariablePath.UserPath })
    }

    function Test-InParamBlock {
        param([System.Management.Automation.Language.Ast]$Ast)
        for ($node = $Ast.Parent; $null -ne $node; $node = $node.Parent) {
            if ($node -is [System.Management.Automation.Language.ParamBlockAst]) { return $true }
        }
        $false
    }

    # True when the variable is what an assignment writes: $x = ..., $x[i] = ... or $x.p = ...
    function Test-IsAssignmentTarget {
        param([System.Management.Automation.Language.Ast]$Ast)
        $node = $Ast
        # -and and -or have equal precedence in PowerShell, so each pair is bracketed.
        while (($node.Parent -is [System.Management.Automation.Language.IndexExpressionAst] -and $node.Parent.Target -eq $node) -or
            ($node.Parent -is [System.Management.Automation.Language.MemberExpressionAst] -and $node.Parent.Expression -eq $node)) {
            $node = $node.Parent
        }
        $node.Parent -is [System.Management.Automation.Language.AssignmentStatementAst] -and $node.Parent.Left -eq $node
    }

    # The finally blocks in a function.
    function Get-FinallyBlock {
        param([System.Management.Automation.Language.Ast]$Ast)
        @(Find-Node -Ast $Ast -Type ([System.Management.Automation.Language.TryStatementAst]) |
            Where-Object { $null -ne $PSItem.Finally } | ForEach-Object { $PSItem.Finally })
    }
}

Describe 'Source invariants' -Tag 'Static' {

    It 'ConvertFrom-SecureStringToPlaintext S5 the catch block refers to neither the buffer nor the input' -Tag 'SEC' {
        # A unit test cannot reach this: the only way to make the conversion throw is a
        # disposed SecureString, which fails before any plaintext exists. So the proof is
        # that the error path cannot read the value at all.
        $function = Get-SourceFunction -RelativePath (Get-SourcePath 'Private' 'ConvertFrom-SecureStringToPlaintext') -Name 'ConvertFrom-SecureStringToPlaintext'
        $function | Should -Not -BeNullOrEmpty

        $catches = @(Find-Node -Ast $function -Type ([System.Management.Automation.Language.CatchClauseAst]))
        $catches.Count | Should -BeGreaterThan 0 -Because 'the function converts its own errors'

        foreach ($catch in $catches) {
            $variables = @(Find-Node -Ast $catch.Body -Type ([System.Management.Automation.Language.VariableExpressionAst]) |
                ForEach-Object { $PSItem.VariablePath.UserPath })
            $variables | Should -Not -Contain 'ptr'
            $variables | Should -Not -Contain 'SecureString'
            @(Get-MemberName -Ast $catch.Body | Where-Object { $PSItem -in $script:plaintextMembers }) | Should -BeNullOrEmpty
        }
    }

    It 'ConvertFrom-SecureStringToPlaintext S2 zeroes and frees the buffer in a finally block' -Tag 'SEC' {
        # A unit test cannot see unmanaged memory. The proof is the structure: the pointer
        # starts at Zero before the try, and the finally zeroes and frees it.
        $function = Get-SourceFunction -RelativePath (Get-SourcePath 'Private' 'ConvertFrom-SecureStringToPlaintext') -Name 'ConvertFrom-SecureStringToPlaintext'
        $function | Should -Not -BeNullOrEmpty

        $initial = @(Find-Node -Ast $function.Body -Type ([System.Management.Automation.Language.AssignmentStatementAst]) |
            Where-Object { $PSItem.Left.Extent.Text -eq '$ptr' -and $PSItem.Right.Extent.Text -eq '[IntPtr]::Zero' })
        $initial | Should -HaveCount 1

        $frees = @(Get-FinallyBlock -Ast $function.Body | ForEach-Object {
                Find-Node -Ast $PSItem -Type ([System.Management.Automation.Language.InvokeMemberExpressionAst]) |
                    Where-Object { $PSItem.Member.Extent.Text -eq 'ZeroFreeGlobalAllocUnicode' -and $PSItem.Arguments[0].Extent.Text -eq '$ptr' }
            })
        $frees | Should -HaveCount 1
    }

    It 'Invoke-RmanProcess L3 disposes the process in a finally block' {
        $function = Get-SourceFunction -RelativePath (Get-SourcePath 'Private' 'Invoke-RmanProcess') -Name 'Invoke-RmanProcess'
        $disposes = @(Get-FinallyBlock -Ast $function.Body | ForEach-Object {
                Find-Node -Ast $PSItem -Type ([System.Management.Automation.Language.InvokeMemberExpressionAst]) |
                    Where-Object { $PSItem.Member.Extent.Text -eq 'Dispose' -and $PSItem.Expression.Extent.Text -eq '$process' }
            })
        $disposes | Should -HaveCount 1
    }

    It 'Invoke-RmanProcess L6 the timeout branch guards Kill and WaitForExit and ends in the timeout throw' {
        # A unit test cannot make Kill() fail on demand: that needs the process to exit
        # between the timeout and the kill. So the proof is the shape of the branch.
        $function = Get-SourceFunction -RelativePath (Get-SourcePath 'Private' 'Invoke-RmanProcess') -Name 'Invoke-RmanProcess'
        $function | Should -Not -BeNullOrEmpty
        $branches = @(Find-Node -Ast $function.Body -Type ([System.Management.Automation.Language.IfStatementAst]) |
            Where-Object { $PSItem.Clauses[0].Item1.Extent.Text -eq '-not $completed' })
        $branches | Should -HaveCount 1
        $body = $branches[0].Clauses[0].Item2

        # The branch ends in the timeout throw.
        $last = $body.Statements[$body.Statements.Count - 1]
        $last | Should -BeOfType ([System.Management.Automation.Language.ThrowStatementAst])
        $last.Extent.Text | Should -BeLike '*timed out after*'

        # Kill and WaitForExit each sit in a try, directly in the branch, whose catches
        # do not throw.
        foreach ($member in @('Kill', 'WaitForExit')) {
            $calls = @(Find-Node -Ast $body -Type ([System.Management.Automation.Language.InvokeMemberExpressionAst]) |
                Where-Object { $PSItem.Member.Extent.Text -eq $member -and $PSItem.Expression.Extent.Text -eq '$process' })
            $calls | Should -HaveCount 1 -Because "the timeout branch calls $member once"
            $try = $calls[0].Parent
            while ($null -ne $try -and $try -isnot [System.Management.Automation.Language.TryStatementAst]) { $try = $try.Parent }
            $try | Should -Not -BeNullOrEmpty -Because "$member must be inside a try"
            [object]::ReferenceEquals($try.Parent, $body) | Should -BeTrue -Because "the try around $member must sit directly in the timeout branch"
            $try.CatchClauses.Count | Should -BeGreaterThan 0
            $throws = @($try.CatchClauses | ForEach-Object {
                    Find-Node -Ast $PSItem -Type ([System.Management.Automation.Language.ThrowStatementAst])
                })
            $throws | Should -HaveCount 0 -Because "a failed $member must not replace the timeout error"
        }

        # The killed process is given 5 seconds to exit.
        $wait = @(Find-Node -Ast $body -Type ([System.Management.Automation.Language.InvokeMemberExpressionAst]) |
            Where-Object { $PSItem.Member.Extent.Text -eq 'WaitForExit' })
        @($wait[0].Arguments).Count | Should -Be 1
        $wait[0].Arguments[0].Extent.Text | Should -Be '5000'
    }

    It 'Invoke-TnspingProcess L3 disposes the process in a finally block' {
        $function = Get-SourceFunction -RelativePath (Get-SourcePath 'Private' 'Invoke-TnspingProcess') -Name 'Invoke-TnspingProcess'
        $disposes = @(Get-FinallyBlock -Ast $function.Body | ForEach-Object {
                Find-Node -Ast $PSItem -Type ([System.Management.Automation.Language.InvokeMemberExpressionAst]) |
                    Where-Object { $PSItem.Member.Extent.Text -eq 'Dispose' -and $PSItem.Expression.Extent.Text -eq '$proc' }
            })
        $disposes | Should -HaveCount 1
    }

    It 'ConvertFrom-RmanListBackup S1 reads RawLog only: no command but Write-Verbose, and no file, process, environment or credential access' -Tag 'SEC' {
        $function = Get-SourceFunction -RelativePath (Get-SourcePath 'Private' 'ConvertFrom-RmanListBackup') -Name 'ConvertFrom-RmanListBackup'
        $function | Should -Not -BeNullOrEmpty

        @(Get-CommandName -Ast $function.Body | Where-Object { $PSItem -notin @('Set-StrictMode', 'Write-Verbose', 'Out-Null') }) | Should -BeNullOrEmpty
        @(Get-EnvironmentVariableName -Ast $function.Body) | Should -BeNullOrEmpty
        @(Get-TypeName -Ast $function.Body | Where-Object { $PSItem -match $script:sideEffectTypes }) | Should -BeNullOrEmpty
        @($function.Body.ParamBlock.Parameters | ForEach-Object { $PSItem.Name.VariablePath.UserPath }) | Should -Be @('RawLog')
    }

    It 'ConvertFrom-SecureStringToPlaintext S3 is the only function that reads plaintext out of a secure value' -Tag 'SEC' {
        $found = foreach ($function in (Get-AllSourceFunction)) {
            if ($function.Name -eq 'ConvertFrom-SecureStringToPlaintext') { continue }
            foreach ($member in (Get-MemberName -Ast $function.Body)) {
                if ($member -in $script:plaintextMembers) { "$($function.Name): .$member" }
            }
            foreach ($type in (Get-TypeName -Ast $function.Body)) {
                if ($type -match 'NetworkCredential$') { "$($function.Name): [$type]" }
            }
            foreach ($command in @($function.Body.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true))) {
                if ($command.GetCommandName() -eq 'ConvertFrom-SecureString' -and $command.Extent.Text -match '-AsPlainText') {
                    "$($function.Name): ConvertFrom-SecureString -AsPlainText"
                }
            }
        }
        ($found -join '; ') | Should -BeNullOrEmpty
    }

    It 'Invoke-RmanProcess S2 extracts the password only inside the stdin write, never into a variable' -Tag 'SEC' {
        $calls = foreach ($function in (Get-AllSourceFunction)) {
            if ($function.Name -eq 'ConvertFrom-SecureStringToPlaintext') { continue }
            foreach ($command in @($function.Body.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true))) {
                if ($command.GetCommandName() -eq 'ConvertFrom-SecureStringToPlaintext') {
                    [PSCustomObject]@{ Function = $function.Name; Command = $command }
                }
            }
        }
        @($calls).Count | Should -BeGreaterThan 0 -Because 'NamedCredential mode needs the password once'

        foreach ($call in @($calls)) {
            $call.Function | Should -Be 'Invoke-RmanProcess'

            # Walk up from the call. The first thing that holds it must be a WriteLine on
            # StandardInput; an assignment on the way means the plaintext was stored.
            $node    = $call.Command.Parent
            $writeTo = $null
            while ($null -ne $node) {
                $node | Should -Not -BeOfType ([System.Management.Automation.Language.AssignmentStatementAst])
                if ($node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $node.Member.Extent.Text -eq 'WriteLine') {
                    $writeTo = $node.Expression.Extent.Text
                    break
                }
                $node = $node.Parent
            }
            $writeTo | Should -Match 'StandardInput$'
        }
    }

    It 'Get-OracleDatabaseList S1 makes no Oracle connection and reads no credential' -Tag 'SEC' {
        $function = Get-SourceFunction -RelativePath (Get-SourcePath 'Public' 'Get-OracleDatabaseList') -Name 'Get-OracleDatabaseList'
        $function | Should -Not -BeNullOrEmpty

        $forbidden = @('Invoke-RmanProcess', 'Invoke-TnspingProcess', 'ConvertFrom-SecureStringToPlaintext', 'Start-Process',
            'sqlplus', 'sqlplus.exe', 'rman', 'rman.exe', 'tnsping', 'tnsping.exe', 'Get-Credential', 'Get-StoredCredential')
        @(Get-CommandName -Ast $function.Body | Where-Object { $PSItem -in $forbidden }) | Should -BeNullOrEmpty
        @(Get-TypeName -Ast $function.Body | Where-Object { $PSItem -match 'Process|SecureString|PSCredential|Oracle|Data\.' }) | Should -BeNullOrEmpty
        @($function.Body.ParamBlock.Parameters | Where-Object { $PSItem.StaticType -in @([securestring], [pscredential]) }) | Should -BeNullOrEmpty
    }

    It 'Get-OracleDatabaseList L1 is read-only: every command it calls only reads' {
        $function = Get-SourceFunction -RelativePath (Get-SourcePath 'Public' 'Get-OracleDatabaseList') -Name 'Get-OracleDatabaseList'
        $readers = @('Set-StrictMode', 'Get-CimInstance', 'Get-Content', 'Get-Process', 'Get-Date', 'Test-Path', 'Split-Path', 'ForEach-Object', 'Write-Verbose')
        @(Get-CommandName -Ast $function.Body | Where-Object { $PSItem -notin $readers }) | Should -BeNullOrEmpty
        @(Get-AssignedScope -Ast $function.Body) | Should -BeNullOrEmpty
        @(Get-MemberName -Ast $function.Body | Where-Object { $PSItem -match $script:writeMembers }) | Should -BeNullOrEmpty
    }

    It 'Get-RmanBackupStatus S3 hands Credential to Invoke-RmanProcess and to nothing else' -Tag 'SEC' {
        $function = Get-SourceFunction -RelativePath (Get-SourcePath 'Public' 'Get-RmanBackupStatus') -Name 'Get-RmanBackupStatus'
        $function | Should -Not -BeNullOrEmpty

        $uses = @($function.Body.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.VariableExpressionAst] -and $node.VariablePath.UserPath -eq 'Credential'
                }, $true) | Where-Object { -not (Test-InParamBlock -Ast $PSItem) })
        $uses.Count | Should -BeGreaterThan 0

        foreach ($use in $uses) {
            $parent = $use.Parent
            $isNullCheck = $parent -is [System.Management.Automation.Language.BinaryExpressionAst] -and
                ($parent.Left.Extent.Text -eq '$null' -or $parent.Right.Extent.Text -eq '$null')
            $isHandOff = $parent -is [System.Management.Automation.Language.CommandExpressionAst] -and
                $parent.Parent -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $parent.Parent.Left.Extent.Text -eq '$rmanInvokeParams[''Credential'']'
            ($isNullCheck -or $isHandOff) | Should -BeTrue -Because "line $($use.Extent.StartLineNumber): $($parent.Extent.Text)"
        }

        # The parameter table is read in one place: the splat into Invoke-RmanProcess.
        $splats = @($function.Body.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.VariableExpressionAst] -and $node.VariablePath.UserPath -eq 'rmanInvokeParams' -and $node.Splatted
                }, $true))
        $splats.Count | Should -Be 1
        $splats[0].Parent.GetCommandName() | Should -Be 'Invoke-RmanProcess'
        $reads = @($function.Body.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.VariableExpressionAst] -and $node.VariablePath.UserPath -eq 'rmanInvokeParams' -and -not $node.Splatted
                }, $true) | Where-Object { -not (Test-IsAssignmentTarget -Ast $PSItem) })
        ($reads | ForEach-Object { $PSItem.Parent.Extent.Text }) -join '; ' | Should -BeNullOrEmpty
    }

    It 'Set-OracleEnv S2 changes only ORACLE_SID, ORACLE_HOME and ORACLE_BASE, and writes nothing to disk, the registry or another process' -Tag 'SEC' {
        $function = Get-SourceFunction -RelativePath (Get-SourcePath 'Public' 'Set-OracleEnv') -Name 'Set-OracleEnv'
        $function | Should -Not -BeNullOrEmpty

        @(Get-EnvironmentVariableName -Ast $function.Body -Assigned | Where-Object { $PSItem -notin @('ORACLE_SID', 'ORACLE_HOME', 'ORACLE_BASE') }) | Should -BeNullOrEmpty
        $writers = @('Set-Content', 'Add-Content', 'Out-File', 'New-Item', 'Set-Item', 'Remove-Item', 'Copy-Item', 'Move-Item',
            'Set-ItemProperty', 'New-ItemProperty', 'Remove-ItemProperty', 'Start-Process', 'Set-Variable', 'Export-Clixml', 'Export-Csv')
        @(Get-CommandName -Ast $function.Body | Where-Object { $PSItem -in $writers -or $PSItem -match '\.exe$' }) | Should -BeNullOrEmpty
        @(Get-MemberName -Ast $function.Body | Where-Object { $PSItem -match $script:writeMembers -or $PSItem -eq 'SetEnvironmentVariable' }) | Should -BeNullOrEmpty
        @(Get-TypeName -Ast $function.Body | Where-Object { $PSItem -match $script:sideEffectTypes }) | Should -BeNullOrEmpty
    }

    It 'Set-OracleEnv L3 calls neither Read-Host nor Write-Host' {
        $function = Get-SourceFunction -RelativePath (Get-SourcePath 'Public' 'Set-OracleEnv') -Name 'Set-OracleEnv'
        @(Get-CommandName -Ast $function.Body | Where-Object { $PSItem -in @('Read-Host', 'Write-Host') }) | Should -BeNullOrEmpty
    }
}
