#
# Module manifest for module 'TACE.Oracle.Admin'
# Published name: TACE.Oracle.Admin
#
# Copyright © TACE Data Management Inc.
#

@{
    # Module identity
    RootModule        = 'TACE.Oracle.Admin.psm1'
    ModuleVersion     = '0.2.6'
    GUID              = '50e4f865-a551-4f83-beb1-329987147747'
    Author            = 'TACE Data Management Inc.'
    CompanyName       = 'TACE Data Management Inc.'
    Copyright         = 'Copyright © TACE Data Management Inc.'
    Description       = 'PowerShell 7.6+ module for Oracle DBA environment management. Discovers Oracle instances on Windows (via WMI) and Linux (via /etc/oratab), sets ORACLE_SID, ORACLE_HOME, and ORACLE_BASE for the current session, and provides interactive and scripted DBA tooling.'

    # Requirements
    PowerShellVersion = '7.6'

    # FunctionsToExport, AliasesToExport and FileList are not kept here. The build
    # (Scripts\Build-Module.ps1) generates them into the built manifest: functions from
    # the file names in Source\Public\ (rule C-29), aliases from the [Alias()] attributes
    # on those functions (rule C-30), and the file list from what it writes to Output\.
    # The build fails if any of the three is added back here.

    # No cmdlets or variables exported from the module itself
    CmdletsToExport   = @()
    VariablesToExport = @()

    # Private data
    PrivateData       = @{
        PSData = @{
            Tags         = @('Oracle', 'DBA', 'Automation', 'Environment', 'Administration', 'Windows', 'Linux', 'OracleDB', 'PowerShell', 'oraset', 'oraenv')
            ProjectUri   = 'https://github.com/scottyleblanc/TACE.Oracle.Admin'
            LicenseUri   = 'https://github.com/scottyleblanc/TACE.Oracle.Admin/blob/master/LICENSE'
            ReleaseNotes = 'v0.2.6 — AI Development Stack, Stack 6 (independent review): every pull request carries a second-model review of its own commits, run in a confined session, with each finding answered, and the gate fails a pull request whose review is missing, stale or unanswered; a human checklist follows in the pull request template. No change to module behaviour. Not published to PSGallery.'
        }
    }
}
