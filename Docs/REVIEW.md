# Review — TACE.Oracle.Admin

Every pull request is examined by someone other than its author before it merges: a
second-model review, then a human review using the checklist in the pull request
template. The model reviewer follows the review order below, rule by rule; it is told to
read this file. The human review covers what only a person can establish (see "What the
human review covers").

The gate has already run when review starts. Review does not repeat what the gate
checks. It covers what only judgement can: the rules tagged *Review* in `AGENTS.md`,
and whether the change does what it says.

## The review path

1. The author finishes the change and the gate passes locally
   (`.\Scripts\Invoke-Gate.ps1 -Unit`). When the change touches an invariant block, the
   tests it cites or the mutation list, `.\Scripts\Test-InvariantMutation.ps1` passes
   too (rule I-10). Every change is committed.
2. The author runs `.\Scripts\Invoke-ModelReview.ps1`, once. A new Claude Code
   session, with no access to the author's session, memory or instruction files,
   reviews the commits the branch adds to `master` in the order below. It can read the
   repository at the reviewed commit and nothing else; it cannot run commands or
   change files. The script writes its findings to `Review\LastReview.json`.
3. The author fixes the findings worth fixing, in new commits, and answers every
   finding in `Review\LastReview.json` (see "Answering a finding"). The fixes are not
   reviewed again; the human review judges the Responses. Run the gate again after
   the fixes.
4. When `Source\` changed, the integration run follows, and `LastRun.json` is the
   last commit of the branch (rule T-14).
5. The author opens the pull request. CI runs the gate with `-Base`, and its `review`
   check fails when the record is missing, does not cover the branch from its merge
   base, or has an unanswered finding. The maintainer does the human review with the
   template's checklist.

One review per pull request keeps the cost bounded: each new review is a fresh session
over the whole change, which finds a different subset of problems each time and never
settles. A second review is the author's choice, not a rule.

## What the human review covers

A person reading a pull request cannot establish rule by rule that every line holds, so
the checklist does not ask for that. Each rule has an owner:

| Rule or question | Established by |
|---|---|
| Rules tagged *Linter* or *Test* | The gate |
| I-10, a cited test fails when its invariant is broken | `Scripts\Test-InvariantMutation.ps1`, which the author runs when a change touches an invariant block, its tests or `Tests\Mutation\InvariantMutations.psd1` (step 1); it is not part of the gate. The second-model review checks that the mutation list still matches the code |
| The other rules tagged *Review*, line by line | The second-model review, in the order below |
| S-16, no real names in files or commit messages | The gate's patterns and gitleaks for known shapes, the second-model review, and the human for names they recognise as real |
| The change does what it says, and nothing else visible | The human |
| Each finding's Response is right, and a finding that should be fixed is fixed | The human |
| The fix commits after the reviewed commit do what their findings asked | The author; the gate and the human's reading of the Responses |
| The parts of the diff with the most at stake: credentials, RMAN or SQL text, file or backup deletion | The second-model review |
| The gate passed in CI | The ruleset on `master`, which blocks the merge otherwise |

The human checklist has two items: intent, and the findings.

## Review order

Intent first, then tests, then implementation. Code is read last, so the reviewer
judges it against what it is meant to do, not against what it happens to do.

### 1. Intent

What the change claims to do, and whether the documents and invariant blocks say the
same thing.

- The change matches its stated purpose: the commit messages, the `TODO.md` item and
  any decision in `Docs\standards\decisions.md` it cites.
- **D-11** — A document the change touches describes what the code now does.
- **D-02, D-04, D-05, D-06** — `SECURITY.md`, `VERSIONING.md`, `PREREQUISITES.md` and
  `TODO.md` are updated where the change affects them.
- **I-02** — An invariant block states what the function does today.
- **I-04** — No invariant identifier is renumbered or reused.
- **I-08** — A change to a function's behaviour updates its invariant block.
- **S-14, S-15** — A function that connects to Oracle states the privilege it needs,
  and the connection is attributable to a named account.
- **D-12** — A new or changed standard is one sentence plus one example.

### 2. Tests

Whether the tests prove the intent, not only that they pass.

- **I-10** — A test cited on an invariant would fail if the invariant were broken.
- **T-04** — Unit tests touch the filesystem only under `TestDrive:\`.
- **T-05** — Unit tests mock every Oracle binary and need no real credential.
- **T-06** — Mandatory and type checks read the function's metadata.
- **T-07** — A mock of an Oracle tool returns output captured from the real tool.
- **T-11** — An environment test uses the sentinel helpers.
- A behaviour the change adds has a test that would fail without it.

### 3. Implementation

The code itself, read against the intent and the tests above.

- **S-11** — Text sent to RMAN or SQL embeds only values validated as typed
  parameters. A `[string]` from the caller placed in an RMAN or SQL script is a
  finding, whatever `[Validate*]` attribute it carries, unless the attribute limits it
  to characters that cannot end or extend a command.
- **S-03** — Plaintext is extracted from a secure value only inline at the stdin write.
- **S-16** — No real host, account, bucket or other infrastructure name is committed.
- **C-12** — A pipeline result used as an array is wrapped in `@()`.
- **C-13** — A value that can be an array goes to `ConvertTo-Json` with `-InputObject`.
- **C-20** — A caller checks `Success` before it uses `Data`.
- **C-24** — A security requirement in a comment or `.NOTES` carries `[SEC]`.
- Defects no rule names: a wrong result, an unhandled path, a resource not released.

## Severity

| Severity | Meaning |
|---|---|
| High | A security rule broken, data changed or lost when it should not be, or a wrong result on a normal path |
| Medium | Another *Review* rule broken, or a defect on an uncommon path |
| Low | A document out of step with the code, unclear code, or a gap in a test that does not hide a defect |

## Answering a finding

Each finding in `Review\LastReview.json` has a `Response`. The author sets it to one of
these, followed by the reason:

| Response | When |
|---|---|
| `Fixed: <commit>` | The finding is right and a later commit on the branch fixes it |
| `Rejected: <reason>` | The finding is wrong: the code already does what it asks |
| `Accepted: <reason>` | The finding is right and is not fixed in this pull request, with the reason that is safe |
| `Deferred: <TODO item>` | The finding is right and its item is added to `TODO.md` on the branch |

The gate fails while any `Response` is empty or does not start with one of these words.
It cannot judge the reason; the human checklist does.

Fix a High finding. Fix a Medium one, or say in its Response why it is safe not to. A Low
finding is usually answered, not fixed: each fix is new code that no model reviews.

## Limits

- The record is the author's attestation, as `LastRun.json` is (decision 30). The gate
  proves it covers the branch and is answered, not that the session ran as recorded.
- Commits after the reviewed one are not checked to be fixes, by the gate or a model.
  They are the author's; a large change after the review should be reviewed again.
- The model reviewer is a second session of the same model family as the author. It
  shares the author's blind spots more than a different model or a person would.
- A review can miss a defect, and the same change reviewed twice gives different
  findings. On the Stack 6 pull request, later reviews found real problems in the
  original code that the first review missed. The gate stays the deterministic check;
  review adds judgement on top.
- GitHub does not let the author of a pull request approve it, and this repository has
  one maintainer, so no approval is required (decision 33). The human checklist is
  completed by the maintainer in the pull request.
