#Requires -Version 7.0

<#
.SYNOPSIS
    Syncs the TACE.Oracle.Admin module folder to an S3 staging bucket.

.DESCRIPTION
    Uses the AWS CLI to sync the module root to s3://<S3Bucket>/staging/TACE.Oracle.Admin/.
    Only new or changed files are uploaded. Use -Upload to force a full copy regardless of changes.

.PARAMETER S3Bucket
    Name of the S3 staging bucket (the name only, without s3://). Required. No bucket
    name is kept in this repository.

.PARAMETER Upload
    Performs a full recursive copy instead of a sync. All files are uploaded unconditionally.

.PARAMETER DryRun
    Shows what would be transferred without uploading anything.

.EXAMPLE
    .\Sync-ToS3.ps1 -S3Bucket '<staging-bucket>'

.EXAMPLE
    .\Sync-ToS3.ps1 -S3Bucket '<staging-bucket>' -DryRun

.EXAMPLE
    .\Sync-ToS3.ps1 -S3Bucket '<staging-bucket>' -Upload

.NOTES
    Copyright © TACE Data Management Inc.
    Module  : TACE.Oracle.Admin
    Requires: AWS CLI v2 installed and configured with credentials for the staging bucket
    **Invocation:** Standalone — run from a checkout with AWS credentials available.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$')]
    [string] $S3Bucket,

    [switch] $Upload,
    [switch] $DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleRoot = Join-Path -Path $PSScriptRoot -ChildPath '..'
$moduleRoot = (Resolve-Path -Path $moduleRoot).Path
$s3Target   = "s3://$S3Bucket/staging/TACE.Oracle.Admin/"

# Verify AWS CLI is available
if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    Write-Error '[Sync-ToS3] AWS CLI not found. Install it from https://aws.amazon.com/cli/'
}

Write-Host "[Sync-ToS3] Source : $moduleRoot"
Write-Host "[Sync-ToS3] Target : $s3Target"

$excludes = @('--exclude', '.git/*', '--exclude', '.claude/*')

if ($Upload) {
    $awsArgs = @('s3', 'cp', $moduleRoot, $s3Target, '--recursive') + $excludes
    Write-Host '[Sync-ToS3] Mode   : upload (full recursive copy)'
}
else {
    $awsArgs = @('s3', 'sync', $moduleRoot, $s3Target) + $excludes
    Write-Host '[Sync-ToS3] Mode   : sync (new and changed files only)'
}

if ($DryRun) {
    $awsArgs += '--dryrun'
    Write-Host '[Sync-ToS3] Dry run enabled — no files will be transferred'
}

Write-Host ''

if ($PSCmdlet.ShouldProcess($s3Target, 'Upload module files')) {
    & aws @awsArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Error "[Sync-ToS3] AWS CLI exited with code $LASTEXITCODE"
    }
    else {
        Write-Host "`n[Sync-ToS3] Done."
    }
}
