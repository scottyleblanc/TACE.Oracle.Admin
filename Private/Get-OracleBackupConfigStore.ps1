#Requires -Version 7.0
<#
.SYNOPSIS
    Reads the OracleBackup JSON configuration file and returns the config object.
    Creates the default config file with restrictive ACLs if it does not exist.

.DESCRIPTION
    This is a private helper called by the module root at import time to populate
    $script:OracleBackupConfig, and by any function that needs to read current
    configuration directly from disk rather than from the session cache.

    Config file location: <ModuleRoot>\Config\OracleBackup.json

    Default configuration values:
        BackupBasePath      : C:\app\oracle\backup
        FastRecoveryArea    : C:\app\oracle\fast_recovery_area
        LogBasePath         : C:\app\oracle\backup\logs
        LogRetentionHotDays : 15
        LogRetentionWarmDays: 90
        OracleHome          : (empty — must be set via Set-OracleBackupConfig)

.OUTPUTS
    [PSCustomObject] — the current configuration object.

.NOTES

    [SEC] Config file is written with restrictive ACLs on creation:
    Windows — inheritance disabled; current user and Administrators only.

    [SEC] OracleHome value from config is treated as untrusted input.
    Callers must validate it via Assert-OracleEnvironment before use in
    path construction or process invocation.
#>
function Get-OracleBackupConfigStore {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    #--------------------------------------------------------------
    # INVARIANTS
    #
    # PRE-CONDITIONS
    #   P1 The config file is the one named by ORACLE_BACKUP_CONFIG_PATH when that is
    #       set, and Config\OracleBackup.json under the module folder otherwise.
    #       Guard: the path resolution at the start of the body.
    #
    # SECURITY INVARIANTS
    #   [SEC] S1 A config file created here is given restricted permissions straight
    #       after it is written.
    #       Guard: the Set-RestrictiveAcl call that follows the write.
    #   [SEC] S2 The config holds paths and defaults, never a credential.
    #       Limitation: nothing checks what the file contains.
    #   [SEC] S3 OracleHome read from the config is untrusted until checked.
    #       Limitation: the caller's duty, met by Assert-OracleEnvironment.
    #   [SEC] S4 ORACLE_BACKUP_CONFIG_PATH is used without validation, so an environment
    #       variable decides where the config is read from and created.
    #       Limitation: accepted for test isolation. Not reviewed for production use.
    #
    # POST-CONDITIONS
    #   R1 Returns an object with all eight settings. A setting missing from the file
    #       takes its default.
    #       Test: none yet.
    #   R2 When the file does not exist it is written with the defaults, and the defaults
    #       are returned.
    #       Test: none yet.
    #   T1 Every throw starts with 'Failed to load OracleBackup configuration from' and
    #       names the path.
    #       Test: none yet.
    #
    # EXECUTION INVARIANTS
    #   L1 The first call can create a folder and a file. It is not under ShouldProcess.
    #       Limitation: a caller's -WhatIf does not reliably prevent the write.
    #--------------------------------------------------------------

    # Resolve config path — allow override via environment variable for test isolation
    $configPath = if ($env:ORACLE_BACKUP_CONFIG_PATH) {
        $env:ORACLE_BACKUP_CONFIG_PATH
    }
    else {
        $resolved = Join-Path $PSScriptRoot '..' 'Config' 'OracleBackup.json'
        [System.IO.Path]::GetFullPath($resolved)
    }

    $defaultConfig = [PSCustomObject]@{
        BackupBasePath       = 'C:\app\oracle\backup'
        FastRecoveryArea     = 'C:\app\oracle\fast_recovery_area'
        LogBasePath          = 'C:\app\oracle\backup\logs'
        LogRetentionHotDays  = 15
        LogRetentionWarmDays = 90
        OracleHome           = ''
        DefaultAuthMode      = 'OSAuth'
        DefaultWalletAlias   = ''
    }

    try {
        if (-not (Test-Path $configPath)) {
            Write-Verbose "[Get-OracleBackupConfigStore] Config file not found — creating default at $configPath"

            $configDir = Split-Path $configPath -Parent
            if (-not (Test-Path $configDir)) {
                $null = New-Item -Path $configDir -ItemType Directory -Force
            }

            $defaultConfig |
                ConvertTo-Json -Depth 5 |
                Set-Content -Path $configPath -Encoding UTF8

            # [SEC] Apply restrictive ACLs immediately after creation —
            # disable inheritance; grant current user and BUILTIN\Administrators only.
            Set-RestrictiveAcl -Path $configPath

            Write-Verbose "[Get-OracleBackupConfigStore] Default config written to $configPath"
            return $defaultConfig
        }

        $raw = Get-Content -Path $configPath -Raw -Encoding UTF8
        $loaded = $raw | ConvertFrom-Json

        # Ensure all expected keys are present — merge with defaults for forward compatibility
        $merged = [PSCustomObject]@{
            BackupBasePath       = if ($null -ne $loaded.BackupBasePath)       { $loaded.BackupBasePath }       else { $defaultConfig.BackupBasePath }
            FastRecoveryArea     = if ($null -ne $loaded.FastRecoveryArea)     { $loaded.FastRecoveryArea }     else { $defaultConfig.FastRecoveryArea }
            LogBasePath          = if ($null -ne $loaded.LogBasePath)          { $loaded.LogBasePath }          else { $defaultConfig.LogBasePath }
            LogRetentionHotDays  = if ($null -ne $loaded.LogRetentionHotDays)  { $loaded.LogRetentionHotDays }  else { $defaultConfig.LogRetentionHotDays }
            LogRetentionWarmDays = if ($null -ne $loaded.LogRetentionWarmDays) { $loaded.LogRetentionWarmDays } else { $defaultConfig.LogRetentionWarmDays }
            OracleHome           = if ($null -ne $loaded.OracleHome)           { $loaded.OracleHome }           else { $defaultConfig.OracleHome }
            DefaultAuthMode      = if ($null -ne $loaded.PSObject.Properties['DefaultAuthMode'])    { $loaded.DefaultAuthMode }    else { $defaultConfig.DefaultAuthMode }
            DefaultWalletAlias   = if ($null -ne $loaded.PSObject.Properties['DefaultWalletAlias']) { $loaded.DefaultWalletAlias } else { $defaultConfig.DefaultWalletAlias }
        }

        Write-Verbose "[Get-OracleBackupConfigStore] Configuration loaded from $configPath"
        return $merged
    }
    catch {
        throw "Failed to load OracleBackup configuration from '$configPath': $($PSItem.Exception.Message)"
    }
}
