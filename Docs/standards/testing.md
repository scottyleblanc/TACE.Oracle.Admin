# Testing Standards

- **T-01** — Tests use Pester 5.
  Example: `Import-Module Pester -MinimumVersion 5.0`. *Linter.*
- **T-02** — Every function, public or private, has its own test file, named for the function.
  Example: `Tests\Set-RestrictiveAcl.Tests.ps1` for the private helper `Set-RestrictiveAcl`. *Linter.*
- **T-03** — A test file groups its tests under these contexts: `Parameter Validation`, `Implementation`, `Return object contract`, `Security`, and `WhatIf support` where the function supports `ShouldProcess`.
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
- **T-09** — A test that proves an invariant names that invariant's ID.
  Example: `It 'S2: argument list contains no password' { ... }`. *Linter.*
