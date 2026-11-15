#Requires -Version 7.6
<#
.SYNOPSIS
    Checks the INVARIANTS block of every function and builds the invariant index.

.DESCRIPTION
    Reads every .ps1 file under Source\Public\ and Source\Private\, finds each function, and parses
    the '# INVARIANTS' comment block in its body against Docs\standards\invariants.md.

    It reports:
      - a function with no block (rule I-01)
      - an entry whose prefix does not belong to its section, or a duplicate identifier
        within a function (rule I-03)
      - an entry with no enforcement line (rule I-05)
      - a security entry without the [SEC] tag (rule I-06)
      - a line inside a block that it cannot read

    It reads source text only. It does not import the module or run any function.

    With -IndexPath it also writes the index: one line per invariant, with what
    enforces it and whether that is in place.

.PARAMETER RepoRoot
    The repository root. Defaults to two levels above this script's folder (Tests\Lint\).

.PARAMETER IndexPath
    Where to write the index. Nothing is written when this is omitted.

.OUTPUTS
    [PSCustomObject] with Success, Data and Message. Success is false when any function
    has no block or any entry is malformed. Data.IndexMarkdown holds the index text
    whether or not it was written.

.EXAMPLE
    .\Tests\Lint\Invoke-InvariantLint.ps1

    Checks every block and returns the result.

.EXAMPLE
    .\Tests\Lint\Invoke-InvariantLint.ps1 -IndexPath .\Docs\standards\invariants-index.md

    Checks every block and regenerates the index.

.NOTES
    Copyright © TACE Data Management Inc.
    **Invocation:** Standalone — safe to run with `pwsh -File`; also called by
    Tests\Static\InvariantConformance.Tests.ps1. Part of the static tier: fast, and safe
    to run on every change.
#>
[CmdletBinding(SupportsShouldProcess)]
[OutputType([PSCustomObject])]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$RepoRoot = (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent),

    [Parameter()]
    [ValidateNotNull()]
    [string]$IndexPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    # Which identifier prefixes each section may hold (invariants.md, Sections).
    $sectionPrefixes = [ordered]@{
        'PRE-CONDITIONS'       = @('P')
        'SECURITY INVARIANTS'  = @('S')
        'POST-CONDITIONS'      = @('R', 'T')
        'EXECUTION INVARIANTS' = @('L')
    }
    $entryPattern   = '^(?<sec>\[SEC\]\s+)?(?<prefix>[PSRTL])(?<number>\d+)\s+(?<text>.+)$'
    $keywordPattern = '^(?<keyword>Type|Guard|Test|Static|Limitation):\s*(?<note>.*)$'

    $resolvedRoot = (Resolve-Path -LiteralPath $RepoRoot).ProviderPath

    $files = @(
        foreach ($folder in @('Public', 'Private')) {
            $folderPath = Join-Path -Path $resolvedRoot -ChildPath 'Source' -AdditionalChildPath $folder
            Get-ChildItem -LiteralPath $folderPath -Filter '*.ps1' -File
        }
    )
    $files = @($files | Sort-Object -Property FullName)

    $catalog       = [System.Collections.Generic.List[PSCustomObject]]::new()
    $defects       = [System.Collections.Generic.List[PSCustomObject]]::new()
    $missingBlock  = [System.Collections.Generic.List[string]]::new()
    $functionCount = 0

    foreach ($file in $files) {
        $relative = [System.IO.Path]::GetRelativePath($resolvedRoot, $file.FullName) -replace '\\', '/'
        $lines    = @(Get-Content -LiteralPath $file.FullName)

        $tokens      = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
        $functions = @($ast.FindAll(
                { param([System.Management.Automation.Language.Ast]$node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] },
                $false))

        foreach ($function in $functions) {
            $functionCount++
            $functionName = $function.Name
            $firstLine    = $function.Extent.StartLineNumber
            $lastLine     = $function.Extent.EndLineNumber

            # Find the block header inside this function.
            $headerLine = 0
            for ($lineNumber = $firstLine; $lineNumber -le $lastLine; $lineNumber++) {
                if ($lines[$lineNumber - 1] -match '^\s*#\s*INVARIANTS\s*$') {
                    $headerLine = $lineNumber
                    break
                }
            }

            if ($headerLine -eq 0) {
                $missingBlock.Add("${relative}::$functionName")
                continue
            }

            $section = ''
            $current = $null
            $seenIds = [System.Collections.Generic.HashSet[string]]::new()
            $entries = [System.Collections.Generic.List[hashtable]]::new()

            for ($lineNumber = $headerLine + 1; $lineNumber -le $lastLine; $lineNumber++) {
                $line = $lines[$lineNumber - 1]

                # The block ends at the first line that is not a comment.
                if ($line -notmatch '^\s*#') { break }

                $rest    = $line -replace '^\s*#', ''
                $trimmed = $rest.Trim()
                $indent  = $rest.Length - $rest.TrimStart().Length

                if ($trimmed -eq '' -or $trimmed -match '^-+$') { continue }

                if ($sectionPrefixes.Contains($trimmed)) {
                    $section = $trimmed
                    $current = $null
                    continue
                }

                # An entry line is indented three spaces after the '#'.
                if ($indent -eq 3 -and $trimmed -match $entryPattern) {
                    $id = "$($Matches['prefix'])$($Matches['number'])"
                    $current = @{
                        Id        = $id
                        Prefix    = $Matches['prefix']
                        Sec       = -not [string]::IsNullOrEmpty($Matches['sec'])
                        Section   = $section
                        Statement = $Matches['text']
                        Keyword   = ''
                        Note      = ''
                        Line      = $lineNumber
                    }
                    $entries.Add($current)

                    if (-not $seenIds.Add($id)) {
                        $defects.Add([PSCustomObject]@{
                                File = $relative; Function = $functionName; Line = $lineNumber; Id = $id
                                Reason = 'Identifier is used more than once in this function.'
                            })
                    }
                    continue
                }

                # Anything deeper belongs to the current entry.
                if ($indent -ge 7 -and $null -ne $current) {
                    if ($current.Keyword -eq '' -and $trimmed -match $keywordPattern) {
                        $current.Keyword = $Matches['keyword']
                        $current.Note    = $Matches['note']
                    }
                    elseif ($current.Keyword -eq '') {
                        $current.Statement = "$($current.Statement) $trimmed"
                    }
                    else {
                        $current.Note = "$($current.Note) $trimmed"
                    }
                    continue
                }

                $defects.Add([PSCustomObject]@{
                        File = $relative; Function = $functionName; Line = $lineNumber; Id = ''
                        Reason = 'Line in the block is not a section heading, an entry or a continuation.'
                    })
            }

            if ($entries.Count -eq 0) {
                $defects.Add([PSCustomObject]@{
                        File = $relative; Function = $functionName; Line = $headerLine; Id = ''
                        Reason = 'Block has no entries.'
                    })
            }

            foreach ($entry in $entries) {
                $reasons = [System.Collections.Generic.List[string]]::new()

                if ($entry.Section -eq '') {
                    $reasons.Add('Entry appears before any section heading.')
                }
                elseif ($sectionPrefixes[$entry.Section] -notcontains $entry.Prefix) {
                    $reasons.Add("Prefix '$($entry.Prefix)' does not belong under '$($entry.Section)'.")
                }
                if ($entry.Prefix -eq 'S' -and -not $entry.Sec) {
                    $reasons.Add('Security entry has no [SEC] tag.')
                }
                if ($entry.Keyword -eq '') {
                    $reasons.Add('Entry has no enforcement line (Type, Guard, Test, Static or Limitation).')
                }

                foreach ($reason in $reasons) {
                    $defects.Add([PSCustomObject]@{
                            File = $relative; Function = $functionName; Line = $entry.Line; Id = $entry.Id
                            Reason = $reason
                        })
                }

                $state = switch ($entry.Keyword) {
                    'Limitation' { 'Accepted' }
                    'Type'       { 'Enforced' }
                    'Guard'      { 'Enforced' }
                    ''           { 'Unknown' }
                    default      { if ($entry.Note -match '^none yet') { 'Unproven' } else { 'Enforced' } }
                }

                $catalog.Add([PSCustomObject]@{
                        File      = $relative
                        Function  = $functionName
                        Id        = $entry.Id
                        Sec       = $entry.Sec
                        Section   = $entry.Section
                        Statement = $entry.Statement
                        Keyword   = $entry.Keyword
                        Note      = $entry.Note
                        State     = $state
                        Line      = $entry.Line
                    })
            }
        }
    }

    # --- Check that every cited test exists (rule I-09) --------------------------------

    # A cited test must be in the test file named for the source file, in the Tests\Unit\
    # folder that mirrors its source folder. Test titles are not unique across files, so a
    # match anywhere else would prove nothing.
    $testsPath    = Join-Path -Path $resolvedRoot -ChildPath 'Tests' -AdditionalChildPath 'Unit'
    $titlesByFile = @{}

    foreach ($item in $catalog) {
        if ($item.Keyword -ne 'Test' -or $item.State -ne 'Enforced') { continue }

        $sourceName   = [System.IO.Path]::GetFileNameWithoutExtension($item.File)
        $sourceFolder = Split-Path -Path (Split-Path -Path $item.File -Parent) -Leaf
        $testKey      = "$sourceFolder/$sourceName"

        if (-not $titlesByFile.ContainsKey($testKey)) {
            $titles   = [System.Collections.Generic.HashSet[string]]::new()
            $testFile = Join-Path -Path $testsPath -ChildPath $sourceFolder -AdditionalChildPath "$sourceName.Tests.ps1"
            if (Test-Path -LiteralPath $testFile) {
                $testText = Get-Content -LiteralPath $testFile -Raw
                $found    = [regex]::Matches($testText, '(?m)^\s*It\s+([''"])(?<title>.+?)\1')
                foreach ($match in $found) {
                    $null = $titles.Add($match.Groups['title'].Value)
                }
            }
            $titlesByFile[$testKey] = $titles
        }
        $testTitles = $titlesByFile[$testKey]

        $cited = @([regex]::Matches($item.Note, "'(?<title>[^']+)'") | ForEach-Object { $PSItem.Groups['title'].Value })

        if ($cited.Count -eq 0) {
            $defects.Add([PSCustomObject]@{
                    File = $item.File; Function = $item.Function; Line = $item.Line; Id = $item.Id
                    Reason = 'Test line names no test. Give each test title in single quotes.'
                })
            continue
        }

        foreach ($title in $cited) {
            if (-not $testTitles.Contains($title)) {
                $defects.Add([PSCustomObject]@{
                        File = $item.File; Function = $item.Function; Line = $item.Line; Id = $item.Id
                        Reason = "Cited test not found in Tests\Unit\$sourceFolder\$sourceName.Tests.ps1: '$title'."
                    })
            }
        }
    }

    # --- Build the index ---------------------------------------------------------------

    $enforced    = @($catalog | Where-Object { $PSItem.State -eq 'Enforced' })
    $unproven    = @($catalog | Where-Object { $PSItem.State -eq 'Unproven' })
    $accepted    = @($catalog | Where-Object { $PSItem.State -eq 'Accepted' })
    $security    = @($catalog | Where-Object { $PSItem.Sec })
    $secUnproven = @($unproven | Where-Object { $PSItem.Sec })

    $index = [System.Collections.Generic.List[string]]::new()
    $index.Add('# Invariant Index')
    $index.Add('')
    $index.Add('Generated by `Tests\Lint\Invoke-InvariantLint.ps1 -IndexPath`. Do not edit by hand.')
    $index.Add('The block in each function is the source; this is a one-line cross-reference.')
    $index.Add('Identifiers are local to a function. The format is defined in [invariants.md](invariants.md).')
    $index.Add('')
    $index.Add('| Measure | Count |')
    $index.Add('|---|--:|')
    $index.Add("| Functions | $functionCount |")
    $index.Add("| Invariants | $($catalog.Count) |")
    $index.Add("| Security invariants | $($security.Count) |")
    $index.Add("| Enforced (type, guard, test or static check in place) | $($enforced.Count) |")
    $index.Add("| Unproven (test or static check not written yet) | $($unproven.Count) |")
    $index.Add("| Unproven security invariants | $($secUnproven.Count) |")
    $index.Add("| Accepted limitations | $($accepted.Count) |")

    $currentFile     = ''
    $currentFunction = ''
    foreach ($item in $catalog) {
        if ($item.File -ne $currentFile) {
            $currentFile     = $item.File
            $currentFunction = ''
            $index.Add('')
            $index.Add("## $currentFile")
        }
        if ($item.Function -ne $currentFunction) {
            $currentFunction = $item.Function
            $index.Add('')
            $index.Add("### $currentFunction")
            $index.Add('')
        }

        $secTag = if ($item.Sec) { ' `[SEC]`' } else { '' }
        $how = switch ($item.State) {
            'Unproven' { "$($item.Keyword), none yet" }
            'Accepted' { 'Limitation' }
            default    { $item.Keyword }
        }
        $index.Add("- **$($item.Id)**$secTag $($item.Statement) *($how)*")
    }

    $indexMarkdown = ($index -join "`n") + "`n"

    if ($IndexPath -ne '' -and $PSCmdlet.ShouldProcess($IndexPath, 'Write invariant index')) {
        [System.IO.File]::WriteAllText($IndexPath, $indexMarkdown, [System.Text.UTF8Encoding]::new($false))
    }

    $success = ($missingBlock.Count -eq 0) -and ($defects.Count -eq 0)
    $message = if ($success) {
        "$($catalog.Count) invariants in $functionCount functions. $($unproven.Count) unproven, $($accepted.Count) accepted limitations."
    }
    else {
        "$($missingBlock.Count) function(s) with no block, $($defects.Count) malformed entr$(if ($defects.Count -eq 1) { 'y' } else { 'ies' })."
    }

    return [PSCustomObject]@{
        Success = $success
        Data    = [PSCustomObject]@{
            FunctionCount = $functionCount
            EntryCount    = $catalog.Count
            Enforced      = $enforced.Count
            Unproven      = $unproven.Count
            Accepted      = $accepted.Count
            MissingBlock  = @($missingBlock)
            Defects       = @($defects)
            Catalog       = @($catalog)
            IndexMarkdown = $indexMarkdown
        }
        Message = $message
    }
}
catch {
    return [PSCustomObject]@{
        Success = $false
        Data    = $null
        Message = "Invariant lint failed: $($PSItem.Exception.Message)"
    }
}
