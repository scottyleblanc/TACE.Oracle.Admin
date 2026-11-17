# Changelog — TACE.Oracle.Admin

All notable changes to this project will be documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versioning follows [Semantic Versioning](https://semver.org/).

---

## [Unreleased]

Stack 6 of the AI Development Stack — independent review. No change to module behaviour.

### Added

- `Docs/REVIEW.md`: the review path and the review order every pull request follows,
  intent then tests then implementation, with the Review rules each step checks, a
  severity scale and how the author answers a finding.
- `.github/pull_request_template.md`: the review record, the human checklist in the same
  order, and the evidence.
- `Scripts/Invoke-ModelReview.ps1`: the second-model review. A new headless Claude Code
  session reviews the branch's commits in a temporary worktree and writes
  `Review/LastReview.json`. Its prompt and output schema are in `Review/`.
- `Invoke-Gate.ps1 -Base`: a `review` check. A pull request that changes any file other
  than the evidence files fails without a completed, current review whose every finding
  is answered.
- `Test-SeededDefect.ps1`: cases `review missing`, `review current`, `review unanswered`
  and `review stale`, fourteen in all.
- Decision 35: how every pull request is examined by someone other than its author.

### Changed

- `Test-SeededDefect.ps1`: the evidence cases add a review record before the integration
  evidence, in the order `Docs/REVIEW.md` gives; `evidence stale` now also fails `review`.

### Security

- The reviewer session has no command tools, no write tools, no settings, instruction
  files, memory or MCP servers, and reads only the committed files of the reviewed
  commit. CI calls no model and the workflow still holds no secret.

---

## [0.2.5] - 2026-11-16

Stack 5 of the AI Development Stack — agent instructions. Not published to PSGallery.
No change to module behaviour. Record in `Docs/audit/stack-5-agent-instructions.md`.

### Added

- `AGENTS.md`: the instructions AI agents are given, generated from `Docs/standards/`
  by the new `Scripts/Export-AgentInstruction.ps1`; 87 rules, carried word for word.
  Cursor reads it directly; Claude Code reads it through a local, gitignored import.
- `Tests/Static/AgentInstruction.Tests.ps1`: fails when the committed `AGENTS.md` does
  not match the standards or drops a rule.
- `Test-SeededDefect.ps1`: an `instructions` case, ten in all. A rule added to the
  standards without regenerating `AGENTS.md` fails the gate on `static` alone.
- Decision 34: one generated `AGENTS.md`, committed and checked; no per-tool copies.
- `Docs/audit/stack-5-agent-instructions.md`: the same generation task, three runs
  with and three without `AGENTS.md`. Every run ended on a passing gate and met the
  same Review rules; with the standards in the repository, the file made no
  measurable difference.
- `TODO.md`: a Stack 7 item for the tool-permission behaviour found while setting up
  the comparison, and a backlog item for the rules the shared instruction file
  repeats from `AGENTS.md`.

### Fixed

- `Docs/standards/README.md`: the Status section said nothing was enforced; it now
  states what the gate enforces.

## [0.2.4] - 2026-11-16

Stack 4 of the AI Development Stack — enforced gate. Not published to PSGallery. No
change to module behaviour. Record in `Docs/audit/stack-4-enforced-gate.md`.

### Added

- `.github/workflows/gate.yml`: runs the gate on every pull request into `master`, on a
  Windows runner. It installs the tools and calls `Scripts/Invoke-Gate.ps1 -Unit -Base
  origin/master`; it holds no logic of its own.
- `Scripts/Install-GateTool.ps1`: installs PSScriptAnalyzer 1.25.0, Pester 5.7.1 and
  gitleaks 8.30.1 when missing.
- `Invoke-Gate.ps1 -Base <branch>`: `commits` and `messages` check the commits in
  `<branch>..HEAD` rather than those not on a remote, which in CI is none. Adds the
  `evidence` check, rule T-14: when `Source/` changed, `Tests/Integration/LastRun.json`
  must be current.
- `Test-SeededDefect.ps1`: four more cases, nine in all. A secret in a commit message
  that is already on a remote passes without `-Base` and fails with it; integration
  evidence passes when current and fails when stale.
- Decisions 32 (`-Base` and the CI checkout) and 33 (the `master` ruleset, no bypass).

### Changed

- `master` changes only through a pull request merged with a merge commit; the local
  `--no-ff` merge and push in `VERSIONING.md` is replaced.

### Security

- The workflow has a read-only token, no secrets, the `pull_request` trigger only, no
  credentials kept in the checkout, and its one action pinned to a full commit SHA.
- The gitleaks download in CI is checked against a pinned SHA-256 before it is unpacked.
- `master` is protected by a ruleset with no bypass: a pull request is required, and the
  `gate` check from GitHub Actions must pass on a head that is up to date with `master`.
  Force pushes and deletion are blocked. The repository allows only GitHub-owned actions
  pinned to a full SHA, and secret scanning with push protection is on. A pull request
  carrying the seeded defects was blocked.

## [0.2.3] - 2026-11-16

Stack 3 of the AI Development Stack — tests. Not published to PSGallery. Records are in
`Docs/audit/stack-3-mutation.md`, `stack-3-integration.md` and
`stack-3-seeded-defect.md`.

### Added

- Rule I-11: every invariant except a limitation names its proof. A `Type:` or `Guard:`
  line is followed by a `Test:` or `Static:` line, so removing the enforcement fails a
  test. Rule I-12: a `Static:` line cites a check in
  `Tests/Static/SourceInvariants.Tests.ps1` whose title starts with the function name.
- Fixture tests for the linter's proof rules in `Tests/Static/InvariantConformance.Tests.ps1`.
- `Scripts/Test-InvariantMutation.ps1` and `Tests/Mutation/InvariantMutations.psd1`: break
  each invariant in a temporary copy and confirm its cited tests fail (rule I-10). It
  refuses to run when a security invariant with a proof has no mutation. Result in
  `Docs/audit/stack-3-mutation.md`.
- `Tests/Unit/Set-EnvironmentSentinel.ps1` and `Compare-EnvironmentSentinel.ps1`, and rule
  T-11: session-environment tests set known values first and compare every variable.
- `Tests/Static/SourceInvariants.Tests.ps1`, the static checks cited on `Static:` lines.
  The first: `ConvertFrom-SecureStringToPlaintext` S5.
- Tests for 23 invariants that had none, among them 7 security invariants:
  `Invoke-RmanProcess` S1 (no password in the argument list, checked from a file the
  fake RMAN writes, since stdout is scrubbed), S4, S5, S6; `Get-RmanBackupStatus` S5;
  `Remove-RmanObsoleteBackup` S8; `Set-OracleEnv` S1 (no remembered instance list).
  Unproven invariants fall from 35 to 12.
- Static checks for 11 invariants in `Tests/Static/SourceInvariants.Tests.ps1`, read from
  the syntax tree: only `ConvertFrom-SecureStringToPlaintext` turns a secure value into
  plaintext (S3), and it zeroes the buffer in a `finally` (S2); the password is extracted
  only inside the stdin write (`Invoke-RmanProcess` S2); `ConvertFrom-RmanListBackup`
  reads only its input (S1); `Get-OracleDatabaseList` connects to nothing and changes
  nothing (S1, L1); `Get-RmanBackupStatus` hands Credential only to
  `Invoke-RmanProcess` (S3); `Set-OracleEnv` changes only the three Oracle variables
  and never prompts or writes to the host (S2, L3); both process wrappers dispose in a
  `finally` (L3).
- `Invoke-RmanProcess` L5 split in two, so each claim has its own proof. L5, the
  timeout kills the whole process tree, has a unit test that checks no child of the
  fake RMAN survives. New L6, a failed kill or wait does not replace the timeout error,
  has a static check of the timeout branch. No invariant is now unproven.

### Fixed

- `Invoke-OraEnv` (`oraset`) with no SID threw when discovery failed or found no Oracle
  instance: an empty list became `$null`, and `.Count` on it throws under StrictMode.
  It now passes on to `Set-OracleEnv`, which returns the Message to show. The defect
  came from the `Set-OracleEnv` split earlier in this stack, and was found by a
  coverage test.
- Twelve security invariants cited tests that passed with the invariant broken. The
  environment tests compared with a value earlier tests had already polluted; the
  credential tests ran with no credential; the tnsping scrub test never reached the
  message; ConfirmImpact and directory inheritance were untested. Nine non-security
  citations were weak in the same way. All now fail when their invariant is broken.

### Changed

- **Breaking:** `Set-OracleEnv` no longer prompts or writes to the host. With several
  instances and no `-SID` it returns `Success = $false` with a Message listing them;
  pass `-SID`. Its `Write-Host` suppression is removed. The menu, the confirmation line
  and the `-Verbose` `ORACLE_HOME`/`ORACLE_BASE` lines moved to `Invoke-OraEnv`
  (`oraset`, `oraenv`), which shows the Message from `Set-OracleEnv` on success.
  Interactive use through the aliases is unchanged apart from the wording of the
  confirmation line.
- `Docs/standards/invariants-index.md` is now the invariant-to-test map: each invariant
  is followed by the tests or static checks that prove it. "Enforced" is replaced by
  "Proven"; a type or guard no longer counts as proven without a test.
- The 35 `Type:` and `Guard:` entries carry a proof line: 17 cite an existing test, 18
  are `Test: none yet.` Unproven invariants rise from 17 to 35 (15 security) because
  they are now counted, not because anything regressed.
- Every cited unit test follows rule T-09. 95 titles now start with the IDs they are
  cited for, and 26 tests cited for a security invariant gained the Pester tag `SEC`.
  Citations in the source blocks are updated to match; no test body changed. A leading
  `[SEC] ` in a title is dropped in favour of the tag, and a `SEC-NN:` prefix moves to
  the end as `(SEC-NN)`. One stale ID is removed: `ConvertFrom-RmanListBackup`'s title
  `R1, P2 ...` named P2, a limitation that cites no test. The two `Invoke-RmanProcess`
  R2 titles shared by tests in several authentication modes now end with the mode, so
  each citation names one test.
- The invariant linter checks rule T-09: a cited test's title starts with exactly the
  IDs it is cited for, and a test cited for a security invariant carries the `SEC` tag.
  Run against the previous commit it reports the same 95 titles and 26 tags.
- Rules I-09 and I-12 now also require a cited title to be unique in its file, and the
  linter refuses one that several tests share, since that citation names no single
  test. Run before the R2 titles were made unique, it reports exactly those two.
- A static check cited for a security invariant must carry the `SEC` tag (rule I-12),
  and the linter refuses one without it, as it already did for unit tests. All 8 such
  checks already carry it.
- Rule T-03: a test that proves a security invariant may sit in the context that holds
  its setup; the `SEC` tag marks it as a security test. The Stack 3 item "every
  security invariant has a test in a `Security` context" is met through the tag rather
  than by moving 20 tests out of the contexts whose setup they use.
- Rule T-12 and a coverage floor: `Scripts/Invoke-UnitTest.ps1` measures coverage of
  the built module, maps it back to each file in `Source/`, prints a per-file table and
  fails below 95%. `-Verbose` lists every missed command by source line. JaCoCo XML goes
  to `Tests/TestResults/coverage.xml`. Coverage is 97.7% (734 of 751 commands) after
  five tests for reachable gaps: the `Set-OracleEnv` catch block, `Invoke-OraEnv` when
  discovery fails, finds nothing, or `Set-OracleEnv` returns nothing, and an RMAN row
  that ends before its last columns. The 17 commands left are recorded in `Docs/TODO.md`
  by reason.
- The integration tier: `Scripts/Invoke-IntegrationTest.ps1` runs `Tests/Integration/`
  against a local Oracle database with OS authentication, and `Invoke-Gate.ps1
  -Integration` runs it after the gate. The pre-push hook never does. Five guards, from
  OracleBackup's AD-020, run first: host allowlist, opt-in variable
  (`ORACLE_ADMIN_RUN_INTEGRATION`), complete local config, database-name denylist, and
  an existing test folder. A failed guard fails the run. The local config,
  `Tests/Integration/IntegrationConfig.local.ps1`, is gitignored; an example is
  committed. Tests for `Get-RmanBackupStatus` and `Remove-RmanObsoleteBackup` take
  control file backups and run a real `DELETE OBSOLETE`. 13 static tests cover the
  guards. First runs against Oracle Database 21c XE: 12 of 12. Record in
  `Docs/audit/stack-3-integration.md`.
- `Invoke-Gate.ps1 -Unit` adds the unit tier, coverage floor included, as a seventh
  check (decision 31). The pre-push hook does not pass it; CI will from Stack 4.
  `Scripts/Test-SeededDefect.ps1` gains a fifth case, a behaviour defect: dropping
  `Get-RmanBackupStatus`'s CompletionTime sort (breaking R3) fails the gate with `-Unit`
  on `unit` alone, through the one test R3 cites. The control case now runs with
  `-Unit`. Record in `Docs/audit/stack-3-seeded-defect.md`.
- Integration evidence (decision 30, rule T-14): each run of the integration tier writes
  `Tests/Integration/LastRun.json` with the commit, whether the working tree was clean,
  the database edition and version, the PowerShell and Pester versions, the totals and
  each test's outcome. No host name, path or SID. It counts as evidence only for a
  passing run on a clean tree, and is committed as the last commit of a branch. A static
  test holds the file to its agreed fields. Rule T-13 records the integration test rules
  (decision 29), deferred to Stack 3 at ratification.
- Signing references in `Assert-OracleEnvironment`, its tests and `Docs/SECURITY.md` now
  state only the fact: Oracle binaries are not signed. The claims that Oracle signs
  distribution archives, and the references to the old design decision, are removed.
  The tests' pass-through mocks return `NotSigned`, the real state; one test keeps a
  valid Oracle-signed mock to cover the accepting side of the signer check. `R1` is
  retitled without "valid Oracle signature, SYSTEM owner"; the owner is not checked.
  The RMAN functions' integrity-failure mocks use `HashMismatch`, since `NotSigned`
  never fails the check.

---

## [0.2.2] - 2026-11-15

Stack 2 of the AI Development Stack — deterministic checks. Not published to PSGallery.
The seeded-defect result is in `Docs/audit/stack-2-seeded-defects.md`.

### Added

- Rule C-33 and its custom analyzer rule `Measure-C33ShouldProcessGate` (decision 27).
  In `Source/`, a call to a cmdlet that accepts `-WhatIf` must be inside a
  `ShouldProcess` gate, after an early return, or pass `-WhatIf` explicitly.
- gitleaks 8.30.1 as the general secret scanner (`PREREQUISITES.md`). A first scan of the
  full history and the working tree found nothing.
- `Scripts/Invoke-Gate.ps1`, the single command for every static check (decision 28). It
  runs pinned tool versions, the analyzer, the static tier, gitleaks over the working
  tree and over unpushed commits, and an unpushed commit-message check.
- `.githooks/pre-push` runs the gate before every push, once turned on with
  `git config core.hooksPath .githooks`.
- `.gitleaks.toml`: the default gitleaks rules, skipping the generated `Output/` and
  `Tests/TestResults/` folders.
- `Scripts/Test-SeededDefect.ps1` plants a lint violation, a committed secret and a secret
  in a commit message in a temporary copy. It checks that the gate fails on exactly the
  expected checks for each.
- `Tests/Lint/PublicRepoPatterns.psd1`: the S-16 patterns, read by both the static tier
  and the gate's commit-message check.
- `Scripts/Build-Module.ps1` builds the module: it merges `Source/` (classes, private,
  public) into one `TACE.Oracle.Admin.psm1` under `Output/TACE.Oracle.Admin/<version>/`
  and generates the manifest's `FunctionsToExport`, `AliasesToExport` and `FileList`
  (rules C-28 to C-30). It fails when a public file does not define exactly one function
  named for the file, or when the source manifest declares a generated list. `-Package`
  builds and lists a local `.nupkg` from the built module.
- `Tests/Unit/Get-BuiltModulePath.ps1` — the one place the unit tests find the built
  module; it fails with an instruction to build when there is none.
- Decisions 21 to 23 in `Docs/standards/decisions.md`: PascalCase folder names, linters
  beside the tests that call them, and the config path in the version folder.
- `.gitattributes` with `* text=auto eol=lf`: every text file is LF in the repository
  and in every checkout, whatever a machine's `core.autocrlf` is. The index was already
  LF, so no file's content changed.
- Decisions 24 and 25: minimum PowerShell 7.6 LTS, and the analyzer settings.
- `.vscode/settings.json`, committed as the one exception to the ignored `.vscode/`. It
  points the editor's live analysis at `Tests/Lint/PSScriptAnalyzerSettings.psd1`.
- PSScriptAnalyzer pinned to 1.25.0 in `PREREQUISITES.md`, with the folders it covers.
- A `SuppressMessageAttribute` for `PSAvoidUsingWriteHost`, with a reason, on each
  console tool in `Scripts/`. Also one for `PSUseShouldProcessForStateChangingFunctions`
  on `Set-RestrictiveAcl`, pending the inherited `-WhatIf` item in `TODO.md`.
- Custom PSScriptAnalyzer rules in `Tests/Lint/PSScriptAnalyzerRules/` (decision 26),
  one per house rule the built-in rules do not cover: C-05 output type, C-08 platform
  detection, C-09 parameter types, C-10 public parameter validation, C-11 backtick
  continuation, C-14 string-built paths, C-15 file encoding, C-17 `$_`, C-18 emojis.
  The settings file loads them next to the built-in rules.
- `Tests/Static/PSScriptAnalyzerRules.Tests.ps1`: what each custom rule must report and
  what it must not.
- `Tests/Static/BuildModule.Tests.ps1`: the build refuses a public file that does not
  define exactly one function named for the file, a source tree with no public
  function, and a source manifest that declares a generated list (rules C-28 to C-30).
  Each test builds a copy of `Build-Module.ps1` against a fixture on `TestDrive`.
- `Tests/Static/SourceTestLayout.Tests.ps1` checks two rules:
  - C-03: every source file defines one function, named for the file.
  - T-02: each function has its own test file in the mirrored `Tests/Unit/` folder, and
    no test file is left without its source file.
- `Tests/Unit/Private/ConvertFrom-RmanListBackup.Tests.ps1`: the parser's first tests of
  its own, which prove invariants R1 to R5.
- `Source/Private/Invoke-TnspingProcess.ps1` and `Source/Private/Invoke-CredentialScrub.ps1`,
  each with its own test file. The functions and their tests moved there unchanged, out
  of `Assert-OracleEnvironment` and `Invoke-RmanProcess` (rule C-03). `Invoke-TnspingProcess`
  gained comment-based help. Its S2 limitation now names the public callers' alias
  validation.

### Changed

- Layout (decision 16): `Public/` and `Private/` moved under `Source/`, with the source
  manifest and the head of the root module. `Invoke-OraEnv` moved from `Private/` to
  `Source/Public/`, since it is exported (C-29). The hand-kept load lists, export lists
  and file list are gone.
- Unit tests moved to `Tests/Unit/Public/`, `Tests/Unit/Private/` and
  `Tests/Unit/Module/`, and import the built module. `Scripts/Invoke-UnitTest.ps1`
  builds first, then runs `Tests/Unit/` recursively.
- `scripts/` renamed `Scripts/`. `Invoke-InvariantLint.ps1` moved to `Tests/Lint/`, and
  now looks up a cited test in the `Tests/Unit/` folder that mirrors the source folder.
- `Get-OracleBackupConfigStore` resolves `Config/OracleBackup.json` in the folder that
  holds the module's `.psm1`. For an installed module this is the same version folder as
  before; for a checkout it is now under `Output/`, not the repository root.
- `Publish-ToGallery.ps1` publishes from `Output/TACE.Oracle.Admin/<version>/`; the
  `build/<version>/staging/` folder is no longer used.
- Rules C-01, C-03, C-28, C-29, C-32, T-02, T-10, I-01 and I-09 examples updated for the
  new paths. The Stack 1 closing tasks are ticked in `TODO.md`.
- **Breaking:** the minimum PowerShell version is 7.6 LTS, up from 7.0 (decision 24).
  `#Requires -Version 7.6` on every script and `PowerShellVersion = '7.6'` in the
  manifest; the module no longer loads on 7.0 to 7.5. Rule C-01, the README,
  `PREREQUISITES.md` and the WN22-CC-000480 row in `SECURITY.md` updated.
- `PSScriptAnalyzerSettings.psd1` moved from the repository root to `Tests/Lint/`
  (decision 25). The settings now report every severity. The file is no longer copied
  into the built module or the package.
- `Assert-OracleEnvironment` and `Get-OracleBackupConfigStore`: three `Join-Path` calls
  now name their parameters, which clears the analyzer's positional-parameter findings.
  Behaviour is unchanged.
- Fixed violations of ratified rules found by the new custom rules. Behaviour is
  unchanged:
  - C-17: `$_` written `$PSItem` in `Get-OracleDatabaseList`, `Set-OracleEnv` and
    `Test-LinuxBuild.ps1`
  - C-05: `[OutputType()]` added to `Get-OracleDatabaseList`, `Set-OracleEnv`,
    `Invoke-OraEnv` and the two helpers in `Test-LinuxBuild.ps1`
  - C-09: the AST predicates in `Build-Module.ps1` and `Invoke-InvariantLint.ps1` type
    their parameter
  - C-11: the tnsping call in `Assert-OracleEnvironment` is splatted
- The settings file now loads the custom rules alongside the built-in rules.
- **Breaking:** `Get-OracleDatabaseList -Platform` takes `ValidateSet('Windows',
  'Linux', 'Unsupported')` (rule C-10). An unknown value now throws a parameter error
  instead of returning `Success = $false` (rule C-22). `'Unsupported'`, the value
  detection gives on any other OS, still returns `Success = $false` (rule C-07).
- `Invoke-CredentialScrub` sets `StrictMode` and `$ErrorActionPreference` like every
  other function. Its help now describes the one pattern it scrubs and names its callers.
- Version 0.2.2 in the source manifest, the root module and the public functions'
  `.NOTES`. The manifest description now says PowerShell 7.6+, not 7+.
- `README.md` and `SECURITY.md` status blocks, the `SECURITY.md` audit record, and the
  Stack 2 row in `STAGES.md` updated for the close. The Stack 2 closing tasks are
  ticked in `TODO.md`.

### Fixed

- A first run under a caller's `-WhatIf` failed. A caller's `-WhatIf` reached
  `Get-OracleBackupConfigStore` and skipped creating the default config folder and file.
  `Set-RestrictiveAcl` then failed on the missing file. The three writes now pin
  `-WhatIf:$false`, because creating and securing the default config is part of reading
  it. Invariants L1 in both functions, with a test each.

### Security

- **Breaking:** `-WalletAlias` on `Get-RmanBackupStatus` and `Remove-RmanObsoleteBackup`
  accepts only letters, digits, `_`, `.` and `-` (rule C-10, invariants S6 and S10). The
  alias is written into the `CONNECT` line on RMAN's stdin and passed to tnsping, so a
  newline, `;`, space or quote could add an RMAN command or an argument. The pattern
  ends in `\z`, so a trailing newline is refused too. The empty default still passes.

---

## [0.2.1] - 2026-11-14

Stack 1 of the AI Development Stack — intent. Not published to PSGallery.

### Added

- `Docs/standards/` — the ratified standards, one sentence plus one example each, with
  an ID and the layer that enforces each: `coding.md`, `security.md`, `testing.md`,
  `documentation.md`, and `decisions.md` for contested, deferred and open questions.
- `Docs/standards/invariants.md` — the format of the invariant block: sections,
  identifiers, and the five ways an entry can be enforced.
- An `# INVARIANTS` block in every function under `Public\` and `Private\`: 149
  invariants in 13 functions, 54 of them security invariants. Comments only; no
  behaviour changes.
- `scripts/Invoke-InvariantLint.ps1` — checks every block and generates
  `Docs/standards/invariants-index.md`.
- `Tests/Static/InvariantConformance.Tests.ps1` and `scripts/Invoke-StaticTest.ps1` — the
  first checks in the static tier. They fail when a function has no block, an entry is
  malformed, or the committed index is out of date.
- `Tests/Get-OracleBackupConfigStore.Tests.ps1` — tests for S4, R1 and R2.
- `Tests/Static/PublicRepoHygiene.Tests.ps1` — the machine check for rule S-16 in the
  static tier: fails on an AWS account ID, an ARN, an access key ID, a literal S3
  target, an email address outside the reserved example domains, or a private key in
  any file git tracks or would add. Failure messages show only a value's first
  characters.
- `Private/Test-WindowsPlatform.ps1` — returns `$IsWindows`, so a test can simulate
  another platform; `$IsWindows` itself is read-only.
- Rules C-28 and C-29 in `Docs/standards/coding.md`: module source under `source\`,
  built into one merged `.psm1` with a generated manifest, and exports equal to the
  `source\Public\` file names. Recorded as decision 16; the move is the first task of
  Stack 2, and the current layout is listed as a known finding until then.
- Rule C-27 in `Docs/standards/coding.md`: when `ShouldProcess` declines, a function
  changes nothing and returns `Success = $true`, `Data.Applied = $false`, and a Message
  starting with `WhatIf:`. Recorded as decision 14.

### Changed

- `Set-OracleEnv` and `Remove-RmanObsoleteBackup` follow C-27. Both add `Applied` to
  `Data`. Under `-WhatIf`, `Remove-RmanObsoleteBackup` now returns `Success = $true`
  with `DatabaseName` and `Applied = $false`, where it returned `Success = $false` and
  no `Data`. Breaking for a caller that read `Success = $false` as "skipped".
- The `oraset` and `oraenv` aliases are declared with `[Alias('oraset', 'oraenv')]` on
  `Invoke-OraEnv`, replacing the two `Set-Alias` lines in the root module (new rule
  C-30, decision 17). Same names, same target, still exported.
- `Build-Module.ps1`, `Sync-ToS3.ps1` and `Test-LinuxBuild.ps1` take the S3 staging
  bucket as `-S3Bucket` instead of a name written into the scripts. It is required by
  `Sync-ToS3.ps1` and `Test-LinuxBuild.ps1`; `Build-Module.ps1` skips the upload when
  it is omitted. No bucket name is kept in the repository.
- Scripts in `scripts/` follow new rule C-32 (decision 20): Verb-Noun names and an
  `**Invocation:**` line in `.NOTES`. `scripts/test.unit.ps1` is renamed
  `scripts/Invoke-UnitTest.ps1`; the static runner is `scripts/Invoke-StaticTest.ps1`.
- `PSAvoidUsingWriteHost` is no longer excluded for the whole repository (new rule C-31,
  decision 18). `Set-OracleEnv` and `Invoke-OraEnv`, the two interactive functions, carry
  a `SuppressMessageAttribute` with the reason, so every other function is checked.
- Rules D-11 and T-09 reworded and ratified, and I-05 ratified (decision 19). D-11 now
  says a document-code contradiction is fixed in whichever side is wrong. T-09 now says
  a cited test's title starts with each ID it is cited for, and security tests carry
  the Pester tag `SEC`; four tests from this stage are renamed or tagged to match.
- Test runners follow new rule T-10: one script per tier, holding its own configuration.
  the unit runner is rewritten to the house rules and no longer runs
  `Unblock-File`. `Tests/UnitTests.pester.ps1` is removed. Results go to
  `Tests/TestResults/static.xml` and `unit.xml`; the unit file was `UnitTests.xml`.
- `Get-RmanBackupStatus` and `Remove-RmanObsoleteBackup` check the platform first (rule
  C-07). Off Windows they return `Success = $false`, "Windows only. Linux support is not
  yet built.", before reading the config or starting a process. Before, they failed
  later with a misleading "rman.exe not found".

### Fixed

- `Get-RmanBackupStatus` and `Remove-RmanObsoleteBackup` failed whenever the config had
  no `OracleHome`. `Assert-OracleEnvironment` found and validated the home through
  `ORACLE_HOME`, but the callers then passed the empty config value to
  `Invoke-RmanProcess`, which rejected it at parameter binding. The callers now use
  the home that `Assert-OracleEnvironment` validated.
- `Get-OracleBackupConfigStore` failed to load a config file that was missing any
  setting: under StrictMode, reading a missing property throws. A missing or null
  setting now takes its default, as documented.
- `Assert-OracleEnvironment` told the reader to run `Set-OracleBackupConfig` when no
  Oracle home was found; this module has no such function. The message now names the
  two ways to set one: `OracleHome` in `Config\OracleBackup.json`, or `ORACLE_HOME`.
- `Set-OracleEnv -WhatIf` set nothing but returned "ORACLE_SID set to '<SID>'." It now
  returns a `WhatIf:` preview with `Data.Applied = $false`.
- `Invoke-TnspingProcess` could hang its caller indefinitely. It read stdout to the end
  before waiting, so a `tnsping` that never exited was never timed out, and heavy stderr
  output could stall the child. It now reads both streams asynchronously, waits up to
  `-TimeoutSeconds` (default 30), and on timeout kills the process tree and throws.
- `Invoke-RmanProcess` on timeout now kills the whole process tree rather than the RMAN
  process alone, guards the kill so it cannot replace the timeout error, and waits for
  the killed process to exit.
- `Get-OracleDatabaseList` on Windows reported "No Oracle database services found" when
  the service query itself failed (WMI stopped, access denied, an invalid query): the
  query suppressed its errors. It now returns `Success = $false` with the error, and
  `Set-OracleEnv` passes that on instead of saying the host has no instances.
- The unit test runner exited 0 when tests failed, and worked only from the repository
  root. Both tier scripts now exit 1 when any test or any test file fails, including a
  file that fails to parse, which counts only as a failed container.
- Both process helpers build the child `PATH` with `Join-Path` and
  `[System.IO.Path]::PathSeparator`, under the exact name `PATH`, in place of a string
  joined with `\` and `;`.

### Removed

- `Remove-RmanObsoleteBackup` `-CatalogConnection` and `-CatalogCredential`. Recovery
  catalog support was half-built and is withdrawn until a catalog is in scope. Breaking
  for any caller that passed either parameter; `0.2.0` was not published to PSGallery.

### Security

- `Remove-RmanObsoleteBackup` no longer places caller text in the RMAN script.
  `-CatalogConnection` was inserted after a non-empty check only, so a crafted value
  could append RMAN commands; `-CatalogCredential` was accepted and silently ignored.
  New invariant S9: the RMAN script is fixed text, with a test. S6 and S7 are retired.
- `Remove-RmanObsoleteBackup` `-WhatIf` no longer has side effects. The `ShouldProcess`
  gate now runs before the config read and the environment check, so a preview cannot
  create the config file or run `tnsping`. Invariant L1 changes from a limitation to a
  tested guarantee.
- `Get-OracleBackupConfigStore` no longer reads `ORACLE_BACKUP_CONFIG_PATH`. The
  variable let anything that could set the process environment choose which config
  file supplied `OracleHome` and where a new one was created. Tests now set the
  module-scoped `$script:ConfigPathOverride` through `InModuleScope`; production
  always uses `Config\OracleBackup.json` under the module folder. Invariant S4
  changes from a limitation to a tested guarantee.
- `Docs/SECURITY.md` now states that the binary signature check cannot detect a
  replaced Oracle binary: Oracle executables are unsigned, so a patched binary and a
  tampered one both pass. Recorded as an open item; no behaviour change.

---

## [0.2.0] - 2026-11-14

Stack 0 of the AI Development Stack — setup and baseline. Not published to PSGallery.

### Added

- `Docs/STAGES.md` and `Docs/TODO.md`: AI Development Stack plan recorded — the layer
  model, build rules, test bed, and goals, deliverables and tasks for Stack 0 to Stack 10.
- `Get-RmanBackupStatus` — reports the most recent RMAN backup for a database. Read-only.
- `Remove-RmanObsoleteBackup` — runs RMAN `DELETE OBSOLETE`. `SupportsShouldProcess`,
  `ConfirmImpact = 'High'`.
- Private helpers: `Invoke-RmanProcess` (with `Invoke-CredentialScrub`),
  `ConvertFrom-SecureStringToPlaintext`, `Assert-OracleEnvironment` (with
  `Invoke-TnspingProcess`), `ConvertFrom-RmanListBackup`, `Get-OracleBackupConfigStore`,
  `Set-RestrictiveAcl`.
- Unit tests for the copied functions. Unit test count: 117 → 291 (all passing).
- `Docs/audit/stack-0-baseline.md` — size, test and analyzer baseline, and known gaps.
- These functions were copied from the Oracle backup module as working examples for the
  AI Development Stack. `Get-RmanBackupStatus` reads its configuration through
  `Get-OracleBackupConfigStore` in place of a module-level cache, so importing the module
  still writes nothing to disk.
- `.gitignore`: `Config/` (local runtime configuration, created on first use).

### Changed

- Completed Stage 1, 1.3, 1.4 and 2 items removed from `Docs/TODO.md` and
  `Docs/STAGES.md`. Items not already in this changelog were added to the 0.1.0,
  0.1.3, 0.1.4, 0.1.5 and 0.1.6 entries.

---

## [0.1.7] - 2026-11-14

### Changed

- `Docs/STAGES.md` and `Docs/TODO.md`: Stage 2 (PSGallery publication) closed out. It was
  still shown as pending although the module was published at v0.1.5 and v0.1.6. The
  planned `Publish-Module` steps are replaced with the build and publish workflow actually
  used (`Build-Module.ps1`, `Publish-ToGallery.ps1`).
- `Docs/README.md` and `Docs/SECURITY.md`: status blocks corrected — version, and unit
  test count 107 → 117.
- Documentation only. No functional changes; not published to PSGallery.

---

## [0.1.6] - 2026-03-17

### Changed

- Version bump to resolve PSGallery 409 conflict. v0.1.5 was published with an
  incomplete package (no `FileList`) during an earlier session and cannot be
  overwritten. No functional changes.
- Published to PSGallery; `master` pushed and tagged `v0.1.6`. No record was kept of
  the propagation check or the clean-session install smoke test.

---

## [0.1.5] - 2026-03-17

Stage 2 — PSGallery publication. Published to PSGallery with an incomplete package
(see 0.1.6).

### Added

- Root `README.md` for PSGallery — `Install-Module` first, absolute GitHub links.
- `PSScriptAnalyzerSettings.psd1` — suppresses `PSUseBOMForUnicodeEncodedFile`
  (PS7 false positive) and `PSAvoidUsingWriteHost` (intentional interactive design).

- `scripts/Build-Module.ps1` — stages module files to `build\<version>\staging\`, builds
  a `.nupkg` to `build\<version>\repo\`, lists package contents, and uploads the `.nupkg`
  and `Test-LinuxBuild.ps1` to S3 staging. Enforces version consistency across all build
  files and warns if the matching git tag does not exist. Build artifacts are retained by
  version and never overwritten.
- `scripts/Publish-ToGallery.ps1` — publishes the staged build to PSGallery. Requires
  `Build-Module.ps1` to have run first. Enforces a clean git working tree and a matching
  git tag before publishing.
- `scripts/Test-LinuxBuild.ps1` — downloads the latest versioned build from S3, installs
  it into a temporary local PSResource repository, and runs 9 smoke tests covering module
  load, exported functions, aliases, return object shape, and credential safety. Linux only.
  Exits 0 on pass, 1 on failure.
- `Tests\Invoke-OraEnv.Tests.ps1` — 10 unit tests covering parameter validation,
  SID pass-through, verbose pass-through, output suppression, error host output, and
  security (no credential fragments in output).

### Changed

- `Set-OracleEnv`: `ORACLE_HOME` and `ORACLE_BASE` are always set in the session but
  are only printed to the host when `-Verbose` is specified. `ORACLE_SID` is always printed.
- `Invoke-OraEnv`: passes `-Verbose` through to `Set-OracleEnv` so that `oraset -v`
  and `oraset <SID> -v` display all three environment variables.
- Manifest: added `FileList` to restrict the published PSGallery package to module source
  files only — excludes `.git`, `Tests`, `Docs`, `scripts`, and build artifacts.
- Manifest: `ProjectUri` and `LicenseUri` updated to
  `https://github.com/scottyleblanc/TACE.Oracle.Admin` with branch `master`.
- `README.md`: added Session Usage section documenting PowerShell session scope,
  the `$env:` prefix requirement, and a real Linux example.
- `.gitignore`: added `build/`; `Docs/HANDOFF.md` and `Docs/Publish-Steps.md` removed
  from the repository (ephemeral planning docs).
- Unit test count: 102 → 117 (all passing).
- Module renamed for publication: `OracleAdmin.psd1` → `TACE.Oracle.Admin.psd1`,
  `OracleAdmin.psm1` → `TACE.Oracle.Admin.psm1`, repo folder `OracleAdmin\` →
  `TACE.Oracle.Admin\`. `RootModule`, all file headers and `.NOTES` blocks, and the
  `Import-Module` path and `-ModuleName` references in all test files updated to match.
- Manifest: `Tags` expanded — added `Windows`, `Linux`, `OracleDB`, `PowerShell`.
- Manifest: `Invoke-OraEnv` retained in `FunctionsToExport`. PowerShell resolves
  exported alias targets in the caller's scope — if `Invoke-OraEnv` is not exported,
  `oraset` and `oraenv` throw "not recognized" at call time.
- `LICENSE`: effective date filled in (`2026-03-17`).
- `Docs\README.md`, `PREREQUISITES.md`, `SECURITY.md`, `VERSIONING.md`, `CHANGELOG.md`,
  `TODO.md` — all updated to the `TACE.Oracle.Admin` name.
- PSGallery account confirmed; Publish-scoped API key generated and stored outside
  this repo. Publishing uses `Publish-PSResource` (`Microsoft.PowerShell.PSResourceGet`)
  in place of the `PowerShellGet` 2.x `Publish-Module` steps originally planned.
- Pre-publish validation: `Test-ModuleManifest` passed; `Invoke-ScriptAnalyzer` clean
  apart from 3 Information-level `Join-Path` positional parameter findings in test
  files (accepted); `Invoke-Pester` 101 passed, 0 failed.

### Fixed

- `PSShouldProcess` analyzer finding — removed `SupportsShouldProcess` from `Invoke-OraEnv`.
- `PSAvoidUsingPositionalParameters` in the `.psm1` — `Join-Path` now uses named parameters.

---

## [0.1.4] - 2026-03-13

### Added

- `Get-OracleDatabaseList`: multi-platform support via `$Platform` parameter
  (auto-detected from `$IsWindows`/`$IsLinux`; override with `-Platform` for testing).
  - Windows path: existing `Win32_Service` discovery, unchanged.
  - Linux path: parses `/etc/oratab`; derives `OracleHome` from the file directly and
    `OracleBase` via string split (preserves `/` on all platforms); determines `Status`
    by checking for an `ora_pmon_<SID>` process; `ServiceName` is `$null`.
  - Unsupported platform: returns `Success=$false` with a descriptive message.
- Unit test count: 82 → 102 (all passing). New contexts cover Linux oratab happy path,
  file not found, comment/blank line skipping, malformed lines, wildcard SID entries,
  `Get-Content` failure, and unsupported platform.
- `VERSIONING.md`: documented branch/tag naming convention (`vX.Y.Z-dev` for branches,
  `vX.Y.Z` for tags) to prevent push ambiguity.
- Project documentation updated for the multi-platform release.

---

## [0.1.3] - 2026-03-13

### Changed

- `Get-OracleDatabaseList`: switched service discovery from `Get-Service` to
  `Get-CimInstance Win32_Service` to expose the `PathName` (service executable path).
  `ORACLE_HOME` is now derived from `PathName` by stripping `\bin\ORACLE.EXE`.
  `ORACLE_BASE` is derived from `ORACLE_HOME` by stripping `\product\{version}\{home}`.
  Both values are added to each Data entry as `OracleHome` and `OracleBase`.
  Returns `$null` for either field if `PathName` cannot be parsed.
- `Set-OracleEnv`: now sets `$env:ORACLE_HOME` and `$env:ORACLE_BASE` from the
  resolved instance's discovered values. Warns (but still sets `ORACLE_SID`) if
  either value cannot be determined. Returns `OracleHome` and `OracleBase` in
  the `Data` object.
- Unit test count: 70 → 82 (all passing). New tests cover `OracleBase` derivation,
  quoted and unquoted `PathName` parsing, null `PathName` handling, and
  `$env:ORACLE_BASE` set/not-set behaviour.
- Project documentation updated for the environment variable derivation.

---

## [0.1.2] - 2026-03-12

### Changed

- `README.md`: added AI-assisted development and support guidance section.
- `LICENSE`: incorporated AI language.

---

## [0.1.1] - 2026-03-11

### Added

- `Invoke-OraEnv` (`Private\Invoke-OraEnv.ps1`) — interactive wrapper for
  `Set-OracleEnv` that discards the return object for clean terminal output.
  Writes `[ERROR]` to host on failure. Target of the `oraset` and `oraenv` aliases.
- `oraset` and `oraenv` aliases registered in `OracleAdmin.psm1` and exported
  via `OracleAdmin.psd1`.
- `Tests\OracleAdmin.Module.Tests.ps1` — module-level tests verifying both
  aliases exist, resolve to `Invoke-OraEnv`, and are exported by the module.

### Fixed

- `Set-OracleEnv`: service status check now applies to both the interactive
  menu path and the `-SID` parameter path; previously only checked on the
  parameter path.
- `Set-OracleEnv`: `Write-Host` confirmation now emits before `Write-Warning`
  so the SID confirmation always appears first.
- `Set-OracleEnv`: initialize `$serviceWarning = $null` to satisfy
  `Set-StrictMode -Version Latest` on the interactive menu path.
- `Set-OracleEnv`: `Write-Host` output changed from
  `[Set-OracleEnv] ORACLE_SID = <SID>` to `ORACLE_SID set to '<SID>'`.
- `Set-OracleEnv`: service-stopped warning shortened to
  `[Set-OracleEnv] OracleService<SID> is Stopped.`

---

## [0.1.0] - 2026-03-11

### Added

- Module scaffold: `OracleAdmin.psm1`, `OracleAdmin.psd1`, `Public\`, `Private\`,
  `Tests\`, `Docs\` directories.
- `Get-OracleDatabaseList` — discovers Oracle database instances on the local
  Windows host via `OracleService*` service query. Returns SID, Status, and
  ServiceName. Migrated and hardened from `powershell\functions\get-oracledatabaselist.ps1`.
- `Set-OracleEnv` — sets `ORACLE_SID` for the current session. Validates SID
  against discovered instances. Auto-selects when one instance found; presents
  numbered menu when multiple instances found. Warns on stopped service but
  allows the set. Session-only — no disk writes.
- Unit tests for both public functions (`Tests\*.Tests.ps1`). Pester suite run;
  all tests passing.
- Required project documentation: `README.md`, `SECURITY.md`, `CHANGELOG.md`,
  `VERSIONING.md`, `PREREQUISITES.md`, `TODO.md`.
- Local shell profiles (`profile.ps1`, `profile.common.ps1`, outside this repo)
  updated to import the module and alias `oraset`.
- Git repository initialised; initial commit.

### Security

- Confirmed no credential leakage in `Message`, verbose output, or pipeline output.
