#Requires -Version 7.6
<#
.SYNOPSIS
    Guards and helpers for the integration tier.

.DESCRIPTION
    Dot-source this file. It defines:

      Assert-IntegrationTestAllowed     runs the five guards; throws on the first failure
      Invoke-IntegrationRman            runs an RMAN script through the module's own
                                        Invoke-RmanProcess, with OS authentication
      New-IntegrationBackup             backs up the current control file into the test
                                        folder, with a fixed tag and a name prefix
      Remove-IntegrationBackup          deletes every backup with the fixed tag, and any
                                        test piece left in the test folder
      Get-IntegrationDatabaseVersion    reads the database edition and version for the
                                        run evidence
      Set-IntegrationConfigOverride     points the module's config at a file that holds
                                        only the integration OracleHome
      Clear-IntegrationConfigOverride   undoes that

    The guards, in order (OracleBackup design decision AD-020):
      1. Host allowlist     $env:COMPUTERNAME is in AllowedHosts
      2. Opt-in variable    the opt-in variable holds the opt-in value in this session
      3. Config complete    OracleHome, TestDatabaseName and TestBackupDestination are
                            set and well-formed
      4. Database denylist  TestDatabaseName matches no denied pattern
      5. Destination exists TestBackupDestination exists, and OracleHome\bin\rman.exe too

    A guard that fails throws, so the run fails and names the guard. It never skips:
    a run with a guard down must not look like a pass.

    The helpers need the built module imported first. They call it through its module
    scope, so they do not depend on Pester.

.NOTES
    Copyright © TACE Data Management Inc.
    **Invocation:** Helper — dot-sourced by Scripts\Invoke-IntegrationTest.ps1 and by each
    integration test file.
    [SEC] Only OS authentication is used. No credential is read, held or passed.
    [SEC] TestBackupDestination is placed inside an RMAN FORMAT string, so guard 3 refuses
    a path that holds a quote.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-IntegrationTestAllowed {
    <#
    .SYNOPSIS
        Runs the five integration guards. Throws on the first one that fails.
    .PARAMETER Config
        The configuration from IntegrationConfig.ps1.
    .EXAMPLE
        Assert-IntegrationTestAllowed -Config $config
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$Config
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $local = 'Tests\Integration\IntegrationConfig.local.ps1'

    # Guard 1: host allowlist.
    $hostName = $env:COMPUTERNAME
    $allowed  = @($Config.AllowedHosts | Where-Object { -not [string]::IsNullOrWhiteSpace($PSItem) })
    if ($allowed.Count -eq 0) {
        throw "[INTEGRATION] Guard 1 (host allowlist): no host is allowed. Add this host's name to AllowedHosts in $local."
    }
    if (@($allowed | Where-Object { $PSItem -ieq $hostName }).Count -eq 0) {
        throw "[INTEGRATION] Guard 1 (host allowlist): this host is not in AllowedHosts in $local."
    }

    # Guard 2: opt-in variable, read from this process only.
    $optIn = [System.Environment]::GetEnvironmentVariable($Config.OptInVariableName, [System.EnvironmentVariableTarget]::Process)
    if ($optIn -ne $Config.OptInVariableValue) {
        throw "[INTEGRATION] Guard 2 (opt-in): set `$env:$($Config.OptInVariableName) = '$($Config.OptInVariableValue)' in this session first."
    }

    # Guard 3: the configuration is complete and well-formed.
    foreach ($name in @('OracleHome', 'TestDatabaseName', 'TestBackupDestination')) {
        if ([string]::IsNullOrWhiteSpace($Config.$name)) {
            throw "[INTEGRATION] Guard 3 (config): $name is not set in $local."
        }
    }
    if ($Config.TestDatabaseName -notmatch '\A[A-Za-z][A-Za-z0-9_]{0,29}\z') {
        throw '[INTEGRATION] Guard 3 (config): TestDatabaseName is not a valid SID.'
    }
    if ($Config.TestBackupDestination.Contains("'") -or $Config.TestBackupDestination.Contains('"')) {
        throw '[INTEGRATION] Guard 3 (config): TestBackupDestination must not contain a quote.'
    }

    # Guard 4: database denylist.
    foreach ($pattern in @($Config.DeniedDatabasePatterns)) {
        if ($Config.TestDatabaseName -imatch [regex]::Escape($pattern)) {
            throw "[INTEGRATION] Guard 4 (denylist): TestDatabaseName matches the denied pattern '$pattern'. The tier must not run against a production database."
        }
    }

    # Guard 5: the test environment is prepared.
    if (-not (Test-Path -LiteralPath $Config.TestBackupDestination -PathType Container)) {
        throw '[INTEGRATION] Guard 5 (destination): TestBackupDestination does not exist. Create the folder by hand before the first run.'
    }
    $rman = Join-Path -Path $Config.OracleHome -ChildPath 'bin' -AdditionalChildPath 'rman.exe'
    if (-not (Test-Path -LiteralPath $rman -PathType Leaf)) {
        throw '[INTEGRATION] Guard 5 (destination): rman.exe is not under OracleHome\bin.'
    }
}

function Invoke-IntegrationRman {
    <#
    .SYNOPSIS
        Runs an RMAN script against the integration database through Invoke-RmanProcess.
    .PARAMETER Config
        The configuration from IntegrationConfig.ps1.
    .PARAMETER Script
        The RMAN commands, each ending in a semicolon.
    .PARAMETER TimeoutSeconds
        How long RMAN may run. Defaults to 300.
    .EXAMPLE
        Invoke-IntegrationRman -Config $config -Script 'LIST BACKUP SUMMARY;'
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$Config,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Script,

        [Parameter()]
        [ValidateRange(30, 3600)]
        [int]$TimeoutSeconds = 300
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $module = Get-Module -Name 'TACE.Oracle.Admin'
    if ($null -eq $module) { throw '[INTEGRATION] The built module is not imported.' }

    $params = @{
        RmanBinaryPath = Join-Path -Path $Config.OracleHome -ChildPath 'bin' -AdditionalChildPath 'rman.exe'
        RmanScript     = $Script
        OracleHome     = $Config.OracleHome
        OracleSid      = $Config.TestDatabaseName
        TimeoutSeconds = $TimeoutSeconds
    }
    & $module { param([hashtable]$Params) Invoke-RmanProcess @Params } $params
}

function New-IntegrationBackup {
    <#
    .SYNOPSIS
        Backs up the current control file into the test folder and returns its piece files.
    .DESCRIPTION
        A control file backup is allowed with the database open in NOARCHIVELOG mode, and
        needs no change to the database or its RMAN configuration.
    .PARAMETER Config
        The configuration from IntegrationConfig.ps1.
    .PARAMETER Prefix
        A letter or two that names this backup's pieces: IT_<Prefix>_<RMAN unique name>.
    .EXAMPLE
        $first = New-IntegrationBackup -Config $config -Prefix 'A'
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$Config,

        [Parameter(Mandatory)]
        [ValidatePattern('\A[A-Z]{1,2}\z')]
        [string]$Prefix
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $format = Join-Path -Path $Config.TestBackupDestination -ChildPath "IT_${Prefix}_%U"
    $result = Invoke-IntegrationRman -Config $Config -Script "BACKUP CURRENT CONTROLFILE FORMAT '$format' TAG 'INTEGRATION_TEST';"
    if (-not $result.Success) {
        throw "[INTEGRATION] The control file backup '$Prefix' failed. RMAN output:`n$($result.StdOut)`n$($result.StdErr)"
    }
    $pieces = @(Get-ChildItem -LiteralPath $Config.TestBackupDestination -Filter "IT_${Prefix}_*" -File)
    if ($pieces.Count -eq 0) {
        throw "[INTEGRATION] The control file backup '$Prefix' reported success but wrote no piece to the test folder."
    }
    , [System.IO.FileInfo[]]$pieces
}

function Remove-IntegrationBackup {
    <#
    .SYNOPSIS
        Deletes every backup with the integration tag, then any test piece left on disk.
    .DESCRIPTION
        Runs at the start and end of each test file, so an interrupted run leaves nothing
        behind for the next one.
    .PARAMETER Config
        The configuration from IntegrationConfig.ps1.
    .EXAMPLE
        Remove-IntegrationBackup -Config $config
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$Config
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if (-not $PSCmdlet.ShouldProcess('backups tagged INTEGRATION_TEST', 'Delete')) { return }

    # Every test backup carries this tag, and every piece name starts with 'IT_'.
    $tag    = 'INTEGRATION_TEST'
    $result = Invoke-IntegrationRman -Config $Config -Script "CROSSCHECK BACKUP TAG '$tag';`nDELETE NOPROMPT BACKUP TAG '$tag';"
    # With nothing tagged, RMAN reports that the specification matches no backup. That
    # is a clean state, not a failure.
    if (-not $result.Success -and $result.StdOut -notmatch 'does not match any backup') {
        throw "[INTEGRATION] Cleanup of backups tagged $tag failed. RMAN output:`n$($result.StdOut)"
    }

    foreach ($piece in @(Get-ChildItem -LiteralPath $Config.TestBackupDestination -Filter 'IT_*' -File)) {
        Remove-Item -LiteralPath $piece.FullName -Force -WhatIf:$false
    }
}

function Get-IntegrationDatabaseVersion {
    <#
    .SYNOPSIS
        Returns the integration database's edition code and full version, from V$INSTANCE.
    .DESCRIPTION
        Recorded in the run evidence. Returns 'unknown' for a value it cannot read rather
        than throwing, so a failed lookup never hides the test results.
    .PARAMETER Config
        The configuration from IntegrationConfig.ps1.
    .EXAMPLE
        Get-IntegrationDatabaseVersion -Config $config
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$Config
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $result  = Invoke-IntegrationRman -Config $Config -Script 'SELECT EDITION, VERSION_FULL FROM V$INSTANCE;' -TimeoutSeconds 120
    $edition = 'unknown'
    $version = 'unknown'
    if ($result.Success -and $result.StdOut -match '(?m)^(?<edition>[A-Z]{2,4})\s+(?<version>\d+(?:\.\d+){4})\s*$') {
        $edition = $Matches['edition']
        $version = $Matches['version']
    }
    [PSCustomObject]@{ Edition = $edition; Version = $version }
}

function Set-IntegrationConfigOverride {
    <#
    .SYNOPSIS
        Points the module's config at a file that holds only the integration OracleHome.
    .DESCRIPTION
        Sets the module-scoped $script:ConfigPathOverride, the override unit tests use, so
        the module's real config file is neither read nor written.
    .PARAMETER Config
        The configuration from IntegrationConfig.ps1.
    .PARAMETER Path
        Where to write the config file, for example under TestDrive:.
    .EXAMPLE
        Set-IntegrationConfigOverride -Config $config -Path (Join-Path -Path $TestDrive -ChildPath 'config.json')
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$Config,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if (-not $PSCmdlet.ShouldProcess($Path, 'Write integration config and point the module at it')) { return }

    $json = ConvertTo-Json -InputObject ([PSCustomObject]@{ OracleHome = $Config.OracleHome }) -Depth 2
    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8 -WhatIf:$false
    $module = Get-Module -Name 'TACE.Oracle.Admin'
    & $module { param([string]$ConfigPath) $script:ConfigPathOverride = $ConfigPath } $Path
}

function Clear-IntegrationConfigOverride {
    <#
    .SYNOPSIS
        Removes the module's config override set by Set-IntegrationConfigOverride.
    .EXAMPLE
        Clear-IntegrationConfigOverride
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param()

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $module = Get-Module -Name 'TACE.Oracle.Admin'
    if ($null -ne $module -and $PSCmdlet.ShouldProcess('module config override', 'Clear')) {
        & $module { $script:ConfigPathOverride = $null }
    }
}
