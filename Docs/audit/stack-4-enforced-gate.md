# Stack 4 — Enforced Gate

The check that closes Stack 4: a pull request carrying the seeded defects from Stacks 2
and 3 runs the gate in CI, fails it, and cannot be merged into `master`. A clean pull
request passes and can.

| Field | Value |
|---|---|
| Recorded | 2026-11-16 |
| Workflow | `.github\workflows\gate.yml`, job `gate`, `windows-latest` |
| Command in CI | `.\Scripts\Install-GateTool.ps1`, then `.\Scripts\Invoke-Gate.ps1 -Unit -Base origin/master` |
| Tools in CI | PSScriptAnalyzer 1.25.0, Pester 5.7.1, gitleaks 8.30.1 (zip checked against a pinned SHA-256) |
| Ruleset | "master: pull request and gate required", active |

## Branch protection

A ruleset on the default branch, `master`. No one is on its bypass list; GitHub reports
`current_user_can_bypass: never` for the repository owner.

| Rule | Setting |
|---|---|
| Pull request | Required for every change; 0 approvals (review is Stack 6); merge commits only |
| Required check | `gate`, from the GitHub Actions app only, so a status of the same name posted any other way does not count |
| Up to date | The pull request must contain the head of `master` before it merges |
| History | Force pushes and deletion of `master` are blocked |

## Least privilege

| Control | Setting |
|---|---|
| Token | `permissions: contents: read`; the repository default is also read-only |
| Secrets | None used or referenced |
| Trigger | `pull_request` only; `pull_request_target` is not used |
| Checkout | The pull request head, `persist-credentials: false`, so the token is not left in the working copy |
| Actions | One action, `actions/checkout`, pinned to a full commit SHA. Repository settings allow only GitHub-owned actions and require SHA pinning |
| Repository | Secret scanning and push protection on |

## Results

| Pull request | Content | Gate in CI | Merge state |
|---|---|---|---|
| #1, `v0.2.4-dev` | The Stack 4 changes | All 8 checks passed; unit 405, coverage 97.7% | `CLEAN`: can merge |
| #2, `demo/seeded-defects` | Three seeded defects, below | Failed on analyzer, messages, evidence, unit | `BLOCKED`: cannot merge |

The seeded defects on #2, each a commit marked "Stack 4 demo, do not merge":

| Defect | From | Gate check that failed | Detail shown |
|---|---|---|---|
| `$_` in `Test-WindowsPlatform.ps1` | Stack 2 lint | analyzer | `[C-17] $_ used. Write $PSItem.` |
| `Get-RmanBackupStatus` picks the highest Key, not the latest CompletionTime | Stack 3 behaviour | unit | 404 passed, 1 failed: the R3 test |
| A 12-digit number in a commit message, standing in for an AWS account ID | Stack 2 message | messages | `S-16 no AWS account ID: 000000***` |
| `Source\` changed with no new integration run | Rule T-14 | evidence | Files changed after the run's commit |

The same command run locally on the branch before the push failed on the same four
checks.

## The gate's -Base switch

Locally, `commits` and `messages` check the commits not yet on any remote. In a CI
checkout every commit is on a remote, so those checks would pass having checked
nothing. `-Base` makes them check the pull request's own commits, `Base..HEAD`, and adds
the `evidence` check. `Scripts\Test-SeededDefect.ps1` shows both sides: a token in a
commit message that is already on a remote passes the gate without `-Base` and fails it
with `-Base`. Its nine cases pass.

## What this does not cover

- The seeded secret in a file was not pushed: a token-format string, even a generated
  one, would stay readable in a public pull request. That case is covered by
  `Scripts\Test-SeededDefect.ps1`, which runs the same gate script.
- The `evidence` check proves the integration record is current and consistent, not
  that the run happened (decision 30's accepted limit). It needs a local Oracle database,
  so only a contributor with one can change `Source\`.
- CI runs on Windows only; the unit tier is not yet run on Linux (TODO.md, Post-Project
  Notes).
- A passing gate with no approval can merge: review is Stack 6.
