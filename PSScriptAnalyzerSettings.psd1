@{
    # PSScriptAnalyzer settings for TACE.Oracle.Admin
    #
    # Rules excluded from analysis with documented rationale.

    ExcludeRules = @(

        # PS7 projects use UTF-8 without BOM (-Encoding UTF8 default).
        # PSSA fires this rule when non-ASCII characters (e.g. the copyright
        # symbol in file headers) appear without a BOM. This is a false positive
        # for PS7 — adding a BOM would violate the project encoding standard.
        'PSUseBOMForUnicodeEncodedFile'

        # PSAvoidUsingWriteHost is NOT excluded (rule C-31). The two interactive
        # functions, Set-OracleEnv and Invoke-OraEnv, carry a SuppressMessageAttribute
        # with the reason, so every other function is still checked.
    )
}
