#Requires -Version 7.6
<#
.SYNOPSIS
    Static tier: the custom PSScriptAnalyzer rules in Tests\Lint\PSScriptAnalyzerRules\.

.DESCRIPTION
    Each rule is run against small fixture files on TestDrive: code it must report and
    code it must not. Decision 26.

.NOTES
    Copyright © TACE Data Management Inc.
#>

BeforeAll {
    Import-Module PSScriptAnalyzer -RequiredVersion 1.25.0

    $script:repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $script:ruleDir  = Join-Path -Path $script:repoRoot -ChildPath 'Tests' -AdditionalChildPath 'Lint', 'PSScriptAnalyzerRules'
    $script:rulePath = Join-Path -Path $script:ruleDir -ChildPath '*.psm1'

    # Writes $Code to a fixture file and returns the findings of one custom rule.
    function Invoke-Rule {
        param(
            [Parameter(Mandatory)] [string] $Rule,
            [Parameter(Mandatory)] [string] $Code,
            [string] $RelativePath = 'Fixture.ps1'
        )
        $path = Join-Path -Path 'TestDrive:' -ChildPath $RelativePath
        $null = New-Item -Path (Split-Path -Path $path -Parent) -ItemType Directory -Force
        Set-Content -Path $path -Value $Code -Encoding UTF8
        $fullPath = (Resolve-Path -Path $path).ProviderPath
        @(Invoke-ScriptAnalyzer -Path $fullPath -CustomRulePath $script:rulePath -IncludeRule $Rule |
            Where-Object { $PSItem.RuleName -eq $Rule })
    }
}

Describe 'Custom rule set' {
    It 'loads every rule file, and each reports under its own file name' {
        $files = @(Get-ChildItem -Path $script:ruleDir -Filter '*.psm1' -File)
        $rules = @(Get-ScriptAnalyzerRule -CustomRulePath $script:rulePath | Where-Object { $PSItem.SourceType -ne 'Builtin' })
        $files.Count | Should -Be 10
        @($rules.RuleName | Sort-Object) | Should -Be @($files.BaseName | Sort-Object)
    }

    It 'honours a SuppressMessageAttribute on the function' {
        $code = @'
function Get-Thing {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('Measure-C17UsePSItem', '', Justification = 'Fixture.')]
    [OutputType([int])]
    param()
    1..2 | ForEach-Object { $_ }
}
'@
        Invoke-Rule -Rule 'Measure-C17UsePSItem' -Code $code | Should -HaveCount 0
    }
}

Describe 'C-05 Measure-C05OutputTypeDeclared' {
    It 'reports a function with a param block but no [OutputType()]' {
        Invoke-Rule -Rule 'Measure-C05OutputTypeDeclared' -Code "function Get-A {`n    [CmdletBinding()]`n    param()`n}" | Should -HaveCount 1
    }
    It 'reports a function with no param block' {
        Invoke-Rule -Rule 'Measure-C05OutputTypeDeclared' -Code "function Get-A ([string] `$Name) { `$Name }" | Should -HaveCount 1
    }
    It 'does not report a function that declares its output type' {
        Invoke-Rule -Rule 'Measure-C05OutputTypeDeclared' -Code "function Get-A {`n    [CmdletBinding()]`n    [OutputType([PSCustomObject])]`n    param()`n}" | Should -HaveCount 0
    }
}

Describe 'C-08 Measure-C08PlatformFromAutomaticVariable' {
    It 'reports $env:OS' {
        Invoke-Rule -Rule 'Measure-C08PlatformFromAutomaticVariable' -Code 'if ($env:OS -eq ''Windows_NT'') { 1 }' | Should -HaveCount 1
    }
    It 'reports [Environment]::GetEnvironmentVariable(''OS'')' {
        Invoke-Rule -Rule 'Measure-C08PlatformFromAutomaticVariable' -Code '[Environment]::GetEnvironmentVariable(''OS'')' | Should -HaveCount 1
    }
    It 'does not report $IsWindows or another environment variable' {
        Invoke-Rule -Rule 'Measure-C08PlatformFromAutomaticVariable' -Code 'if ($IsWindows) { $env:PATH }' | Should -HaveCount 0
    }
}

Describe 'C-09 Measure-C09ParameterTyped' {
    It 'reports an untyped function parameter' {
        Invoke-Rule -Rule 'Measure-C09ParameterTyped' -Code "function Get-A {`n    param(`$Name)`n}" | Should -HaveCount 1
    }
    It 'reports an untyped script block parameter' {
        Invoke-Rule -Rule 'Measure-C09ParameterTyped' -Code '$f = { param($node) $node }' | Should -HaveCount 1
    }
    It 'does not report typed parameters' {
        Invoke-Rule -Rule 'Measure-C09ParameterTyped' -Code "function Get-A {`n    param([string] `$Name, [switch] `$Force)`n}" | Should -HaveCount 0
    }
}

Describe 'C-10 Measure-C10PublicParameterValidated' {
    BeforeAll {
        $script:publicPath = Join-Path -Path 'Source' -ChildPath 'Public' -AdditionalChildPath 'Get-A.ps1'
    }
    It 'reports a public parameter with no [Validate*] attribute' {
        $code = "function Get-A {`n    param([Parameter()] [string] `$Name)`n}"
        Invoke-Rule -Rule 'Measure-C10PublicParameterValidated' -Code $code -RelativePath $script:publicPath | Should -HaveCount 1
    }
    It 'does not report a validated public parameter' {
        $code = "function Get-A {`n    param([ValidateNotNullOrEmpty()] [string] `$Name)`n}"
        Invoke-Rule -Rule 'Measure-C10PublicParameterValidated' -Code $code -RelativePath $script:publicPath | Should -HaveCount 0
    }
    It 'does not report switch, SecureString or PSCredential parameters' {
        $code = "function Get-A {`n    param([switch] `$Force, [SecureString] `$Password, [PSCredential] `$Credential)`n}"
        Invoke-Rule -Rule 'Measure-C10PublicParameterValidated' -Code $code -RelativePath $script:publicPath | Should -HaveCount 0
    }
    It 'does not check a file outside Source\Public' {
        $code = "function Get-A {`n    param([string] `$Name)`n}"
        $privatePath = Join-Path -Path 'Source' -ChildPath 'Private' -AdditionalChildPath 'Get-A.ps1'
        Invoke-Rule -Rule 'Measure-C10PublicParameterValidated' -Code $code -RelativePath $privatePath | Should -HaveCount 0
    }
}

Describe 'C-11 Measure-C11NoLineContinuation' {
    It 'reports a backtick line continuation' {
        $code = "Get-ChildItem ``" + "`n" + '    -Path .'
        Invoke-Rule -Rule 'Measure-C11NoLineContinuation' -Code $code | Should -HaveCount 1
    }
    It 'does not report splatting or a backtick escape inside a string' {
        $code = '$p = @{ Path = ''.'' }' + "`n" + 'Get-ChildItem @p' + "`n" + '"a`tb"'
        Invoke-Rule -Rule 'Measure-C11NoLineContinuation' -Code $code | Should -HaveCount 0
    }
}

Describe 'C-14 Measure-C14PathWithJoinPath' {
    It 'reports <Case>' -ForEach @(
        @{ Case = 'a joined string passed to -Path';            Code = 'Test-Path -Path "$oracleHome\bin"' }
        @{ Case = 'a joined string passed positionally';        Code = 'Get-Content "$root/file.txt"' }
        @{ Case = 'a joined string in a path-named variable';   Code = '$binPath = "$oracleHome\bin"' }
        @{ Case = 'a joined string under a path-named key';     Code = '$p = @{ LiteralPath = "$dir\x.log" }' }
        @{ Case = '+ with a separator constant';                Code = '$x = $oracleHome + ''\bin''' }
        @{ Case = '-join with a separator';                     Code = '$x = $parts -join ''\''' }
    ) {
        Invoke-Rule -Rule 'Measure-C14PathWithJoinPath' -Code $Code | Should -HaveCount 1
    }
    It 'does not report <Case>' -ForEach @(
        @{ Case = 'a path shown in a message';  Code = 'throw "Source\$name.psd1 declares a generated key."' }
        @{ Case = 'a URL';                      Code = '$uri = "https://$server/api"' }
        @{ Case = 'Join-Path';                  Code = '$binPath = Join-Path -Path $oracleHome -ChildPath ''bin''' }
        @{ Case = 'a non-path joined string';   Code = '$connect = "CONNECT $user/$secret@$alias"' }
    ) {
        Invoke-Rule -Rule 'Measure-C14PathWithJoinPath' -Code $Code | Should -HaveCount 0
    }
}

Describe 'C-15 Measure-C15EncodingNamed' {
    It 'reports <Case>' -ForEach @(
        @{ Case = 'Set-Content without -Encoding';          Code = 'Set-Content -Path $p -Value $v' }
        @{ Case = 'Out-File without -Encoding';             Code = '$v | Out-File -FilePath $p' }
        @{ Case = 'a splat with no Encoding key';           Code = '$s = @{ Path = $p; Value = $v }' + "`n" + 'Set-Content @s' }
        @{ Case = 'WriteAllText with no encoding argument'; Code = '[System.IO.File]::WriteAllText($p, $v)' }
        @{ Case = 'redirection to a file';                  Code = 'Get-Date > $p' }
    ) {
        Invoke-Rule -Rule 'Measure-C15EncodingNamed' -Code $Code | Should -HaveCount 1
    }
    It 'does not report <Case>' -ForEach @(
        @{ Case = 'Set-Content with -Encoding';          Code = 'Set-Content -Path $p -Value $v -Encoding UTF8' }
        @{ Case = 'a splat with an Encoding key';        Code = '$s = @{ Path = $p; Encoding = ''UTF8'' }' + "`n" + 'Set-Content @s' }
        @{ Case = 'a splat given Encoding later';        Code = '$s = @{ Path = $p }' + "`n" + '$s.Encoding = ''UTF8''' + "`n" + 'Add-Content @s' }
        @{ Case = 'WriteAllText with an encoding';       Code = '[System.IO.File]::WriteAllText($p, $v, [System.Text.UTF8Encoding]::new($false))' }
        @{ Case = 'redirection to $null';                Code = 'Get-Date > $null' }
        @{ Case = 'Tee-Object to a variable';            Code = 'Get-Date | Tee-Object -Variable d' }
    ) {
        Invoke-Rule -Rule 'Measure-C15EncodingNamed' -Code $Code | Should -HaveCount 0
    }
}

Describe 'C-17 Measure-C17UsePSItem' {
    It 'reports $_ in a script block and inside a double-quoted string' {
        Invoke-Rule -Rule 'Measure-C17UsePSItem' -Code '1..2 | ForEach-Object { "v: $($_)"; $_ }' | Should -HaveCount 2
    }
    It 'does not report $PSItem, or $_ inside a single-quoted string' {
        Invoke-Rule -Rule 'Measure-C17UsePSItem' -Code '1..2 | ForEach-Object { $PSItem; ''$_'' }' | Should -HaveCount 0
    }
}

Describe 'C-33 Measure-C33ShouldProcessGate' {
    BeforeAll {
        $script:sourcePath = Join-Path -Path 'Source' -ChildPath 'Private' -AdditionalChildPath 'Set-A.ps1'
        # Wraps a body in a function that supports ShouldProcess.
        function New-Gated {
            param([string] $Body)
            "function Set-A {`n    [CmdletBinding(SupportsShouldProcess)]`n    param([string] `$Path)`n$Body`n}"
        }
    }

    It 'reports <Case>' -ForEach @(
        @{ Case = 'a write with no ShouldProcess decision'; Body = '    Set-Content -Path $Path -Value 1 -Encoding UTF8' }
        @{ Case = 'a write in the else branch of the gate'; Body = "    if (`$PSCmdlet.ShouldProcess(`$Path, 'Set')) { 1 } else { Remove-Item -Path `$Path }" }
        @{ Case = 'a write before the early return';        Body = "    New-Item -Path `$Path`n    if (-not `$PSCmdlet.ShouldProcess(`$Path, 'Set')) { return }" }
    ) {
        Invoke-Rule -Rule 'Measure-C33ShouldProcessGate' -Code (New-Gated -Body $Body) -RelativePath $script:sourcePath | Should -HaveCount 1
    }

    It 'does not report <Case>' -ForEach @(
        @{ Case = 'a write inside the gate';            Body = "    if (`$PSCmdlet.ShouldProcess(`$Path, 'Set')) { Set-Content -Path `$Path -Value 1 -Encoding UTF8 }" }
        @{ Case = 'a write after the early return';     Body = "    if (-not `$PSCmdlet.ShouldProcess(`$Path, 'Set')) { return }`n    Remove-Item -Path `$Path" }
        @{ Case = 'a write gated by a saved decision';  Body = "    `$applied = `$PSCmdlet.ShouldProcess(`$Path, 'Set')`n    if (`$applied) { New-Item -Path `$Path }" }
        @{ Case = 'a write that pins -WhatIf:$false';   Body = '    New-Item -Path $Path -ItemType Directory -Force -WhatIf:$false' }
        @{ Case = 'ForEach-Object';                     Body = '    1..2 | ForEach-Object { $PSItem }' }
    ) {
        Invoke-Rule -Rule 'Measure-C33ShouldProcessGate' -Code (New-Gated -Body $Body) -RelativePath $script:sourcePath | Should -HaveCount 0
    }

    It 'does not check a file outside Source' {
        $code = New-Gated -Body '    Set-Content -Path $Path -Value 1 -Encoding UTF8'
        $scriptsPath = Join-Path -Path 'Scripts' -ChildPath 'Set-A.ps1'
        Invoke-Rule -Rule 'Measure-C33ShouldProcessGate' -Code $code -RelativePath $scriptsPath | Should -HaveCount 0
    }
}

Describe 'C-18 Measure-C18NoEmoji' {
    It 'reports <Case>' -ForEach @(
        @{ Case = 'an emoji in a comment';     Char = 0x1F600 }
        @{ Case = 'a check mark in a string';  Char = 0x2713 }
        @{ Case = 'a warning sign';            Char = 0x26A0 }
    ) {
        $glyph = [char]::ConvertFromUtf32($Char)
        Invoke-Rule -Rule 'Measure-C18NoEmoji' -Code "# done $glyph`n'ok $glyph'" | Should -Not -HaveCount 0
    }
    It 'does not report box drawing, an em dash, an arrow or the copyright sign' {
        $text = -join @(0x2500, 0x2014, 0x2192, 0x00A9 | ForEach-Object { [char]::ConvertFromUtf32($PSItem) })
        Invoke-Rule -Rule 'Measure-C18NoEmoji' -Code "# $text`n'$text'" | Should -HaveCount 0
    }
}
