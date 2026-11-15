#Requires -Version 7.6

<#
.SYNOPSIS
    Builds TACE.Oracle.Admin from Source\ into Output\, and optionally packages it.

.DESCRIPTION
    Merges the module source into one .psm1 with a generated manifest (rules C-28, C-29,
    C-30). The built module is what the unit tests import and what a package is made from.

    Build layout:
      Output\
        TACE.Oracle.Admin\
          <version>\
            TACE.Oracle.Admin.psd1        generated manifest
            TACE.Oracle.Admin.psm1        Source\TACE.Oracle.Admin.psm1, then every file
                                          in Source\Classes\, Source\Private\ and
                                          Source\Public\, in that order
            README.md, LICENSE
        Package\
          <version>\                      local NuGet repository (.nupkg), -Package only

    The manifest is generated from Source\TACE.Oracle.Admin.psd1 plus three lists the
    build works out itself:
      - FunctionsToExport: the file names in Source\Public\. Each public file must define
        exactly one function, named for the file (C-29).
      - AliasesToExport: the [Alias()] attributes on those functions (C-30).
      - FileList: the files written to the version folder.
    The source manifest must not declare any of the three.

    Every build replaces Output\TACE.Oracle.Admin\<version>\. Other versions under
    Output\ are left alone. Output\ is not committed.

    Pre-build gates:
      - All build file .NOTES versions must match the manifest version
      - With -Package, warns if the matching git tag does not exist

.PARAMETER Package
    Also builds a local NuGet package from the built module into
    Output\Package\<version>\ and lists its contents.

.PARAMETER S3Bucket
    Name of the S3 staging bucket (the name only, without s3://). Requires -Package.
    When given, the package and Test-LinuxBuild.ps1 are uploaded to
    s3://<S3Bucket>/staging/TACE.Oracle.Admin/<version>/. No bucket name is kept in this
    repository.

.PARAMETER AwsProfile
    AWS CLI profile to use for the S3 upload. Defaults to 'tace-aws-admin'.

.EXAMPLE
    .\Scripts\Build-Module.ps1

    Builds the module into Output\. This is what Scripts\Invoke-UnitTest.ps1 runs first.

.EXAMPLE
    .\Scripts\Build-Module.ps1 -Package

    Builds, then packages locally and lists the package contents.

.EXAMPLE
    .\Scripts\Build-Module.ps1 -Package -S3Bucket '<staging-bucket>' -AwsProfile 'other-profile'

    Builds, packages, and uploads to the staging bucket.

.NOTES
    Copyright © TACE Data Management Inc.
    Module  : TACE.Oracle.Admin
    Requires: PowerShell 7.6+; with -Package, Microsoft.PowerShell.PSResourceGet and git;
              with -S3Bucket, the AWS CLI
    **Invocation:** Standalone — run from a checkout; every path is resolved from this
    script's location. Replaces Output\TACE.Oracle.Admin\<version>\. With -Package it
    registers a temporary local PSResource repository (removed again in a finally block),
    and with -S3Bucket it uploads the package and smoke-test script to S3.
#>

[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'Console build tool: reports progress and the package contents at the terminal. Scripts\ are not module code (decision 25).')]
param(
    [Parameter()]
    [switch] $Package,

    [Parameter()]
    [ValidatePattern('^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$')]
    [string] $S3Bucket,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $AwsProfile = 'tace-aws-admin'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not [string]::IsNullOrEmpty($S3Bucket) -and -not $Package) {
    throw '[Build-Module] -S3Bucket uploads the package, so it requires -Package.'
}

$moduleName = 'TACE.Oracle.Admin'
$repoRoot   = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')).ProviderPath
$sourceRoot = Join-Path -Path $repoRoot -ChildPath 'Source'

# Files copied unchanged from the repository root into the built module.
$rootFiles = @(
    'README.md'
    'LICENSE'
)

# Merge order (C-28): classes, then private, then public.
$sourceFolders = @('Classes', 'Private', 'Public')

# -- Read the source manifest ------------------------------------------------

$sourceManifestPath = Join-Path -Path $sourceRoot -ChildPath "$moduleName.psd1"
$sourcePsm1Path     = Join-Path -Path $sourceRoot -ChildPath "$moduleName.psm1"
$manifestData       = Import-PowerShellDataFile -LiteralPath $sourceManifestPath
$version            = [string]$manifestData.ModuleVersion
$tagName            = "v$version"

foreach ($generatedKey in @('FunctionsToExport', 'AliasesToExport', 'FileList')) {
    if ($manifestData.ContainsKey($generatedKey)) {
        throw "[Build-Module] Source\$moduleName.psd1 declares $generatedKey. The build generates it; remove it from the source manifest."
    }
}

Write-Host "[Build-Module] Module  : $moduleName v$version"

# -- Collect source files ----------------------------------------------------

$sourceFiles = @(
    foreach ($folder in $sourceFolders) {
        $folderPath = Join-Path -Path $sourceRoot -ChildPath $folder
        if (Test-Path -LiteralPath $folderPath) {
            @(Get-ChildItem -LiteralPath $folderPath -Filter '*.ps1' -File | Sort-Object -Property Name) |
                ForEach-Object { [PSCustomObject]@{ Folder = $folder; File = $PSItem } }
        }
    }
)

# -- Check .NOTES version consistency across all build files -----------------

$filesToScan = @(
    $sourcePsm1Path
    foreach ($file in $rootFiles) { Join-Path -Path $repoRoot -ChildPath $file }
    $sourceFiles | ForEach-Object { $PSItem.File.FullName }
)

$versionMismatches = @()
foreach ($filePath in $filesToScan) {
    if (-not (Test-Path -LiteralPath $filePath)) { continue }
    $content = Get-Content -LiteralPath $filePath -Raw
    if ($content -match '(?m)Version\s*[=:]\s*[''"]?([\d.]+)[''"]?') {
        $fileVersion = $Matches[1]
        if ($fileVersion -ne $version) {
            $versionMismatches += "$(Split-Path -Leaf $filePath) — Version: $fileVersion"
        }
    }
}

if ($versionMismatches.Count -gt 0) {
    $list = $versionMismatches -join "`n  "
    throw "[Build-Module] Version mismatch in build files (expected $version):`n  $list"
}

Write-Host "[Build-Module] Version check : all build files match $version [OK]"

# -- Work out exports from the public files (C-29, C-30) ---------------------

$functionsToExport = [System.Collections.Generic.List[string]]::new()
$aliasesToExport   = [System.Collections.Generic.List[string]]::new()

foreach ($entry in @($sourceFiles | Where-Object { $PSItem.Folder -eq 'Public' })) {
    $tokens      = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($entry.File.FullName, [ref]$tokens, [ref]$parseErrors)
    if (@($parseErrors).Count -gt 0) {
        throw "[Build-Module] Source\Public\$($entry.File.Name) does not parse: $($parseErrors[0].Message)"
    }

    $expected  = $entry.File.BaseName
    $functions = @($ast.FindAll(
            { param([System.Management.Automation.Language.Ast]$node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] },
            $false))
    if ($functions.Count -ne 1 -or $functions[0].Name -ne $expected) {
        $found = ($functions | ForEach-Object { $PSItem.Name }) -join ', '
        throw "[Build-Module] Source\Public\$($entry.File.Name) must define exactly one function, $expected (rule C-29). Found: $found"
    }
    $functionsToExport.Add($expected)

    $paramBlock = $functions[0].Body.ParamBlock
    if ($null -ne $paramBlock) {
        foreach ($attribute in @($paramBlock.Attributes | Where-Object { $PSItem.TypeName.Name -eq 'Alias' })) {
            foreach ($argument in $attribute.PositionalArguments) {
                $aliasesToExport.Add([string]$argument.SafeGetValue())
            }
        }
    }
}

if ($functionsToExport.Count -eq 0) {
    throw '[Build-Module] No public functions found under Source\Public\.'
}

Write-Host "[Build-Module] Functions : $($functionsToExport -join ', ')"
Write-Host "[Build-Module] Aliases   : $(if ($aliasesToExport.Count -gt 0) { $aliasesToExport -join ', ' } else { '(none)' })"

# -- Prepare the version folder ----------------------------------------------

$outputRoot = Join-Path -Path $repoRoot -ChildPath 'Output'
$moduleDir  = Join-Path -Path $outputRoot -ChildPath $moduleName -AdditionalChildPath $version

if (Test-Path -LiteralPath $moduleDir) {
    Remove-Item -LiteralPath $moduleDir -Recurse -Force
}
$null = New-Item -Path $moduleDir -ItemType Directory -Force

Write-Host "[Build-Module] Output  : $moduleDir"

# -- Write the merged .psm1 --------------------------------------------------

$builder = [System.Text.StringBuilder]::new()
$null = $builder.Append(((Get-Content -LiteralPath $sourcePsm1Path -Raw) -replace "`r`n", "`n").TrimEnd())
$null = $builder.Append("`n")

foreach ($entry in $sourceFiles) {
    $relative = "Source\$($entry.Folder)\$($entry.File.Name)"
    $body     = ((Get-Content -LiteralPath $entry.File.FullName -Raw) -replace "`r`n", "`n").TrimEnd()
    $null = $builder.Append("`n#region $relative`n`n")
    $null = $builder.Append($body)
    $null = $builder.Append("`n`n#endregion $relative`n")
    Write-Verbose "[Build-Module] Merged: $relative"
}

$builtPsm1 = Join-Path -Path $moduleDir -ChildPath "$moduleName.psm1"
[System.IO.File]::WriteAllText($builtPsm1, $builder.ToString(), [System.Text.UTF8Encoding]::new($false))

# -- Copy root files ---------------------------------------------------------

foreach ($file in $rootFiles) {
    $src = Join-Path -Path $repoRoot -ChildPath $file
    if (-not (Test-Path -LiteralPath $src)) {
        throw "[Build-Module] Required file not found: $src"
    }
    Copy-Item -LiteralPath $src -Destination $moduleDir
}

# -- Write the generated manifest --------------------------------------------

$fileList = @(
    "$moduleName.psd1"
    "$moduleName.psm1"
    $rootFiles
)

$manifestParams = @{}
foreach ($key in $manifestData.Keys) {
    if ($key -ne 'PrivateData') { $manifestParams[$key] = $manifestData[$key] }
}
if ($manifestData.ContainsKey('PrivateData')) {
    $privateData = $manifestData['PrivateData']
    $otherKeys   = @($privateData.Keys | Where-Object { $PSItem -ne 'PSData' })
    if ($otherKeys.Count -gt 0) {
        throw "[Build-Module] PrivateData keys other than PSData are not supported by the build: $($otherKeys -join ', ')"
    }
    if ($privateData.ContainsKey('PSData')) {
        foreach ($key in $privateData['PSData'].Keys) {
            $manifestParams[$key] = $privateData['PSData'][$key]
        }
    }
}

$builtManifest = Join-Path -Path $moduleDir -ChildPath "$moduleName.psd1"
$manifestParams['Path']              = $builtManifest
$manifestParams['FunctionsToExport'] = @($functionsToExport)
$manifestParams['AliasesToExport']   = @($aliasesToExport)
$manifestParams['FileList']          = $fileList

New-ModuleManifest @manifestParams

# New-ModuleManifest writes an empty export list as a comment, which leaves the key unset.
# Unset AliasesToExport or FunctionsToExport means "export everything", so restore every
# empty export list as a real entry.
$manifestText = [System.IO.File]::ReadAllText($builtManifest)
$manifestText = [regex]::Replace($manifestText,
    '(?m)^# ((?:Functions|Cmdlets|Variables|Aliases)ToExport = @\(\))(?=\r?$)',
    '$1')
[System.IO.File]::WriteAllText($builtManifest, $manifestText, [System.Text.UTF8Encoding]::new($false))

$validated = Test-ModuleManifest -Path $builtManifest
if ($validated.Version.ToString() -ne $version) {
    throw "[Build-Module] Built manifest version $($validated.Version) does not match $version."
}

Write-Host "[Build-Module] Built   : $builtManifest [OK]"

if (-not $Package) {
    return
}

# -- Git tag check -----------------------------------------------------------

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Warning '[Build-Module] git not found. Cannot verify tag existence.'
}
else {
    $tagExists = git -C $repoRoot tag --list $tagName
    if (-not $tagExists) {
        Write-Warning "[Build-Module] Git tag '$tagName' does not exist. Create the tag before publishing to PSGallery."
    }
    else {
        Write-Host "[Build-Module] Git tag  : $tagName [OK]"
    }
}

# -- Build local package -----------------------------------------------------

$localRepo = Join-Path -Path $outputRoot -ChildPath 'Package' -AdditionalChildPath $version
if (Test-Path -LiteralPath $localRepo) {
    Remove-Item -LiteralPath $localRepo -Recurse -Force
}
$null = New-Item -Path $localRepo -ItemType Directory -Force

$repoName = 'TACELocalBuild'
if (Get-PSResourceRepository -Name $repoName -ErrorAction SilentlyContinue) {
    Unregister-PSResourceRepository -Name $repoName
}
Register-PSResourceRepository -Name $repoName -Uri $localRepo -Trusted

try {
    Publish-PSResource -Path $builtManifest -Repository $repoName -ApiKey 'unused'
}
finally {
    Unregister-PSResourceRepository -Name $repoName
}

$nupkg = Get-ChildItem -Path $localRepo -Filter '*.nupkg' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $nupkg) {
    throw '[Build-Module] No .nupkg found after build.'
}

# -- List package contents ---------------------------------------------------

Write-Host "[Build-Module] Package : $($nupkg.Name)"
Write-Host '[Build-Module] Contents:'

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($nupkg.FullName)
try {
    $entries = @($zip.Entries |
        Where-Object { $PSItem.FullName -notmatch '^_rels/' -and $PSItem.FullName -notmatch '^\[' -and $PSItem.FullName -notmatch '\.nuspec$' -and $PSItem.FullName -notmatch '^package/' } |
        Sort-Object FullName)
    foreach ($entry in $entries) {
        Write-Host "  $($entry.FullName)"
    }
}
finally {
    $zip.Dispose()
}

Write-Host ''
Write-Host "[Build-Module] Package retained at: $localRepo"

# -- Push to S3 staging ------------------------------------------------------

$testScript = Join-Path -Path $PSScriptRoot -ChildPath 'Test-LinuxBuild.ps1'

if ([string]::IsNullOrEmpty($S3Bucket)) {
    Write-Host '[Build-Module] [INFO] No -S3Bucket given. Skipping S3 upload.'
}
elseif (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    Write-Warning '[Build-Module] AWS CLI not found. Skipping S3 upload.'
}
else {
    $s3Target = "s3://$S3Bucket/staging/$moduleName/$version/"
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
        Write-Warning '[Build-Module] Test-LinuxBuild.ps1 not found in Scripts\ — skipping.'
    }

    Write-Host '[Build-Module] S3 upload complete.'
}

Write-Host "[Build-Module] Verify the contents above, then run Publish-ToGallery.ps1 to publish."
