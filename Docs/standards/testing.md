# Testing Standards

- **T-01** — Tests use Pester 5.
  Example: `Import-Module Pester -MinimumVersion 5.0`. *Linter.*
- **T-02** — Every function, public or private, has its own test file, named for the function, in the folder under `Tests\Unit\` that mirrors its source folder.
  Example: `Tests\Unit\Private\Set-RestrictiveAcl.Tests.ps1` for the private helper `Source\Private\Set-RestrictiveAcl.ps1`. *Linter.*
- **T-03** — A test file groups its tests under these contexts: `Parameter Validation`, `Implementation`, `Return object contract`, `Security`, and `WhatIf support` where the function supports `ShouldProcess`. A test that proves a security invariant may sit in whichever context holds the setup it needs; the `SEC` tag (T-09), not the context, marks it as a security test.
  Example: `Context 'Security' { It 'Message contains no credential fragment' { ... } }`. *Linter.*
- **T-04** — A unit test touches the filesystem only under `TestDrive:\`.
  Example: `$configPath = Join-Path -Path $TestDrive -ChildPath 'config.json'`. *Review.*
- **T-05** — A unit test mocks every Oracle binary and needs no database and no real credential.
  Example: `Mock -CommandName Invoke-RmanProcess -ModuleName TACE.Oracle.Admin -MockWith { ... }`. *Review.*
- **T-06** — A mandatory or type check on a parameter reads the function's metadata, so no test can stop at a prompt.
  Example: `(Get-Command Get-RmanBackupStatus).Parameters['DatabaseName'].Attributes`. *Review.*
- **T-07** — A mock of an Oracle tool returns output captured from the real tool.
  Example: a mocked `LIST BACKUP SUMMARY` uses the real column layout. *Review.*
- **T-08** — Every `Security` context asserts all of these: no password in the argument list; no credential fragment in `Message` on success or failure; none in verbose output; none in a re-thrown error; and no change to the session environment.
  Example: `$result.Message | Should -Not -Match $testPassword`. *Test.*
- **T-09** — A test cited on an invariant's `Test:` line starts its title with the ID of each invariant it is cited for, comma-separated, then says what it proves. A test cited for a security invariant also carries the Pester tag `SEC`.
  Example: `It 'S1, L2 kills a tnsping that runs past TimeoutSeconds and throws' -Tag 'SEC' { ... }`. *Linter.*
- **T-10** — Each test tier has one entry script, `Scripts\Invoke-<Tier>Test.ps1`, that holds its own Pester configuration, resolves every path from its own location, writes NUnit XML results to `Tests\TestResults\<tier>.xml`, and exits 1 when any test or any test file fails (`FailedCount` or `FailedContainersCount`) and 0 otherwise. The tiers are `static` (`Invoke-StaticTest.ps1`, `Tests\Static\`, with the linters it calls in `Tests\Lint\`), `unit` (`Invoke-UnitTest.ps1`, which builds the module first, then runs `Tests\Unit\` recursively against the built module) and `integration` (`Invoke-IntegrationTest.ps1`, `Tests\Integration\*.Integration.Tests.ps1`, local only, behind five guards; also `Invoke-Gate.ps1 -Integration`).
  Example: `.\Scripts\Invoke-UnitTest.ps1` writes `Tests\TestResults\unit.xml` and exits 1 if a test file fails to parse. *Test.*
- **T-11** — A test that asserts a call leaves the session environment unchanged sets sentinel values first with `Tests\Unit\Set-EnvironmentSentinel.ps1`, and compares and restores with `Compare-EnvironmentSentinel.ps1` in a `finally` block. Comparing with the value read before the call passes whenever an earlier test has already left the value the call would set.
  Example: `$sentinel = & (Join-Path $PSScriptRoot '..' 'Set-EnvironmentSentinel.ps1')`, then `($changed -join ', ') | Should -BeNullOrEmpty`. *Review.*
- **T-12** — The unit tier measures code coverage of the built module, mapped back to the files in `Source\`, and fails when the share of commands run falls below the floor set in `Scripts\Invoke-UnitTest.ps1`. The floor is raised when coverage rises, and lowered only by a recorded decision. A command a unit test cannot reach is recorded in `Docs\TODO.md` with its reason, not covered by a test that exists only to run it.
  Example: `[FAIL] coverage: 94.8% of commands (712 of 751), floor 95.0%.` *Test.*
- **T-13** — An integration test file is named `<Function>.Integration.Tests.ps1` in `Tests\Integration\`, connects with OS authentication only, and runs the five guards in `IntegrationTestHelpers.ps1` before it touches a database. A failed guard fails the run; it never skips. Everything a test creates on the database or disk carries the fixed tag `INTEGRATION_TEST` and the name prefix `IT_`, and is removed at the start and end of the file.
  Example: `Assert-IntegrationTestAllowed -Config $script:config` as the first call in `BeforeAll`. *Test.*
- **T-14** — A branch whose changes reach the database through `Source\` ends with a commit of `Tests\Integration\LastRun.json` from a passing run on a clean tree of the commit before it. The file holds no host name, path or SID.
  Example: commit the code, run `.\Scripts\Invoke-IntegrationTest.ps1`, then commit `LastRun.json` alone. *Review until Stack 4, then Test.*
