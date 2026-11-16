# TODO — TACE.Oracle.Admin

Tasks are ordered top-to-bottom. Each stage depends on the one above being stable.
`[SEC]` items are first-class requirements — no stage is complete until its `[SEC]`
items are checked off.

---

Completed work for Stage 1, Stage 1.3, Stage 1.4 and Stage 2 is recorded in
`CHANGELOG.md` (versions 0.1.0 to 0.1.7).

---

## AI Development Stack

Each stack section opens with a goal: what its items accomplish when they are all
checked off. Deliverables and definitions of done are in `STAGES.md`. Every stack stage
ends with the same three closing tasks: record the seeded-defect result in
`Docs\audit\`, update `CHANGELOG.md` and tag, and publish the write-up.

### Stack 0 — Setup and scope

**Goal:** three example functions, with their helpers and tests, run in this repo, and
the starting unit-test count and analyzer findings are recorded as the baseline every
later stage is measured against.

- [x] Record the plan in `STAGES.md` and `TODO.md`
- [x] Sync the local clone of the Oracle backup module with its remote
- [x] Decide what happens to the parked standards-audit work: reuse, merge or leave —
      discarded from this repo; kept privately as reference for Stack 1
- [x] [SEC] Move untracked local working files out of the repo tree so they cannot
      be committed by mistake
- [x] [SEC] Review the earlier standards variance notes for sensitive detail before
      any part of them is committed to this public repo — closed at Stack 1 as not
      applicable: no part of them was committed. They stay in the private archive, and
      the Stack 1 standards were written fresh
- [x] Select three example functions: one read-only, one state-changing, one on the
      credential-handling path; list the private helpers each depends on —
      `Get-RmanBackupStatus`, `Remove-RmanObsoleteBackup`, `Invoke-RmanProcess`;
      see `Docs\audit\stack-0-baseline.md`
- [x] Copy functions, helpers and tests into `Public\`, `Private\` and `Tests\`;
      update `FunctionsToExport` and `FileList`
- [x] Record the baseline: unit test count, PSScriptAnalyzer findings by rule
- [x] Decide how the Oracle database for the integration tier is provided and which
      version, against the 19c target — Oracle Database Express Edition, installed
      locally; version confirmed in Stack 3
- [x] Confirm the version scheme for stack stages; record it in `VERSIONING.md` —
      Stack 0 is `v0.2.0`; later stack stages are patch releases
- [x] Unit suite passes (291 of 291)
- [x] Update `README.md`, `Docs\README.md`, `Docs\SECURITY.md` and
      `Docs\PREREQUISITES.md` for the two new public functions and the
      credential-handling path
- [x] Write-up: project page status and Stack 0 post

### Stack 1 — Intent

**Goal:** every rule the code must follow is specified — the ratified standards, and
an invariant block in every function naming what enforces each entry — and every gap
found while specifying them is either fixed or accepted as a stated limitation.

- [x] List the candidate standards; mark each ratified, rejected or deferred —
      see `Docs\standards\decisions.md`
- [x] Write the ratified standards to `Docs\standards\`, one sentence plus one example each
- [x] Settle the four open items in `Docs\standards\decisions.md` — decisions 15 to 18:
      test runners (T-10), module layout (C-28, C-29), aliases (C-30), `Write-Host` (C-31)
- [x] Settle the invariant block format: sections, identifiers, and how each entry
      names what enforces it — `Docs\standards\invariants.md`
- [x] Write an `# INVARIANTS` block into each function body: what must hold before,
      during and after, each entry with an ID — 149 invariants in 13 functions
- [x] [SEC] Write the security invariants: stdin-only credential handling, no
      credential fragments in `Message`, verbose or error output, no session
      environment changes — 54 security invariants
- [x] Add a script that lists every invariant and what enforces it —
      `scripts\Invoke-InvariantLint.ps1`, index in `Docs\standards\invariants-index.md`
- [x] [SEC] Check that every test cited for a security invariant would fail if the
      invariant were broken — five citations withdrawn and marked `Test: none yet`
- [x] Decide the findings below: fix, or accept as a limitation — all decided; one
      accepted as a limitation, the rest fixed with tests
- [x] Seeded defect: a function with no block, and a malformed entry, both fail the
      static tier — both exit 1 on the rule-specific check; recorded in
      `Docs\audit\stack-1-seeded-defects.md`
- [x] Closing tasks

#### Findings from writing the invariant blocks

Each was recorded as a `Limitation:` in the named block. A fixed finding's entry now
names the test or guard that enforces it; an accepted one stays a `Limitation:` with its
reason. Items marked "found while" were discovered while working on the one above.

- [x] [SEC] `Remove-RmanObsoleteBackup` S7 — `-CatalogConnection` reaches the RMAN
      script after a non-empty check only — parameter removed; S9 added
- [x] [SEC] `Remove-RmanObsoleteBackup` S6 — `-CatalogCredential` is accepted and not
      used — parameter removed; S9 added
- [x] [SEC] `Remove-RmanObsoleteBackup` L1 — the environment check runs before the
      confirmation gate, so `-WhatIf` can create the config file and run `tnsping` —
      gate moved first; L1 now has a test
- [x] [SEC] `Get-OracleBackupConfigStore` S4 — an environment variable decides where
      the config file is read from and created — replaced by a module-scoped test
      override; S4 now has a test
- [x] [SEC] `Assert-OracleEnvironment` S9 — `tnsping.exe` is not signature-checked —
      accepted as a limitation: Oracle binaries are unsigned, so the check would add
      nothing. S4 and S9 reworded to say so
- [x] `Assert-OracleEnvironment` L1, `Get-RmanBackupStatus` L3, `Remove-RmanObsoleteBackup`
      L2 — the `ORACLE_HOME` fallback is not passed on (suspected; needs a test) —
      confirmed: both functions failed on parameter binding. Callers now derive the
      home from the validated binary path; L2 and L3 have tests
- [x] `Get-OracleBackupConfigStore` R1 — found while confirming the item above: a config
      file missing any setting failed to load under StrictMode instead of taking the
      default. Fixed; R1 has a test
- [x] `Assert-OracleEnvironment` T2 — error message names a function this module lacks —
      message now names the config file and `ORACLE_HOME`; T2 has a test
- [x] `Set-OracleEnv` R6 — reports success with "ORACLE_SID set to" under `-WhatIf` —
      new rule C-27: a declined `ShouldProcess` returns a successful preview with
      `Data.Applied = $false` and a `WhatIf:` Message. Applied to `Set-OracleEnv` and
      `Remove-RmanObsoleteBackup` (whose R3 returned `Success = $false`); both tested
- [x] `Get-RmanBackupStatus` P3, `Remove-RmanObsoleteBackup` P3 — no platform check (rule
      C-07) — both return `Success = $false` off Windows before touching the config or
      RMAN, through a mockable `Test-WindowsPlatform` helper; P3 tested in both.
      Linux stays out of scope; see Post-Project Notes
- [x] `Invoke-TnspingProcess` L1, L2 — output read order and no exit check — worse than
      recorded: the synchronous stdout read blocked before the 30-second wait, so a hung
      tnsping hung its caller indefinitely. Now reads both streams asynchronously, kills
      the process tree on timeout, and takes `-TimeoutSeconds`; L1, L2, S1, R1 and the
      new L4 have tests that run the real helper
- [x] `Invoke-RmanProcess` T1, L5 — found while fixing the item above: a timeout killed
      only the RMAN process, not its tree, with no guard around `Kill()` and no wait
      after it. Fixed to the same pattern; T1 and T2 have a test
- [x] `Invoke-RmanProcess` and `Invoke-TnspingProcess` L4 — child `PATH` now built with
      `Join-Path` and `[System.IO.Path]::PathSeparator`, under the exact name `PATH`
- [x] `Get-OracleDatabaseList` L2 — a failed service query reads as "no instances" —
      the query now uses `-ErrorAction Stop`, so any error returns `Success = $false`;
      a query that matches nothing still returns an empty result. L2 has a test

### Stack 2 — Deterministic checks

**Goal:** one command, `Scripts\Invoke-Gate.ps1`, runs every static check — the
analyzer, the house rules, secret scanning and the `-WhatIf` checks — and fails on a
planted lint violation and a planted secret.

- [x] Move to the `Source\` layout first (rules C-28, C-29; decision 16), so every
      check below is written once, against the final layout:
      - `Public\` and `Private\` moved under `Source\`; `Invoke-OraEnv` moved to
        `Source\Public\`; no `Source\Classes\` until a class exists
      - `Scripts\Build-Module.ps1` merges `Source\` (classes, private, public) into one
        `.psm1` under `Output\TACE.Oracle.Admin\<version>\`, with `FileList`,
        `FunctionsToExport` and `AliasesToExport` generated (aliases from `[Alias()]`
        attributes, rule C-30); `Output\` is gitignored; `-Package` packages from it
      - Tests moved to `Tests\Unit\Public\` and `Tests\Unit\Private\`, plus
        `Tests\Unit\Module\` for the module-level test, and import the built module
        through `Tests\Unit\Get-BuiltModulePath.ps1`; the unit runner builds first
      - Linters live in `Tests\Lint\`, custom analyzer rules in
        `Tests\Lint\PSScriptAnalyzerRules\` (decision 22); folders are PascalCase
        throughout, so `scripts\` became `Scripts\` (decision 21)
      - The config path moved into the version folder, so S4 holds (decision 23)
      - Updated with it: both tier scripts and rule T-10, rule T-02, the invariant
        linter's source folders and its source-to-test lookup (I-09), the publish
        script, and the README and PREREQUISITES instructions. `Test-LinuxBuild.ps1`
        installs from the package and needed only its example path changed
- [x] Extend `Tests\Lint\PSScriptAnalyzerSettings.psd1` from the ratified standards
      (decision 25):
      - Settings moved from the repository root to `Tests\Lint\`, and out of the package;
        a committed `.vscode\settings.json` points the editor at them
      - PSScriptAnalyzer pinned to 1.25.0. Coverage is `Source\`, `Scripts\` and
        `Tests\Lint\`, not `*.Tests.ps1`. Every finding fails, Information included
      - `Scripts\` console tools carry one script-level `Write-Host` suppression each
      - Built-in rules cover C-04, C-06, C-31, S-01, S-03 and S-13. C-05, C-09, C-10,
        C-11, C-14, C-15, C-17 and C-18 need custom rules (next item)
      - Fixed in `Source\`: three positional `Join-Path` calls. `Set-RestrictiveAcl` is
        suppressed for `ShouldProcess`, pending the inherited `-WhatIf` item below
      - Minimum PowerShell raised to 7.6 LTS (decision 24); the compatibility rules
        are not used, because their bundled profiles stop at 7.0
      - First run: 130 findings under the old settings and coverage; 0 now, over 22 files.
        The gate's version check comes with `Invoke-Gate.ps1`
- [x] Write custom analyzer rules for house standards that can be machine-checked, in
      `Tests\Lint\PSScriptAnalyzerRules\` (decision 26):
      - [x] Nine rules, one file each: C-05, C-08, C-09, C-10, C-11, C-14, C-15, C-17,
            C-18. Loaded by the settings file next to the built-in rules
      - [x] `Tests\Static\PSScriptAnalyzerRules.Tests.ps1`: what each rule must report and
            what it must not, plus loading and suppression; 44 tests
      - [x] First run: 46 violations of ratified rules that nothing had checked, now fixed:
            25 uses of `$_`, 5 functions without `[OutputType()]`, 2 untyped predicate
            parameters, 1 backtick continuation (splatted now). C-14 was narrowed to path
            contexts after 7 false positives; the one deliberate `-join '/'` is suppressed
            with the reason
      - [x] C-10: three public parameters had no `[Validate*]` attribute.
            `Get-OracleDatabaseList -Platform` takes `ValidateSet('Windows', 'Linux',
            'Unsupported')`: an unknown value now throws, and `'Unsupported'` still
            reaches the C-07 branch. [SEC] `-WalletAlias` on `Get-RmanBackupStatus` and
            `Remove-RmanObsoleteBackup` takes `ValidatePattern('^[A-Za-z0-9_.-]*\z')`,
            so it cannot inject into RMAN's stdin (S6, S10)
      - The static tier takes about 18 s longer: each fixture loads the rule modules
- [x] Static checks for the build's own rules: a public file that defines a second
      function, or a source manifest that declares `FunctionsToExport`, fails the build
      (C-28, C-29). The build enforces both today; nothing proves it does
      - `Tests\Static\BuildModule.Tests.ps1`, 11 tests. Each copies the real
        `Build-Module.ps1` into a minimal repository on `TestDrive` and plants one
        defect: a second function, a misnamed function, no function, no public file,
        or `FunctionsToExport`, `AliasesToExport` or `FileList` in the source manifest
      - A clean fixture is built first and checked for the generated exports, aliases
        (C-30) and file list, and for an empty export list kept as an entry
      - Proven by mutation: removing each of the three build checks fails exactly the
        tests aimed at it
- [x] T-02 check: `Source\Private\ConvertFrom-RmanListBackup.ps1` has no test file of its
      own. Found during the layout move; the T-02 linter check will report it
      - `Tests\Static\SourceTestLayout.Tests.ps1`: one function per source file, named
        for the file (C-03); a test file for each in the mirrored `Tests\Unit\` folder,
        and no test file without a source file (T-02)
      - Run against the previous commit, it reports the three known findings, and
        nothing else
      - Fixed:
        - `Invoke-TnspingProcess` moved out of `Assert-OracleEnvironment.ps1`, and
          `Invoke-CredentialScrub` out of `Invoke-RmanProcess.ps1`, into files of their
          own. Their tests moved with them. These were the C-03 known findings at
          ratification
        - `ConvertFrom-RmanListBackup.Tests.ps1` is new, with 15 tests. R1 to R5 are now
          proven, so 18 invariants are unproven, down from 23
- [x] [SEC] Add secret scanning. The pattern checks for rule S-16 exist
      (`Tests\Static\PublicRepoHygiene.Tests.ps1`); add with them:
      - a general secret scanner for credential formats the patterns do not cover.
        Chosen: gitleaks, pinned to 8.30.1 (PREREQUISITES.md). It runs locally and needs
        no GitHub access. A first scan of all 20 commits and the working tree found
        nothing, so no allowlist is needed yet. `PublicRepoHygiene.Tests.ps1` stays: it
        covers identifiers gitleaks does not treat as secrets
      - ~~a local-only script that checks changed files, the diff and commit messages
        against the private resource list~~ **Deferred: accepted limitation (2026-11-15).**
        Where a private identifier list lives, and its format, affects every public
        repository, not just this one, so it is decided across repositories first.
        Until then, a real resource name that matches no S-16 pattern (a bucket name,
        a host name) is caught only by review. This is how the S3 staging bucket name
        reached this repository's history before v0.2.1. Recorded as an open item in
        `SECURITY.md`
      - a commit-message check, since the static tier reads files only. Built into the
        gate (decision 28). gitleaks does not read commit messages (tested), so each
        unpushed message is piped to `gitleaks stdin` and checked against the S-16
        patterns. Those patterns moved to `Tests\Lint\PublicRepoPatterns.psd1`, shared
        with `PublicRepoHygiene.Tests.ps1`
      - `.gitleaks.toml`: the default rules, plus `Output\` and `Tests\TestResults\`
        skipped, because gitleaks scans a folder without reading `.gitignore`
- [x] Static check: a state-changing call in a function with no `ShouldProcess` gate of
      its own fails the static tier — under an inherited `-WhatIf` it is skipped or
      runs unguarded
      - Rule C-33 (decision 27), custom analyzer rule `Measure-C33ShouldProcessGate`,
        `Source\` only. 11 tests in `Tests\Static\PSScriptAnalyzerRules.Tests.ps1`
      - Found and fixed first: a first run under a caller's `-WhatIf` failed, because the
        default config and its ACL were skipped. The three writes pin `-WhatIf:$false`
        (L1 in `Get-OracleBackupConfigStore` and `Set-RestrictiveAcl`). Run against
        the previous commit, the rule reports exactly those three calls; today it
        reports nothing
- [x] Cleanup of temporary files pins `-WhatIf:$false`, so a preview still removes
      them; checked statically
      - Merged into C-33 as one of its cases. `Source\` has no temporary file cleanup
        today
- [x] Create `Scripts\Invoke-Gate.ps1` as the single entry point (decision 28)
      - Six checks, all run even after a failure: tools (pinned versions), analyzer,
        static tier, gitleaks over the working tree, gitleaks over unpushed commits,
        unpushed commit messages. Exits 1 on any failure; found values are redacted
      - `.githooks\pre-push` runs it before every push, once turned on with
        `git config core.hooksPath .githooks`
      - [x] Turn the hook on in this clone
- [x] Seeded defects: one lint violation, one planted secret
      - `Scripts\Test-SeededDefect.ps1` copies the repository to the temp folder and
        runs the gate four times: clean, a planted `$_`, a token committed in a file,
        and a token in a commit message only. Each must fail exactly the expected
        checks. All four pass
      - Its first run caught a real finding in itself: a helper named `New-` that
        changes nothing. It also showed that "the expected checks are among the
        failures" was too loose a test, so it now requires the exact set
- [x] Closing tasks
      - Seeded-defect result in `Docs\audit\stack-2-seeded-defects.md`
      - `CHANGELOG.md` 0.2.2 and tag `v0.2.2`
      - Write-up: Stack 2 post and project page row

### Stack 3 — Tests

**Goal:** every invariant is proven by a test that fails when the invariant is broken,
coverage cannot fall below a set floor, and
a local tier tests the code against a real Oracle database.

- [x] Map every invariant to at least one Pester test; fill the gaps
  - [x] The map: `Docs\standards\invariants-index.md` now lists each invariant with the
        tests or static checks that prove it, generated by the linter
  - [x] Rule I-11: every entry except a limitation names its proof. A `Type:` or `Guard:`
        line is followed by a `Test:` or `Static:` line. Rule I-12: a `Static:` line cites
        a check in `Tests\Static\SourceInvariants.Tests.ps1` named for the function. Both
        checked by the linter, with fixture tests in `InvariantConformance.Tests.ps1`
  - [x] The 35 `Type:` and `Guard:` entries checked against I-10: 17 cite a test that
        would fail if the invariant broke; 18 are `Test: none yet.`, including every
        entry where an existing test proves only part of it
  - [x] Check the existing citations against I-10. `Scripts\Test-InvariantMutation.ps1`
        breaks each security invariant in a temporary copy and runs its cited tests;
        mutations are in `Tests\Mutation\InvariantMutations.psd1`. First run: 14 of 36
        security mutations survived, across 12 invariants. Nine non-security citations
        were also weak. All fixed; final run 44 of 44 caught. Record in
        `Docs\audit\stack-3-mutation.md`. Rule T-11 (environment sentinels) added
  - [x] Fill the gaps: 35 unproven (15 security), of which 7 are static checks
    - [x] 23 proven by new unit tests, each security one with a mutation: the
          parameter checks, the throw prefixes, the ORACLE_HOME fallback, column
          positions, the default config path, and in `Invoke-RmanProcess` the argument
          list, output and exception scrubbing, verbose output and the stdin sequence
    - [x] The static checks (8 entries), plus three guards a unit test cannot observe:
          the buffer zeroing in `ConvertFrom-SecureStringToPlaintext` (S2) and the
          dispose in `finally` in both process wrappers (L3). Twelve checks in
          `Tests\Static\SourceInvariants.Tests.ps1`, each reading the syntax tree, each
          with a mutation. Built at Scott's request (2026-11-15) for review after the fact
    - [x] `Invoke-RmanProcess` L5: the tree kill can be tested, the "failed kill does
          not replace the timeout error" part cannot without faking .NET. Scott chose to
          split it (2026-11-16): L5 the tree kill, by a unit test; L6 the failed kill or
          wait, by a static check. One proof per entry, so the format is unchanged
- [x] Bring every cited test to rule T-09: rename the cited tests whose title does not
      start with the IDs they prove (54 at the end of Stack 1), tag the security ones
      `SEC`, update the citations, and add the linter check
      - Done 2026-11-16: 95 titles renamed and 26 tags added (the count grew with the
        Stack 3 proofs). The linter now refuses a title or a missing tag that breaks T-09
- [x] `Set-OracleEnv` is documented for scripts and automation, but writes to the host
      and can show a `Read-Host` menu (its L1, L2). Move the menu and host output into
      `Invoke-OraEnv`, the interactive wrapper, so `Set-OracleEnv` is silent and needs
      no `Write-Host` suppression. A behaviour change: decide it with its tests
      - Done as agreed by Scott (2026-11-15). `Set-OracleEnv` with several instances
        and no `-SID` returns `Success = $false` listing them (R7); L1 and L2 retired;
        new L3 (no `Read-Host`, no `Write-Host`) is proven statically with the other
        static rules. `Invoke-OraEnv` owns the menu and host output (R4 to R6, S2
        replacing S1)
- [x] [SEC] Every security invariant has a test in a `Security` context
      - Closed by the tag, not by moving tests (Scott, 2026-11-16). The item predates
        the `SEC` tag. Its aim, that every security invariant is proven and its proof
        can be found, is met by rules T-09 and I-12: each one proven by a unit test or a
        static check cites one tagged `SEC`, the linter refuses one without the tag, and
        `Invoke-Pester -Tag SEC` runs them all. Of 55 security invariants, 34 are proven
        by unit tests, 8 by static checks, and 13 are accepted limitations. 20 of the
        cited unit tests stay in the context whose setup they use; the `Security`
        context keeps the leak checks of rule T-08
- [x] Measure coverage; set a floor in the gate script. The tests import the merged
      `.psm1`, so coverage is reported against `Output\` lines; map it back to `Source\`
      files through the `#region Source\...` markers the build writes
      - Done 2026-11-16 as agreed by Scott. The floor is in `Scripts\Invoke-UnitTest.ps1`,
        not the gate: the gate holds only checks that read source text. Rule T-12.
        Measured 96.7%; five tests added for reachable gaps; now 97.7% (734 of 751
        commands). Floor 95%. Coverage adds about 4 seconds to the unit run
      - One of the new tests found a defect, fixed: `Invoke-OraEnv` with no SID threw
        under StrictMode when discovery failed or found no instance. It came from the
        `Set-OracleEnv` split earlier in this stack
      - The 17 commands left uncovered, by reason:
        - Unreachable from a unit test (13): the logging after a failed kill or wait in
          both process wrappers (8; proven statically, L6); the empty-`PATH` branch in
          both, since .NET always fills the child `PATH` (2); the `$null` fallbacks in
          `Get-OracleDatabaseList` for a path with no parent (2); and one line in
          `ConvertFrom-RmanListBackup` (153) that cannot run at all: once line 150 has
          passed, the length it checks is at least 1. Left in place; removing it is a
          code change, not a test task
        - Linux only (4): the non-Windows skip in `Set-RestrictiveAcl` and three branches
          of the `/etc/oratab` parser. Left for the Linux work in Post-Project Notes
- Unit tests on Linux: moved out of Stack 3 to Post-Project Notes (Scott, 2026-11-16).
  Linux support was put out of scope in Stack 1; running the unit suite on Linux is the
  same work
- [x] Install the Oracle database chosen in Stack 0; confirm version and edition
      - Oracle Database 21c Express Edition, RMAN reports 21.3.0.0.0 (2026-11-16).
        NOARCHIVELOG, RMAN retention REDUNDANCY 1, control file autobackup on
- [x] Add the local-only integration and soak tier behind a gate-script switch
      - Soak dropped from Stack 3 (Scott, 2026-11-16). OS authentication only
      - First runs 2026-11-16: 12 of 12 through the tier script and through the gate
        with `-Integration`. Record in `Docs\audit\stack-3-integration.md`
      - Built: `Scripts\Invoke-IntegrationTest.ps1`, `Invoke-Gate.ps1 -Integration`, and
        `Tests\Integration\` with the five guards of OracleBackup's AD-020 (host
        allowlist, opt-in variable, complete config, database denylist, test folder).
        A failed guard fails the run instead of skipping it. 13 static tests cover the
        guards. Tests for `Get-RmanBackupStatus` and `Remove-RmanObsoleteBackup` take
        control file backups and run a real `DELETE OBSOLETE`, as agreed
- [x] Decide how a local integration result is attached to a pull request
      - Scott chose a committed results file (2026-11-16; decision 30, rule T-14). The
        tier script writes `Tests\Integration\LastRun.json`; it is evidence only for a
        passing run on a clean tree, and is committed last. The staleness check is a
        Stack 4 item, below
- [x] Seeded defect: one behaviour change that breaks an invariant
      - `Get-RmanBackupStatus` loses its CompletionTime sort (breaks R3). The gate with
        the new `-Unit` switch (Scott's choice, decision 31) fails on `unit` alone; the
        one test that fails is the one R3 cites. Added to `Scripts\Test-SeededDefect.ps1`
        as a fifth case; all five pass. Record in `Docs\audit\stack-3-seeded-defect.md`
- [x] Closing tasks
      - [x] Records: `Docs\audit\stack-3-mutation.md`, `stack-3-integration.md`,
            `stack-3-seeded-defect.md`
      - [x] `CHANGELOG.md` 0.2.3 and tag `v0.2.3`
      - [x] Write-up: Stack 3 post and project page row

### Stack 4 — Enforced gate

**Goal:** a change that fails the gate cannot be merged to `master`: CI runs the gate on
every pull request, branch protection requires it to pass, and the workflow holds no
secrets.

- [ ] Add `.github\workflows\gate.yml` calling only the gate script, with `-Unit`
      (decision 31), so a behaviour defect is blocked too
- [ ] Turn on branch protection: pull request required, checks required
- [ ] [SEC] Workflow runs with least privilege and no stored secrets
- [ ] Seeded defects from Stack 2 and Stack 3 are blocked at merge
- [ ] Integration evidence is current (rule T-14, decision 30): when a pull request
      changes `Source\`, `Tests\Integration\LastRun.json` must show `Evidence = true`, and
      nothing but that file may change between the commit it names and the pull request
      head
- [ ] Closing tasks

### Stack 5 — Agent instructions

**Goal:** the AI agent is given the standards through instruction files generated from
`Docs\standards\`, the same source the gate enforces, and their effect on gate failures
is measured.

- [ ] Generate agent instruction files from `Docs\standards\`
- [ ] Run one small generation task with and without them; compare gate failures
- [ ] Closing tasks

### Stack 6 — Independent review

**Goal:** no change is examined only by its author: every pull request follows a fixed
review path — template, human checklist and a second-model review — shown working on
one real pull request.

- [ ] Add a pull request template
- [ ] Write the review order and the human checklist
- [ ] Choose the second-model review mechanism; add it as a script step
- [ ] Take one pull request through the full path with findings attached
- [ ] Closing tasks

### Stack 7 — Containment

**Goal:** the AI agent can run and read only what its committed rules allow; credential
material is outside its reach, and a planted attempt to read it is blocked.

- [ ] Commit agent permission settings
- [ ] [SEC] Add ignore files covering credential material
- [ ] [SEC] Write the rules for what the agent may run or read
- [ ] Seeded defect: an attempt to read ignored material
- [ ] Closing tasks

### Stack 8 — Release

**Goal:** the gate refuses a release whose version differs between manifest, tag and
changelog, or whose package contains a file not listed in `FileList`.

- [ ] Gate check: version agreement across manifest, tag and changelog
- [ ] [SEC] Gate check: `FileList` completeness and package contents
- [ ] Refresh the signing and publish guidance in `SECURITY.md`
- [ ] Seeded defects: a version mismatch and a stray file
- [ ] Closing tasks

### Stack 9 — Feedback loop

**Goal:** every defect that escapes the stack becomes a new check, and the committed
docs and tests alone are shown to be enough to find and fix a planted defect.

- [ ] Start the escaped-defect log in `Docs\audit\`
- [ ] Convert at least one entry into a check
- [ ] Run one ownership drill; record the result
- [ ] Closing tasks

### Stack 10 — Wrap-up

**Goal:** the gate script, settings, templates and CI wrapper work as a reusable
template, proven by producing a working gate on a fresh, empty repo and on an existing
repo, and the project is written up.

- [ ] Lift the gate script, settings, templates and CI wrapper into a template
- [ ] Prove the template on a fresh, empty repo
- [ ] Prove the template on a file copy of an existing private module repo (a class, its
      own packaging step, a host other than GitHub); refresh the copy after that repo's
      source-layout move lands
- [ ] Write-up: final project page and summary post

---

## Stage 3 — Future Functions (TBD)

Built through the stack, after Stack 10.

- [ ] `Get-OracleStatus` — report instance open mode, database role, archivelog mode
- [ ] `Test-OracleConnection` — validate connectivity via OS auth; return structured result
- [ ] Additional DBA utility functions (to be defined)

---

## OracleBackup Migration (after Stack 10)

All of `OracleBackup` moves into this module once the current stack scope is complete.
Each function comes in through the stack's checks, with its own invariant block.

- [ ] [SEC] Carry the Stack 1 config-path fix across: `Set-OracleBackupConfig` and any
      other config reader or writer use the fixed module path and
      `$script:ConfigPathOverride`, never `ORACLE_BACKUP_CONFIG_PATH`. In `OracleBackup`
      today, `Set-OracleBackupConfig` also writes to the path that variable names
- [ ] [SEC] Re-check each Stack 1 finding fixed here against the incoming copy of the
      same function, so an older version does not bring a fixed defect back
- [ ] Config file location: `Get-OracleBackupConfigStore` writes
      `Config\OracleBackup.json` inside the module folder. A module installed for all
      users lives under `Program Files`, which an ordinary user cannot write, so the
      first call there fails. Since Stack 2 the folder is the version folder, so a
      rebuild or an upgrade also starts with no config file (decision 23). Choose a
      per-user or per-machine location that outlives a version before the config writer
      moves in

---

## Backlog — Outside the AI Development Stack Project

Not part of the stack or the OracleBackup migration. Recorded so the idea is not lost.

- [ ] [SEC] Binary write-permission check: fail when `ORACLE_HOME\bin` or a resolved
      binary is writable by `Users`, `Authenticated Users` or `Everyone`. Survives
      patching; does not depend on the file owner
- [ ] [SEC] Binary baseline: record SHA-256 of the binaries the module runs, with the
      patch level, in a restricted file; fail on mismatch with a message that says to
      update the baseline after patching. Needs a `ShouldProcess` update command and a
      step in the patch runbook

---

## Post-Project Notes — Linux Support

The RMAN functions are Windows only for now, and guarded (rule C-07). Notes for a later
port; no code is planned. `Get-OracleDatabaseList` and `Set-OracleEnv` already support
Linux through `oratab`. Porting the OracleBackup functions as they move in would share
this work.

- Binary names: `rman.exe` and `tnsping.exe` are hard-coded in `Assert-OracleEnvironment`;
  Linux uses `rman` and `tnsping`. Choose the name by platform
- Child `PATH`: done in Stack 1. Both process helpers use `Join-Path`,
  `[System.IO.Path]::PathSeparator` and the exact name `PATH` (environment names are
  case-sensitive off Windows). Keep that pattern in any process helper that moves in
- Binary integrity: `Get-AuthenticodeSignature` is Windows only. On Linux the
  write-permission check in the backlog above is the replacement
- Config file permissions: `Set-RestrictiveAcl` does nothing off Windows, so the config
  file is left at the umask default. Set mode `600` on Linux
- Default paths: the config defaults are under `C:\app\oracle`. Linux needs its own, for
  example under `/u01/app/oracle`
- Remove the C-07 guard from each function as it is ported, with a Linux test tier
- Unit tests on Linux (moved here from Stack 3). Every test that starts a fake RMAN or
  tnsping writes a `.cmd` file, so those tests are Windows only; they need a shell-script
  equivalent. The 4 Linux-only commands left uncovered (rule T-12) are covered then
