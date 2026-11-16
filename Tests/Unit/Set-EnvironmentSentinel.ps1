#Requires -Version 7.6
<#
.SYNOPSIS
    Puts known sentinel values in the session environment before a call whose test asserts
    that the call changes nothing, and returns a snapshot to compare against.

.DESCRIPTION
    A test that reads $env:ORACLE_SID before a call and compares it afterwards proves
    nothing when an earlier test in the same session has already left the value the call
    would set. This script removes that dependency on test order.

    It sets ORACLE_HOME, ORACLE_SID, ORACLE_BASE and NLS_DATE_FORMAT to sentinel values no
    function in the module would write, and puts a sentinel entry at the front of PATH so
    child processes still find their commands. It returns a snapshot of the whole
    environment as it then stands, and the original values of the variables it changed.

    Pass the snapshot to Compare-EnvironmentSentinel.ps1 after the call, in a finally
    block: it reports every variable that changed and restores the original environment.

    It is not a test file: Pester runs only *.Tests.ps1 files.

.OUTPUTS
    [PSCustomObject] with Original (the replaced values) and Expected (the environment
    with the sentinels in place).

.EXAMPLE
    $sentinel = & (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'Set-EnvironmentSentinel.ps1')
    try { Invoke-Something }
    finally { $changed = & (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'Compare-EnvironmentSentinel.ps1') -Snapshot $sentinel }
    $changed | Should -BeNullOrEmpty

.NOTES
    Copyright © TACE Data Management Inc.
    **Invocation:** Helper — called with the call operator from a unit test. Changes the
    current session environment until Compare-EnvironmentSentinel.ps1 restores it.
#>
[CmdletBinding(SupportsShouldProcess)]
[OutputType([PSCustomObject])]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$names    = @('ORACLE_HOME', 'ORACLE_SID', 'ORACLE_BASE', 'NLS_DATE_FORMAT', 'PATH')
$original = @{}
foreach ($name in $names) {
    $original[$name] = [System.Environment]::GetEnvironmentVariable($name)
}

if ($PSCmdlet.ShouldProcess('session environment', 'Set sentinel values')) {
    foreach ($name in @('ORACLE_HOME', 'ORACLE_SID', 'ORACLE_BASE', 'NLS_DATE_FORMAT')) {
        [System.Environment]::SetEnvironmentVariable($name, "TACE_SENTINEL_$name")
    }
    $pathValue = if ([string]::IsNullOrEmpty($original['PATH'])) { 'TACE_SENTINEL_PATH' }
                 else { 'TACE_SENTINEL_PATH' + [System.IO.Path]::PathSeparator + $original['PATH'] }
    [System.Environment]::SetEnvironmentVariable('PATH', $pathValue)
}

$expected = @{}
foreach ($entry in [System.Environment]::GetEnvironmentVariables().GetEnumerator()) {
    $expected[[string]$entry.Key] = [string]$entry.Value
}

[PSCustomObject]@{
    Original = $original
    Expected = $expected
}
