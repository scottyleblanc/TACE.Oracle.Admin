# TACE.Oracle.Admin — Stage Roadmap

Tasks are ordered top-to-bottom. Each stage depends on the one above being stable.
`[SEC]` items are first-class requirements — no stage is complete until its `[SEC]`
items are checked off.

---

## Stage 1 — Foundation (v0.1.0) — COMPLETE

See `CHANGELOG.md` for the completed work.

---

## Stage 1.3 — Environment Variable Derivation (v0.1.3) — COMPLETE

See `CHANGELOG.md` for the completed work.

---

## Stage 1.4 — Multi-Platform Discovery (v0.1.4) — COMPLETE

See `CHANGELOG.md` for the completed work.

---

## Stage 2 — PSGallery Publication (v0.1.5, v0.1.6) — COMPLETE

See `CHANGELOG.md` for the completed work (entries 0.1.5 and 0.1.6).

---

## AI Development Stack (Stack 0 – Stack 10)

Stack stages are numbered `Stack N` to keep them distinct from the module's own
`Stage N` history above. They come before Stage 3: new functions are added only
once the stack is in place to check them.

### The question

What can a senior DBA do to make AI-generated code as correct, secure, safe,
consistent, and supportable as possible — and which practices would a senior
software engineer apply as a matter of course?

### The layer model

Each layer catches what the one before it missed. None depends on the author,
human or AI, being careful on the day.

| Layer | Name | What it is |
|---|---|---|
| 1 | Intent | What the code must do and must never do, written before generation |
| 2 | Agent instructions | The standards the AI is given, from one canonical source |
| 3 | Deterministic checks | Linter, formatter, secret scanning |
| 4 | Tests | Unit, invariant, integration, soak |
| 5 | Independent review | A second AI session that did not write the code, then a human |
| 6 | Enforced gate | Automation that runs the checks and blocks the merge |
| 7 | Agent containment | What the AI may touch, run, and read |
| 8 | Release and supportability | Versioning, changelog, packaging, runbooks |
| 9 | Feedback loop | Every escaped defect becomes a new check |

### Build rules

- **One layer at a time.** A stack stage is finished before the next begins.
- **Enforcement before more rules.** The gate is built early; later layers are
  measured against it. The build order below is therefore not the layer order.
- **Deterministic before AI-judged.** A linter gives the same answer every time.
- **Checks live in repo scripts.** The CI file is a thin wrapper that calls them,
  so the stack can move to another platform without a rewrite.
- **Seeded defect.** Each stage plants a deliberate violation on a throwaway
  branch — the kind that layer exists to catch. The stage is not done until the
  layer catches it. Results are recorded in `Docs\audit\`.
- **Write-up.** Each stage closes with a post and a project page update on
  tacedata.ca.

### Test bed

This module is the shell. Three functions from the Oracle backup module are
copied in as working examples — one read-only, one state-changing, one that
handles credentials — with their private helpers and tests. Integration and
soak tests run locally against an Oracle database; they do not run in public CI.

### Stage overview

| Stack | Name | Layer | Status |
|---|---|---|---|
| 0 | Setup and scope | — | Complete (v0.2.0) |
| 1 | Intent | 1 | Complete (v0.2.1) |
| 2 | Deterministic checks | 3 | Complete (v0.2.2) |
| 3 | Tests | 4 | Not started |
| 4 | Enforced gate | 6 | Not started |
| 5 | Agent instructions | 2 | Not started |
| 6 | Independent review | 5 | Not started |
| 7 | Containment | 7 | Not started |
| 8 | Release | 8 | Not started |
| 9 | Feedback loop | 9 | Not started |
| 10 | Wrap-up | — | Not started |

Version numbers are assigned at stage close per `VERSIONING.md`; the scheme for
stack stages is confirmed during Stack 0.

---

### Stack 0 — Setup and scope

**Goal:** a working test bed with a recorded baseline, before any layer is built.

**Deliverables:** example functions, helpers and tests copied in; baseline
numbers recorded; version scheme for stack stages agreed.

**Done when:** the examples load and their existing tests pass; the baseline
(unit test count, analyzer findings by rule) is recorded; all `[SEC]` items
are checked off.

---

### Stack 1 — Intent (layer 1)

**Goal:** the rules exist in writing before anything enforces them.

**Deliverables:** `Docs\standards\` with the ratified standards, one file per
topic; invariants written into an `# INVARIANTS` block in each function body, in
the code, with an ID each; a script that lists every invariant and whether a test cites it.

**Done when:** every function has written invariants; every candidate standard
is ratified, rejected or deferred; each standard is one sentence plus one example.

---

### Stack 2 — Deterministic checks (layer 3)

**Goal:** one command runs every machine check.

**Deliverables:** extended `Tests\Lint\PSScriptAnalyzerSettings.psd1`; custom rules for
house standards that can be machine-checked; secret scanning;
`Scripts\Invoke-Gate.ps1` as the single entry point.

**Done when:** the gate script runs locally with one command; a seeded lint
violation and a seeded secret both fail it.

---

### Stack 3 — Tests (layer 4)

**Goal:** every invariant is proven by a test, and coverage is measured.

**Deliverables:** an invariant-to-test map; a coverage floor that fails the unit tier
(not the gate script, which holds only checks that read source text);
a local-only integration tier (soak tests dropped from Stack 3)
behind a separate gate-script switch.

**Done when:** the map is complete; a seeded behaviour defect fails the gate run with
`-Unit`;
the integration tier runs locally with one command.

---

### Stack 4 — Enforced gate (layer 6)

**Goal:** a failing change cannot reach `master`.

**Deliverables:** `.github\workflows\gate.yml` that only calls the gate script, with
`-Unit`;
branch protection requiring a pull request and passing checks.

**Done when:** a pull request carrying the seeded defects from Stack 2 and
Stack 3 is blocked from merging.

---

### Stack 5 — Agent instructions (layer 2)

**Goal:** the AI is told the standards, from the same source the gate enforces.

**Deliverables:** agent instruction files for each AI tool in use, generated
from `Docs\standards\`; a comparison of gate failures for the same small
generation task with and without the instructions.

**Done when:** every instruction file derives from the one source; the
comparison is recorded.

---

### Stack 6 — Independent review (layer 5)

**Goal:** the author of the code is never its only examiner.

**Deliverables:** pull request template; a review order (intent, then tests,
then implementation); a second-model review as a script step; a human checklist.

**Done when:** one pull request goes through the full review path with the
findings attached.

---

### Stack 7 — Containment (layer 7)

**Goal:** the AI can reach only what the task needs.

**Deliverables:** committed agent permission settings; ignore files covering
credential material; written rules for what the agent may run or read.

**Done when:** a seeded attempt to read ignored material is blocked.

---

### Stack 8 — Release (layer 8)

**Goal:** a release cannot go out inconsistent or with stray files.

**Deliverables:** gate checks for version agreement (manifest, tag, changelog),
`FileList` completeness and package contents; refreshed signing and publish
guidance.

**Done when:** a seeded version mismatch and a seeded stray file both fail the gate.

---

### Stack 9 — Feedback loop (layer 9)

**Goal:** the stack gets stronger each time something escapes it.

**Deliverables:** an escaped-defect log in `Docs\audit\` under the rule "each
entry ends in a new check"; one ownership drill — a seeded defect located and
fixed using only the committed docs and tests.

**Done when:** at least one log entry has become a check; the drill result is
recorded.

---

### Stack 10 — Wrap-up

**Goal:** the stack can be reused on another repo.

**Deliverables:** the reusable parts (gate script, settings, templates, CI
wrapper) lifted into a template; a summary write-up answering the question
layer by layer.

**Done when:** the template produces a working gate on a fresh, empty repo, and
on a file copy of an existing private module repo: one with a class, its own
packaging step and a host other than GitHub.

---

## Stage 3 — Future Functions (TBD)

Built through the stack, after Stack 10.

- [ ] `Get-OracleStatus` — report instance open mode, database role, archivelog mode
- [ ] `Test-OracleConnection` — validate connectivity via OS auth; return structured result
- [ ] Additional DBA utility functions (to be defined)
