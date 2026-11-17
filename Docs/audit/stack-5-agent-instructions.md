# Stack 5 — Agent Instructions

The comparison that closes Stack 5: the same small generation task, run by an AI agent
with and without `AGENTS.md`, each result checked by the gate. The question is whether
giving the agent the standards adds anything beyond what the gate and the repository
already provide.

| Field | Value |
|---|---|
| Recorded | 2026-11-16 |
| Agent | Claude Code 2.1.308, headless (`claude -p`), model `claude-opus-5-5` |
| Starting point | Tag `v0.2.4`: `Docs\standards\` present, no `AGENTS.md`, gate passes all 7 checks |
| Runs | 3 without, 3 with, alternating |
| Measure | `Scripts\Invoke-Gate.ps1 -Unit` on each finished change; every gate run the agent made, from the session record; the Review rules the task touches |

## Method

Each run starts from a fresh clone of the repository at `v0.2.4`, in a folder outside
the one that holds the shared instruction files. Claude Code runs with all instruction
files and memory turned off: `--safe-mode`, `CLAUDE_CODE_DISABLE_CLAUDE_MDS=1` and
`CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`. A test question confirmed it: asked to list the
instructions in its context, the agent answered `NONE`. The "with" runs add `AGENTS.md`
with `--append-system-prompt-file`, and that agent reported `AGENTS.md` and nothing
else. That is the only difference between the conditions.

The "without" agent can still read `Docs\standards\` and the existing functions. The
comparison measures what the instruction file adds on top of that, which is the case
in any repository built this way.

The prompt, the same in every run:

> Add a public function Get-OracleTnsAlias to this PowerShell module. It reads
> tnsnames.ora from a directory given as a parameter and returns the names of the net
> service aliases defined in it. Include its unit tests. Work only in this folder. Do
> not commit. To run a script in this repository, use the Bash tool with:
> pwsh -NoProfile -File ./<path to script> [arguments]

Tools allowed: Read, Edit, Write, Glob, Grep, and the Bash tool running
`pwsh -NoProfile -File ./Scripts/*` or `./Tests/Lint/*`. The PowerShell tool was off:
no allow rule matches a script called by path in that tool. The last sentence of the
prompt tells the agent the one form that works. Edits were accepted without asking
(`--permission-mode acceptEdits`).

## Results

| Run | Turns | Minutes | Cost (USD) | Gate runs | First gate run after the change | Final gate | Standards files read |
|---|--:|--:|--:|--:|---|---|--:|
| without-1 | 39 | 6.5 | 1.94 | 1 | Passed (without `-Unit`; unit tier run on its own) | Passed | 5 |
| without-2 | 42 | 7.4 | 1.86 | 1 | Passed | Passed | 5 |
| without-3 | 31 | 8.4 | 1.67 | 2 | Passed (one earlier run, before any change) | Passed | 5 |
| with-1 | 37 | 7.5 | 2.19 | 1 | Passed (three earlier attempts refused by the tool rules) | Passed | 0 |
| with-2 | 40 | 8.9 | 1.75 | 2 | Failed: `secrets`, 1 finding | Passed | 0 |
| with-3 | 44 | 9.8 | 1.99 | 2 | Failed: `secrets`, 2 findings | Passed | 0 |
| **Median, without** | 39 | 7.4 | 1.86 | | 0 of 3 failed | 3 of 3 passed | 5 |
| **Median, with** | 40 | 8.9 | 1.99 | | 2 of 3 failed | 3 of 3 passed | 0 |

"Standards files read" counts the files in `Docs\standards\` the agent opened. Each
"without" agent read the README, `coding.md`, `testing.md`, `documentation.md` and
`invariants.md`, but not `security.md`.

### The two `secrets` failures

Both came from rule T-08, which requires every `Security` context to prove that no
credential fragment reaches `Message`, verbose output or a re-thrown error. To test
that, the agents put made-up passwords in the test file, such as `'Tns_S3cret_Pw9'`
and `'Tns_Fixture_Pwd_91'`, and gitleaks flagged them. Each agent fixed it by changing
the string until gitleaks no longer matched (`'TnsTestPass1'`, `'Gr8Backup!Pwd77'`). The
values are fake, so nothing leaked. The fix is still "change it until the scanner stops
matching", which only review can judge.

### Review rules

Each finished change was checked by hand against the Review rules the task touches.
Rules about credentials, RMAN or SQL do not apply to a function that only reads a file.

| Rule | without-1 | without-2 | without-3 | with-1 | with-2 | with-3 |
|---|---|---|---|---|---|---|
| C-12 pipeline results wrapped in `@()` | Yes | Yes | Yes | Yes | Yes | Yes |
| C-24 `[SEC]` on security requirements in `.NOTES` | Yes | Yes | Yes | Yes | Yes | Yes |
| D-11 README function table and docs updated | Yes | Yes | Yes | Yes | Yes | Yes |
| T-04 filesystem only under `TestDrive:` | Yes | Yes | Yes | Yes | Yes | Yes |
| T-06 parameter checks read metadata | Yes | Yes | Yes | Yes | Yes | Yes |
| T-11 environment sentinel used | Yes | Yes | Yes | Yes | Yes | Yes |
| Security invariants added to the mutation list | Yes | Yes | Yes | Yes | No | No |

Every run produced the four test contexts T-03 requires, a full invariant block (10 to
14 entries, 3 or 4 of them security entries), and the same set of documents updated.

## Finding

With the gate in place and the standards in the repository, `AGENTS.md` made no
measurable difference to the result. Every run in both conditions ended on a passing
gate, and both conditions met the same Review rules. Without the file, the agent found
the standards itself: every "without" agent read five of the six standards files
before writing code. With it, the agent read none, but used no fewer turns.

Where the conditions differed, the "with" runs came out slightly worse: longer, two
first gate runs failed on `secrets`, and two of three left the mutation list
unchanged. Three runs each way cannot separate that from chance, so it is not a
finding against the file either.

What this shows about the layers:

- **The gate is what makes the result correct.** Both conditions converged on the same
  passing result because the agent ran the gate and fixed what it reported.
- **In this repository, `AGENTS.md` saves the agent a lookup, not a defect.** The
  standards are in `Docs\standards\` and five existing functions show them applied, so
  an agent that reads before it writes finds them.
- **Review rules held in both conditions,** because the existing code shows them. That
  is a property of this repository, not a guarantee: in a repository whose code does
  not already follow the rules, the instruction file is the only thing that states the
  Review rules before review (Stack 6).

## Limitations

- Three runs per condition, one task, one model and one repository. The comparison
  can show a large, consistent effect or its absence; it cannot measure a small one.
- The "without" condition is not "no standards": the standards are in the repository.
  A repository without `Docs\standards\` was not tested.
- with-1 had three gate attempts refused by the tool rules (a `cd` to an absolute
  path, and an absolute script path), which added turns to that run.
- The Review-rule check is a reading of each change, not a second-model review.

## Pilot, set aside

A first pair of runs used broader tool rules and recorded only the final result. In it,
the "without" agent found a command form the rules allowed and ran the gate; the "with"
agent's gate call was refused, it could not regenerate the invariant index, and it
stopped with the `static` check failing. That measured the tool rules, not the
instructions, so the pair was set aside, the rules were tested, and the six runs above
were made under the corrected rules. The rule test also found that in `acceptEdits`
mode the PowerShell tool deleted a file without asking while refusing a read-only lint
script; that is recorded for Stack 7 in `TODO.md`.
