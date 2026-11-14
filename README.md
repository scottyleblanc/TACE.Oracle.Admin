# TACE.Oracle.Admin

Oracle database administration utilities for PowerShell Core 7+.

Discovers Oracle instances on the local host, sets the active session environment
(`ORACLE_SID`, `ORACLE_HOME`, `ORACLE_BASE`), and provides DBA tooling for Windows
and Linux. Designed for both interactive DBA use and scripted automation.

---

## Installation

```powershell
Install-Module 'TACE.Oracle.Admin' -Scope CurrentUser
```

Import in your session:

```powershell
Import-Module 'TACE.Oracle.Admin'
```

To install for all users (requires elevation):

```powershell
Install-Module 'TACE.Oracle.Admin' -Scope AllUsers
```

### Requirements

- PowerShell 7.0 or later
- Windows or Linux
- Windows: Oracle Database or Client installation (provides `OracleService*` Windows services)
- Linux: `/etc/oratab` populated by the Oracle installer

---

## Functions

| Function | Description |
|---|---|
| `Get-OracleDatabaseList` | Discovers Oracle database instances on the local host. Windows: queries `Win32_Service` for `OracleService*` services. Linux: parses `/etc/oratab`. Returns `SID`, `Status`, `ServiceName`, `OracleHome`, and `OracleBase` for each instance. |
| `Set-OracleEnv` | Sets `ORACLE_SID`, `ORACLE_HOME`, and `ORACLE_BASE` for the current PowerShell session from a validated instance. Auto-selects when one instance is found; presents a numbered menu when multiple instances are present. Always prints `ORACLE_SID`; add `-Verbose` to also print `ORACLE_HOME` and `ORACLE_BASE`. |
| `Invoke-OraEnv` | Interactive terminal wrapper for `Set-OracleEnv`. Suppresses the return object for clean output. Target of the `oraset` and `oraenv` aliases. Use `Set-OracleEnv` directly in scripts and automation. |
| `Get-RmanBackupStatus` | Returns the most recent RMAN backup for a database, with its age. Read-only. Windows only. In development — not in the published release. |
| `Remove-RmanObsoleteBackup` | Deletes RMAN backups that are obsolete under the configured retention policy. Asks for confirmation; supports `-WhatIf`. Windows only. In development — not in the published release. |

## Aliases

| Alias | Target |
|---|---|
| `oraset` | `Invoke-OraEnv` |
| `oraenv` | `Invoke-OraEnv` |

---

## Quick Start

```powershell
# Discover all Oracle instances on this host
$result = Get-OracleDatabaseList
if ($result.Success) {
    $result.Data | Format-Table SID, Status, OracleHome
}

# Set the active Oracle environment (interactive — presents a menu if multiple instances)
Set-OracleEnv

# Or set a specific SID directly
Set-OracleEnv -SID ORCL

# Interactive shorthand (alias — suppresses return object for clean terminal output)
oraset
oraset ORCL

# Add -Verbose (-v) to also print ORACLE_HOME and ORACLE_BASE
oraset -v
oraset ORCL -v
```

---

## Session Usage

`Set-OracleEnv` sets environment variables within the **current PowerShell session only**.
Environment variables do not propagate to a parent shell process.

**Correct usage — stay inside a persistent `pwsh` session:**

```powershell
# Start PowerShell (Linux)
pwsh

# Import the module and set the environment
Import-Module 'TACE.Oracle.Admin'
oraset

# Reference environment variables using the $env: prefix
cd $env:ORACLE_HOME

# example
PS /home/oracle> oraset
[Set-OracleEnv] One instance found. Using SID: FREE
ORACLE_SID set to 'FREE'
PS /home/oracle> cd $env:ORACLE_HOME
PS /opt/oracle/product/26ai/dbhomeFree> echo $env:ORACLE_SID
FREE

```

**To load the module automatically** on every `pwsh` session, add it to your profile:

```powershell
# Open your profile for editing
nano $PROFILE

# Add this line
Import-Module 'TACE.Oracle.Admin'
```

> Note: Running `pwsh -Command "oraset"` spawns a child process — the environment
> variables are set inside that process and lost when it exits. Always use an
> interactive `pwsh` session.

---

## Output Contract

Every function returns a `PSCustomObject` with this shape:

```powershell
[PSCustomObject]@{
    Success = [bool]     # $true if the operation completed as intended
    Data    = $null      # payload: object, array, or $null for void operations
    Message = [string]   # human-readable status — always safe to log
}
```

Always check `Success` before consuming `Data`. `Message` is always safe to write
to a log file — it will never contain passwords or credential values.

### Error handling

- **Terminating throw**: unrecoverable failures (e.g. required helper not found at load time)
- **`Success=$false`**: expected, handleable outcomes (e.g. SID not found, no Oracle services
  present, invalid menu selection) — inspect `Message` and decide how to proceed

---

## Logging and Diagnostics

Run any function with `-Verbose` to see audit-level detail:

```
[Get-OracleDatabaseList] Querying Oracle instances on Windows at 2026-03-17 14:00:00Z
[Set-OracleEnv] ORACLE_SID set to 'ORCL' at 2026-03-17 14:00:01Z
```

Verbose output never contains passwords, credential values, or sensitive path fragments.

---

## Security

The environment functions (`Get-OracleDatabaseList`, `Set-OracleEnv`, `Invoke-OraEnv`)
do not handle passwords or credentials. They work through Windows services
(`Win32_Service`), Linux `/etc/oratab`, and session environment variables only. No
Oracle connection is made and no credential material is required.

`Set-OracleEnv` is session-only — nothing is written to disk, the registry, or any
external process. SID validation always derives from live service discovery — never
from a hardcoded list.

The RMAN functions (in development) connect to a database through RMAN. Passwords are
accepted only as `PSCredential` or `SecureString`, are passed to RMAN through stdin
and never on the command line, and Oracle environment variables are set on the RMAN
child process only. Importing the module writes nothing to disk; a local configuration
file is created with restricted permissions the first time an RMAN function runs.

For the full security reference and STIG compliance status, see
[SECURITY.md](https://github.com/scottyleblanc/TACE.Oracle.Admin/blob/master/Docs/SECURITY.md).

---

## AI-Assisted Development and Support

This module was developed by TACE as a generic, reusable artifact. AI tooling was
used during development as part of TACE's standard engineering practice.

Once this module has been adopted and integrated into your environment, any
AI-assisted activity involving it — including troubleshooting, triage, incident
response, or code modification — should be conducted through your organization's
enterprise AI tooling.

At that point, interactions with the module will occur in the context of your
specific infrastructure, and the data governance protections of an enterprise AI
account apply. Using personal or consumer-tier AI accounts for support work
involving deployed modules introduces data handling risks that are outside TACE's
control and may conflict with your organization's own data governance obligations.

---

## License and Source

- [LICENSE](https://github.com/scottyleblanc/TACE.Oracle.Admin/blob/master/LICENSE)
- [Source and issue tracker](https://github.com/scottyleblanc/TACE.Oracle.Admin)
