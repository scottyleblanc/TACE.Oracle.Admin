#Requires -Version 7.0

<#
.SYNOPSIS
    Builds and publishes TACE.Oracle.Admin to the PowerShell Gallery.

.DESCRIPTION
    Stages publishable module files into a versioned build directory, then either
    publishes to PSGallery or runs a local test. Build artifacts are always retained
    at build\<version>\ for inspection and audit.

    Build directory layout:
      build\
        <version>\
          staging\    — module files copied for packaging
          repo\       — local NuGet repository (.nupkg)

    Files included in the published package:
      - TACE.Oracle.Admin.psd1
      - TACE.Oracle.Admin.psm1
      - PSScriptAnalyzerSettings.psd1
      - README.md
      - LICENSE
      - Public\*.ps1
      - Private\*.ps1

    Pre-publish gates (live publish only):
      - Working tree must be clean (no uncommitted changes)
      - A git tag matching the module version must exist (e.g. v0.1.5)

    Pre-publish gates (local test):
      - Warns if the matching git tag does not exist, but continues

.PARAMETER ApiKey
    PSGallery API key (Push scope). Retrieve from Windows Credential Manager —
    never pass as a plaintext argument in a scheduled task or CI pipeline.

.PARAMETER LocalTest
    Stages and packages the module locally without publishing to PSGallery.
    Retains all build artifacts in build\<version>\. No API key required.

.EXAMPLE
    # Verify package contents before publishing
    .\scripts\Publish-ToGallery.ps1 -LocalTest

.EXAMPLE
    # Live publish
    $key = Read-Host -AsSecureString 'PSGallery API Key'
    $plain = [System.Net.NetworkCredential]::new('', $key).Password
    .\scripts\Publish-ToGallery.ps1 -ApiKey $plain

.NOTES
    Copyright © TACE Data Management Inc.
    Module  : TACE.Oracle.Admin
    Requires: Microsoft.PowerShell.PSResourceGet, git
#>

[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Gallery')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Gallery')]
    [ValidateNotNullOrEmpty()]
    [string] $ApiKey,

    [Parameter(Mandatory, ParameterSetName = 'LocalTest')]
    [switch] $LocalTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleRoot = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')

$filesToCopy = @(
    'TACE.Oracle.Admin.psd1'
    'TACE.Oracle.Admin.psm1'
    'PSScriptAnalyzerSettings.psd1'
    'README.md'
    'LICENSE'
)

$foldersToCopy = @(
    'Public'
    'Private'
)

# -- Validate manifest -------------------------------------------------------

$manifestPath = Join-Path -Path $moduleRoot -ChildPath 'TACE.Oracle.Admin.psd1'
$validated    = Test-ModuleManifest -Path $manifestPath
$version      = $validated.Version.ToString()
$tagName      = "v$version"

Write-Host "[Publish-ToGallery] Module  : $($validated.Name) v$version"

# -- Build paths -------------------------------------------------------------

$buildDir   = Join-Path -Path $moduleRoot -ChildPath 'build'
$versionDir = Join-Path -Path $buildDir   -ChildPath $version
$stagingDir = Join-Path -Path $versionDir -ChildPath 'staging'
$localRepo  = Join-Path -Path $versionDir -ChildPath 'repo'

Write-Host "[Publish-ToGallery] Build   : $versionDir"

if (Test-Path -Path $versionDir) {
    Write-Warning "[Publish-ToGallery] Build directory for v$version already exists — contents will be overwritten."
    Remove-Item -Path $versionDir -Recurse -Force
}

# -- Git checks --------------------------------------------------------------

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Error '[Publish-ToGallery] git not found. Cannot verify tag or working tree state.'
}

$tagExists = git -C $moduleRoot tag --list $tagName
if (-not $tagExists) {
    if ($LocalTest) {
        Write-Warning "[Publish-ToGallery] Git tag '$tagName' does not exist. Tag before publishing to PSGallery."
    }
    else {
        Write-Error "[Publish-ToGallery] Git tag '$tagName' does not exist. Create and push the tag before publishing."
    }
}
else {
    Write-Host "[Publish-ToGallery] Git tag : $tagName [OK]"
}

if (-not $LocalTest) {
    $gitStatus = git -C $moduleRoot status --porcelain
    if ($gitStatus) {
        Write-Error "[Publish-ToGallery] Working tree is not clean. Commit or stash all changes before publishing.`n$gitStatus"
    }
    Write-Host '[Publish-ToGallery] Working tree : clean [OK]'
}

# -- Stage -------------------------------------------------------------------

Write-Host "[Publish-ToGallery] Staging files..."

New-Item -Path $stagingDir -ItemType Directory -Force | Out-Null
New-Item -Path $localRepo  -ItemType Directory -Force | Out-Null

foreach ($file in $filesToCopy) {
    $src = Join-Path -Path $moduleRoot -ChildPath $file
    if (-not (Test-Path -Path $src)) {
        Write-Error "[Publish-ToGallery] Required file not found: $src"
    }
    Copy-Item -Path $src -Destination $stagingDir
    Write-Verbose "[Publish-ToGallery] Staged: $file"
}

foreach ($folder in $foldersToCopy) {
    $src  = Join-Path -Path $moduleRoot -ChildPath $folder
    $dest = Join-Path -Path $stagingDir -ChildPath $folder
    if (-not (Test-Path -Path $src)) {
        Write-Error "[Publish-ToGallery] Required folder not found: $src"
    }
    Copy-Item -Path $src -Destination $dest -Recurse
    Write-Verbose "[Publish-ToGallery] Staged folder: $folder"
}

$stagedManifest = Join-Path -Path $stagingDir -ChildPath 'TACE.Oracle.Admin.psd1'

# -- Build local package (always) --------------------------------------------

$repoName = 'TACELocalBuild'
if (Get-PSResourceRepository -Name $repoName -ErrorAction SilentlyContinue) {
    Unregister-PSResourceRepository -Name $repoName
}
Register-PSResourceRepository -Name $repoName -Uri $localRepo -Trusted

try {
    Publish-PSResource -Path $stagedManifest -Repository $repoName -ApiKey 'unused'
}
finally {
    Unregister-PSResourceRepository -Name $repoName
}

$nupkg = Get-ChildItem -Path $localRepo -Filter '*.nupkg' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $nupkg) {
    Write-Error '[Publish-ToGallery] No .nupkg found after build.'
}

Write-Host "[Publish-ToGallery] Package : $($nupkg.Name)"

# -- List package contents ---------------------------------------------------

Write-Host '[Publish-ToGallery] Contents:'

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip     = [System.IO.Compression.ZipFile]::OpenRead($nupkg.FullName)
$entries = $zip.Entries |
           Where-Object { $_.FullName -notmatch '^_rels/' -and $_.FullName -notmatch '^\[' -and $_.FullName -notmatch '\.nuspec$' -and $_.FullName -notmatch '^package/' } |
           Sort-Object FullName
foreach ($entry in $entries) {
    Write-Host "  $($entry.FullName)"
}
$zip.Dispose()

Write-Host "`n[Publish-ToGallery] Build artifacts retained at: $versionDir"

# -- Publish to PSGallery (live only) ----------------------------------------

if (-not $LocalTest) {
    if ($PSCmdlet.ShouldProcess('PSGallery', "Publish TACE.Oracle.Admin v$version")) {
        Publish-PSResource -Path $stagedManifest -ApiKey $ApiKey
        Write-Host "[Publish-ToGallery] Published to PSGallery successfully."
    }
}
else {
    Write-Host '[Publish-ToGallery] Local test complete. Run without -LocalTest to publish to PSGallery.'
}
