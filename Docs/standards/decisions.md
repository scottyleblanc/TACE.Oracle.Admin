# Decisions

Rules that were contested when the standards were ratified on 2026-11-14: a rule the
code contradicted, a rule that was never defined, or a practice nobody had written down.

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
- C-07: the RMAN functions have no platform guard.
- C-10: `-WalletAlias` on the RMAN functions has a type and no validation attribute.
- C-11: backtick continuation in `Assert-OracleEnvironment`.
- C-13: `Get-OracleBackupConfigStore` pipes to `ConvertTo-Json` (a single object, so the defect cannot occur there).
- C-14: `"$OracleHome\bin;..."` built by string in two places.

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

- Test runner layout: a configuration file plus an entry-point script, results written to `Tests\TestResults\`.
- Module layout: `Public\`, `Private\`, `Tests\`, `Docs\`, `scripts\`, and what the root module loads.
- Alias export pattern: `Set-Alias` in the root module, listed in `AliasesToExport`, documented in the README.
- The `PSAvoidUsingWriteHost` exclusion for the two interactive functions.
