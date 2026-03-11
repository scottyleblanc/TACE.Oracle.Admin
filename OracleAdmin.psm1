#Requires -Version 7.0
<#
.SYNOPSIS
    Oracle database administration utility module.

.DESCRIPTION
    TACE.OracleAdmin provides PowerShell functions for Oracle database
    environment management and administration utilities on Windows.

    Functions are designed for interactive DBA use and automation alike.
    All public functions return a standard PSCustomObject { Success, Data, Message }.

.NOTES
    Copyright © TACE Data Management Inc.
    Published name : TACE.OracleAdmin
    Internal name  : OracleAdmin
    Version        : 0.1.0
    Stage          : 1 — Foundation
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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
