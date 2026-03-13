#Requires -Version 7.0
<#
.SYNOPSIS
    Oracle database administration utility module.

.DESCRIPTION
    TACE.OracleAdmin provides PowerShell functions for Oracle database
    environment management and administration utilities on Windows and Linux.

    Functions are designed for interactive DBA use and automation alike.
    All public functions return a standard PSCustomObject { Success, Data, Message }.

.NOTES
    Copyright © TACE Data Management Inc.
    Published name : TACE.OracleAdmin
    Internal name  : OracleAdmin
    Version        : 0.1.4
    Stage          : 1 — Foundation
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region -- Load private functions

$privateFunctions = @(
    'Invoke-OraEnv.ps1'
)

foreach ($function in $privateFunctions) {
    $functionPath = Join-Path $PSScriptRoot 'Private' $function
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
)

foreach ($function in $publicFunctions) {
    $functionPath = Join-Path $PSScriptRoot 'Public' $function
    if (-not (Test-Path $functionPath)) {
        throw "Required public function not found: $functionPath"
    }
    . $functionPath
}

#endregion

#region -- Aliases

Set-Alias -Name oraset -Value Invoke-OraEnv
Set-Alias -Name oraenv -Value Invoke-OraEnv

#endregion
