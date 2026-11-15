#Requires -Version 7.6
<#
.SYNOPSIS
    Static tier: Scripts\Build-Module.ps1 enforces the build's own rules.

.DESCRIPTION
    Each test copies the real Build-Module.ps1 into a minimal repository on TestDrive,
    plants one defect, and checks that the build refuses it. The build resolves every
    path from its own location, so the copy builds the fake repository and never touches
    this one. A clean fixture is built first, so a refusal is known to come from the
    planted defect. Rules C-28, C-29 and C-30.

.NOTES
    Copyright © TACE Data Management Inc.
    Runs the build script, not the module: nothing here imports TACE.Oracle.Admin.
#>

BeforeAll {
    $script:buildScript = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath '..' -AdditionalChildPath 'Scripts', 'Build-Module.ps1'
    $script:buildScript = (Resolve-Path -Path $script:buildScript).ProviderPath

    # A public function with an [Alias()] attribute, as the build expects it.
    function Get-PublicFile {
        param([Parameter(Mandatory)] [string] $Name, [string[]] $Alias = @())
        $aliasLine = if ($Alias.Count -gt 0) { "    [Alias($(($Alias | ForEach-Object { "'$PSItem'" }) -join ', '))]`n" } else { '' }
        "function $Name {`n    [CmdletBinding()]`n    [OutputType([PSCustomObject])]`n$aliasLine    param()`n    [PSCustomObject]@{ Success = `$true; Data = `$null; Message = 'ok' }`n}`n"
    }

    # Builds a minimal repository under TestDrive and returns the path of its build script.
    # -ManifestExtra adds lines to the source manifest; -Public maps file names to file text.
    function New-FixtureRepo {
        param(
            [Parameter(Mandatory)] [string] $Name,
            [hashtable] $Public = @{},
            [string] $ManifestExtra = ''
        )
        $root    = Join-Path -Path 'TestDrive:' -ChildPath $Name
        $source  = Join-Path -Path $root -ChildPath 'Source'
        $publicDir = Join-Path -Path $source -ChildPath 'Public'
        $scripts   = Join-Path -Path $root -ChildPath 'Scripts'
        foreach ($dir in $publicDir, $scripts) { $null = New-Item -Path $dir -ItemType Directory -Force }

        $manifest = @"
@{
    RootModule        = 'TACE.Oracle.Admin.psm1'
    ModuleVersion     = '9.9.9'
    GUID              = '00000000-0000-0000-0000-000000000001'
    Author            = 'Fixture'
    PowerShellVersion = '7.6'
    CmdletsToExport   = @()
    VariablesToExport = @()
$ManifestExtra
}
"@
        Set-Content -Path (Join-Path -Path $source -ChildPath 'TACE.Oracle.Admin.psd1') -Value $manifest -Encoding UTF8
        Set-Content -Path (Join-Path -Path $source -ChildPath 'TACE.Oracle.Admin.psm1') -Value "Set-StrictMode -Version Latest`n" -Encoding UTF8
        Set-Content -Path (Join-Path -Path $root -ChildPath 'README.md') -Value '# Fixture' -Encoding UTF8
        Set-Content -Path (Join-Path -Path $root -ChildPath 'LICENSE') -Value 'Fixture' -Encoding UTF8
        foreach ($file in $Public.Keys) {
            Set-Content -Path (Join-Path -Path $publicDir -ChildPath $file) -Value $Public[$file] -Encoding UTF8
        }

        $copy = Join-Path -Path $scripts -ChildPath 'Build-Module.ps1'
        Copy-Item -LiteralPath $script:buildScript -Destination $copy
        (Resolve-Path -Path $copy).ProviderPath
    }
}

Describe 'Build-Module.ps1' {

    Context 'A clean source tree builds' {
        BeforeAll {
            $build = New-FixtureRepo -Name 'clean' -Public @{
                'Get-Alpha.ps1' = Get-PublicFile -Name 'Get-Alpha' -Alias 'ga'
                'Set-Beta.ps1'  = Get-PublicFile -Name 'Set-Beta'
            }
            & $build 6>$null
            $script:builtPath = Join-Path -Path (Split-Path -Path (Split-Path -Path $build -Parent) -Parent) -ChildPath 'Output' -AdditionalChildPath 'TACE.Oracle.Admin', '9.9.9', 'TACE.Oracle.Admin.psd1'
            $script:built = Import-PowerShellDataFile -LiteralPath $script:builtPath
        }

        It 'C-29 exports exactly the functions named by the files in Source\Public' {
            @($script:built.FunctionsToExport | Sort-Object) | Should -Be @('Get-Alpha', 'Set-Beta')
        }

        It 'C-30 exports the aliases declared by [Alias()] attributes' {
            @($script:built.AliasesToExport) | Should -Be @('ga')
        }

        It 'C-28 generates FileList from the files it wrote' {
            @($script:built.FileList | Sort-Object) | Should -Be @('LICENSE', 'README.md', 'TACE.Oracle.Admin.psd1', 'TACE.Oracle.Admin.psm1')
        }

        It 'C-29 keeps an empty export list as a real entry, not a comment' {
            $text = Get-Content -LiteralPath $script:builtPath -Raw
            $text | Should -Match '(?m)^VariablesToExport = @\(\)'
            $text | Should -Not -Match '(?m)^# VariablesToExport'
        }
    }

    Context 'A public file that breaks C-29 fails the build' {
        It 'C-29 refuses a public file that defines a second function' {
            $build = New-FixtureRepo -Name 'second' -Public @{
                'Get-Alpha.ps1' = (Get-PublicFile -Name 'Get-Alpha') + (Get-PublicFile -Name 'Get-Extra')
            }
            { & $build 6>$null } | Should -Throw '*Get-Alpha.ps1 must define exactly one function*Found: Get-Alpha, Get-Extra*'
        }

        It 'C-29 refuses a public file whose function is not named for the file' {
            $build = New-FixtureRepo -Name 'misnamed' -Public @{
                'Get-Alpha.ps1' = Get-PublicFile -Name 'Get-Other'
            }
            { & $build 6>$null } | Should -Throw '*Get-Alpha.ps1 must define exactly one function, Get-Alpha*'
        }

        It 'C-29 refuses a public file that defines no function' {
            $build = New-FixtureRepo -Name 'nofunction' -Public @{ 'Get-Alpha.ps1' = "`$x = 1`n" }
            { & $build 6>$null } | Should -Throw '*Get-Alpha.ps1 must define exactly one function*'
        }

        It 'C-29 refuses a source tree with no public function' {
            $build = New-FixtureRepo -Name 'nopublic'
            { & $build 6>$null } | Should -Throw '*No public functions found*'
        }
    }

    Context 'A source manifest that declares a generated list fails the build' {
        It 'C-29 refuses a source manifest that declares <Key>' -ForEach @(
            @{ Key = 'FunctionsToExport'; Line = "    FunctionsToExport = @('Get-Alpha')" }
            @{ Key = 'AliasesToExport';   Line = "    AliasesToExport   = @()" }
            @{ Key = 'FileList';          Line = "    FileList          = @('TACE.Oracle.Admin.psm1')" }
        ) {
            $build = New-FixtureRepo -Name "manifest-$Key" -ManifestExtra $Line -Public @{
                'Get-Alpha.ps1' = Get-PublicFile -Name 'Get-Alpha'
            }
            { & $build 6>$null } | Should -Throw "*declares $Key. The build generates it*"
        }
    }
}
