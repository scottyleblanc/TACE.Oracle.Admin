#Requires -Version 7.0

<#
.SYNOPSIS
    Publishes the current build of TACE.Oracle.Admin to the PowerShell Gallery.

.DESCRIPTION
    Publishes the built module from Output\TACE.Oracle.Admin\<version>\ to PSGallery.
    Build-Module.ps1 must be run first (with -Package, to inspect the package
    contents beforehand) — this script will not proceed if no
    build exists for the current module version.

    Pre-publish gates:
      - Output\TACE.Oracle.Admin\<version>\ must exist (Build-Module.ps1 must have run)
      - Working tree must be clean (no uncommitted changes)
      - A git tag matching the module version must exist (e.g. v0.1.5)

.PARAMETER ApiKey
    PSGallery API key (Push scope). Retrieve from Windows Credential Manager —
    never pass as a plaintext argument in a scheduled task or CI pipeline.

.EXAMPLE
    $key = Read-Host -AsSecureString 'PSGallery API Key'
    $plain = [System.Net.NetworkCredential]::new('', $key).Password
    .\Scripts\Publish-ToGallery.ps1 -ApiKey $plain

.NOTES
    Copyright © TACE Data Management Inc.
    Module  : TACE.Oracle.Admin
    Requires: Microsoft.PowerShell.PSResourceGet, git
    **Invocation:** Standalone — interactive; prompts for the API key with
    Read-Host -AsSecureString. Run Build-Module.ps1 first.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $ApiKey
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleRoot = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')

# -- Read version from manifest ----------------------------------------------

$manifestPath = Join-Path -Path $moduleRoot -ChildPath 'Source' -AdditionalChildPath 'TACE.Oracle.Admin.psd1'
$version      = [string](Import-PowerShellDataFile -LiteralPath $manifestPath).ModuleVersion
$tagName      = "v$version"

Write-Host "[Publish-ToGallery] Module  : TACE.Oracle.Admin v$version"

# -- Verify build exists -----------------------------------------------------

$stagingDir     = Join-Path -Path $moduleRoot -ChildPath 'Output' -AdditionalChildPath 'TACE.Oracle.Admin', $version
$stagedManifest = Join-Path -Path $stagingDir -ChildPath 'TACE.Oracle.Admin.psd1'

if (-not (Test-Path -Path $stagingDir)) {
    Write-Error "[Publish-ToGallery] No build found for v$version. Run Build-Module.ps1 first."
}
if (-not (Test-Path -Path $stagedManifest)) {
    Write-Error "[Publish-ToGallery] Staged manifest not found at: $stagedManifest. Run Build-Module.ps1 first."
}

Write-Host "[Publish-ToGallery] Build   : $stagingDir [OK]"

# -- Git checks --------------------------------------------------------------

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Error '[Publish-ToGallery] git not found. Cannot verify tag or working tree state.'
}

$gitStatus = git -C $moduleRoot status --porcelain
if ($gitStatus) {
    Write-Error "[Publish-ToGallery] Working tree is not clean. Commit or stash all changes before publishing.`n$gitStatus"
}
Write-Host '[Publish-ToGallery] Working tree : clean [OK]'

$tagExists = git -C $moduleRoot tag --list $tagName
if (-not $tagExists) {
    Write-Error "[Publish-ToGallery] Git tag '$tagName' does not exist. Create and push the tag before publishing."
}
Write-Host "[Publish-ToGallery] Git tag      : $tagName [OK]"

# -- Publish -----------------------------------------------------------------

if ($PSCmdlet.ShouldProcess('PSGallery', "Publish TACE.Oracle.Admin v$version")) {
    Publish-PSResource -Path $stagedManifest -ApiKey $ApiKey
    Write-Host "[Publish-ToGallery] Published TACE.Oracle.Admin v$version to PSGallery successfully."
}
