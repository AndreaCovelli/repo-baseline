# AGENTS.md

- `bin/baseline check` is read-only; never run `bin/baseline apply` unless the
  user asked for it, and name the repositories explicitly.
- Changes to `.github/workflows/check.yml` reach every repository once Renovate
  bumps them: keep inputs backward compatible within a major version, and
  release with a semver tag.
- Pin actions by full commit SHA with a version comment.
- Run `mise run check` before committing.
