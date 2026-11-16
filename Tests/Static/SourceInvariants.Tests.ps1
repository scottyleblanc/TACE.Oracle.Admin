#Requires -Version 7.6

# Static tier. Proves invariants that a unit test cannot reach, by reading the source.
# Each title starts with the function name and the identifiers it proves (rule I-12), and
# is cited on a Static: line in that function's INVARIANTS block. It parses files only; it
# does not import the module or run a function.

BeforeAll {
    $script:repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent

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
}

Describe 'Source invariants' -Tag 'Static' {

    It 'ConvertFrom-SecureStringToPlaintext S5 the catch block refers to neither the buffer nor the input' -Tag 'SEC' {
        # A unit test cannot reach this: the only way to make the conversion throw is a
        # disposed SecureString, which fails before any plaintext exists. So the proof is
        # that the error path cannot read the value at all.
        $relative = Join-Path -Path 'Source' -ChildPath 'Private' -AdditionalChildPath 'ConvertFrom-SecureStringToPlaintext.ps1'
        $function = Get-SourceFunction -RelativePath $relative -Name 'ConvertFrom-SecureStringToPlaintext'
        $function | Should -Not -BeNullOrEmpty

        $catches = @($function.FindAll({
                    param([System.Management.Automation.Language.Ast]$node)
                    $node -is [System.Management.Automation.Language.CatchClauseAst]
                }, $true))
        $catches.Count | Should -BeGreaterThan 0 -Because 'the function converts its own errors'

        foreach ($catch in $catches) {
            $variables = @($catch.Body.FindAll({
                        param([System.Management.Automation.Language.Ast]$node)
                        $node -is [System.Management.Automation.Language.VariableExpressionAst]
                    }, $true) | ForEach-Object { $PSItem.VariablePath.UserPath })
            $variables | Should -Not -Contain 'ptr'
            $variables | Should -Not -Contain 'SecureString'
            $catch.Body.Extent.Text | Should -Not -Match 'PtrToString|SecureStringTo'
        }
    }
}
