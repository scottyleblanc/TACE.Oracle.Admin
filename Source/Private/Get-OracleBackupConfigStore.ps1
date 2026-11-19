#Requires -Version 7.6
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
        OracleHome          : (empty — set it in the config file, or ORACLE_HOME is used)

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
    #   P1 The config file is Config\OracleBackup.json under the module folder, unless
    #       the module-scoped test override $script:ConfigPathOverride is set.
    #       Guard: the path resolution at the start of the body.
    #       Test: 'P1 reads Config\OracleBackup.json under the module folder when no override is set',
    #       'P1 reads the override path when one is set'.
    #
    # SECURITY INVARIANTS
    #   [SEC] S1 A config file created here is given restricted permissions straight
    #       after it is written.
    #       Guard: the Set-RestrictiveAcl call that follows the write.
    #       Test: 'S1, L1 creates the folder, file and ACL even when the caller runs under -WhatIf'.
    #   [SEC] S2 The config holds paths and defaults, never a credential.
    #       Limitation: nothing checks what the file contains.
    #   [SEC] S3 OracleHome read from the config is untrusted until checked.
    #       Limitation: the caller's duty, met by Assert-OracleEnvironment.
    #   [SEC] S4 No environment variable or caller input decides where the config is
    #       read from or created. Only the module-scoped test override can change the path.
    #       Test: 'S4 ORACLE_BACKUP_CONFIG_PATH does not change the config path'.
    #
    # POST-CONDITIONS
    #   R1 Returns an object with all eight settings. A setting missing from the file
    #       takes its default.
    #       Test: 'R1 a setting missing from the file takes its default'.
    #   R2 When the file does not exist it is written with the defaults, and the defaults
    #       are returned.
    #       Test: 'R2 writes the defaults to the override path when the file is absent'.
    #   T1 Every throw starts with 'Failed to load OracleBackup configuration from' and
    #       names the path.
    #       Test: 'T1 a file it cannot read throws with the prefix and the path'.
    #
    # EXECUTION INVARIANTS
    #   L1 The first call creates the folder, the file and its ACL even when the caller
    #       runs under -WhatIf: creating the default is part of reading the config, not a
    #       change being previewed. The writes pin -WhatIf:$false.
    #       Test: 'S1, L1 creates the folder, file and ACL even when the caller runs under -WhatIf'.
    #--------------------------------------------------------------

    # [SEC] S4 — fixed path under the module folder. Only the module-scoped test
    # override (set through InModuleScope) can change it; no environment variable can.
    $configPath = if (-not [string]::IsNullOrWhiteSpace($script:ConfigPathOverride)) {
        $script:ConfigPathOverride
    }
    else {
        # In the built module $PSScriptRoot is the version folder, which holds the .psm1.
        $resolved = Join-Path -Path $PSScriptRoot -ChildPath 'Config' -AdditionalChildPath 'OracleBackup.json'
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

            # Creating the default config is part of reading it, not a change a caller
            # previews: -WhatIf:$false keeps a caller's -WhatIf from skipping it (L1).
            $configDir = Split-Path $configPath -Parent
            if (-not (Test-Path $configDir)) {
                $null = New-Item -Path $configDir -ItemType Directory -Force -WhatIf:$false
            }

            $defaultConfig |
                ConvertTo-Json -Depth 5 |
                Set-Content -Path $configPath -Encoding UTF8 -WhatIf:$false

            # [SEC] Apply restrictive ACLs immediately after creation —
            # disable inheritance; grant current user and BUILTIN\Administrators only.
            Set-RestrictiveAcl -Path $configPath

            Write-Verbose "[Get-OracleBackupConfigStore] Default config written to $configPath"
            return $defaultConfig
        }

        $raw = Get-Content -Path $configPath -Raw -Encoding UTF8
        $loaded = $raw | ConvertFrom-Json

        # Merge with defaults: a setting missing from the file (or null in it) takes its
        # default (R1). Look each one up through PSObject.Properties — under StrictMode,
        # reading a missing property directly throws.
        $merged = [ordered]@{}
        foreach ($property in $defaultConfig.PSObject.Properties) {
            $fileValue = $loaded.PSObject.Properties[$property.Name]
            $merged[$property.Name] = if ($null -ne $fileValue -and $null -ne $fileValue.Value) {
                $fileValue.Value
            }
            else {
                $property.Value
            }
        }
        $merged = [PSCustomObject]$merged

        Write-Verbose "[Get-OracleBackupConfigStore] Configuration loaded from $configPath"
        return $merged
    }
    catch {
        $safeMessage = Invoke-CredentialScrub -Content $PSItem.Exception.Message
        throw "Failed to load OracleBackup configuration from '$configPath': $safeMessage"
    }
}
