# Stack 3 — Seeded Behaviour Defect

The check that closes the Stack 3 test work: a behaviour defect, in valid code that every
static check passes, fails the gate once the unit tier is in it. The defect was planted
in a temporary copy of the repository, never in this one, by
`Scripts\Test-SeededDefect.ps1`.

| Field | Value |
|---|---|
| Recorded | 2026-11-16 |
| Branch | `v0.2.3-dev`, working tree on top of `135bcc7` |
| PowerShell | 7.6.10 |
| Pester | 5.7.1 |
| Command | `.\Scripts\Test-SeededDefect.ps1`, which runs `.\Scripts\Invoke-Gate.ps1` once per case |

## The gate and the unit tier

The Stack 3 plan said a seeded behaviour defect must fail the gate. The gate holds only
the checks that read source text, and a behaviour defect is caught by the unit tier. The
gate gained a `-Unit` switch (decision 31): the pre-push hook stays fast and runs without
it; CI, from Stack 4, passes it. The defect case and the control run with `-Unit`.

## Defect and results

| Case | Defect planted | Expected to fail | Gate failed on | Result |
|---|---|---|---|---|
| control | none, with `-Unit` | nothing | nothing (exit 0) | Pass |
| lint | `$_` in a function (rule C-17) | analyzer | analyzer (exit 1) | Pass |
| secret | a generated token, committed in a file | secrets, commits | secrets, commits (exit 1) | Pass |
| message | a generated token, only in a commit message | messages | messages (exit 1) | Pass |
| behaviour | `Get-RmanBackupStatus` loses its CompletionTime sort and picks the highest Key, breaking R3, with `-Unit` | unit | unit (exit 1) | Pass |

The behaviour defect is one line removed: a plausible simplification that leaves valid,
lint-clean code. Run against the function's own test file, it fails exactly one test,
the one R3 cites: 'R3 should select the most recent record by CompletionTime (Key 94
over Key 95)'.

The lint, secret and message cases are the Stack 2 cases, run again unchanged.

## What this does not cover

- One defect shows one kind of break is caught. The mutation script
  (`Scripts\Test-InvariantMutation.ps1`, `Docs\audit\stack-3-mutation.md`) covers every
  security invariant and more, mechanically.
- Blocking at merge needs CI and branch protection, which are Stack 4.
