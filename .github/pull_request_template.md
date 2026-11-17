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

The review order is in [Docs/REVIEW.md](../Docs/REVIEW.md): intent, then tests, then
implementation. Tick each item once checked; strike out one that does not apply and say
why.

### 1. Intent

- [ ] The change does what this description and its TODO item or decision say
- [ ] Every document the change touches describes what the code now does (D-11)
- [ ] Invariant blocks state today's behaviour, no ID is renumbered or reused, and a
      behaviour change updated its block (I-02, I-04, I-08)
- [ ] A function that connects to Oracle states its privilege and named account (S-14, S-15)

### 2. Tests

- [ ] Each cited test would fail if its invariant were broken (I-10)
- [ ] Unit tests use `TestDrive:\`, mock every Oracle binary, read parameter metadata,
      use real tool output in mocks and the environment sentinel (T-04 to T-07, T-11)
- [ ] New behaviour has a test that fails without it

### 3. Implementation

- [ ] No caller-supplied string reaches RMAN or SQL text unless its validation limits it
      to characters that cannot end or extend a command (S-11)
- [ ] Plaintext is extracted only inline at the stdin write (S-03)
- [ ] No real host, account, bucket or infrastructure name, in files or commit messages (S-16)
- [ ] Pipeline results used as arrays are wrapped in `@()`, arrays reach `ConvertTo-Json`
      by `-InputObject`, callers check `Success` before `Data`, and security comments
      carry `[SEC]` (C-12, C-13, C-20, C-24)

### Findings

- [ ] I read every finding in `Review/LastReview.json`, and each Response is right:
      a fix is a new commit and a new review, not a Response
- [ ] Every `Deferred:` finding has its item in `TODO.md`

## Evidence

- [ ] `.\Scripts\Invoke-Gate.ps1 -Unit` passed locally
- [ ] `Source\` changed: `Tests/Integration/LastRun.json` is the last commit (T-14)
      <!-- or: Source\ not changed -->
