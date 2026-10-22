# repo-baseline

Shared CI and GitHub settings for my actively maintained repositories (the ones
that use [renovate-config](https://github.com/AndreaCovelli/renovate-config)).

## Reusable check workflow

`.github/workflows/check.yml` checks out the repository, skips the run when no
relevant path changed, installs the tools locked in `mise.toml`, and runs
`mise run check`. Each repository calls it and adds a `Validate` gate job; the
`main` ruleset requires only `Validate`.

```yaml
jobs:
  check:
    name: Check
    uses: AndreaCovelli/repo-baseline/.github/workflows/check.yml@<sha> # vX.Y.Z
    permissions:
      contents: read
      pull-requests: read
    with:
      force: ${{ inputs.force == true }}
      paths: |
        **/*.go
        go.mod
        go.sum
        mise.toml
        mise.lock
        .github/workflows/**

  validate:
    name: Validate
    needs: [check] # and every other job in the workflow
    if: always()
    runs-on: ubuntu-26.04
    timeout-minutes: 5
    steps:
      - name: Check CI results
        env:
          NEEDS: ${{ toJSON(needs) }}
        run: jq -e 'all(.[]; .result == "success" or .result == "skipped")' <<<"$NEEDS"
```

| Input | Default | Purpose |
|---|---|---|
| `paths` | empty (always run) | paths-filter patterns, one per line; `!pattern` excludes |
| `force` | `false` | run regardless of changed paths (release workflows) |
| `task` | `check` | mise task to run |
| `setup-task` | empty | mise task to run first, e.g. `setup` for `uv sync --locked` |
| `install-args` | empty (all tools) | subset of mise tools to install |
| `cache-path` | empty (no cache) | dependency cache directories, one per line |
| `cache-key-files` | empty | globs whose contents key the dependency cache |
| `timeout-minutes` | `25` | job timeout |

Never put `paths:` on the caller's `pull_request` trigger: a required check that
never reports blocks the pull request.

## Settings and rulesets

`baseline/` describes the repository settings, Actions token permissions,
security features, and rulesets every managed repository should have. A
repository is managed when it is a non-archived, non-fork repository of the
owner whose `renovate.json` extends `github>AndreaCovelli/renovate-config`.
Repositories are discovered at run time, so no list of repository names is kept
here.

```sh
bin/baseline check                    # drift report for every managed repository
bin/baseline check my-repo            # one repository
bin/baseline apply --only settings,security my-repo
bin/baseline apply my-repo            # everything, including rulesets
```

Apply the rulesets only after the repository's default branch reports the
`Validate` check; until then pull requests cannot merge. `check` never changes
anything; `apply` needs explicit repository names or `--all`. Rulesets that the
baseline does not manage are reported, never deleted.
