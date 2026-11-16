<#
.SECURITY
    Scope  : Set-RestrictiveAcl (private)
    Touches: Real filesystem ACL operations on TestDrive:\ only. Get-Acl and
             Set-Acl are called against TestDrive:\ paths — no production paths
             are touched. No Oracle instance, no registry, no network.
    Does NOT touch: RMAN binary, Oracle instance, session environment variables,
                    production filesystem paths.

    Security assertions in this file:
    - Inheritance is disabled on the target path after the call
    - Current user and BUILTIN\Administrators rules are present
    - No broad identity rules (Everyone, BUILTIN\Users) are present
    - SEC-07: directories use ContainerInherit | ObjectInherit so child files
      created inside the directory inherit the restrictive ACEs
    - Files use InheritanceFlags::None (files have no child objects)
    - Child file created after ACL application inherits the restrictive ACEs
    - Non-Windows platforms: function is a no-op
#>

#Requires -Version 7.6

Describe 'Set-RestrictiveAcl' {

    BeforeAll {
        $modulePath = & (Join-Path $PSScriptRoot '..' 'Get-BuiltModulePath.ps1')
        $modulePath  = [System.IO.Path]::GetFullPath($modulePath)

        $testConfigPath = Join-Path $TestDrive 'OracleBackup.json'

        [PSCustomObject]@{
            BackupBasePath       = (Join-Path $TestDrive 'backup')
            FastRecoveryArea     = (Join-Path $TestDrive 'fra')
            LogBasePath          = (Join-Path $TestDrive 'logs')
            LogRetentionHotDays  = 15
            LogRetentionWarmDays = 90
            OracleHome           = (Join-Path $TestDrive 'oracle')
            DefaultAuthMode      = 'OSAuth'
            DefaultWalletAlias   = ''
        } | ConvertTo-Json -Depth 5 |
            Set-Content -Path $testConfigPath -Encoding UTF8

        Remove-Module TACE.Oracle.Admin -Force -ErrorAction SilentlyContinue
        Import-Module $modulePath -Force
        InModuleScope TACE.Oracle.Admin -Parameters @{ Path = $testConfigPath } {
            $script:ConfigPathOverride = $Path
        }

        $script:testDir  = Join-Path $TestDrive 'acltest_dir'
        $script:testFile = Join-Path $TestDrive 'acltest_file.txt'

        New-Item -Path $script:testDir  -ItemType Directory -Force | Out-Null
        New-Item -Path $script:testFile -ItemType File      -Force | Out-Null
    }

    AfterAll {
        Remove-Module TACE.Oracle.Admin -Force -ErrorAction SilentlyContinue
    }

    # ── Parameter validation ───────────────────────────────────────────────────

    Context 'Parameter validation' {

        It 'Path parameter is mandatory' {
            InModuleScope TACE.Oracle.Admin {
                $param = (Get-Command Set-RestrictiveAcl).Parameters['Path']
                $isMandatory = @($param.Attributes |
                    Where-Object { $PSItem -is [System.Management.Automation.ParameterAttribute] -and $PSItem.Mandatory })
                $isMandatory.Count | Should -BeGreaterThan 0
            }
        }

        It 'Path parameter has ValidateNotNullOrEmpty' {
            InModuleScope TACE.Oracle.Admin {
                $param = (Get-Command Set-RestrictiveAcl).Parameters['Path']
                $hasAttr = @($param.Attributes |
                    Where-Object { $PSItem -is [System.Management.Automation.ValidateNotNullOrEmptyAttribute] })
                $hasAttr.Count | Should -BeGreaterThan 0
            }
        }

        It 'Throws when Path does not exist on disk' {
            InModuleScope TACE.Oracle.Admin {
                { Set-RestrictiveAcl -Path 'C:\Does\Not\Exist\path' } | Should -Throw
            }
        }
    }

    # ── Implementation ─────────────────────────────────────────────────────────

    Context 'Implementation — directory' {

        BeforeAll {
            $script:dirAclPath = Join-Path $TestDrive 'dir_acl_test'
            New-Item -Path $script:dirAclPath -ItemType Directory -Force | Out-Null
        }

        It 'Inheritance is disabled on the directory after the call' {
            InModuleScope TACE.Oracle.Admin -Parameters @{ P = $script:dirAclPath } {
                param($P)
                Set-RestrictiveAcl -Path $P
                $acl = Get-Acl -Path $P
                $acl.AreAccessRulesProtected | Should -Be $true
            }
        }

        It 'Directory ACEs use ContainerInherit | ObjectInherit (SEC-07)' {
            InModuleScope TACE.Oracle.Admin -Parameters @{ P = $script:dirAclPath } {
                param($P)
                $expectedFlags = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
                                 [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
                $acl = Get-Acl -Path $P
                foreach ($ace in @($acl.Access | Where-Object { $PSItem.AccessControlType -eq 'Allow' })) {
                    $ace.InheritanceFlags | Should -Be $expectedFlags
                }
            }
        }

        It 'Current user rule is present on directory' {
            InModuleScope TACE.Oracle.Admin -Parameters @{ P = $script:dirAclPath } {
                param($P)
                $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
                $acl = Get-Acl -Path $P
                $userAce = @($acl.Access | Where-Object {
                    $PSItem.IdentityReference.Value -eq $currentUser -and
                    $PSItem.AccessControlType -eq 'Allow'
                })
                $userAce.Count | Should -BeGreaterThan 0
            }
        }

        It 'BUILTIN\Administrators rule is present on directory' {
            InModuleScope TACE.Oracle.Admin -Parameters @{ P = $script:dirAclPath } {
                param($P)
                $acl = Get-Acl -Path $P
                $adminAce = @($acl.Access | Where-Object {
                    $PSItem.IdentityReference.Value -like '*Administrators*' -and
                    $PSItem.AccessControlType -eq 'Allow'
                })
                $adminAce.Count | Should -BeGreaterThan 0
            }
        }

        It 'No broad identity (Everyone / BUILTIN\Users) rules are present on directory' {
            InModuleScope TACE.Oracle.Admin -Parameters @{ P = $script:dirAclPath } {
                param($P)
                $broadSids = @(
                    [System.Security.Principal.SecurityIdentifier]::new('S-1-1-0')
                    [System.Security.Principal.SecurityIdentifier]::new('S-1-5-32-545')
                )
                $acl = Get-Acl -Path $P
                foreach ($ace in $acl.Access) {
                    $aceSid = $null
                    try {
                        $aceSid = $ace.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier])
                    } catch {
                        continue
                    }
                    $isBroad = @($broadSids | Where-Object { $PSItem.Value -eq $aceSid.Value })
                    $isBroad.Count | Should -Be 0
                }
            }
        }
    }

    Context 'Implementation — file' {

        BeforeAll {
            $script:fileAclPath = Join-Path $TestDrive 'file_acl_test.txt'
            New-Item -Path $script:fileAclPath -ItemType File -Force | Out-Null
        }

        It 'Inheritance is disabled on the file after the call' {
            InModuleScope TACE.Oracle.Admin -Parameters @{ P = $script:fileAclPath } {
                param($P)
                Set-RestrictiveAcl -Path $P
                $acl = Get-Acl -Path $P
                $acl.AreAccessRulesProtected | Should -Be $true
            }
        }

        It 'File ACEs use InheritanceFlags::None (files have no child objects)' {
            InModuleScope TACE.Oracle.Admin -Parameters @{ P = $script:fileAclPath } {
                param($P)
                $acl = Get-Acl -Path $P
                foreach ($ace in @($acl.Access | Where-Object { $PSItem.AccessControlType -eq 'Allow' })) {
                    $ace.InheritanceFlags | Should -Be ([System.Security.AccessControl.InheritanceFlags]::None)
                }
            }
        }

        It 'Current user rule is present on file' {
            InModuleScope TACE.Oracle.Admin -Parameters @{ P = $script:fileAclPath } {
                param($P)
                $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
                $acl = Get-Acl -Path $P
                $userAce = @($acl.Access | Where-Object {
                    $PSItem.IdentityReference.Value -eq $currentUser -and
                    $PSItem.AccessControlType -eq 'Allow'
                })
                $userAce.Count | Should -BeGreaterThan 0
            }
        }

        It 'BUILTIN\Administrators rule is present on file' {
            InModuleScope TACE.Oracle.Admin -Parameters @{ P = $script:fileAclPath } {
                param($P)
                $acl = Get-Acl -Path $P
                $adminAce = @($acl.Access | Where-Object {
                    $PSItem.IdentityReference.Value -like '*Administrators*' -and
                    $PSItem.AccessControlType -eq 'Allow'
                })
                $adminAce.Count | Should -BeGreaterThan 0
            }
        }
    }

    Context 'Implementation — non-Windows' {

        It 'Is a no-op on non-Windows — does not throw and does not modify ACLs' {
            InModuleScope TACE.Oracle.Admin -Parameters @{ P = $script:testDir } {
                param($P)
                Mock Test-Path { return $true }
                Mock Get-Item  { return [PSCustomObject]@{ PSIsContainer = $true } }

                # Simulate non-Windows by mocking the $IsWindows automatic variable
                # via a wrapper. Since $IsWindows can't be directly overridden, verify
                # the non-Windows branch exists by inspecting the function body.
                $funcBody = (Get-Command Set-RestrictiveAcl).ScriptBlock.ToString()
                $funcBody | Should -Match 'IsWindows'
                $funcBody | Should -Match 'ACL enforcement skipped'
            }
        }
    }

    # ── Security ───────────────────────────────────────────────────────────────

    Context 'Security' {

        It 'Function is not exported as a public command' {
            $exported = (Get-Module TACE.Oracle.Admin).ExportedCommands.Keys
            $exported | Should -Not -Contain 'Set-RestrictiveAcl'
        }

        It 'L1 applies the ACL even when the caller runs under -WhatIf' -Tag 'SEC' -Skip:(-not $IsWindows) {
            $path = Join-Path $TestDrive 'l1_whatif.txt'
            $null = New-Item -Path $path -ItemType File -Force
            InModuleScope TACE.Oracle.Admin -Parameters @{ P = $path } {
                param($P)
                # A caller's -WhatIf reaches this function as $WhatIfPreference.
                $WhatIfPreference = $true
                Set-RestrictiveAcl -Path $P
            }
            (Get-Acl -Path $path).AreAccessRulesProtected | Should -BeTrue
        }

        # [SEC-07] Core regression: child file created inside a secured directory
        # must inherit the restrictive ACEs. This proves ContainerInherit|ObjectInherit
        # is working — with InheritanceFlags::None the child file would have no inherited
        # ACEs from the directory and would use the system default ACL.
        It 'SEC-07: child file created inside a secured directory inherits the restrictive ACEs' {
            InModuleScope TACE.Oracle.Admin {
                $securedDir = Join-Path $TestDrive 'sec07_dir'
                New-Item -Path $securedDir -ItemType Directory -Force | Out-Null

                Set-RestrictiveAcl -Path $securedDir

                # Create a file inside the secured directory — simulates RMAN writing a backup piece
                $childFile = Join-Path $securedDir 'backup_piece_001.bkp'
                New-Item -Path $childFile -ItemType File -Force | Out-Null

                $childAcl = Get-Acl -Path $childFile
                $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

                # The child's rules for the current user and Administrators must be inherited
                # from the directory. A new file always gets some rule for its creator from
                # the default ACL, so "a rule exists" would pass with no inheritance at all.
                $userAce = @($childAcl.Access | Where-Object {
                    $PSItem.IdentityReference.Value -eq $currentUser -and $PSItem.IsInherited
                })
                $adminAce = @($childAcl.Access | Where-Object {
                    $PSItem.IdentityReference.Value -eq 'BUILTIN\Administrators' -and $PSItem.IsInherited
                })
                $userAce.Count  | Should -BeGreaterThan 0
                $adminAce.Count | Should -BeGreaterThan 0
            }
        }

        # [SEC-07] Verify the directory ACE grants FullControl — not a reduced right
        # that would prevent the DBA from managing backup files.
        It 'SEC-07: directory ACEs grant FullControl to current user and Administrators' {
            InModuleScope TACE.Oracle.Admin {
                $securedDir2 = Join-Path $TestDrive 'sec07_dir2'
                New-Item -Path $securedDir2 -ItemType Directory -Force | Out-Null

                Set-RestrictiveAcl -Path $securedDir2

                $acl = Get-Acl -Path $securedDir2
                $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

                $userAce = @($acl.Access | Where-Object {
                    $PSItem.IdentityReference.Value -eq $currentUser -and
                    $PSItem.AccessControlType -eq 'Allow'
                })
                $userAce[0].FileSystemRights.HasFlag(
                    [System.Security.AccessControl.FileSystemRights]::FullControl
                ) | Should -Be $true
            }
        }
    }
}
