Get-ChildItem -Path '.\tests' -Recurse | Unblock-File

# Run-UnitTests.ps1
Invoke-Pester -Configuration (& "$PSScriptRoot\..\Tests\UnitTests.pester.ps1")
$xml = [xml](Get-Content .\Tests\TestResults\UnitTests.xml)
$xml.'test-results' | Select-Object total, failures, errors, skipped

