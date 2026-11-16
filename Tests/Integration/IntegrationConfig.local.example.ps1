#Requires -Version 7.6
<#
.SYNOPSIS
    Example of this machine's integration settings. Copy to IntegrationConfig.local.ps1.

.DESCRIPTION
    IntegrationConfig.local.ps1 is gitignored. It returns a hashtable whose keys replace
    the shared values in IntegrationConfig.ps1. Every value below is a placeholder.

    Create TestBackupDestination by hand before the first run; guard 5 refuses a folder
    that does not exist. Only use a host and database that may lose backups: the tests
    run DELETE OBSOLETE, which acts on the whole database.

.NOTES
    Copyright © TACE Data Management Inc.
    **Invocation:** Template — copied, not run. Its copy is called by IntegrationConfig.ps1.
#>
@{
    AllowedHosts          = @('MY-DEV-HOST')
    OracleHome            = 'C:\app\oracle\product\21c\dbhomeXE'
    TestDatabaseName      = 'XE'
    TestBackupDestination = 'C:\app\oracle\integration_test'
}
