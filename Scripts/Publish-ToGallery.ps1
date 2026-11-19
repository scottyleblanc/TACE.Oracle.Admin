#Requires -Version 7.6

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
      - The version folder must hold exactly the files its FileList names:
        Publish-PSResource packages the whole folder, whatever FileList says

.PARAMETER ApiKey
    PSGallery API key (Push scope), as a SecureString. Copy it from Windows Credential
    Manager into Read-Host -AsSecureString; never paste it as plain text. The plain
    text is extracted only inline, in the Publish-PSResource call.

.EXAMPLE
    $key = Read-Host -AsSecureString 'PSGallery API Key'
    .\Scripts\Publish-ToGallery.ps1 -ApiKey $key

    Omitting -ApiKey makes PowerShell prompt for it with masked input.

.NOTES
    Copyright © TACE Data Management Inc.
    Module  : TACE.Oracle.Admin
    Requires: Microsoft.PowerShell.PSResourceGet, git
    **Invocation:** Standalone — interactive; prompts for the API key with
    Read-Host -AsSecureString. Run Build-Module.ps1 first.
#>

[CmdletBinding(SupportsShouldProcess)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'Console publish tool: reports each step at the terminal. Scripts\ are not module code (decision 25).')]
param(
    # [SEC] S-01: a SecureString, so a plain-text key is refused at the call.
    [Parameter(Mandatory)]
    [ValidateNotNull()]
    [SecureString] $ApiKey
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

# [SEC] The folder is what gets packaged, so it must hold only the files FileList names.
$listed  = @((Import-PowerShellDataFile -LiteralPath $stagedManifest).FileList | ForEach-Object { $PSItem -replace '\\', '/' })
$onDisk  = @(Get-ChildItem -LiteralPath $stagingDir -File -Recurse -Force | ForEach-Object { [System.IO.Path]::GetRelativePath($stagingDir, $PSItem.FullName) -replace '\\', '/' })
$extra   = @($onDisk | Where-Object { $listed -notcontains $PSItem })
$missing = @($listed | Where-Object { $onDisk -notcontains $PSItem })
if ($extra.Count -gt 0 -or $missing.Count -gt 0) {
    Write-Error "[Publish-ToGallery] The build folder does not match FileList. Not in FileList: $($extra -join ', '). Missing: $($missing -join ', '). Run Build-Module.ps1 -Package again."
}
Write-Host "[Publish-ToGallery] FileList : $($listed.Count) files, nothing else in the folder [OK]"

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
    # [SEC] S-03: the plain text exists only inside this call, never in a variable.
    Publish-PSResource -Path $stagedManifest -ApiKey ([System.Net.NetworkCredential]::new('', $ApiKey).Password)
    Write-Host "[Publish-ToGallery] Published TACE.Oracle.Admin v$version to PSGallery successfully."
}
