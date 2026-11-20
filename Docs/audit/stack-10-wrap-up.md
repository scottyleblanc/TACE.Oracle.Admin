# Stack 10 — Wrap-up

The test that closes Stack 10: whether the reusable parts of the stack, lifted into a
template, give a fresh, empty repository a working gate, in the pre-push hook and in
CI on real pull requests.

| Field | Value |
|---|---|
| Recorded | 2026-11-19 |
| Template | A separate repository, taken into the target as a git subtree at `tools/gate` (`git subtree add --squash`); decision 38 |
| Target | A new, empty private GitHub repository, created for the proof and not kept |
| Tools | PowerShell 7.6, PSScriptAnalyzer 1.25.0, Pester 5.7.1, gitleaks 8.30.1; CI on `windows-latest` |
| Template's own tests | 82 static tests: 21 gate behaviour cases, each in a throwaway repository, 16 analyzer rule cases and 45 unbranded-file checks; the template's gate passes on itself |

## What the template holds

| Part | From this repository |
|---|---|
| Gate script, one data config file, checks numbered in run order | `Scripts\Invoke-Gate.ps1`, made config-driven |
| Config, tools, analyzer, static, secrets, commits, messages, permissions and review checks | The same checks; the review check reads its record and exempt files from the config |
| Optional version and unit checks, off by default | `version` without the root-module and function-header rules; the unit tier as a script the config names |
| Analyzer settings and eight custom rules | The rules that assume no module layout (C-05, C-08, C-09, C-11, C-14, C-15, C-17, C-18); C-10 and C-33 stay here |
| A per-file, per-rule analyzer baseline | New: a repository with existing findings fails only on new ones |
| gitleaks config and commit message patterns, review script and checklist, agent permission check | The same, without this repository's names |
| Pre-push hook, GitHub Actions and Bitbucket Pipelines wrappers, pull request template | New wrappers; the Bitbucket one installs PowerShell from a hash-checked release archive |

The template is public and released under the MIT licence, with the copyright held by
TACE Data Management Inc. Its licence file is the only file in it that names TACE.

Not in the template: the package, evidence and integration checks, the invariant
linter, the mutation script, the seeded-defect script and the instruction generator.
Each assumes this repository's module layout or its database.

## The fresh-repository proof

The target started as one commit holding a README. The template was added as a
subtree, its config, hook, workflow and pull request template were copied in, and the
config was left as shipped.

| Case | Pre-push hook | CI on a pull request |
|---|---|---|
| Empty repository, config as shipped | 8 of 8 checks passed; the analyzer reported no files to analyze, the static check no test folder | — |
| A small function, the analyzer pointed at it, one review run and its finding answered | Passed | Passed, 9 of 9 checks, the review check included; merged |
| A seeded secret (a fake token) | Refused: secrets and commits checks | Failed on the secrets and commits checks; closed unmerged |
| A seeded analyzer finding (a cmdlet alias) | Refused: analyzer check | Failed on the analyzer check; closed unmerged |

Both seeded pull requests also failed the review check, since neither carried a review
record. The fake token did not appear in the CI log: gitleaks runs with `--redact`.

## What the proof found

A private repository on GitHub's free plan cannot require a check before merge: the
branch protection request was refused with "Upgrade to GitHub Pro or make this
repository public". On such a repository the gate runs on every pull request, but a
failing pull request can still be merged. The template's README, review guide and
GitHub wrapper now say so. This repository is public, so its ruleset still blocks the
merge (decision 33).

## Moved out of Stack 10

The proof on a file copy of an existing private module repository, one with a class,
its own packaging step and a host other than GitHub, is now a task of its own in
`TODO.md`. Bringing that much existing code under the gate's rules is a project in
itself, and it runs on another machine. The template's Bitbucket wrapper and its Linux
install path have not run yet.

## Result

The template gives a fresh repository a working gate: every enabled check passes on
nothing and says so, a clean change passes in CI, and a planted secret or analyzer
finding fails both the hook and CI. This is the template half of the plan's
end-of-project test; the other half, the summary post answering the question layer by
layer, follows the existing-repository proof.
