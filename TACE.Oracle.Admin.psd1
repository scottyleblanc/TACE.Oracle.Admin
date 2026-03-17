#
# Module manifest for module 'TACE.Oracle.Admin'
# Published name: TACE.Oracle.Admin
#
# Copyright © TACE Data Management Inc.
#

@{
    # Module identity
    RootModule        = 'TACE.Oracle.Admin.psm1'
    ModuleVersion     = '0.1.4'
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

    # Private data
    PrivateData       = @{
        PSData = @{
            Tags         = @('Oracle', 'DBA', 'Automation', 'Environment', 'Administration', 'Windows', 'Linux', 'OracleDB', 'PowerShell')
            ProjectUri   = 'https://github.com/scottyleblanc/OracleAdmin'
            LicenseUri   = 'https://github.com/scottyleblanc/OracleAdmin/blob/main/LICENSE'
            ReleaseNotes = 'v0.1.4 — Add multi-platform support: Linux discovery via /etc/oratab and ora_pmon process check; -Platform parameter on Get-OracleDatabaseList for testability; OracleHome and OracleBase derived on both platforms.'
        }
    }
}
