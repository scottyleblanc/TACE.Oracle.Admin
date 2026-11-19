# Security Standards

How each mechanism is built in this module is described in [SECURITY.md](../SECURITY.md).
This file states the rules.

## Credentials

- **S-01** — A password parameter is typed `[SecureString]` or `[PSCredential]`, never `[string]`.
  Example: `[PSCredential]$Credential`. *Linter.*
- **S-02** — A password reaches an Oracle tool through stdin only, never in the argument list.
  Example: `$process.StandardInput.WriteLine(...)`, with `$psi.Arguments` holding no credential. *Test.*
- **S-03** — Plaintext is extracted from a secure value inline at the stdin write, and is never assigned to a variable.
  Example: `WriteLine("CONNECT TARGET $user/$(ConvertFrom-SecureStringToPlaintext -SecureString $pw)@$alias;")`. *Review.*
- **S-04** — Source code holds no credentials, connection strings or TNS entries.
  Example: a connection alias arrives as a parameter or from the config file, never as a literal. *Linter.*

## What leaves a function

- **S-05** — `Message` on a return object holds no password, no credential value and no value derived from one, on any code path.
  Example: `Message = "DELETE OBSOLETE failed for 'CDB1'."`. *Test.*
- **S-06** — Output captured from an Oracle tool is scrubbed before it is returned, stored or logged.
  Example: `$stdOut = Invoke-CredentialScrub -Content $stdOut`. *Test.*
- **S-07** — An exception message is scrubbed before it is re-thrown or placed in `Message`.
  Example: `$safeMessage = Invoke-CredentialScrub -Content $PSItem.Exception.Message`. *Test and Linter.* The linter half is `Tests\Static\ExceptionScrub.Tests.ps1`: every `.Exception.Message` read in `Source\` is an argument of `Invoke-CredentialScrub`. Exception text reached another way, such as `"$PSItem"`, is left to review.
- **S-08** — Verbose output holds no password or credential value at any verbosity level.
  Example: `Write-Verbose "[Invoke-RmanProcess] NamedCredential: user='$($Credential.UserName)'"` logs the user name, never the password. *Test.*
- **S-09** — No function writes an object that carries a credential to the pipeline.
  Example: the `Data` object of an RMAN function has `AuthMode`, not the credential. *Test.*

## Processes and environment

- **S-10** — Environment variables for a child process are set on that process only.
  Example: `$psi.EnvironmentVariables['ORACLE_SID'] = $OracleSid`, never `$env:ORACLE_SID = $OracleSid`. *Test.*
- **S-11** — Text sent to RMAN or SQL embeds only values that were validated as typed parameters.
  Example: a `[datetime]` parameter formatted into a script, never a raw string from the caller. *Review.*
- **S-12** — No assembly is loaded from a remote or user-writable path.
  Example: no `Add-Type -Path` pointing outside `$PSHOME`. *Linter.*
- **S-13** — Security functions use FIPS-compliant algorithms: SHA-256 or stronger, AES-256, never MD5 or SHA-1.
  Example: `Get-FileHash -Algorithm SHA256` when a hash protects integrity. *Linter.*

## Oracle access

- **S-14** — A function that connects to Oracle states the privilege it needs in `.NOTES`.
  Example: `Requires SYSBACKUP or SYSDBA.` *Review.*
- **S-15** — A connection made by automation is attributable to a named account.
  Example: OS authentication under a dedicated service account, not a shared login. *Review.*

## This repository

- **S-16** — This repo is public: no credentials, account identifiers or infrastructure detail are committed, in files or commit messages.
  Example: a placeholder such as `<ORACLE_HOME>` in a document, or a `-S3Bucket` parameter, never a real host or bucket name. *Linter and Review.* The linter half is `Tests\Static\PublicRepoHygiene.Tests.ps1`: account IDs, ARNs, access keys, literal S3 targets, email addresses and private keys. A real name that matches no pattern, and commit messages, are left to review. A cross-check against a private identifier list is deferred until its design is decided across all public repositories (`TODO.md`, Stack 2).
- **S-17** — The committed agent permission files keep every documented deny rule, allow nothing beyond the documented allow rules, and hold no setting beyond the documented keys.
  Example: removing `Bash(git push *)` from the deny list of `.claude/settings.json` fails the gate until `Tests\Lint\AgentPermissions.psd1` and `SECURITY.md` section 12 change with it. *Linter.* The check is `Tests\Static\AgentPermissions.Tests.ps1`; a file may add deny rules.
