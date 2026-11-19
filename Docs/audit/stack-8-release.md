# Stack 8 — Release

The test that closes Stack 8: whether the gate refuses a release whose version differs
between the manifest, the function headers, the changelog and the tags, or whose
package holds a file `FileList` does not name. Nothing was published.

| Field | Value |
|---|---|
| Recorded | 2026-11-19 |
| Checks | `version` (every run; tag rule with `-Base`) and `package` (with `-Base`) in `Scripts\Invoke-Gate.ps1`; decision 36 |
| Package tool | `Publish-PSResource` (Microsoft.PowerShell.PSResourceGet) into a temporary local folder repository; no remote repository |
| Proof | `Scripts\Test-SeededDefect.ps1`, 19 cases, each planted in a temporary copy of the repository |

## How Publish-PSResource treats FileList

A built version folder was copied, a file `stray.txt` was added next to the four files
`FileList` names, and the folder was packaged with `Publish-PSResource` into a local
folder repository. The `.nupkg` held `stray.txt`. `Publish-PSResource` packages every
file in the version folder and does not read `FileList`, so a correct `FileList` does
not keep a file out of the package. The `package` check therefore opens the `.nupkg`
and compares its entries with `FileList`, in both directions.

## First run of the version check

The first gate run with the `version` check failed on the real repository:
`Source\Public\Get-RmanBackupStatus.ps1` and `Source\Public\Remove-RmanObsoleteBackup.ps1`
had no `Version :` line in `.NOTES`. The build's own version check skips a file with no
version line, so neither had been checked. Both now carry the copyright, module and
version lines the other public functions carry.

## Seeded cases

| Case | Planted | Expected | Result |
|---|---|---|---|
| `version mismatch` | The newest `CHANGELOG.md` release heading renamed `9.9.9` | Fails on `version` only | As expected |
| `version released` | A branch that passes every other `-Base` check, with its version tagged at the base | Fails on `version` only | As expected |
| `stray file` | `Build-Module.ps1` writes `build-notes.txt` into the version folder after `FileList` is made; uncommitted, so no review or evidence is due | Fails on `package` only | As expected |

The other 15 cases, from Stacks 2 to 6, behaved as before; the three `-Base` cases
that expect a pass (`evidence current`, `review current`, `review fixed`) also passed
`package`, so the check does not fail a correct package.
With `review stale` (below), 19 of 19 cases behaved as expected.

The first version of the `stray file` seed copied `Docs\TODO.md` into the version
folder. It also failed `static`: `Tests\Static\BuildModule.Tests.ps1` runs the build
script against a minimal fixture repository that has no `Docs\TODO.md`, so the planted
line threw there. The seed now writes its own file, which depends on nothing outside
the version folder.

## A gap in the review check

Running the full gate on this branch before its review, `review` passed. The record it
accepted was the Stack 7 pull request's, which covers a commit already on `master`.
The check required the reviewed commit to be in HEAD's history and the review's base to
be the merge base or older (so that updating a branch keeps its review valid); a record
left by the previous pull request meets both. Every pull request after the first could
therefore merge with no review of its own. The check now also requires the reviewed
commit not to be in the base. Seeded case `review stale`: after a branch with a review
merges, the next pull request makes a docs change and keeps the old record; the gate
fails on `review` only.

## Cost

| Item | Time |
|---|---|
| `Build-Module.ps1 -Package`, the `package` check's work | About 1 second |
| `Test-SeededDefect.ps1`, 19 cases | 24 minutes 51 seconds |

The seeded run is by hand, when the gate changes; it is not in the gate or CI. In CI
the `package` check adds one package build per pull request.

## Result

The gate with `-Base` refuses a pull request whose version disagrees between the
manifest, `Source\TACE.Oracle.Admin.psm1`, a public function's `.NOTES` or the newest
`CHANGELOG.md` release; whose version is lower than the latest tag; that changes
the files the package is made from (`Source\`, `README.md`, `LICENSE`,
`Scripts\Build-Module.ps1`) under a version already tagged; or whose package holds a file `FileList` does
not name, or lacks one it names. `Scripts\Publish-ToGallery.ps1` takes its API key as a
`[SecureString]` and refuses a version folder holding a file `FileList` does not name.
The tag itself is made by hand after the merge; the next pull request's `version` check
sees it.
