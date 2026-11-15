# Stack 2 — Seeded Defects

The check that closes Stack 2: one command runs every static check, and it fails on a
planted lint violation and a planted secret. The defects were planted in a temporary
copy of the repository, never in this one, by `Scripts\Test-SeededDefect.ps1`.

| Field | Value |
|---|---|
| Recorded | 2026-11-15 |
| Branch | `v0.2.2-dev`, working tree on top of `2b7429c` with the version bump |
| PowerShell | 7.6.10 |
| Pester | 5.7.1 |
| PSScriptAnalyzer | 1.25.0, settings from `Tests\Lint\PSScriptAnalyzerSettings.psd1` |
| gitleaks | 8.30.1, settings from `.gitleaks.toml` |
| Command | `.\Scripts\Test-SeededDefect.ps1`, which runs `.\Scripts\Invoke-Gate.ps1` once per case |

## Defects and results

Each case starts from the clean copy. A case passes only when the gate fails on exactly
the expected checks: a defect caught by the wrong check, or a check failing for an
unrelated reason, does not count.

| Case | Defect planted | Expected to fail | Gate failed on | Result |
|---|---|---|---|---|
| control | none | nothing | nothing (exit 0) | Pass |
| lint | `$_` in `Source\Private\Test-WindowsPlatform.ps1` (rule C-17) | analyzer | analyzer (exit 1) | Pass |
| secret | a token in the GitHub format, committed in `Docs\seeded-note.md` | secrets, commits | secrets, commits (exit 1) | Pass |
| message | the same kind of token, only in a commit message | messages | messages (exit 1) | Pass |

The tokens are generated at random for each run and never printed; they are valid
nowhere. gitleaks reports them redacted.

The message case is there because gitleaks does not scan commit messages: tested
before the gate was built, a token in a message passed `gitleaks git`. The gate pipes
each unpushed message to `gitleaks stdin` and checks it against the S-16 patterns.

## What the first run found

The first run failed on the control case. The planting script had a helper named
`New-FakeToken`, which changes no state; the analyzer flagged it under
`PSUseShouldProcessForStateChangingFunctions`. It was renamed `Get-FakeToken`.

The same run showed the pass condition was too loose. A case passed when the expected
checks were among the failures, so with the analyzer failing in every case, the secret
and message cases passed for the wrong reason. The condition now requires the exact set.

## The repository at close

| Check | Result |
|---|---|
| Analyzer | 0 findings over 37 files in `Source\`, `Scripts\` and `Tests\Lint\` |
| Static tier | 118 passed |
| Unit tier | 352 passed (not part of the gate) |
| gitleaks, full history and working tree | no leaks |

## What this does not cover

- No check compares the repository against a list of private identifiers. A real
  resource name with no recognisable shape is caught only by review. Deferred as an
  accepted limitation (`TODO.md`, `SECURITY.md` Open Items).
- The analyzer does not read `*.Tests.ps1` files (decision 25).
- The gate runs locally, by hand or from the pre-push hook, which is turned on per
  clone and can be skipped with `git push --no-verify`. Nothing yet blocks a merge;
  that is Stack 4.
- The unit tier is not in the gate. A behaviour defect is a Stack 3 seeded defect.
