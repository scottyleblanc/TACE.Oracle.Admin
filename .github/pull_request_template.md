## What this changes

<!-- One or two sentences: what the change does and why. Name the TODO.md item or decision. -->

## Second-model review

<!-- From Review/LastReview.json. The gate's review check fails if the record is missing,
stale or has an unanswered finding. -->

- Reviewed commit:
- Findings: <!-- count by severity, e.g. 0 High, 1 Medium, 2 Low -->

| Id | Severity | Rule | Finding | Response |
|---|---|---|---|---|
| | | | | |

## Human review

Only what a person can establish. Rules checked line by line are covered by the gate, the
mutation run and the second-model review; see "What the human review covers" in
`Docs/REVIEW.md`. Tick an item once done; strike out one that does not apply and say why.

- [ ] **Intent:** the change does what this description and its TODO item or decision say,
      and nothing else I can see
- [ ] **Findings:** I read every finding and agree with each Response. One I disagree with
      is fixed in a new commit, followed by a new review
- [ ] **Risk read:** I read the parts of the diff that touch credentials, RMAN or SQL text,
      file or backup deletion, or the gate and saw nothing wrong
      <!-- or: none of these changed -->
- [ ] **Evidence:** the gate passed in CI, and the review record names this branch's last
      code commit

## Evidence

- [ ] `.\Scripts\Invoke-Gate.ps1 -Unit` passed locally
- [ ] An invariant block, its tests or the mutation list changed:
      `.\Scripts\Test-InvariantMutation.ps1` passed (I-10) <!-- or: none changed -->
- [ ] `Source\` changed: `Tests/Integration/LastRun.json` is the last commit (T-14)
      <!-- or: Source\ not changed -->
