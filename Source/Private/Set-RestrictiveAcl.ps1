#Requires -Version 7.6
<#
.SYNOPSIS
    Applies restrictive ACLs to a file or directory at creation time.

.DESCRIPTION
    Disables ACL inheritance and sets explicit access rules granting Full Control
    to the current user and BUILTIN\Administrators only. All other inherited entries
    are removed.

    For directories, InheritanceFlags is set to ContainerInherit | ObjectInherit so
    the restrictive ACEs propagate to all child files and subdirectories created
    inside the directory (e.g. RMAN backup pieces written after the ACL is applied).
    For files, InheritanceFlags is None — files have no child objects to inherit.

    This helper is called immediately after creating sensitive files or directories
    — specifically the module configuration file and backup destination directories.
    It must never be called on paths that should remain broadly accessible.

.PARAMETER Path
    The file or directory path to secure. Must exist on disk before calling.

.OUTPUTS
    None. Throws a terminating error if ACL application fails.

.NOTES

    [SEC] This function is private. It must only be called immediately after
    creating a sensitive file or directory — never on pre-existing paths whose
    ACLs were set by another process or administrator.

    [SEC] On non-Windows platforms this function is a no-op with a Verbose
    message. Filesystem permissions on non-Windows hosts must be managed via
    chmod/umask at the OS level.

    [SEC] InheritanceFlags::None on a directory protects only the directory object
    itself — RMAN-created backup files inside it do not inherit the ACE. Using
    ContainerInherit | ObjectInherit for directories ensures child objects are
    protected (SEC-07, STIG V-270578).
#>
function Set-RestrictiveAcl {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Private helper that secures a path the module has just created. It is never previewed: Set-Acl pins -WhatIf:$false (invariant L1).')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    #--------------------------------------------------------------
    # INVARIANTS
    #
    # PRE-CONDITIONS
    #   P1 Path is a non-empty string.
    #       Type: Mandatory and ValidateNotNullOrEmpty.
    #       Test: 'P1 Path parameter is mandatory',
    #       'P1 Path parameter has ValidateNotNullOrEmpty'.
    #   P2 Path exists on disk.
    #       Guard: the Test-Path check throws when it does not.
    #       Test: 'P2 throws when Path does not exist on disk'.
    #   P3 Path was created by this module immediately before the call.
    #       Limitation: the caller's duty. Nothing here checks who created the path.
    #
    # SECURITY INVARIANTS
    #   [SEC] S1 On Windows, inheritance is disabled and inherited rules are removed.
    #       Test: 'S1 inheritance is disabled on the directory after the call',
    #       'S1 inheritance is disabled on the file after the call'.
    #   [SEC] S2 On Windows, the current user and BUILTIN\Administrators are granted
    #       access, and Everyone and BUILTIN\Users are not.
    #       Test: 'S2 current user rule is present on directory',
    #       'S2 BUILTIN\Administrators rule is present on directory',
    #       'S2 no broad identity (Everyone / BUILTIN\Users) rules are present on directory'.
    #   [SEC] S3 Rules on a directory are inherited by what is created inside it. Rules on
    #       a file are not inheritable.
    #       Test: 'S3 directory ACEs use ContainerInherit | ObjectInherit (SEC-07)',
    #       'S3 child file created inside a secured directory inherits the restrictive ACEs (SEC-07)',
    #       'S3 file ACEs use InheritanceFlags::None (files have no child objects)'.
    #   [SEC] S4 On a platform other than Windows nothing is changed.
    #       Limitation: permissions are left to the operating system.
    #
    # POST-CONDITIONS
    #   R1 Returns nothing.
    #       Type: OutputType void.
    #       Test: 'R1 returns nothing'.
    #   T1 Every throw starts with 'Failed to apply restrictive ACL to' and names the path.
    #       Test: 'T1 a failure throws with the prefix and the path'.
    #
    # EXECUTION INVARIANTS
    #   L1 Permissions are changed without a ShouldProcess check of its own, and a
    #       caller's -WhatIf does not skip them: Set-Acl pins -WhatIf:$false. It only
    #       secures a path the module has just created, so skipping it would leave that
    #       path open or make the caller fail.
    #       Test: 'L1 applies the ACL even when the caller runs under -WhatIf'.
    #--------------------------------------------------------------

    try {
        if (-not (Test-Path -Path $Path)) {
            throw "Path does not exist: '$Path'"
        }

        # Non-Windows: ACL enforcement is OS-managed; log and return
        if (-not $IsWindows) {
            Write-Verbose "[Set-RestrictiveAcl] Non-Windows platform — ACL enforcement skipped for: $Path"
            return
        }

        $item = Get-Item -Path $Path

        # Get current ACL object
        $acl = Get-Acl -Path $Path

        # Disable inheritance and remove all inherited rules
        # $false = do not preserve inherited rules as explicit rules
        $acl.SetAccessRuleProtection($true, $false)

        # [SEC-07] Use ContainerInherit | ObjectInherit for directories so child files
        # and subdirectories created by RMAN inherit the restrictive ACEs. Files have no
        # child objects so InheritanceFlags::None is correct for them (STIG V-270578).
        $inheritanceFlags = if ($item.PSIsContainer) {
            [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
            [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
        } else {
            [System.Security.AccessControl.InheritanceFlags]::None
        }

        # Grant Full Control to current user
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $userRule = [System.Security.AccessControl.FileSystemAccessRule]::new(
            $currentUser,
            [System.Security.AccessControl.FileSystemRights]::FullControl,
            $inheritanceFlags,
            [System.Security.AccessControl.PropagationFlags]::None,
            [System.Security.AccessControl.AccessControlType]::Allow
        )
        $acl.AddAccessRule($userRule)

        # Grant Full Control to BUILTIN\Administrators
        $adminRule = [System.Security.AccessControl.FileSystemAccessRule]::new(
            'BUILTIN\Administrators',
            [System.Security.AccessControl.FileSystemRights]::FullControl,
            $inheritanceFlags,
            [System.Security.AccessControl.PropagationFlags]::None,
            [System.Security.AccessControl.AccessControlType]::Allow
        )
        $acl.AddAccessRule($adminRule)

        # Apply the ACL. -WhatIf:$false: securing a path the module has just created is
        # never skipped by a caller's -WhatIf (L1).
        Set-Acl -Path $Path -AclObject $acl -WhatIf:$false

        Write-Verbose "[Set-RestrictiveAcl] Restrictive ACL applied to: $Path"
    }
    catch {
        $safeMessage = Invoke-CredentialScrub -Content $PSItem.Exception.Message
        throw "Failed to apply restrictive ACL to '$Path': $safeMessage"
    }
}
