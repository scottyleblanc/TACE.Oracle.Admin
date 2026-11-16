<#
.SECURITY
    Scope  : Invoke-CredentialScrub (private)
    Touches: Strings only. No process, file, network or environment access.

    Security assertions in this file:
    - The password in a user/password@service pattern is replaced (S1)
    - The function is not exported
#>

#Requires -Version 7.6

Describe 'Invoke-CredentialScrub' {

    BeforeAll {
        Remove-Module TACE.Oracle.Admin -Force -ErrorAction SilentlyContinue
        Import-Module (& (Join-Path $PSScriptRoot '..' 'Get-BuiltModulePath.ps1')) -Force
    }

    AfterAll {
        Remove-Module TACE.Oracle.Admin -Force -ErrorAction SilentlyContinue
    }

    Context 'Implementation' {

        It 'Invoke-CredentialScrub returns clean content unchanged' {
            InModuleScope TACE.Oracle.Admin {
                $clean = 'Recovery Manager: Release 19.0.0.0.0 - Production'
                $result = Invoke-CredentialScrub -Content $clean
                $result | Should -Be $clean
            }
        }

        It 'Invoke-CredentialScrub handles empty string without error' {
            InModuleScope TACE.Oracle.Admin {
                $result = Invoke-CredentialScrub -Content ''
                $result | Should -BeOfType [string]
                $result | Should -BeExactly ''
            }
        }
    }

    Context 'Security' {

        It 'Invoke-CredentialScrub scrubs credential fragment matching user/pass@service' -Tag 'SEC' {
            InModuleScope TACE.Oracle.Admin {
                $raw = 'CONNECT TARGET backup_user/S3cr3tP@ss!@ORCL_SVC; BACKUP DATABASE;'
                $scrubbed = Invoke-CredentialScrub -Content $raw
                $scrubbed | Should -Not -Match 'S3cr3tP@ss!'
                $scrubbed | Should -Match '\*\*\*SCRUBBED\*\*\*'
            }
        }

        It 'Invoke-CredentialScrub is not exported as a public command' {
            (Get-Module TACE.Oracle.Admin).ExportedCommands.Keys | Should -Not -Contain 'Invoke-CredentialScrub'
        }
    }
}
