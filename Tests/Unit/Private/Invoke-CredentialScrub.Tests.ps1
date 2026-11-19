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

    Context 'Parameter validation' {

        It 'P1 Content is a mandatory string that accepts an empty string' {
            $param = InModuleScope TACE.Oracle.Admin { (Get-Command Invoke-CredentialScrub).Parameters['Content'] }
            $param.ParameterType | Should -Be ([string])
            @($param.Attributes | Where-Object { $PSItem -is [System.Management.Automation.ParameterAttribute] -and $PSItem.Mandatory }) |
                Should -Not -BeNullOrEmpty
            @($param.Attributes | Where-Object { $PSItem -is [System.Management.Automation.AllowEmptyStringAttribute] }) |
                Should -Not -BeNullOrEmpty
        }
    }

    Context 'Implementation' {

        It 'R2 returns clean content unchanged' {
            InModuleScope TACE.Oracle.Admin {
                $clean = 'Recovery Manager: Release 19.0.0.0.0 - Production'
                $result = Invoke-CredentialScrub -Content $clean
                $result | Should -Be $clean
            }
        }

        It 'R1 handles empty string without error' {
            InModuleScope TACE.Oracle.Admin {
                $result = Invoke-CredentialScrub -Content ''
                $result | Should -BeOfType [string]
                $result | Should -BeExactly ''
            }
        }
    }

    Context 'Security' {

        It 'S1 scrubs credential fragment matching user/pass@service' -Tag 'SEC' {
            InModuleScope TACE.Oracle.Admin {
                $raw = 'CONNECT TARGET backup_user/S3cr3tP@ss!@ORCL_SVC; BACKUP DATABASE;'
                $scrubbed = Invoke-CredentialScrub -Content $raw
                # The password holds an @: no part of it may remain (escaped defect E4).
                $scrubbed | Should -BeExactly 'CONNECT TARGET backup_user/***SCRUBBED***@ORCL_SVC; BACKUP DATABASE;'
            }
        }

        It 'Invoke-CredentialScrub is not exported as a public command' {
            (Get-Module TACE.Oracle.Admin).ExportedCommands.Keys | Should -Not -Contain 'Invoke-CredentialScrub'
        }
    }
}
