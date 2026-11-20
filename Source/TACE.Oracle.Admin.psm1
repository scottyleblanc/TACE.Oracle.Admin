#Requires -Version 7.6
<#
.SYNOPSIS
    Oracle database administration utility module.

.DESCRIPTION
    TACE.Oracle.Admin provides PowerShell functions for Oracle database
    environment management and administration utilities on Windows and Linux.

    Functions are designed for interactive DBA use and automation alike.
    All public functions return a standard PSCustomObject { Success, Data, Message }.

.NOTES
    Copyright © TACE Data Management Inc.
    Published name : TACE.Oracle.Admin
    Internal name  : OracleAdmin
    Version        : 0.2.10
    Stage          : 1 — Foundation

    This file is the head of the built module. Build-Module.ps1 copies it to the top of
    Output\TACE.Oracle.Admin\<version>\TACE.Oracle.Admin.psm1 and appends every function
    from Source\Classes\, Source\Private\ and Source\Public\, in that order (rule C-28).
    Do not import it directly: build, then import the module under Output\.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region -- Module state

# [SEC] Test-only override for the config file path used by Get-OracleBackupConfigStore.
# Module-scoped, so only code running inside the module (tests via InModuleScope) can
# set it. Production always uses Config\OracleBackup.json in the module's version folder.
$script:ConfigPathOverride = $null

#endregion

#region -- Aliases

# Aliases are declared with an [Alias()] attribute on the function they target (rule
# C-30): oraset and oraenv are on Invoke-OraEnv. The build reads those attributes and
# writes AliasesToExport into the built manifest.

#endregion
