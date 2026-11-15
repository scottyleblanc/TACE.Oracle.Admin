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
        Justification = 'Private helper called inside the caller''s ShouldProcess gate. Whether it needs a gate of its own is decided by the inherited -WhatIf item in TODO.md (Stack 2).')]
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
    #   P2 Path exists on disk.
    #       Guard: the Test-Path check throws when it does not.
    #   P3 Path was created by this module immediately before the call.
    #       Limitation: the caller's duty. Nothing here checks who created the path.
    #
    # SECURITY INVARIANTS
    #   [SEC] S1 On Windows, inheritance is disabled and inherited rules are removed.
    #       Test: 'Inheritance is disabled on the directory after the call',
    #       'Inheritance is disabled on the file after the call'.
    #   [SEC] S2 On Windows, the current user and BUILTIN\Administrators are granted
    #       access, and Everyone and BUILTIN\Users are not.
    #       Test: 'Current user rule is present on directory',
    #       'BUILTIN\Administrators rule is present on directory',
    #       'No broad identity (Everyone / BUILTIN\Users) rules are present on directory'.
    #   [SEC] S3 Rules on a directory are inherited by what is created inside it. Rules on
    #       a file are not inheritable.
    #       Test: 'SEC-07: child file created inside a secured directory inherits the restrictive ACEs',
    #       'File ACEs use InheritanceFlags::None (files have no child objects)'.
    #   [SEC] S4 On a platform other than Windows nothing is changed.
    #       Limitation: permissions are left to the operating system.
    #
    # POST-CONDITIONS
    #   R1 Returns nothing.
    #       Type: OutputType void.
    #   T1 Every throw starts with 'Failed to apply restrictive ACL to' and names the path.
    #       Test: none yet.
    #
    # EXECUTION INVARIANTS
    #   L1 Permissions are changed without a ShouldProcess check of its own.
    #       Limitation: a private helper. The calling function decides.
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

        # Apply the ACL
        Set-Acl -Path $Path -AclObject $acl

        Write-Verbose "[Set-RestrictiveAcl] Restrictive ACL applied to: $Path"
    }
    catch {
        throw "Failed to apply restrictive ACL to '$Path': $($PSItem.Exception.Message)"
    }
}
