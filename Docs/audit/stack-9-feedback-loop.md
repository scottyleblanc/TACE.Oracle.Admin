# Stack 9 — Feedback Loop

The test that closes Stack 9: whether someone new to this repository, with only the
committed docs, tests and gate, can find and fix a planted defect. The escaped-defect
log, the other half of the stack, is `Docs\audit\escaped-defects.md`.

| Field | Value |
|---|---|
| Recorded | 2026-11-19 |
| Agent | Claude Code 2.1.308, headless (`claude -p`), model `claude-opus-5-5`, `--setting-sources project`, `--permission-mode acceptEdits` |
| Starting point | `master` at `bb6645b` exported with `git archive` into a folder outside the repository, one defect planted, then a new git repository with one commit and no remote |
| Not given | Git history, ignored files (no local `.claude\CLAUDE.md`, no session handoff notes), user memory, and any statement of the symptom |
| Settings | The committed `.claude/settings.json`; the folder was trusted once, interactively, before the run, so the allow rules applied |
| Prompt | "A defect has been planted in this repository. Find it and fix it. Report what was wrong, how you found it, what you changed, and how you know the fix is right." |

## The planted defect

In `Source\Public\Remove-RmanObsoleteBackup.ps1`, the `catch` block placed the raw
exception text in `Message` instead of the scrubbed text, and the scrub call was
removed with it:

```powershell
Message = "Remove-RmanObsoleteBackup failed: $($PSItem.Exception.Message)"
```

The function accepts a credential, so an error holding a connect string would return
the password to the caller (rules S-05 and S-07, invariant S8). The code is valid and
the analyzer and static tier pass it. In the copy, the gate failed on `unit` only:
404 passed, 1 failed, test `S8 exception text is scrubbed before it is placed in
Message`. This is a different function from the seeded `behaviour` case.

## Result

| Measure | Value |
|---|---|
| Found and fixed | Yes |
| Fix | The scrub call restored before `Message` is built, the same as the original code, plus a `[SEC] S8` comment and a CHANGELOG `[Unreleased]` `Security` entry |
| Gate after the fix | All 8 checks pass; unit 405 of 405 |
| Time | 5 min 42 s |
| Turns | 14 |
| Permission refusals | 2, both Bash commands outside the allow rules (an inline `pwsh -Command` and a `sed`/`grep` pipeline); the agent used the Grep and Read tools instead |

## How it was found

The agent ran `.\Scripts\Invoke-Gate.ps1 -Unit` first, as `AGENTS.md` says to. It read
the failing test's name from `Tests\TestResults\unit.xml`, then the function and the
test, compared the `catch` block with `Get-RmanBackupStatus`, and fixed the code, not
the test. It cited rules S-05, S-07 and D-07 without opening a document: `AGENTS.md`
was loaded at session start, because no `CLAUDE.md` exists in the folder or above it.

Files it opened: `Tests\TestResults\unit.xml`, `Source\Public\Remove-RmanObsoleteBackup.ps1`,
`Tests\Unit\Public\Remove-RmanObsoleteBackup.Tests.ps1`, `Source\Public\Get-RmanBackupStatus.ps1`
(by search) and `Docs\CHANGELOG.md`.

## What it shows

The gate named the failing invariant, the test named the expected behaviour, and the
generated `AGENTS.md` carried the rules, so no session notes or history were needed.
The test's title, starting with its invariant ID (T-09), led straight to the
invariant block in the function. The drill tests a defect a test already covers; a
defect no test covers is what the escaped-defect log is for.

The agent also reported that `Set-OracleEnv` and `Get-OracleDatabaseList` place
unscrubbed exception text in `Message`, and that four private helpers re-throw it
unscrubbed. Rule S-07 covers every exception message, so this is escaped-defect entry
E5: all six now scrub, and `Tests\Static\ExceptionScrub.Tests.ps1` fails on any
exception message in `Source\` read outside `Invoke-CredentialScrub`.
