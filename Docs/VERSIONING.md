# Versioning — TACE.OracleAdmin

## Commit Message Format

Follows [Conventional Commits](https://www.conventionalcommits.org/):

```
type(scope): short description

Optional body — why, not what.
```

## Commit Types

| Type | When to use |
|---|---|
| `feat` | New public function or capability |
| `fix` | Bug fix in existing behaviour |
| `sec` | Security fix; maps to `[SEC]` TODO items and `CHANGELOG.md ### Security` |
| `docs` | Documentation only (no code change) |
| `test` | Test additions or corrections (no production code change) |
| `chore` | Manifest version bump, dependency update, scaffold changes |
| `refactor` | Internal restructure with no behaviour change |

## Semantic Versioning Rules

| Change | Version bump |
|---|---|
| New public function, new parameter on existing function | Minor (0.x.0) |
| Bug fix, internal refactor, docs | Patch (0.0.x) |
| Breaking change to function signature or return shape | Major (x.0.0) |
| Security fix | Patch minimum; Minor if behaviour changes |

Breaking changes require a `BREAKING CHANGE:` footer in the commit body.

## Branching Strategy

- `master` — stable, tagged releases only
- `vX.Y.Z-dev` — one branch per version (e.g. `v0.1.4-dev`)
- Merge to `master` with `--no-ff` to preserve branch history
- Tag `master` after each merge using the bare version: `git tag vX.Y.Z`

**Branch and tag names must never be identical.** Using the `-dev` suffix on
branches avoids ambiguity when pushing — `git push origin vX.Y.Z` would match
both the branch and the tag and will fail. Push the tag explicitly if needed:
`git push origin refs/tags/vX.Y.Z`

## Version–Commit–Changelog Mapping

1. Update version in `OracleAdmin.psd1` (`ModuleVersion`) and `OracleAdmin.psm1` (`.NOTES`)
2. Add entry to `CHANGELOG.md`
3. Commit all three in the same commit: `chore(manifest): bump version to 0.x.0`
4. `TODO.md` and `CHANGELOG.md` travel in the same commit as the code they describe —
   never in a separate trailing commit
