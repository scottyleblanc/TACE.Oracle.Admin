#Requires -Version 7.6
<#
.SYNOPSIS
    Converts a SecureString to a plaintext string for use at an external process
    stdin boundary only.

.DESCRIPTION
    This is a private security helper. Plaintext must be extracted inline at the
    point of use — never assigned to a named variable that persists beyond the
    immediate call. This function must never be called from any context other than
    writing to an external process stdin stream.

    Callers are responsible for ensuring the returned string is used immediately
    and not stored, logged, or passed as a command-line argument.

.PARAMETER SecureString
    The SecureString to convert.

.OUTPUTS
    [string] — plaintext value. Treat as sensitive; use immediately and discard.

.NOTES

    [SEC] This function is private. It must never be exported or called from
    public function code except at the stdin write boundary of Invoke-RmanProcess.

    [SEC] The caller must never assign the return value to a named variable.
    Correct pattern:
        $writer.WriteLine((ConvertFrom-SecureStringToPlaintext -SecureString $pwd))

    Incorrect pattern (never do this):
        $plaintext = ConvertFrom-SecureStringToPlaintext -SecureString $pwd
        $writer.WriteLine($plaintext)

    [SEC] $ptr is pre-initialized to [IntPtr]::Zero before the try block (SEC-06).
    If SecureStringToGlobalAllocUnicode throws before assignment completes, $ptr
    remains [IntPtr]::Zero and the finally guard correctly skips ZeroFreeGlobalAllocUnicode.
    Without the pre-initialization, $ptr is undefined in the throw path and the
    guard may evaluate incorrectly (APSC-DV-000160).
#>
function ConvertFrom-SecureStringToPlaintext {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [SecureString]$SecureString
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    #--------------------------------------------------------------
    # INVARIANTS
    #
    # PRE-CONDITIONS
    #   P1 SecureString is a non-null SecureString.
    #       Type: Mandatory and the SecureString type.
    #
    # SECURITY INVARIANTS
    #   [SEC] S1 The return value is plaintext. The caller uses it at a stdin write and
    #       never stores it.
    #       Limitation: the caller's duty. See Invoke-RmanProcess S2.
    #   [SEC] S2 The unmanaged buffer is zeroed and freed on every path.
    #       Guard: the finally block.
    #   [SEC] S3 This is the only place in the module that turns a secure value into
    #       plaintext.
    #       Static: none yet.
    #   [SEC] S4 The function is not exported and cannot be called from outside the module.
    #       Test: 'Function is not exported as a public command',
    #       'Is not callable outside module scope'.
    #   [SEC] S5 A throw does not contain the plaintext.
    #       Test: 'Throw message does not contain the input plaintext when conversion fails'.
    #
    # POST-CONDITIONS
    #   R1 Returns the exact plaintext, including an empty string and special characters.
    #       Test: 'Returns the correct plaintext for a standard password',
    #       'Returns an empty string for an empty SecureString',
    #       'Handles special characters correctly'.
    #   T1 Every throw starts with 'Failed to convert SecureString:'.
    #       Test: 'SEC-06: Throws a clean "Failed to convert SecureString" error when conversion fails — not a pointer or memory error'.
    #--------------------------------------------------------------

    # [SEC-06] Pre-initialize to [IntPtr]::Zero so the finally guard is reliable
    # even when SecureStringToGlobalAllocUnicode throws before assignment completes.
    $ptr = [IntPtr]::Zero

    try {
        $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToGlobalAllocUnicode($SecureString)
        return [System.Runtime.InteropServices.Marshal]::PtrToStringUni($ptr)
    }
    catch {
        throw "Failed to convert SecureString: $($PSItem.Exception.Message)"
    }
    finally {
        # Always zero and free the unmanaged memory, even if an exception occurred.
        # Guard is reliable because $ptr is always a valid IntPtr (never undefined).
        if ($ptr -ne [IntPtr]::Zero) {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeGlobalAllocUnicode($ptr)
        }
    }
}
