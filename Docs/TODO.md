# TODO — TACE.OracleAdmin

Tasks are ordered top-to-bottom. Each stage depends on the one above being stable.
`[SEC]` items are first-class requirements — no stage is complete until its `[SEC]`
items are checked off.

---

## Stage 1 — Foundation (v0.1.0)

- [x] Scaffold module structure (`Public\`, `Private\`, `Tests\`, `Docs\`)
- [x] Write `OracleAdmin.psm1` and `OracleAdmin.psd1`
- [x] Implement `Get-OracleDatabaseList`
- [x] Implement `Set-OracleEnv` with interactive menu and SID validation
- [x] Write unit tests for `Get-OracleDatabaseList`
- [x] Write unit tests for `Set-OracleEnv`
- [x] Write required project documentation
- [x] Update `profile.ps1` and `profile.common.ps1` — import module, alias `oraset`
- [x] Run Pester suite; confirm all tests pass
- [x] [SEC] Confirm no credential leakage in Message, Verbose, or pipeline output
- [x] Git init and initial commit

---

## Stage 2 — Future (TBD)

- [ ] `Get-OracleStatus` — report instance open mode, database role, archivelog mode
- [ ] `Test-OracleConnection` — validate connectivity via OS auth; return structured result
- [ ] Additional DBA utility functions (to be defined)
