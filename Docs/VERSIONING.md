# Versioning — TACE.Oracle.Admin

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

### AI Development Stack stages

`v0.2.0` marks the start of the stack work: Stack 0 adds public functions, so it is
a minor release. Stack 1 to Stack 10 add checks, tooling and documentation, not
public functions, so each closes as a patch release (`v0.2.1` onward). A stack stage
that does change a function signature or return shape follows the table above, with
one exception: while the module is unpublished during the stack work, a breaking
change does not trigger a major bump. It is still marked with a `BREAKING CHANGE:`
footer and recorded in `CHANGELOG.md`, and the stage closes as its planned patch
release.

Stack releases are git tags only. Nothing is published to PSGallery while the stack
work is in progress: the module is a test bed, not a functional tool, until the stages
are complete. The last version on PSGallery stays `0.1.6` until then.

## Branching Strategy

- `master` — stable, tagged releases only
- `vX.Y.Z-dev` — one branch per version (e.g. `v0.1.4-dev`)
- Merge to `master` through a pull request, with GitHub's "Create a merge commit" (the
  same as `--no-ff`; the only method allowed). A ruleset with no bypass requires the
  pull request and a passing `gate` check, so a direct push to `master` is refused
- Tag `master` after each merge using the bare version: `git tag vX.Y.Z`

**Branch and tag names must never be identical.** Using the `-dev` suffix on
branches avoids ambiguity when pushing — `git push origin vX.Y.Z` would match
both the branch and the tag and will fail. Push the tag explicitly if needed:
`git push origin refs/tags/vX.Y.Z`

## Version–Commit–Changelog Mapping

1. Update version in `Source\TACE.Oracle.Admin.psd1` (`ModuleVersion`) and `Source\TACE.Oracle.Admin.psm1` (`.NOTES`); the built manifest takes its version from the source manifest
2. Add entry to `CHANGELOG.md`
3. Commit all three in the same commit: `chore(manifest): bump version to 0.x.0`
4. `TODO.md` and `CHANGELOG.md` travel in the same commit as the code they describe —
   never in a separate trailing commit
