#Requires -Version 7.6

# Static tier. Rule S-07: exception text is scrubbed before it is re-thrown or placed in
# Message. Every `.Exception.Message` read in Source\ must be an argument of
# Invoke-CredentialScrub. Reads the syntax tree only, so comments and help text never
# count. Exception text reached another way is left to review (see the helper).

BeforeDiscovery {
    $repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $script:sourceFiles = @(foreach ($folder in @('Public', 'Private')) {
            $dir = Join-Path -Path $repoRoot -ChildPath 'Source' -AdditionalChildPath $folder
            foreach ($file in @(Get-ChildItem -LiteralPath $dir -Filter '*.ps1' -File)) {
                @{ Path = (Join-Path -Path 'Source' -ChildPath $folder -AdditionalChildPath $file.Name) }
            }
        })
}

BeforeAll {
    $script:repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    . (Join-Path -Path $script:repoRoot -ChildPath 'Tests' -AdditionalChildPath 'Lint', 'Find-UnscrubbedExceptionText.ps1')
}

Describe 'Exception text is scrubbed' -Tag 'Static', 'SEC' {

    It 'found source files to check' -ForEach @(@{ Count = $script:sourceFiles.Count }) {
        $Count | Should -BeGreaterThan 0
    }

    It 'S-07: <Path> scrubs every exception message it reads' -ForEach $script:sourceFiles {
        $full   = Join-Path -Path $script:repoRoot -ChildPath $Path
        $tokens = $null
        $errors = $null
        $ast    = [System.Management.Automation.Language.Parser]::ParseFile($full, [ref]$tokens, [ref]$errors)
        $hits   = @(Find-UnscrubbedExceptionText -Ast $ast)
        ($hits -join "`n") | Should -BeNullOrEmpty -Because 'exception text can carry a connect string; pass it through Invoke-CredentialScrub first (S-07)'
    }
}
