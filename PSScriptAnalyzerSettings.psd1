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

        # Write-Host is used intentionally in Set-OracleEnv and Invoke-OraEnv.
        # Both functions are explicitly interactive — they present menus and
        # confirm environment variable changes to the user at the terminal.
        # Write-Host is correct for this purpose; Write-Output would pollute
        # the pipeline and interfere with the return object contract.
        'PSAvoidUsingWriteHost'
    )
}
