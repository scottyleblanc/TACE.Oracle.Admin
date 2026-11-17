## What this changes

<!-- One or two sentences: what the change does and why. Name the TODO.md item or decision. -->

## Second-model review

<!-- From Review/LastReview.json. The gate's review check fails if the record is missing,
does not cover the branch, or has an unanswered finding. -->

- Reviewed commit:
- Findings: <!-- count by severity, e.g. 0 High, 1 Medium, 2 Low -->

| Id | Severity | Rule | Finding | Response |
|---|---|---|---|---|
| | | | | |

## Human review

The decisions only a person makes. Everything else is covered by the gate, the second-model
review or the author; see "What the human review covers" in `Docs/REVIEW.md`.

- [ ] **Intent:** the change does what this description and its TODO item or decision say,
      and nothing else I can see
- [ ] **Findings:** I read every finding and agree with each Response

## Evidence

- [ ] `.\Scripts\Invoke-Gate.ps1 -Unit` passed locally
- [ ] An invariant block, its tests or the mutation list changed:
      `.\Scripts\Test-InvariantMutation.ps1` passed (I-10) <!-- or: none changed -->
- [ ] `Source\` changed: `Tests/Integration/LastRun.json` is the last commit (T-14)
      <!-- or: Source\ not changed -->
