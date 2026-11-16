# Stack 3 — Integration Tier, First Runs

The integration tier runs the module against a real Oracle database on the developer's
machine. This record is a summary only: raw output holds host names and paths, and this
repository is public.

| Field | Value |
|---|---|
| Recorded | 2026-11-16 |
| Branch | `v0.2.3-dev` |
| Database | Oracle Database 21c Express Edition; RMAN reports 21.3.0.0.0 |
| Database state | NOARCHIVELOG; RMAN retention REDUNDANCY 1 (default); control file autobackup on (default) |
| Authentication | OS authentication only |
| PowerShell | 7.6.10 |
| Pester | 5.7.1 |
| Command | `.\Scripts\Invoke-IntegrationTest.ps1`, then `.\Scripts\Invoke-Gate.ps1 -Integration` |

## Guards

The five guards of OracleBackup design decision AD-020 run before any test, in the tier
script and again in each test file: host allowlist, opt-in variable, complete local
configuration, database-name denylist, and an existing test folder. A failed guard fails
the run; it never skips.

Before setup, the tier was run three times and refused each time: no allowed host
(guard 1), the opt-in variable unset (guard 2), and the test folder missing (guard 5).
13 tests in `Tests\Static\IntegrationGuards.Tests.ps1` show every guard refusing, with
no database.

## Results

| Run | Tests | Passed | Failed |
|---|--:|--:|--:|
| Tier script | 12 | 12 | 0 |
| Gate with `-Integration` | 12 | 12 | 0 |

| File | What it checks |
|---|---|
| `Get-RmanBackupStatus.Integration.Tests.ps1` | After a control file backup, the newest record is current and available; RawLog is the LIST BACKUP SUMMARY output and lists the test backup; the session environment is unchanged; no credential pattern in Message or RawLog |
| `Remove-RmanObsoleteBackup.Integration.Tests.ps1` | With two control file backups, the first is obsolete. `-WhatIf` deletes nothing; a real run returns Applied true and a deleted count, removes the first backup's pieces from disk, and leaves a current backup; the session environment is unchanged; no credential pattern |

## Effect on the database

- Every test backup is tagged `INTEGRATION_TEST` and cleaned up at the start and end of
  each test file. The test folder was empty after both runs.
- `DELETE OBSOLETE` acts on the whole database. The first run deleted the control file
  autobackup that existed before the tests (taken 2026-11-14). The three earlier backup
  sets were not obsolete and were kept.
- With autobackup on, RMAN takes its own control file autobackup after each test backup,
  outside the test folder and without the test tag. Each run leaves the newest one
  behind; the next run's `DELETE OBSOLETE` removes it, so they do not accumulate.

## What this does not cover

- Wallet and named-credential authentication. Neither is set up on this machine.
- Backups of datafiles. The database runs in NOARCHIVELOG, so an open datafile backup is
  not possible; control file backups exercise the same functions without a restart.
- Soak runs, dropped from Stack 3.
