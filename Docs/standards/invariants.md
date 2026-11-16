# Invariant Blocks

A standard applies to every function. An invariant applies to one function: what must
hold before it runs, while it runs, and after it returns or throws.

## Rules

- **I-01** — Every function carries an `# INVARIANTS` comment block as the first thing in its body, directly after `$ErrorActionPreference = 'Stop'`.
  Example: the block in `Source\Private\Invoke-RmanProcess.ps1`. *Linter.*
- **I-02** — A block is written from what the function does today, not from what it is meant to do one day.
  Example: a parameter that is accepted and ignored is recorded as a limitation, not as a guarantee. *Review.*
- **I-03** — Every entry has an identifier made of a section prefix and a number, unique within its function.
  Example: `P1`, `S2`, `R1`, `T1`, `L1`. *Linter.*
- **I-04** — An identifier is never renumbered or reused once assigned.
  Example: when `S3` is retired, the next security entry is `S4` or higher, and `S3` stays retired. *Review.*
- **I-05** — Every entry is followed by a line that names what enforces it, starting with one of `Type:`, `Guard:`, `Test:`, `Static:` or `Limitation:`.
  Example: `Type: Mandatory and ValidateNotNullOrEmpty.` *Linter.*
- **I-06** — Every security entry carries the `[SEC]` tag.
  Example: `[SEC] S1 No password is placed in the process argument list.` *Linter.*
- **I-07** — A block holds no credential value, secret fragment or sensitive path.
  Example: `S1` describes the password rule without quoting a password. *Linter.*
- **I-08** — A change to a function's behaviour updates its block in the same commit.
  Example: adding an authentication mode adds or amends the entries that mode affects. *Review.*

- **I-09** — A `Test:` line gives each test's exact title in single quotes, and the test is in the test file named for the source file. No other test in that file has the same title, so the citation names one test.
  Example: `Test: 'S2 RMAN script must contain NOPROMPT'.` in `Source\Public\Remove-RmanObsoleteBackup.ps1`, with the test in `Tests\Unit\Public\Remove-RmanObsoleteBackup.Tests.ps1`. *Linter.*
- **I-10** — A test is cited only when it would fail if the invariant were broken.
  Example: a test that mocks the function under test proves nothing about that function, and is not cited. *Review.*
- **I-11** — Every entry except a limitation is proven by a test or a static check. A `Type:` or `Guard:` line is followed by a `Test:` or `Static:` line that names the proof.
  Example: `Guard: the finally block.` followed by `Test: 'S2 zeroes and frees the buffer when the conversion throws'.` *Linter.*
- **I-12** — A `Static:` line gives each check's exact title in single quotes. The check is in `Tests\Static\SourceInvariants.Tests.ps1`, its title is unique in that file, and it starts with the function name, then the IDs it proves.
  Example: `Static: 'Invoke-RmanProcess S2 extracts the password only inside the stdin write'.` *Linter.*

## Sections

In this order. A section with no entries is left out.

| Section heading | Prefix | Holds |
|---|---|---|
| `PRE-CONDITIONS` | `P` | What must be true when the function is called |
| `SECURITY INVARIANTS` | `S` | What must never leak or be changed; every entry is `[SEC]` |
| `POST-CONDITIONS` | `R`, `T` | What holds on a normal return (`R`) and when it throws (`T`) |
| `EXECUTION INVARIANTS` | `L` | What holds on every path through the function |

## What enforces an entry

| Keyword | Meaning | An entry with this keyword is proven by |
|---|---|---|
| `Type:` | PowerShell rejects a bad value at the call | The `Test:` or `Static:` line that follows, which shows the attribute is in place |
| `Guard:` | Code in the function body checks or guarantees it | The `Test:` or `Static:` line that follows, which fails if the guard is removed |
| `Test:` | A Pester test asserts it | The named test, which cites the identifier |
| `Static:` | A check of the source proves a "must never" | The named static check |
| `Limitation:` | Not enforced, on purpose; the risk is stated and accepted | Nothing; the entry makes the gap visible |

A `Type:` or `Guard:` line says what enforces the invariant at run time. The proof line
under it says what fails when that enforcement is removed (I-11).

`Test: none yet.` and `Static: none yet.` are allowed. They mark an invariant that is
stated but not proven, and they are the work list for the test and linter stages.

## Shape

```powershell
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    #--------------------------------------------------------------
    # INVARIANTS
    #
    # PRE-CONDITIONS
    #   P1 DatabaseName is a non-empty string.
    #       Type: Mandatory and ValidateNotNullOrEmpty.
    #       Test: 'P1 DatabaseName is mandatory and rejects an empty string'.
    #
    # SECURITY INVARIANTS
    #   [SEC] S1 ORACLE_SID is never set on the current session.
    #       Test: 'S1: session ORACLE_SID is unchanged after the call'.
    #--------------------------------------------------------------
```

## Index

`Docs\standards\invariants-index.md` lists every invariant, one line each, with the
tests and static checks that prove it. It is the invariant-to-test map. It is generated
from the blocks and is never edited by hand. A test fails when the committed index does
not match the code.
