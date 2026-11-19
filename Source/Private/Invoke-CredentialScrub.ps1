#Requires -Version 7.6
<#
.SYNOPSIS
    Scrubs potential credential fragments from a string.

.DESCRIPTION
    Private helper that sanitises text before it is stored, returned or logged:
    RMAN stdout and stderr (Invoke-RmanProcess), and the exception text every function
    re-throws or places in Message (rule S-07), which includes tnsping output in an
    Assert-OracleEnvironment error.

    One pattern is scrubbed: a connect string of the form user/password@service, whose
    password, up to the last @ in the token, is replaced with ***SCRUBBED***, so a
    password holding an @ is replaced whole. The user and service names are kept. The
    @service suffix is required, so dates (02/27), O/S labels and paths are not matched.

.PARAMETER Content
    The text to scrub. May be empty, which is returned unchanged.

.EXAMPLE
    $safeMessage = Invoke-CredentialScrub -Content $PSItem.Exception.Message

.OUTPUTS
    System.String. The scrubbed text.

.NOTES
    Copyright © TACE Data Management Inc.

    [SEC] This is a best-effort scrub — not a guarantee. The primary defence
    is never placing credentials in command-line arguments in the first place.

    TODO: [SEC] Expand scrub patterns as new credential formats are encountered
    during integration testing against real RMAN output.
#>
function Invoke-CredentialScrub {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Content
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    #--------------------------------------------------------------
    # INVARIANTS
    #
    # PRE-CONDITIONS
    #   P1 Content is a string, and may be empty.
    #       Type: Mandatory and AllowEmptyString.
    #       Test: 'P1 Content is a mandatory string that accepts an empty string'.
    #
    # SECURITY INVARIANTS
    #   [SEC] S1 The password in every user/password@service pattern is replaced with
    #       ***SCRUBBED***, whole, including any @ it holds. The user name and the
    #       service name are kept.
    #       Test: 'S1 scrubs credential fragment matching user/pass@service'.
    #   [SEC] S2 A credential in any other format passes through unchanged.
    #       Limitation: one pattern only. The main defence is that a credential is never
    #       placed where it could be echoed.
    #
    # POST-CONDITIONS
    #   R1 Empty content is returned unchanged.
    #       Test: 'R1 handles empty string without error'.
    #   R2 Content with no matching pattern is returned unchanged.
    #       Test: 'R2 returns clean content unchanged'.
    #--------------------------------------------------------------

    if ([string]::IsNullOrEmpty($Content)) { return $Content }

    # Scrub patterns: RMAN catalog connect strings (user/password@service)
    # Requires @service suffix to be present — avoids matching dates (02/27),
    # OS error labels (O/S), version strings, and Windows path separators.
    # [SEC] The password runs to the last @ in the token, so a password that holds an @
    # is replaced whole; the service name holds no @.
    $scrubbed = $Content -replace '(\w+)/(\S+)@([^@\s]+)', '$1/***SCRUBBED***@$3'

    return $scrubbed
}
