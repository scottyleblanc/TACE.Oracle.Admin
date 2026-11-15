#Requires -Version 7.6
<#
.SYNOPSIS
    Returns the path of the built module manifest that the unit tests import.

.DESCRIPTION
    Unit tests run against the built module, not the source folders (rule C-28). This
    script reads the version from Source\TACE.Oracle.Admin.psd1 and returns the full path
    of Output\TACE.Oracle.Admin\<version>\TACE.Oracle.Admin.psd1.

    It throws when that manifest does not exist, so a test file run on its own fails with
    a clear instruction instead of importing nothing or an old build.
    Scripts\Invoke-UnitTest.ps1 builds the module before it runs the tests.

    It is not a test file: Pester runs only *.Tests.ps1 files.

.OUTPUTS
    [string] The full path of the built manifest.

.EXAMPLE
    $modulePath = & (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'Get-BuiltModulePath.ps1')

    From a test file in Tests\Unit\Public\, Tests\Unit\Private\ or Tests\Unit\Module\.

.NOTES
    Copyright © TACE Data Management Inc.
    **Invocation:** Helper — called with the call operator from each unit test file's
    BeforeAll. Reads files only.
#>
[CmdletBinding()]
[OutputType([string])]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot       = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
$sourceManifest = Join-Path -Path $repoRoot -ChildPath 'Source' -AdditionalChildPath 'TACE.Oracle.Admin.psd1'
$version        = (Import-PowerShellDataFile -LiteralPath $sourceManifest).ModuleVersion

$builtManifest = Join-Path -Path $repoRoot -ChildPath 'Output' -AdditionalChildPath 'TACE.Oracle.Admin', $version, 'TACE.Oracle.Admin.psd1'

if (-not (Test-Path -LiteralPath $builtManifest -PathType Leaf)) {
    throw "[Get-BuiltModulePath] No built module for version $version. Run .\Scripts\Build-Module.ps1 first, or run the suite with .\Scripts\Invoke-UnitTest.ps1, which builds it."
}

[System.IO.Path]::GetFullPath($builtManifest)
