#Requires -Version 7.0

<#
.SYNOPSIS
    Stages and packages TACE.Oracle.Admin into a versioned build directory.

.DESCRIPTION
    Copies publishable module files to build\<version>\staging\, builds a local
    NuGet package into build\<version>\repo\, and lists the package contents.
    Build artifacts are always retained for inspection before publishing.

    Run this script first. Once you have verified the package contents, run
    Publish-ToGallery.ps1 to push the build to PSGallery.

    Build directory layout:
      build\
        <version>\
          staging\    — module files copied for packaging
          repo\       — local NuGet repository (.nupkg)

    Files included in the package:
      - TACE.Oracle.Admin.psd1
      - TACE.Oracle.Admin.psm1
      - PSScriptAnalyzerSettings.psd1
      - README.md
      - LICENSE
      - Public\*.ps1
      - Private\*.ps1

    Pre-build gates:
      - All build file .NOTES versions must match the manifest version
      - Warns if the matching git tag does not exist

.PARAMETER AwsProfile
    AWS CLI profile to use for the S3 upload. Defaults to 'tace-aws-admin'.

.EXAMPLE
    .\scripts\Build-Module.ps1

.EXAMPLE
    .\scripts\Build-Module.ps1 -AwsProfile 'other-profile'

.NOTES
    Copyright © TACE Data Management Inc.
    Module  : TACE.Oracle.Admin
    Requires: Microsoft.PowerShell.PSResourceGet, git, AWS CLI
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $AwsProfile = 'tace-aws-admin'
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

Write-Host "[Build-Module] Module  : $($validated.Name) v$version"

# -- Check .NOTES version consistency across all build files -----------------

$filesToScan = @()
foreach ($file in $filesToCopy) {
    $filesToScan += Join-Path -Path $moduleRoot -ChildPath $file
}
foreach ($folder in $foldersToCopy) {
    $filesToScan += @(Get-ChildItem -Path (Join-Path -Path $moduleRoot -ChildPath $folder) -Recurse -File |
                      Select-Object -ExpandProperty FullName)
}

$versionMismatches = @()
foreach ($filePath in $filesToScan) {
    if (-not (Test-Path -Path $filePath)) { continue }
    $content = Get-Content -Path $filePath -Raw
    if ($content -match '(?m)Version\s*[=:]\s*[''"]?([\d.]+)[''"]?') {
        $fileVersion = $Matches[1]
        if ($fileVersion -ne $version) {
            $versionMismatches += "$(Split-Path -Leaf $filePath) — Version: $fileVersion"
        }
    }
}

if ($versionMismatches.Count -gt 0) {
    $list = $versionMismatches -join "`n  "
    Write-Error "[Build-Module] Version mismatch in build files (expected $version):`n  $list"
}

Write-Host "[Build-Module] Version check : all build files match $version [OK]"

# -- Git tag check -----------------------------------------------------------

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Warning '[Build-Module] git not found. Cannot verify tag existence.'
}
else {
    $tagExists = git -C $moduleRoot tag --list $tagName
    if (-not $tagExists) {
        Write-Warning "[Build-Module] Git tag '$tagName' does not exist. Create the tag before publishing to PSGallery."
    }
    else {
        Write-Host "[Build-Module] Git tag  : $tagName [OK]"
    }
}

# -- Build paths -------------------------------------------------------------

$buildDir   = Join-Path -Path $moduleRoot -ChildPath 'build'
$versionDir = Join-Path -Path $buildDir   -ChildPath $version
$stagingDir = Join-Path -Path $versionDir -ChildPath 'staging'
$localRepo  = Join-Path -Path $versionDir -ChildPath 'repo'

Write-Host "[Build-Module] Build   : $versionDir"

if (Test-Path -Path $versionDir) {
    Write-Warning "[Build-Module] Build directory for v$version already exists — contents will be overwritten."
    Remove-Item -Path $versionDir -Recurse -Force
}

# -- Stage -------------------------------------------------------------------

Write-Host '[Build-Module] Staging files...'

New-Item -Path $stagingDir -ItemType Directory -Force | Out-Null
New-Item -Path $localRepo  -ItemType Directory -Force | Out-Null

foreach ($file in $filesToCopy) {
    $src = Join-Path -Path $moduleRoot -ChildPath $file
    if (-not (Test-Path -Path $src)) {
        Write-Error "[Build-Module] Required file not found: $src"
    }
    Copy-Item -Path $src -Destination $stagingDir
    Write-Verbose "[Build-Module] Staged: $file"
}

foreach ($folder in $foldersToCopy) {
    $src  = Join-Path -Path $moduleRoot -ChildPath $folder
    $dest = Join-Path -Path $stagingDir -ChildPath $folder
    if (-not (Test-Path -Path $src)) {
        Write-Error "[Build-Module] Required folder not found: $src"
    }
    Copy-Item -Path $src -Destination $dest -Recurse
    Write-Verbose "[Build-Module] Staged folder: $folder"
}

# -- Build local package -----------------------------------------------------

$repoName = 'TACELocalBuild'
if (Get-PSResourceRepository -Name $repoName -ErrorAction SilentlyContinue) {
    Unregister-PSResourceRepository -Name $repoName
}
Register-PSResourceRepository -Name $repoName -Uri $localRepo -Trusted

try {
    $stagedManifest = Join-Path -Path $stagingDir -ChildPath 'TACE.Oracle.Admin.psd1'
    Publish-PSResource -Path $stagedManifest -Repository $repoName -ApiKey 'unused'
}
finally {
    Unregister-PSResourceRepository -Name $repoName
}

$nupkg = Get-ChildItem -Path $localRepo -Filter '*.nupkg' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $nupkg) {
    Write-Error '[Build-Module] No .nupkg found after build.'
}

# -- List package contents ---------------------------------------------------

Write-Host "[Build-Module] Package : $($nupkg.Name)"
Write-Host '[Build-Module] Contents:'

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip     = [System.IO.Compression.ZipFile]::OpenRead($nupkg.FullName)
$entries = $zip.Entries |
           Where-Object { $_.FullName -notmatch '^_rels/' -and $_.FullName -notmatch '^\[' -and $_.FullName -notmatch '\.nuspec$' -and $_.FullName -notmatch '^package/' } |
           Sort-Object FullName
foreach ($entry in $entries) {
    Write-Host "  $($entry.FullName)"
}
$zip.Dispose()

Write-Host ''
Write-Host "[Build-Module] Build artifacts retained at: $versionDir"

# -- Push to S3 staging ------------------------------------------------------

$s3Target = "s3://tacedata-s3-bucket-02/staging/TACE.Oracle.Admin/$version/"

$testScript = Join-Path -Path $PSScriptRoot -ChildPath 'Test-LinuxBuild.ps1'

if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    Write-Warning '[Build-Module] AWS CLI not found. Skipping S3 upload.'
}
else {
    Write-Host "[Build-Module] Uploading to : $s3Target (profile: $AwsProfile)"

    aws s3 cp $nupkg.FullName $s3Target --profile $AwsProfile
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "[Build-Module] S3 upload failed for .nupkg with exit code $LASTEXITCODE. Check AWS credentials and bucket permissions."
    }
    else {
        Write-Host "[Build-Module] Uploaded : $($nupkg.Name)"
    }

    if (Test-Path -Path $testScript) {
        aws s3 cp $testScript $s3Target --profile $AwsProfile
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "[Build-Module] S3 upload failed for Test-LinuxBuild.ps1 with exit code $LASTEXITCODE."
        }
        else {
            Write-Host '[Build-Module] Uploaded : Test-LinuxBuild.ps1'
        }
    }
    else {
        Write-Warning '[Build-Module] Test-LinuxBuild.ps1 not found in scripts\ — skipping.'
    }

    Write-Host '[Build-Module] S3 upload complete.'
}

Write-Host "[Build-Module] Verify the contents above, then run Publish-ToGallery.ps1 to publish."
