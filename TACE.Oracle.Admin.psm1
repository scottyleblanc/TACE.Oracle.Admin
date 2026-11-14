#Requires -Version 7.0
<#
.SYNOPSIS
    Oracle database administration utility module.

.DESCRIPTION
    TACE.Oracle.Admin provides PowerShell functions for Oracle database
    environment management and administration utilities on Windows and Linux.

    Functions are designed for interactive DBA use and automation alike.
    All public functions return a standard PSCustomObject { Success, Data, Message }.

.NOTES
    Copyright © TACE Data Management Inc.
    Published name : TACE.Oracle.Admin
    Internal name  : OracleAdmin
    Version        : 0.2.1
    Stage          : 1 — Foundation
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region -- Module state

# [SEC] Test-only override for the config file path used by Get-OracleBackupConfigStore.
# Module-scoped, so only code running inside the module (tests via InModuleScope) can
# set it. Production always uses Config\OracleBackup.json under the module folder.
$script:ConfigPathOverride = $null

#endregion

#region -- Load private functions

$privateFunctions = @(
    'Invoke-OraEnv.ps1'
    'Test-WindowsPlatform.ps1'
    'ConvertFrom-SecureStringToPlaintext.ps1'
    'Set-RestrictiveAcl.ps1'
    'Assert-OracleEnvironment.ps1'
    'Get-OracleBackupConfigStore.ps1'
    'Invoke-RmanProcess.ps1'
    'ConvertFrom-RmanListBackup.ps1'
)

foreach ($function in $privateFunctions) {
    $functionPath = Join-Path -Path $PSScriptRoot -ChildPath 'Private' -AdditionalChildPath $function
    if (-not (Test-Path $functionPath)) {
        throw "Required private function not found: $functionPath"
    }
    . $functionPath
}

#endregion

#region -- Load public functions

$publicFunctions = @(
    'Get-OracleDatabaseList.ps1'
    'Set-OracleEnv.ps1'
    'Get-RmanBackupStatus.ps1'
    'Remove-RmanObsoleteBackup.ps1'
)

foreach ($function in $publicFunctions) {
    $functionPath = Join-Path -Path $PSScriptRoot -ChildPath 'Public' -AdditionalChildPath $function
    if (-not (Test-Path $functionPath)) {
        throw "Required public function not found: $functionPath"
    }
    . $functionPath
}

#endregion

#region -- Aliases

# Aliases are declared with an [Alias()] attribute on the function they target (rule
# C-30): oraset and oraenv are on Invoke-OraEnv. They are exported through
# AliasesToExport in the manifest.

#endregion
