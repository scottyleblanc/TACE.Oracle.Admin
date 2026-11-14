#Requires -Version 7.0

<#
.SYNOPSIS
    Downloads the latest TACE.Oracle.Admin build from S3 and smoke-tests it on Linux.

.DESCRIPTION
    Pulls the latest .nupkg from the S3 staging bucket, installs it into a local
    temporary PSResource repository, imports the module, and runs smoke tests to
    verify the Linux code path before the build is published to PSGallery.

    Smoke tests:
      - Module loads without error
      - Exported functions are present: Get-OracleDatabaseList, Set-OracleEnv, Invoke-OraEnv
      - Exported aliases are present: oraset, oraenv
      - Get-OracleDatabaseList runs on Linux (reads /etc/oratab or returns empty)
      - Return object shape is correct: Success, Data, Message

    Requirements:
      - PowerShell 7.0+
      - AWS CLI configured with credentials for the staging bucket
      - Run on Linux

.PARAMETER S3Bucket
    Name of the S3 staging bucket (the name only, without s3://). Required. The latest
    build is read from s3://<S3Bucket>/staging/TACE.Oracle.Admin/. No bucket name is kept
    in this repository.

.EXAMPLE
    pwsh ./scripts/Test-LinuxBuild.ps1 -S3Bucket '<staging-bucket>'

.NOTES
    Copyright © TACE Data Management Inc.
    Module  : TACE.Oracle.Admin
    Platform: Linux
    **Invocation:** Standalone — run on the Linux test host, not from this checkout.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$')]
    [string] $S3Bucket
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $IsLinux) {
    Write-Error '[Test-LinuxBuild] This script must be run on Linux.'
}

$s3Prefix  = "s3://$S3Bucket/staging/TACE.Oracle.Admin/"
$workDir   = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath 'TACE.Oracle.Admin.Test'
$repoDir   = Join-Path -Path $workDir -ChildPath 'repo'
$repoName  = 'TACELinuxTest'
$passed    = 0
$failed    = 0
$results   = @()

function Write-Pass ([string] $Test) {
    $script:passed++
    $script:results += [PSCustomObject]@{ Result = 'PASS'; Test = $Test }
    Write-Host "[PASS] $Test"
}

function Write-Fail ([string] $Test, [string] $Detail) {
    $script:failed++
    $script:results += [PSCustomObject]@{ Result = 'FAIL'; Test = $Test; Detail = $Detail }
    Write-Host "[FAIL] $Test"
    if ($Detail) { Write-Host "       $Detail" }
}

try {
    # -- Prepare work directory ----------------------------------------------

    if (Test-Path -Path $workDir) {
        Remove-Item -Path $workDir -Recurse -Force
    }
    New-Item -Path $repoDir -ItemType Directory -Force | Out-Null

    # -- Find latest build in S3 ---------------------------------------------

    Write-Host "[Test-LinuxBuild] Scanning $s3Prefix for latest build..."

    $s3List = aws s3 ls $s3Prefix 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "[Test-LinuxBuild] Failed to list S3 path: $s3List"
    }

    $versions = @($s3List |
        Where-Object { $_ -match 'PRE\s+([\d.]+)/' } |
        ForEach-Object { $Matches[1] } |
        Sort-Object { [System.Version]$_ })

    if ($versions.Count -eq 0) {
        Write-Error "[Test-LinuxBuild] No versioned builds found at $s3Prefix"
    }

    $latestVersion = $versions[-1]
    $s3NupkgPrefix = "$s3Prefix$latestVersion/"

    Write-Host "[Test-LinuxBuild] Latest build : v$latestVersion"

    # -- Download .nupkg -----------------------------------------------------

    $s3NupkgList = aws s3 ls $s3NupkgPrefix 2>&1
    $nupkgKey = @($s3NupkgList |
        Where-Object { $_ -match '(TACE\.Oracle\.Admin\.\S+\.nupkg)' } |
        ForEach-Object { $Matches[1] })

    if ($nupkgKey.Count -eq 0) {
        Write-Error "[Test-LinuxBuild] No .nupkg found at $s3NupkgPrefix"
    }

    $localNupkg = Join-Path -Path $repoDir -ChildPath $nupkgKey[0]

    Write-Host "[Test-LinuxBuild] Downloading : $($nupkgKey[0])"
    aws s3 cp "$s3NupkgPrefix$($nupkgKey[0])" $localNupkg 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "[Test-LinuxBuild] Failed to download $($nupkgKey[0]) from S3."
    }
    Write-Host "[Test-LinuxBuild] Download complete."

    # -- Install from local repo ---------------------------------------------

    Write-Host '[Test-LinuxBuild] Installing module...'

    if (Get-PSResourceRepository -Name $repoName -ErrorAction SilentlyContinue) {
        Unregister-PSResourceRepository -Name $repoName
    }
    Register-PSResourceRepository -Name $repoName -Uri $repoDir -Trusted

    Install-PSResource -Name 'TACE.Oracle.Admin' -Repository $repoName -TrustRepository -Reinstall

    # -- Import module -------------------------------------------------------

    Write-Host '[Test-LinuxBuild] Importing module...'

    try {
        Import-Module 'TACE.Oracle.Admin' -Force
        Write-Pass 'Module imports without error'
    }
    catch {
        Write-Fail 'Module imports without error' $_.Exception.Message
    }

    # -- Smoke tests ---------------------------------------------------------

    Write-Host '[Test-LinuxBuild] Running smoke tests...'

    # Exported functions
    foreach ($fn in @('Get-OracleDatabaseList', 'Set-OracleEnv', 'Invoke-OraEnv')) {
        if (Get-Command -Name $fn -ErrorAction SilentlyContinue) {
            Write-Pass "Function '$fn' is available"
        }
        else {
            Write-Fail "Function '$fn' is available" 'Command not found after import'
        }
    }

    # Exported aliases
    foreach ($alias in @('oraset', 'oraenv')) {
        if (Get-Alias -Name $alias -ErrorAction SilentlyContinue) {
            Write-Pass "Alias '$alias' is available"
        }
        else {
            Write-Fail "Alias '$alias' is available" 'Alias not found after import'
        }
    }

    # Get-OracleDatabaseList runs on Linux
    try {
        $result = Get-OracleDatabaseList
        if ($result.PSObject.Properties.Name -contains 'Success' -and
            $result.PSObject.Properties.Name -contains 'Data' -and
            $result.PSObject.Properties.Name -contains 'Message') {
            Write-Pass 'Get-OracleDatabaseList returns correct object shape'
        }
        else {
            Write-Fail 'Get-OracleDatabaseList returns correct object shape' 'Missing Success, Data, or Message property'
        }

        if ($result.Success) {
            Write-Pass 'Get-OracleDatabaseList returns Success=$true'
            Write-Host "       Found $(@($result.Data).Count) instance(s): $(($result.Data | ForEach-Object { $_.SID }) -join ', ')"
        }
        else {
            Write-Fail 'Get-OracleDatabaseList returns Success=$true' $result.Message
        }
    }
    catch {
        Write-Fail 'Get-OracleDatabaseList runs without exception' $_.Exception.Message
    }

    # Message is safe to log (no credential fragments)
    try {
        $result = Get-OracleDatabaseList
        if ($result.Message -notmatch 'password|credential|secret|pwd') {
            Write-Pass 'Get-OracleDatabaseList Message contains no credential fragments'
        }
        else {
            Write-Fail 'Get-OracleDatabaseList Message contains no credential fragments' "Message: $($result.Message)"
        }
    }
    catch {
        Write-Fail 'Get-OracleDatabaseList Message contains no credential fragments' $_.Exception.Message
    }
}
finally {
    # -- Clean up ------------------------------------------------------------

    if (Get-PSResourceRepository -Name $repoName -ErrorAction SilentlyContinue) {
        Unregister-PSResourceRepository -Name $repoName
    }

    if (Test-Path -Path $workDir) {
        Remove-Item -Path $workDir -Recurse -Force
    }

    Remove-Module 'TACE.Oracle.Admin' -Force -ErrorAction SilentlyContinue

    # -- Summary -------------------------------------------------------------

    Write-Host ''
    Write-Host '[Test-LinuxBuild] Results:'
    Write-Host "  Passed : $passed"
    Write-Host "  Failed : $failed"

    if ($failed -gt 0) {
        Write-Host ''
        Write-Host '[Test-LinuxBuild] Failures:'
        $results | Where-Object { $_.Result -eq 'FAIL' } | ForEach-Object {
            Write-Host "  [FAIL] $($_.Test)"
            if ($_.Detail) { Write-Host "         $($_.Detail)" }
        }
        exit 1
    }
    else {
        Write-Host ''
        Write-Host '[Test-LinuxBuild] All tests passed. Safe to publish.'
        exit 0
    }
}
