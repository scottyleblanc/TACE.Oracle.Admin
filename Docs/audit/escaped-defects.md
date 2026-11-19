# Escaped Defects

A defect that got past the checks meant to catch it, and was found later: by a newer
check, a review or a person. The rule: **every entry ends in a check** that now fails
on that defect. An entry with no check is open work, not a closed entry.

| Field | Meaning |
|---|---|
| Found | Stack and date, and what found it |
| Escaped | What was wrong |
| Missed by | The layer that should have caught it, and why it did not |
| Caught by | The check that now fails on it, and the rule it enforces |
| Commit | The commit that added the check |

## Log

| ID | Found | Escaped | Missed by | Caught by | Commit |
|---|---|---|---|---|---|
| E1 | Stack 8, 2026-11-19, first gate run with the `version` check | `Get-RmanBackupStatus` and `Remove-RmanObsoleteBackup` had no `Version :` line in `.NOTES` | The build's version check, which skips a file with no version line, so neither file was checked | Gate `version` check: every public function's `.NOTES` names the manifest version (D-10) | `42ab7e8` |
| E2 | Stack 8, 2026-11-19, when the Stack 8 pull request passed `review` before any review ran | The gate's `review` check accepted a `Review/LastReview.json` left by the previous pull request, so a pull request with no review of its own could merge | The `review` check, which required the reviewed commit to be in HEAD's history and the review's base to be the merge base or older; the previous record met both | Gate `review` check: the reviewed commit must not be an ancestor of the merge base; seeded case `review stale` | `25942cf` |
| E3 | Stack 7, 2026-11-19, model review finding F4 | A deny rule could be removed from `.claude/settings.json` or `.cursor/cli.json`, or an allow rule widened, and the gate still passed | No check read the permission files; only review could see a change to them | Static check `Tests\Static\AgentPermissions.Tests.ps1` against `Tests\Lint\AgentPermissions.psd1` (S-17); seeded case `permission` | `ee20511` |
| E4 | Stack 9, 2026-11-19, by Claude Code while choosing the drill defect | `Invoke-CredentialScrub` ended the password at its first `@`. `backup_user/S3cr3tP@ss!@ORCL_SVC` became `backup_user/***SCRUBBED***@ss!@ORCL_SVC`, so the rest of the password stayed in the output | Unit test S1, which used a password holding an `@` but asserted only that the whole password was gone, so a fragment passed | Unit test S1 asserts the exact scrubbed text; the scrub now runs the password to the last `@` in the token (S-06) | `a612262` |
| E5 | Stack 9, 2026-11-19, by the ownership-drill agent | Six places read exception text without the scrub: `Set-OracleEnv` and `Get-OracleDatabaseList` placed it in `Message`, and `Assert-OracleEnvironment`, `ConvertFrom-SecureStringToPlaintext`, `Get-OracleBackupConfigStore` and `Set-RestrictiveAcl` re-threw it | Rule S-07 was enforced only by unit tests of the functions that handle a credential; the two public functions recorded it as an accepted limitation, and nothing checked the rest | Static check `Tests\Static\ExceptionScrub.Tests.ps1`: every `.Exception.Message` read in `Source\` is an argument of `Invoke-CredentialScrub` (S-07); invariants `Set-OracleEnv` S3 and `Get-OracleDatabaseList` S2 | `a612262` |
