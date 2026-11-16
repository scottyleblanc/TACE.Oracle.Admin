@{
    # PSScriptAnalyzer settings for TACE.Oracle.Admin (decision 25).
    #
    # Pinned to PSScriptAnalyzer 1.25.0 (PREREQUISITES.md). The editor reads this file
    # through .vscode/settings.json; the gate passes it with -Settings.
    #
    # Coverage is set by the caller, not here: Source\, Scripts\ and Tests\Lint\.
    # *.Tests.ps1 files are not analyzed: they build fake credentials on purpose and
    # Pester's mock style raises false positives.
    #
    # Every finding fails, Information included. An exception is a
    # SuppressMessageAttribute with a Justification at the narrowest scope that
    # covers it: the function, or the script for a console tool in Scripts\.

    Severity = @('Error', 'Warning', 'Information')

    # House rules that the built-in rules do not cover (decision 26), run alongside
    # the built-in rules. PSScriptAnalyzer resolves this path against the current
    # directory, not this file, so the analyzer is run from the repository root.
    CustomRulePath      = @('Tests/Lint/PSScriptAnalyzerRules/*.psm1')
    IncludeDefaultRules = $true

    ExcludeRules = @(

        # PS7 projects use UTF-8 without BOM (-Encoding UTF8 default).
        # PSSA fires this rule when non-ASCII characters (e.g. the copyright
        # symbol in file headers) appear without a BOM. This is a false positive
        # for PS7 — adding a BOM would violate the project encoding standard.
        'PSUseBOMForUnicodeEncodedFile'

        # PSAvoidUsingWriteHost is NOT excluded (rule C-31). The one interactive
        # function, Invoke-OraEnv, carries a SuppressMessageAttribute with the reason,
        # so every other function is still checked.
    )
}