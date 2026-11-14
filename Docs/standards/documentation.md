# Documentation Standards

## Required documents

All in `Docs\`, plus a `README.md` at the repo root for the published package.

- **D-01** — `README.md` covers the overview, prerequisites, installation, a table of every exported function, the output contract, logging, the current security state and contributing.
  Example: a new public function appears in the function table in the same commit that adds it. *Linter.*
- **D-02** — `SECURITY.md` describes each security mechanism as built, with its status, why, how and contract, plus open items and an audit record.
  Example: a section is rewritten when the code it describes changes, not at the next release. *Review.*
- **D-03** — `CHANGELOG.md` follows Keep a Changelog, newest release first, with `Added`, `Changed`, `Fixed` and `Security` sections.
  Example: `## [0.2.0] - 2026-11-14`. *Linter.*
- **D-04** — `VERSIONING.md` holds the commit format, commit types, SemVer rules and branching strategy.
  Example: `feat(stack): ...` for a new public function. *Review.*
- **D-05** — `PREREQUISITES.md` holds the language version, external tools, test framework, execution policy, platform support and known limitations.
  Example: `rman.exe` listed against the functions that need it. *Review.*
- **D-06** — `TODO.md` lists open tasks in build order, with `[SEC]` on security tasks.
  Example: `- [ ] [SEC] Add secret scanning`. *Review.*

## Keeping them true

- **D-07** — `TODO.md` and `CHANGELOG.md` change in the same commit as the code they describe.
  Example: the commit that adds a function also adds its changelog line. *Linter.*
- **D-08** — A completed task moves from `TODO.md` to `CHANGELOG.md`; it does not stay ticked in `TODO.md`.
  Example: after a release, `TODO.md` holds only open work. *Linter.*
- **D-09** — No stage is complete while one of its `[SEC]` tasks is open.
  Example: a stage with an unticked `[SEC]` line is not tagged. *Linter.*
- **D-10** — A version number is the same everywhere it appears: manifest, module file, function headers, changelog and tag.
  Example: `ModuleVersion = '0.2.0'` with tag `v0.2.0`. *Linter.*
- **D-11** — A statement in a document that the code contradicts is a defect in the document.
  Example: "this module handles no credentials" once a function accepts one. *Review.*

## Writing a standard

- **D-12** — A standard is one sentence plus one example.
  Example: every rule in this folder. *Review.*
