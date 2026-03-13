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

## Stage 1.3 — Environment Variable Derivation (v0.1.3)

- [x] Switch `Get-OracleDatabaseList` from `Get-Service` to `Get-CimInstance Win32_Service`
      to expose `PathName` (service executable path)
- [x] Derive `ORACLE_HOME` from `PathName` in `Get-OracleDatabaseList`
- [x] Derive `ORACLE_BASE` from `ORACLE_HOME` in `Get-OracleDatabaseList`
- [x] Update `Set-OracleEnv` to set `$env:ORACLE_HOME` and `$env:ORACLE_BASE` from
      discovered instance data; warn if either cannot be determined
- [x] Update unit tests for both functions (82 total, all passing)
- [x] Update project documentation

---

## Stage 1.4 — Multi-Platform Discovery (v0.1.4)

- [x] Add `-Platform` parameter to `Get-OracleDatabaseList` for auto-detection and
      test override (`$IsWindows` / `$IsLinux`)
- [x] Implement Linux discovery path via `/etc/oratab`; derive `OracleBase` using
      string split to preserve `/` separators on all platforms
- [x] Check `ora_pmon_<SID>` process for instance status on Linux
- [x] Return `Success=$false` for unsupported platforms
- [x] Update unit tests (102 total, all passing)
- [x] Update project documentation

---

## Stage 2 — Future (TBD)

- [ ] `Get-OracleStatus` — report instance open mode, database role, archivelog mode
- [ ] `Test-OracleConnection` — validate connectivity via OS auth; return structured result
- [ ] Additional DBA utility functions (to be defined)
