#
# Module manifest for module 'OracleAdmin'
# Published name: TACE.OracleAdmin
#
# Copyright © TACE Data Management Inc.
#

@{
    # Module identity
    RootModule        = 'OracleAdmin.psm1'
    ModuleVersion     = '0.1.0'
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
    )

    # No cmdlets or aliases exported from the module itself
    CmdletsToExport   = @()
    AliasesToExport   = @()
    VariablesToExport = @()

    # Private data
    PrivateData       = @{
        PSData = @{
            Tags         = @('Oracle', 'DBA', 'Automation', 'Environment', 'Administration')
            ProjectUri   = ''
            ReleaseNotes = 'Stage 1 — Foundation: module scaffold, instance discovery, environment setup.'
        }
    }
}
