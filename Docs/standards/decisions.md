# Decisions

Rules that were contested when the standards were ratified on 2026-11-14: a rule the
code contradicted, a rule that was never defined, or a practice nobody had documented.

## Decided

| # | Question | Decision | Rule |
|---|---|---|---|
| 1 | "No try-catch inside module functions", when public functions use try-catch to build `Success = $false` | Blanket rule rejected. Private helpers throw scrubbed errors; public functions catch, scrub and return. | C-21, C-22 |
| 2 | Whether a public function throws on an unrecoverable failure such as a missing binary | It does not. A public function throws only on invalid parameters. | C-22 |
| 3 | Password parameters typed `[SecureString]` only | `[SecureString]` or `[PSCredential]`; never `[string]`. | S-01 |
| 4 | Whether a type alone counts as parameter validation | It does not. A type and a `[Validate*]` attribute, except switches and credential types. | C-10 |
| 5 | "No sensitive path fragments" in `Message`, never defined | Reworded: no password, credential value, or value derived from one. Paths are allowed. | S-05 |
| 6 | `ConvertTo-Json -InputObject` on every call | Narrowed to values that can be arrays, which is where the defect occurs. | C-13 |
| 7 | `$PSItem` over `$_` | Ratified. | C-17 |
| 8 | One function per file | Ratified. | C-03 |
| 9 | `[OutputType()]` and `.OUTPUTS`, practised but unwritten | Ratified. | C-05, C-23 |
| 10 | Test contexts for the return contract and `-WhatIf`, practised but unwritten | Ratified. | T-03 |
| 11 | Box-drawing section separators inside function bodies | Allowed, not required. Not a rule. | — |
| 12 | Platform support, with Windows-only functions in a cross-platform module | New rule: guard on the platform and return `Success = $false` elsewhere. | C-07 |
| 13 | "FIPS algorithms only", scope unclear | Applies to security uses. | S-13 |
| 14 | What a function returns when `ShouldProcess` declines; the two functions disagreed, and one reported a change it had not made | Decided during Stack 1: a successful no-op preview. `Success = $true`, `Data.Applied = $false`, a `WhatIf:` Message. A caller tells a preview from a change by `Applied`, not by `Success`. | C-27 |
| 15 | Test runner layout: a configuration file plus an entry script, practised but unwritten; the unit runner set no exit code and depended on the working directory | Decided during Stack 1: one entry script per tier holding its own configuration, a results file per tier, and an exit code that also counts test files that failed to run. | T-10 |
| 16 | Module layout: `Public\` and `Private\` at the root, four hand-kept file lists (two load lists, `FunctionsToExport`, `FileList`) with nothing checking they agree, and an exported function in `Private\` | Decided during Stack 1: code under `source\`, a build that produces one merged `.psm1` and a generated manifest, tests run against the built module and mirror the source folders. Applied at the start of Stack 2, so the gate is built once, against the final layout. | C-28, C-29 |
| 17 | Alias export pattern: `Set-Alias` in the root module, a hand-kept `AliasesToExport`, and the README, practised but unwritten | Decided during Stack 1: an `[Alias()]` attribute on the target function, no `Set-Alias`; the build generates `AliasesToExport`. The attribute change is made now; generation comes with the Stack 2 build. | C-30 |
| 18 | `PSAvoidUsingWriteHost` excluded for the whole repo, justified by two interactive functions | Decided during Stack 1: the rule stays on; the two functions carry a `SuppressMessageAttribute` with the reason. Whether the analyzer covers `scripts\`, and with what settings, is left to Stack 2. | C-31 |
| 19 | Rules added during Stack 1 and not yet ratified: D-11 read as "the document is always wrong"; T-09 had two title formats, no way to name two invariants, and no checkable form; the I-05 enforcement keywords had no explicit approval | Ratified during Stack 1. D-11 reworded: the defect is fixed in whichever side is wrong. T-09 reworded: a cited test's title starts with each ID it is cited for, comma-separated, and security tests carry the `SEC` tag. I-05 ratified as written. | D-11, T-09, I-05 |
| 20 | Script naming in `scripts\`: five scripts named Verb-Noun, two named `test.<tier>.ps1`, and no script stating how it is meant to be run | Decided during Stack 1: Verb-Noun with an approved verb and a singular noun, and an `**Invocation:**` line in `.NOTES`. The two tier scripts are renamed `Invoke-StaticTest.ps1` and `Invoke-UnitTest.ps1`. A `scripts\lib\` folder is created when the first dot-sourced helper exists. | C-32, T-10 |
| 21 | Folder casing: `Docs`, `Tests`, `Public` and `Private` were PascalCase, `scripts`, `source` and `output` lowercase. PowerShell sets no rule for folder names; the lowercase names follow module-build templates this repository does not use | Decided during Stack 2: PascalCase throughout. `scripts\` became `Scripts\`, the new folders are `Source\` and `Output\`, and the helper folder of C-32 is `Scripts\Lib\`. Paths in code match the case exactly, because Linux file names are case-sensitive. | C-28, C-32 |
| 22 | Where linters and custom analyzer rules live: with the tools in `scripts\`, or beside the tests that call them | Decided during Stack 2: beside the tests. The invariant linter moved to `Tests\Lint\`; custom PSScriptAnalyzer rules go in `Tests\Lint\PSScriptAnalyzerRules\`. A rule's text stays in `Docs\standards\`; the file in `Tests\Lint\` is the check that enforces it. `Scripts\` holds tier runners and build tools. | T-10 |
| 23 | Where the config file lives once the module is one merged `.psm1`: the old path, `..\Config` from `Private\`, would resolve one level above the version folder | Decided during Stack 2: `Config\` inside the version folder, so S4 of `Get-OracleBackupConfigStore` ("a fixed path under the module folder") stays true as written. A rebuild or an upgrade starts with no config file; a location that outlives a version is chosen before the config writer moves in from OracleBackup. | C-28 |
| 24 | Minimum PowerShell version: C-01 and the manifest said 7.0, copied from the shared standard. No code here needs 7.0 specifically, 7.0 and 7.4 are out of support, and the tests run on 7.6 | Decided during Stack 2: 7.6 LTS, the current supported LTS. `#Requires -Version 7.6` on every `.ps1` and `.psm1`, `PowerShellVersion = '7.6'` in the manifest. The minimum and the tested version are now the same, so the analyzer's compatibility rules, whose bundled profiles stop at 7.0, are not used. | C-01 |
| 25 | Analyzer settings, left open by decision 18: where the settings file lives, which folders are analyzed, what fails, and how `Scripts\` console tools use `Write-Host` | Decided during Stack 2: one settings file, `Tests\Lint\PSScriptAnalyzerSettings.psd1`, used by the editor (through a committed `.vscode\settings.json`) and the gate alike. PSScriptAnalyzer pinned to 1.25.0. Analyzed: `Source\`, `Scripts\` and `Tests\Lint\`. Not analyzed: `*.Tests.ps1`, which build fake credentials on purpose. Every finding fails, Information included. An exception is a `SuppressMessageAttribute` with a justification at the narrowest scope: the function, or the whole script for a console tool in `Scripts\`. Formatting rules stay off, because no ratified standard asks for them. | C-31 |
| 26 | How house rules tagged *Linter* that no built-in analyzer rule covers are checked | Decided during Stack 2: one custom PSScriptAnalyzer rule per standard, one `.psm1` per rule in `Tests\Lint\PSScriptAnalyzerRules\`, named `Measure-C<nn><Name>`. That name is what a `SuppressMessageAttribute` cites, and each message starts with the rule ID. A rule returns diagnostic records, not the Success/Data/Message object, because PSScriptAnalyzer requires it. The settings file loads them through `CustomRulePath`, which resolves against the current directory, so the analyzer runs from the repository root. Each rule's known blind spots are listed under `Limitation:` in its help. Rules covered: C-05, C-08, C-09, C-10, C-11, C-14, C-15, C-17, C-18. | C-05, C-08 to C-11, C-14, C-15, C-17, C-18 |
| 27 | What stops a caller's `-WhatIf` from silently skipping, or wrongly running, a state change. Found when a first run under `-WhatIf` failed: `Get-OracleBackupConfigStore` skipped creating its default config, and `Set-RestrictiveAcl` then failed on the missing file | Decided during Stack 2: new rule C-33, checked by the custom rule `Measure-C33ShouldProcessGate`, in `Source\` only (`Scripts\` are console tools). Each call to a cmdlet that accepts `-WhatIf` is gated, comes after an early return, or passes `-WhatIf` explicitly. Only compiled cmdlets are checked, so the result does not depend on which modules a machine has installed. The separate "temporary file cleanup pins `-WhatIf:$false`" item became one case of C-33. Run against the previous commit, the rule reports exactly the three calls that caused the failure. | C-33 |
| 28 | What the single gate command runs, how commit messages are checked, and when the gate runs | Decided during Stack 2: `Scripts\Invoke-Gate.ps1` runs six checks and exits 1 on any failure. The checks are pinned tool versions, the analyzer, the static tier, gitleaks over the working tree, gitleaks over commits not yet on a remote, and those commits' messages. gitleaks does not read commit messages, so each message is piped to `gitleaks stdin` and checked against the S-16 patterns, now shared in `Tests\Lint\PublicRepoPatterns.psd1`. The unit tier is not in the gate. The gate runs by hand and from a committed `.githooks\pre-push` hook, turned on once per clone; a push is where a value becomes public and permanent. `Scripts\Test-SeededDefect.ps1` proves it: each planted defect must fail exactly the expected checks. A check against a private identifier list is deferred (TODO.md). | S-16, T-10 |

## Where invariants live

Decided 2026-11-14: in the code, in an `# INVARIANTS` comment block at the top of each
function body, not in a separate catalog document. See [README.md](README.md).

## How machine checks are built and run

Decided 2026-11-14.

- Checks are separated by speed, in three tiers, each run by its own command.
- **Static:** reads source text and runs no module code. The script analyzer, the
  invariant linter and the documentation checks. Seconds. Run on every change.
- **Unit:** Pester tests that run functions against mocks. Run before every commit.
- **Integration:** tests against a real Oracle database, and soak runs. Run before a release.
- A house rule is checked by a Pester test in `Tests\Static\`, where it gives a clear
  message and can itself be tested. The script analyzer runs in the same tier for the
  general rules it already covers.

## Known findings at ratification

Existing code that breaks a ratified rule. Left in place for the stack layers to catch.

- C-03: `Invoke-RmanProcess.ps1` and `Assert-OracleEnvironment.ps1` each define two functions.
  Fixed in Stack 2: `Invoke-CredentialScrub` and `Invoke-TnspingProcess` have files of their
  own, and `Tests\Static\SourceTestLayout.Tests.ps1` checks C-03.
- C-07: the RMAN functions have no platform guard.
- C-10: `-WalletAlias` on the RMAN functions has a type and no validation attribute.
- C-11: backtick continuation in `Assert-OracleEnvironment`.
- C-13: `Get-OracleBackupConfigStore` pipes to `ConvertTo-Json` (a single object, so the defect cannot occur there).
- C-14: `"$OracleHome\bin;..."` built by string in two places. Fixed during Stack 1.
- C-28: code is in `Public\` and `Private\` at the repository root, loaded from hand-kept
  lists, with no build step. Fixed at the start of Stack 2: code under `Source\`, built
  by `Scripts\Build-Module.ps1`.
- C-29: `Invoke-OraEnv` is exported but lives in `Private\`. Fixed at the start of Stack 2:
  moved to `Source\Public\`.
- C-30: `AliasesToExport` is still hand-kept in the manifest. Fixed at the start of
  Stack 2: generated by the build.

The full list is produced by the linter in Stack 2, not kept by hand here.

## Deferred

| Topic | Until |
|---|---|
| Integration test rules: naming, credentials, cleanup | Stack 3 |
| Ignore-file rules and agent containment | Stack 7 |
| Build, package and publish rules; manifest contents | Stack 8 |
| Wrapper scripts for external orchestrators | Not used in this repo |
| Oracle SQL and PL/SQL rules | No SQL in this repo yet |
| Bulk-mode return shape | No bulk function in this repo yet |

## Open — not yet decided

None. The four practices open at ratification were decided during Stack 1 (decisions
15 to 18).
