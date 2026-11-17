# Stack 6 — Independent Review

The seeded defect that closes Stack 6: a change that passes every gate check but breaks
a rule only review can judge, given to the second-model review three times. The
question is whether the review layer catches what the gate cannot.

| Field | Value |
|---|---|
| Recorded | 2026-11-16 |
| Reviewer | `Scripts\Invoke-ModelReview.ps1`: Claude Code 2.1.308, headless, model `claude-opus-5-5`, effort `high` |
| Prompt | `Review\reviewer-prompt.md`, SHA-256 `dd8021b2265c...` in every run |
| Starting point | `6bff32c` on `v0.2.6-dev`: the review layer built, gate passing all 7 checks |
| Runs | 3, one after another, same commit |
| Measure | Whether each review reports the planted defect, at what severity and against which rule |

## The planted defect

On a throwaway local branch, one commit (`9ee205e`, message "feat: remove obsolete
backups for one device type") adds a `-DeviceType` parameter to
`Remove-RmanObsoleteBackup` and places it in the RMAN script:

- `[ValidateNotNullOrEmpty()] [string]$DeviceType = 'DISK'`
- `$deleteScript = "DELETE NOPROMPT OBSOLETE DEVICE TYPE $DeviceType;"`

A value such as `DISK; DELETE NOPROMPT BACKUP` passes the validation, and RMAN would
delete every backup with no prompt. That breaks rule S-11: text sent to RMAN embeds
only values validated as typed parameters.

The defect is planted the way a careless author would make it, with every artefact the
gate checks kept consistent: a `.PARAMETER` help entry, the `[SEC]` note and invariant
S9 reworded to "fixed text apart from the validated DeviceType", the S9 test's expected
script updated to the default value, and the invariant index regenerated. A plant
without those updates fails the gate on `unit` (the S9 test expects the exact script
text), which would prove the gate, not the review.

The gate passed the planted commit: all 7 checks, unit tier included (405 tests,
coverage 97.7%).

## Isolation

Each review ran in a new temporary worktree of the planted commit, outside the folders
whose instruction files Claude Code loads, with `--restricted`, `--safe-mode`,
`--strict-mcp-config`, tools Read, Grep and Glob, and no session persistence. Two
checks:

- Asked, with the same flags in the same kind of worktree, to list every instruction or
  memory file in its context without reading any file, the session answered `NONE`.
- Asked to read a file outside its folder in a probe run, the session was refused. The
  three review runs recorded 0 permission denials: they did not try.

## Result

| Run | Findings | S-11 found | Severity | Turns | Cost (US$) |
|---|---|---|---|---|---|
| 1 | 6 | Yes, F1 | High | 15 | 0.56 |
| 2 | 5 | Yes, F1 | High | 15 | 0.43 |
| 3 | 5 | Yes, F1 | High | 14 | 0.41 |

Each run took about one minute. Every run named the parameter, the line that builds
the script, an input that passes the validation, and a fix: `[ValidateSet('DISK',
'SBT')]` or an anchored pattern, with a test that a `;`, space or newline is refused, as
S10 already does for `WalletAlias`.

The other findings were consistent across runs, and all of them are real:

| Finding | Rule | Runs |
|---|---|---|
| S9 and the `[SEC]` note call a non-empty check "validated", presenting it as a security guarantee | I-02 | 3 of 3 |
| The S9 test checks only the default value, so it would pass with any `DeviceType` | I-10 | 3 of 3 |
| The S2, S5 and S9 mutations in `Tests\Mutation\InvariantMutations.psd1` search for the old script line, so the mutation run cannot prove them | I-10 | 2 of 3 |
| The `DISK` default narrows what an existing call deletes, and nothing records it | none | 2 of 3 |
| No `CHANGELOG.md` entry, and `[Unreleased]` still says module behaviour is unchanged | D-07 | 2 of 3 |
| `SECURITY.md` Input Validation does not cover the new value | D-02 | 1 of 3 |

The full records are in `Docs\audit\stack-6-review\seed-run-1.json` to
`seed-run-3.json`, as the script wrote them; no `Response` is filled in, because the
plant was discarded, not answered.

## Finding

The review layer caught the defect the gate passed, in every run, at the right severity
and against the right rule. It also found that the plant had quietly broken the mutation
proof for three security invariants: `Test-InvariantMutation.ps1` is not part of the
gate, so nothing else would have reported it before the next mutation run.

What this shows about the layers:

- **The gate checks what the author made consistent.** The planted change kept every
  artefact in step, so every check agreed with it. A reviewer reading the intent first
  asked whether the invariant itself was right.
- **The review rules have to be stated for the reviewer.** `Docs\REVIEW.md` states S-11
  as a concrete test (a `[string]` in RMAN text is a finding unless its validation
  limits the characters), and every run applied that wording.

## Limitations

- Three runs, one planted defect, one model. Three of three shows the defect is caught
  reliably at this effort; it does not measure how often a subtler defect is missed.
- The reviewer is a second session of the model family that wrote the plant's
  surrounding code. A defect that model family does not recognise would be missed by
  both.
- A run reviews one commit range. The record proves which commit was reviewed, not that
  the reviewer read every file; the summary lists what it read.
- The plant is a known class of defect, stated almost word for word in
  `Docs\REVIEW.md`. A defect outside the listed rules depends on the reviewer's general
  judgement, which this record does not test.
