#
# Module manifest for module 'OracleAdmin'
# Published name: TACE.OracleAdmin
#
# Copyright © TACE Data Management Inc.
#

@{
    # Module identity
    RootModule        = 'OracleAdmin.psm1'
    ModuleVersion     = '0.1.1'
    GUID              = '50e4f865-a551-4f83-beb1-329987147747'
    Author            = 'TACE Data Management Inc.'
    CompanyName       = 'TACE Data Management Inc.'
    Copyright         = 'Copyright © TACE Data Management Inc.'
    Description       = 'Oracle database administration utilities — environment management, instance discovery, and DBA tooling.'

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
            Tags         = @('Oracle', 'DBA', 'Automation', 'Environment', 'Administration')
            ProjectUri   = ''
            ReleaseNotes = 'v0.1.1 — Add Invoke-OraEnv wrapper and oraset/oraenv aliases; fix Set-OracleEnv output behavior and service status check.'
        }
    }
}
