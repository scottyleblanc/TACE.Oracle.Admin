# Stack 1 — Seeded Defects

The check that closes Stack 1: the invariant rules are enforced, not only written. Two
defects were planted one at a time, the static tier was run against each, and the
planted file was removed before the next.

| Field | Value |
|---|---|
| Recorded | 2026-11-14 |
| Branch | `v0.2.1-dev`, working tree on top of `a34aef5` |
| PowerShell | 7.6.10 |
| Pester | 5.7.1 |
| Command | `.\scripts\Invoke-StaticTest.ps1` (rule T-10; named `test.static.ps1` when the check was run, renamed by decision 20 before release) |

## Defects and results

| # | Defect planted | Rule | Exit code | Checks that failed |
|---|---|---|---|---|
| 1 | `Private\Get-SeededNoBlock.ps1`: a function with no `# INVARIANTS` block | I-01 | 1 | `I-01: every function in Public and Private has an INVARIANTS block`; `the committed index matches the code` |
| 2 | `Private\Get-SeededMalformed.ps1`: a block with an entry that has no identifier, and an entry with no enforcement line | I-03, I-05 | 1 | `I-03, I-05, I-06: every entry is well formed`; `the committed index matches the code` |

What the checks reported:

- Defect 1: `Private/Get-SeededNoBlock.ps1::Get-SeededNoBlock` has no block.
- Defect 2: line 14, "not a section heading, an entry or a continuation" (the entry
  with no identifier); line 15, `R1` "has no enforcement line (Type, Guard, Test,
  Static or Limitation)".

In both cases the index check also failed, because a new function changes what the
generated index must contain. That is a second, independent signal; the rule-specific
check is the one that names the defect.

After both planted files were removed, the static tier passed: 4 of 4, exit code 0.

## Public repository hygiene (rule S-16)

Added at Stack 1 close, after a real S3 bucket name was found written into three
scripts, where it had been since Stack 0 without any check catching it. The bucket is
now a `-S3Bucket` parameter. `Tests\Static\PublicRepoHygiene.Tests.ps1` was then seeded
with one untracked file holding one fake value per pattern, built at run time so no
fake value is written into the repository's sources.

| Line | Fake value planted | Check that failed |
|---|---|---|
| 1 | a 12-digit number | `S-16: no AWS account ID` |
| 2 | an AWS ARN (the `arn` prefix, then the `aws` partition) | `S-16: no ARN` |
| 3 | AWS's published example access key ID | `S-16: no AWS access key ID` |
| 4 | `s3://` followed by a literal name | `S-16: no literal S3 target` |
| 5 | an address at a non-example domain | `S-16: no email address outside the reserved example domains` |
| 6 | a private key header | `S-04: no private key block` |
| 7 | forms that must pass: an `example.com` address, `s3://$S3Bucket/`, `s3://<staging-bucket>/`, a GUID's 12-digit tail | none, as intended |

Exit code 1, with 6 failed and 5 passed; each failure named its file and line and showed
only the first six characters of the value. With the file removed, the static tier
passed, 11 of 11.

The private resource list was also checked by hand at this close: none of its values
appears in the working tree, in a line this release adds, or in a commit message since
`v0.2.0`. That cross-check becomes a script in Stack 2.

## What this does not cover

- Rule I-06 (`[SEC]` tag on a security entry) shares check 2 but was not seeded here.
- Rules marked *Review* in `Docs\standards\invariants.md` (I-02, I-04, I-08, I-10) have
  no machine check; a seeded breach of those would pass the static tier.
- T-09 (cited tests name their IDs) has no linter check yet; it is a Stack 3 task.
