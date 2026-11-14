# TODO — TACE.Oracle.Admin

Tasks are ordered top-to-bottom. Each stage depends on the one above being stable.
`[SEC]` items are first-class requirements — no stage is complete until its `[SEC]`
items are checked off.

---

Completed work for Stage 1, Stage 1.3, Stage 1.4 and Stage 2 is recorded in
`CHANGELOG.md` (versions 0.1.0 to 0.1.7).

---

## AI Development Stack

Goals, deliverables and definitions of done are in `STAGES.md`. Every stack stage
ends with the same three closing tasks: record the seeded-defect result in
`Docs\audit\`, update `CHANGELOG.md` and tag, and publish the write-up.

### Stack 0 — Setup and scope

- [x] Record the plan in `STAGES.md` and `TODO.md`
- [x] Sync the local clone of the Oracle backup module with its remote
- [x] Decide what happens to the parked standards-audit work: reuse, merge or leave —
      discarded from this repo; kept privately as reference for Stack 1
- [x] [SEC] Move untracked local working files out of the repo tree so they cannot
      be committed by mistake
- [ ] [SEC] Review the earlier standards variance notes for sensitive detail before
      any part of them is committed to this public repo
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

- [x] List the candidate standards; mark each ratified, rejected or deferred —
      see `Docs\standards\decisions.md`
- [x] Write the ratified standards to `Docs\standards\`, one sentence plus one example each
- [ ] Settle the four open items in `Docs\standards\decisions.md`
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
- [ ] Decide the findings below: fix, or accept as a limitation
- [ ] Seeded defect: a function with no block, and a malformed entry, both fail the
      static tier
- [ ] Closing tasks

#### Findings from writing the invariant blocks

Each is recorded as a `Limitation:` in the named block. None is fixed yet. Where one is
fixed, its block entry changes in the same commit.

- [ ] [SEC] `Remove-RmanObsoleteBackup` S7 — `-CatalogConnection` reaches the RMAN
      script after a non-empty check only
- [ ] [SEC] `Remove-RmanObsoleteBackup` S6 — `-CatalogCredential` is accepted and not used
- [ ] [SEC] `Remove-RmanObsoleteBackup` L1 — the environment check runs before the
      confirmation gate, so `-WhatIf` can create the config file and run `tnsping`
- [ ] [SEC] `Get-OracleBackupConfigStore` S4 — an environment variable decides where
      the config file is read from and created
- [ ] [SEC] `Assert-OracleEnvironment` S9 — `tnsping.exe` is not signature-checked
- [ ] `Assert-OracleEnvironment` L1, `Get-RmanBackupStatus` L3, `Remove-RmanObsoleteBackup`
      L2 — the `ORACLE_HOME` fallback is not passed on (suspected; needs a test)
- [ ] `Assert-OracleEnvironment` T2 — error message names a function this module lacks
- [ ] `Set-OracleEnv` R6 — reports success with "ORACLE_SID set to" under `-WhatIf`
- [ ] `Get-RmanBackupStatus` P3, `Remove-RmanObsoleteBackup` P3 — no platform check (rule C-07)
- [ ] `Invoke-TnspingProcess` L1, L2 — output read order and no exit check
- [ ] `Get-OracleDatabaseList` L2 — a failed service query reads as "no instances"

### Stack 2 — Deterministic checks

- [ ] Extend `PSScriptAnalyzerSettings.psd1` from the ratified standards
- [ ] Write custom analyzer rules for house standards that can be machine-checked
- [ ] [SEC] Add secret scanning
- [ ] Create `scripts\Invoke-Gate.ps1` as the single entry point
- [ ] Seeded defects: one lint violation, one planted secret
- [ ] Closing tasks

### Stack 3 — Tests

- [ ] Map every invariant to at least one Pester test; fill the gaps
- [ ] [SEC] Every security invariant has a test in a `Security` context
- [ ] Measure coverage; set a floor in the gate script
- [ ] Unit tests pass on Windows and Linux
- [ ] Install the Oracle database chosen in Stack 0; confirm version and edition
- [ ] Add the local-only integration and soak tier behind a gate-script switch
- [ ] Decide how a local integration result is attached to a pull request
- [ ] Seeded defect: one behaviour change that breaks an invariant
- [ ] Closing tasks

### Stack 4 — Enforced gate

- [ ] Add `.github\workflows\gate.yml` calling only the gate script
- [ ] Turn on branch protection: pull request required, checks required
- [ ] [SEC] Workflow runs with least privilege and no stored secrets
- [ ] Seeded defects from Stack 2 and Stack 3 are blocked at merge
- [ ] Closing tasks

### Stack 5 — Agent instructions

- [ ] Generate agent instruction files from `Docs\standards\`
- [ ] Run one small generation task with and without them; compare gate failures
- [ ] Closing tasks

### Stack 6 — Independent review

- [ ] Add a pull request template
- [ ] Write the review order and the human checklist
- [ ] Choose the second-model review mechanism; add it as a script step
- [ ] Take one pull request through the full path with findings attached
- [ ] Closing tasks

### Stack 7 — Containment

- [ ] Commit agent permission settings
- [ ] [SEC] Add ignore files covering credential material
- [ ] [SEC] Write the rules for what the agent may run or read
- [ ] Seeded defect: an attempt to read ignored material
- [ ] Closing tasks

### Stack 8 — Release

- [ ] Gate check: version agreement across manifest, tag and changelog
- [ ] [SEC] Gate check: `FileList` completeness and package contents
- [ ] Refresh the signing and publish guidance in `SECURITY.md`
- [ ] Seeded defects: a version mismatch and a stray file
- [ ] Closing tasks

### Stack 9 — Feedback loop

- [ ] Start the escaped-defect log in `Docs\audit\`
- [ ] Convert at least one entry into a check
- [ ] Run one ownership drill; record the result
- [ ] Closing tasks

### Stack 10 — Wrap-up

- [ ] Lift the gate script, settings, templates and CI wrapper into a template
- [ ] Prove the template on a fresh, empty repo
- [ ] Write-up: final project page and summary post

---

## Stage 3 — Future Functions (TBD)

Built through the stack, after Stack 10.

- [ ] `Get-OracleStatus` — report instance open mode, database role, archivelog mode
- [ ] `Test-OracleConnection` — validate connectivity via OS auth; return structured result
- [ ] Additional DBA utility functions (to be defined)
