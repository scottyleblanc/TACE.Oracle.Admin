#Requires -Version 7.6
<#
.SYNOPSIS
    Runs the integration tier: Pester tests against a real Oracle database on this machine.

.DESCRIPTION
    Builds the module, runs the five integration guards, then runs every
    *.Integration.Tests.ps1 file under Tests\Integration\ against the built module.
    Rule T-10.

    The guards (Tests\Integration\IntegrationTestHelpers.ps1) check that this host is
    allowed, that the opt-in variable is set in this session, that the local
    configuration is complete, that the database name is not a production name, and that
    the test folder exists. When one fails the run stops before any test starts, prints
    which guard and why, and exits 1. Each test file runs the guards again, so a file run
    on its own is guarded too.

    The tests take control file backups into the test folder and run DELETE OBSOLETE,
    which acts on the whole database. Only run the tier where losing backups is
    acceptable.

    Writes NUnit XML results to Tests\TestResults\integration.xml, replacing the previous
    run. Exits 1 when a guard, a test or a test file fails, and 0 otherwise.

    Also writes the run evidence, Tests\Integration\LastRun.json (rule T-14): the commit
    the run was made against, whether the working tree was clean, the date, the database
    edition and version, the PowerShell and Pester versions, the totals, and each test's
    name and outcome. It holds no host name, path or SID. Evidence is true only for a
    passing run on a clean tree; changes to LastRun.json itself do not count as unclean.
    Commit the file as the last commit of a branch, so a reviewer can see the code passed
    against a real database. No file is written when a guard or the build stops the run.

    Setup, once per machine: copy Tests\Integration\IntegrationConfig.local.example.ps1
    to IntegrationConfig.local.ps1 (gitignored) and fill it in, and create the test folder.
    Before each run: $env:ORACLE_ADMIN_RUN_INTEGRATION = '1'.

.EXAMPLE
    $env:ORACLE_ADMIN_RUN_INTEGRATION = '1'
    .\Scripts\Invoke-IntegrationTest.ps1

.NOTES
    Copyright © TACE Data Management Inc.
    **Invocation:** Standalone — self-contained; safe to run with `pwsh -File`. Runs from
    any working directory: every path is resolved from this script's location. Also run
    by Scripts\Invoke-Gate.ps1 -Integration. Never run by the pre-push hook.
    [SEC] OS authentication only. The local configuration holds no credential.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module Pester -MinimumVersion 5.0

$repoRoot        = Split-Path -Path $PSScriptRoot -Parent
$testsRoot       = Join-Path -Path $repoRoot -ChildPath 'Tests'
$integrationRoot = Join-Path -Path $testsRoot -ChildPath 'Integration'
$resultsDir      = Join-Path -Path $testsRoot -ChildPath 'TestResults'
$resultsFile     = Join-Path -Path $resultsDir -ChildPath 'integration.xml'

# Guards first: nothing is built or run on a host or database that is not allowed.
. (Join-Path -Path $integrationRoot -ChildPath 'IntegrationTestHelpers.ps1')
try {
    $config = & (Join-Path -Path $integrationRoot -ChildPath 'IntegrationConfig.ps1')
    Assert-IntegrationTestAllowed -Config $config
}
catch {
    Write-Output "[FAIL] integration: no tests run. $($PSItem.Exception.Message)"
    exit 1
}

$buildScript = Join-Path -Path $PSScriptRoot -ChildPath 'Build-Module.ps1'
try {
    & $buildScript
}
catch {
    Write-Output "[FAIL] integration: build failed, no tests run. $($PSItem.Exception.Message)"
    exit 1
}

$testFiles = @(Get-ChildItem -Path $integrationRoot -Filter '*.Integration.Tests.ps1' -File |
    Select-Object -ExpandProperty FullName)
if ($testFiles.Count -eq 0) {
    throw "[integration] No test files found under $integrationRoot"
}

$null = New-Item -Path $resultsDir -ItemType Directory -Force

# -- Evidence inputs, read before the tests run -------------------------------------

$evidenceFile     = Join-Path -Path $integrationRoot -ChildPath 'LastRun.json'
$evidenceRelative = 'Tests/Integration/LastRun.json'

$commit = (& git -C $repoRoot rev-parse HEAD 2>$null)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($commit)) { $commit = 'unknown' }
# Untracked files count as changes; ignored files (the local config) do not; nor does
# the evidence file itself, which every run rewrites.
$changes = @(& git -C $repoRoot status --porcelain --untracked-files=all 2>$null |
    Where-Object { $PSItem.Substring(3).Trim('"') -ne $evidenceRelative })
$treeClean = $commit -ne 'unknown' -and $changes.Count -eq 0

Import-Module (& (Join-Path -Path $testsRoot -ChildPath 'Unit' -AdditionalChildPath 'Get-BuiltModulePath.ps1')) -Force
$database = Get-IntegrationDatabaseVersion -Config $config
Remove-Module -Name 'TACE.Oracle.Admin' -Force

Write-Output "[INFO] integration: Oracle $($database.Edition) $($database.Version), OS authentication, $($testFiles.Count) test file(s)."

$pesterConfig = New-PesterConfiguration
$pesterConfig.Run.Path                = [string[]]$testFiles
$pesterConfig.Run.PassThru            = $true
$pesterConfig.Output.Verbosity        = 'Detailed'
$pesterConfig.TestResult.Enabled      = $true
$pesterConfig.TestResult.OutputFormat = 'NUnitXml'
$pesterConfig.TestResult.OutputPath   = $resultsFile

$result = Invoke-Pester -Configuration $pesterConfig

# FailedContainersCount counts a file whose BeforeAll threw, such as a failed guard.
$failed = $result.FailedCount -gt 0 -or $result.FailedContainersCount -gt 0

$label = if ($failed) { '[FAIL]' } else { '[PASS]' }
Write-Output ('{0} integration: {1} passed, {2} failed, {3} skipped, {4} file(s) failed to run. Results: {5}' -f
    $label, $result.PassedCount, $result.FailedCount, $result.SkippedCount, $result.FailedContainersCount, $resultsFile)

# -- Evidence (rule T-14) ----------------------------------------------------------

# Test names are Describe, Context and It titles only. No host name, path or SID.
$tests = @($result.Tests | ForEach-Object {
        [PSCustomObject]@{ Name = $PSItem.ExpandedPath; Result = "$($PSItem.Result)" }
    })
$evidence = [PSCustomObject]@{
    SchemaVersion    = 1
    Commit           = $commit
    WorkingTreeClean = $treeClean
    Passed           = -not $failed
    Evidence         = $treeClean -and -not $failed
    RunAtUtc         = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    Database         = [PSCustomObject]@{ Edition = $database.Edition; Version = $database.Version }
    PowerShell       = $PSVersionTable.PSVersion.ToString()
    Pester           = (Get-Module -Name Pester).Version.ToString()
    Totals           = [PSCustomObject]@{
        Passed           = $result.PassedCount
        Failed           = $result.FailedCount
        Skipped          = $result.SkippedCount
        FailedContainers = $result.FailedContainersCount
    }
    Tests            = $tests
}
$json = (ConvertTo-Json -InputObject $evidence -Depth 5) -replace "`r`n", "`n"
[System.IO.File]::WriteAllText($evidenceFile, $json + "`n", [System.Text.UTF8Encoding]::new($false))

$shortCommit = if ($commit.Length -ge 7) { $commit.Substring(0, 7) } else { $commit }
if ($evidence.Evidence) {
    Write-Output "[INFO] integration: evidence for $shortCommit written to $evidenceRelative. Commit it as the last commit of the branch."
}
elseif (-not $treeClean) {
    Write-Output "[INFO] integration: $evidenceRelative written, but it is not evidence: the working tree had uncommitted changes. Commit them and run again."
}
else {
    Write-Output "[INFO] integration: $evidenceRelative written, but it is not evidence: the run failed."
}

if ($failed) { exit 1 }

# Explicit, so a caller never reads a $LASTEXITCODE left over from an earlier command.
exit 0
