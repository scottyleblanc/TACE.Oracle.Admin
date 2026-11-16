#Requires -Version 7.6
<#
.SYNOPSIS
    Reports every session environment variable changed since Set-EnvironmentSentinel.ps1
    ran, then restores the environment as it was before the sentinels were set.

.DESCRIPTION
    Compares the whole current environment with the snapshot: a variable added, removed
    or given another value is reported by name. Values are never returned, so a leaked
    credential cannot reach the test output.

    It then puts the environment back: variables the call added are removed, variables it
    changed or removed get their snapshot value, and the sentinel variables get the values
    they had before Set-EnvironmentSentinel.ps1 ran. Call it in a finally block.

    It is not a test file: Pester runs only *.Tests.ps1 files.

.PARAMETER Snapshot
    The object returned by Set-EnvironmentSentinel.ps1.

.OUTPUTS
    [string[]] The names of the variables that changed, sorted. Empty when nothing changed.

.EXAMPLE
    finally { $changed = & (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'Compare-EnvironmentSentinel.ps1') -Snapshot $sentinel }

.NOTES
    Copyright © TACE Data Management Inc.
    **Invocation:** Helper — called with the call operator from a unit test, after
    Set-EnvironmentSentinel.ps1. Restores the current session environment.
#>
[CmdletBinding(SupportsShouldProcess)]
[OutputType([string[]])]
param(
    [Parameter(Mandatory)]
    [ValidateNotNull()]
    [PSCustomObject]$Snapshot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$expected = $Snapshot.Expected
$current  = @{}
foreach ($entry in [System.Environment]::GetEnvironmentVariables().GetEnumerator()) {
    $current[[string]$entry.Key] = [string]$entry.Value
}

$changed = [System.Collections.Generic.List[string]]::new()
foreach ($name in $current.Keys) {
    if (-not $expected.ContainsKey($name) -or $expected[$name] -cne $current[$name]) { $changed.Add($name) }
}
foreach ($name in $expected.Keys) {
    if (-not $current.ContainsKey($name)) { $changed.Add($name) }
}

if ($PSCmdlet.ShouldProcess('session environment', 'Restore the values before the sentinels')) {
    foreach ($name in $changed) {
        $value = if ($expected.ContainsKey($name)) { $expected[$name] } else { $null }
        [System.Environment]::SetEnvironmentVariable($name, $value)
    }
    foreach ($name in $Snapshot.Original.Keys) {
        [System.Environment]::SetEnvironmentVariable($name, $Snapshot.Original[$name])
    }
}

, [string[]]@($changed | Sort-Object -Unique)
