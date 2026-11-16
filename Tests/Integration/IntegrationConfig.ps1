#Requires -Version 7.6
<#
.SYNOPSIS
    Returns the integration tier's configuration: shared defaults merged with this
    machine's local values.

.DESCRIPTION
    The shared part, below, holds no machine-specific value: no host name, database or
    path. Those go in IntegrationConfig.local.ps1 beside this file, which is gitignored
    and never committed. Copy IntegrationConfig.local.example.ps1 to start one. The local
    file returns a hashtable; each key it holds replaces the shared value of that name.

    The guards that read this configuration are in IntegrationTestHelpers.ps1.

.OUTPUTS
    [PSCustomObject] The merged configuration.

.EXAMPLE
    $config = & (Join-Path -Path $PSScriptRoot -ChildPath 'IntegrationConfig.ps1')

.NOTES
    Copyright © TACE Data Management Inc.
    **Invocation:** Helper — called with the call operator by
    Scripts\Invoke-IntegrationTest.ps1 and by each integration test file. Reads files only.
    [SEC] The local file is gitignored: host names and paths stay out of the public repo.
#>
[CmdletBinding()]
[OutputType([PSCustomObject])]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$config = [ordered]@{
    # Guard 1. Host names the tier may run on, compared case-insensitively with
    # $env:COMPUTERNAME. Empty here; a production host must never be added.
    AllowedHosts           = [string[]]@()

    # Guard 2. Must be set to the value in the current session before a run, so an
    # approved host does not run the tier by accident.
    OptInVariableName      = 'ORACLE_ADMIN_RUN_INTEGRATION'
    OptInVariableValue     = '1'

    # Guard 3 requires these three. OracleHome and TestDatabaseName name the instance
    # (the SID, reached with OS authentication). TestBackupDestination is the folder the
    # tests write backup pieces to.
    OracleHome             = ''
    TestDatabaseName       = ''
    TestBackupDestination  = ''

    # Guard 4. A database name matching any of these, case-insensitively, is refused.
    # A second line of defence; the host allowlist is the first.
    DeniedDatabasePatterns = [string[]]@('PROD', 'PRD', 'PRODUCTION', 'LIVE', 'P01', 'P02')
}

$localFile = Join-Path -Path $PSScriptRoot -ChildPath 'IntegrationConfig.local.ps1'
if (Test-Path -LiteralPath $localFile -PathType Leaf) {
    $local = & $localFile
    if ($local -isnot [hashtable]) {
        throw "[IntegrationConfig] $localFile must return a hashtable."
    }
    foreach ($key in $local.Keys) {
        if (-not $config.Contains($key)) {
            throw "[IntegrationConfig] Unknown setting '$key' in IntegrationConfig.local.ps1."
        }
        $config[$key] = $local[$key]
    }
}

[PSCustomObject]$config
