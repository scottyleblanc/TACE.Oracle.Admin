#Requires -Version 7.0
<#
.SYNOPSIS
    Runs the static tier: checks that read source text and run no module code.

.DESCRIPTION
    Runs every test under Tests\Static. These checks are fast and are meant to run on
    every change. Exits 1 when any check fails.

.EXAMPLE
    .\scripts\test.static.ps1

.NOTES
    Copyright © TACE Data Management Inc.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot   = Split-Path -Path $PSScriptRoot -Parent
$staticPath = Join-Path -Path $repoRoot -ChildPath 'Tests' -AdditionalChildPath 'Static'

$config = New-PesterConfiguration
$config.Run.Path         = $staticPath
$config.Run.PassThru     = $true
$config.Output.Verbosity = 'Detailed'

$result = Invoke-Pester -Configuration $config

if ($result.FailedCount -gt 0) { exit 1 }
exit 0
