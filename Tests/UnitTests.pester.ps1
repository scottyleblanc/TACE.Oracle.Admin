#Requires -Version 7.0
<#
.SYNOPSIS
    Pester configuration for OracleBackup unit tests.

.DESCRIPTION
    Runs only unit tests. Integration tests are explicitly excluded —
    they live in Tests\Integration\*.Integration.Tests.ps1 and require
    a real Oracle instance.

    Usage:
        Invoke-Pester -Configuration (& .\Tests\UnitTests.pester.ps1)

.NOTES
    Copyright © TACE Data Management Inc.
#>

$config = New-PesterConfiguration

# Glob for unit test files, explicitly excluding integration tests.
# Run.Include/Exclude do not exist in Pester 5 — filter with Get-ChildItem.
$unitTestFiles = Get-ChildItem -Path $PSScriptRoot -Filter '*.Tests.ps1' -File |
    Where-Object { $_.Name -notlike '*.Integration.Tests.ps1' } |
    Select-Object -ExpandProperty FullName

$config.Run.Path                = $unitTestFiles

# Output
$config.Output.Verbosity        = 'Detailed'

# Test results
$config.TestResult.Enabled      = $true
$config.TestResult.OutputPath   = "$PSScriptRoot\TestResults\UnitTests.xml"
$config.TestResult.OutputFormat = 'NUnitXml'

return $config
