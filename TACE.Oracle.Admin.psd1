#
# Module manifest for module 'TACE.Oracle.Admin'
# Published name: TACE.Oracle.Admin
#
# Copyright © TACE Data Management Inc.
#

@{
    # Module identity
    RootModule        = 'TACE.Oracle.Admin.psm1'
    ModuleVersion     = '0.1.5'
    GUID              = '50e4f865-a551-4f83-beb1-329987147747'
    Author            = 'TACE Data Management Inc.'
    CompanyName       = 'TACE Data Management Inc.'
    Copyright         = 'Copyright © TACE Data Management Inc.'
    Description       = 'PowerShell Core 7+ module for Oracle DBA environment management. Discovers Oracle instances on Windows (via WMI) and Linux (via /etc/oratab), sets ORACLE_SID, ORACLE_HOME, and ORACLE_BASE for the current session, and provides interactive and scripted DBA tooling.'

    # Requirements
    PowerShellVersion = '7.0'

    # Exported functions
    FunctionsToExport = @(
        'Get-OracleDatabaseList'
        'Set-OracleEnv'
        'Invoke-OraEnv'
    )

    # No cmdlets exported from the module itself
    CmdletsToExport   = @()
    AliasesToExport   = @('oraset', 'oraenv')
    VariablesToExport = @()

    # Explicit file list — only these files are included in the published package.
    # Dev artifacts (.git, .claude, Tests, Docs, scripts) are excluded by omission.
    FileList          = @(
        'TACE.Oracle.Admin.psd1'
        'TACE.Oracle.Admin.psm1'
        'PSScriptAnalyzerSettings.psd1'
        'README.md'
        'LICENSE'
        'Public\Get-OracleDatabaseList.ps1'
        'Public\Set-OracleEnv.ps1'
        'Private\Invoke-OraEnv.ps1'
    )

    # Private data
    PrivateData       = @{
        PSData = @{
            Tags         = @('Oracle', 'DBA', 'Automation', 'Environment', 'Administration', 'Windows', 'Linux', 'OracleDB', 'PowerShell')
            ProjectUri   = 'https://github.com/scottyleblanc/OracleAdmin'
            LicenseUri   = 'https://github.com/scottyleblanc/OracleAdmin/blob/main/LICENSE'
            ReleaseNotes = 'v0.1.5 — Set-OracleEnv now only prints ORACLE_HOME and ORACLE_BASE when -Verbose is specified; ORACLE_SID is always printed. Invoke-OraEnv passes -Verbose through so oraset -v shows all three env vars.'
        }
    }
}
