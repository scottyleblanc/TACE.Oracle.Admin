# Stack 3 — Do the Cited Tests Prove Anything?

Rule I-10 says a test is cited for an invariant only when it would fail if the invariant
were broken. Until Stack 3 that was checked by review only: the linter confirmed that a
cited test existed, not that it could fail. This record covers the first mechanical check.
Each invariant was broken on purpose in a temporary copy of the repository, and the
tests cited for it were run. Nothing was changed in this repository during a run.

| Field | Value |
|---|---|
| Recorded | 2026-11-15 |
| Branch | `v0.2.3-dev`, working tree on top of `25dd490` |
| PowerShell | 7.6.10 |
| Pester | 5.7.1 |
| Command | `.\Scripts\Test-InvariantMutation.ps1 -RunTimeoutSeconds 180` |
| Mutations | `Tests\Mutation\InvariantMutations.psd1` |

## Scope

All 27 security invariants with a cited proof, with 36 mutations between them. Some
invariants have several ways to break, such as each of the three signature checks in
`Assert-OracleEnvironment` S3, and each gets its own mutation. A further 8 mutations
cover the non-security citations found weak and fixed in this pass.

## First run: before any fix

14 of the 36 security mutations survived. Every cited test passed with the
invariant broken. They cover 12 invariants.

| Cause | Invariants | Example |
|---|---|---|
| The test compared `$env:X` with its value before the call. Earlier tests in the same file had already run the function and left that value, so the comparison passed with the leak in place. Run alone, the same test failed. | `Assert-OracleEnvironment` S8, `Invoke-RmanProcess` S3, `Invoke-TnspingProcess` S1, `Get-RmanBackupStatus` S1, `Remove-RmanObsoleteBackup` S3 | `Get-RmanBackupStatus` setting `$env:ORACLE_SID` passed its test |
| A credential-leak test ran with no credential, so nothing could leak | `Get-RmanBackupStatus` S2, `Remove-RmanObsoleteBackup` S4, S5 | A Message containing `user/password@db` in NamedCredential mode passed |
| The test could not reach the code | `Assert-OracleEnvironment` S7: the mocked tnsping output carried no `TNS-` code, so it never reached the message. `ConvertFrom-SecureStringToPlaintext` S5: the only way to make it throw is a disposed SecureString, which fails before any plaintext exists | Removing the scrub passed |
| Part of the invariant had no test, or the test that would fail was not cited | `Remove-RmanObsoleteBackup` S1 (`ConfirmImpact = 'High'`), `Set-RestrictiveAcl` S3 | Lowering ConfirmImpact to Low passed |

`Invoke-RmanProcess` S3 also had no check of `PATH` at all.

Reading the non-security citations found nine more that could not fail as cited.
Examples: "exactly five properties" checked with `-Contain`, "the only command sent"
checked with `-Match`, and "on every path" tested on one path.

## Fixes

- `Tests\Unit\Set-EnvironmentSentinel.ps1` and `Compare-EnvironmentSentinel.ps1` put
  known values in `ORACLE_HOME`, `ORACLE_SID`, `ORACLE_BASE`, `NLS_DATE_FORMAT` and
  `PATH` before the call. Afterwards they compare the whole environment and restore it.
  Every session-environment test now uses them, so test order no longer matters.
- The credential-leak tests run in NamedCredential mode with a known password.
- The tnsping scrub test mocks output with a `TNS-12154` code and a credential, on stdout
  and on stderr.
- `ConvertFrom-SecureStringToPlaintext` S5 is proven by a static check instead: its catch
  block refers to neither the buffer nor the input
  (`Tests\Static\SourceInvariants.Tests.ps1`, rule I-12).
- New tests: `ConfirmImpact` metadata; an RMAN stderr flood; exact property sets; every
  return path of `Get-OracleDatabaseList` and `Set-OracleEnv`; the highest-Key rule when
  no record has a completion time. One test was tightened: `Set-RestrictiveAcl`'s
  child-file test now requires the rule to be inherited. A new file always gets some
  rule for its creator, so a check that a rule merely exists passed without inheritance.

## Final run

| Mutations | Caught | Survived |
|---|--:|--:|
| Security | 36 | 0 |
| Other | 8 | 0 |
| Total | 44 | 0 |

One mutation was caught by a hang rather than a failure. `Invoke-RmanProcess` L1 was
broken by reading stdout to the end before stderr. The stderr flood test then blocks
for good, as it should, because that is the deadlock L1 prevents. The script kills a
run that passes its timeout and counts it as caught. Before that timeout existed, the
first final run stalled on this mutation and had to be stopped.

## Later runs

| After | Mutations | Caught |
|---|--:|--:|
| The `Set-OracleEnv` split (`Invoke-OraEnv` S2, `Set-OracleEnv` R7) | 3, those two functions only | 3 |
| Tests for 23 unproven invariants, 7 of them security | 60, all | 60 |
| Static checks for 11 invariants | 71, all | 70; the 71st after a fix, below |

The static run's control failed on one check: `ConvertFrom-SecureStringToPlaintext` S5
passed in the static tier but threw under the StrictMode the script's child process sets.
A helper returned one catch clause as a scalar rather than an array, and `.Count` on it
throws under StrictMode. Wrapped in `@()`; the file passes under StrictMode too, and the
function's 5 mutations are all caught.

## What this does not cover

- 35 invariants have no proof yet (`Test: none yet` or `Static: none yet`), 15 of them
  security. There is nothing to mutate until their tests exist.
- A mutation shows that one specific break is caught, not every possible one. The
  mutations target the line that enforces each invariant.
- The script runs locally and takes about 15 minutes. It is not part of the gate.
- Every unit test that starts a fake RMAN or tnsping uses a `.cmd` file, so these runs
  are Windows only. Linux is a later Stack 3 task.
