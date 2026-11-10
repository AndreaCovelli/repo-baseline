# repo-baseline

Shared CI and GitHub settings for my actively maintained repositories (the ones
that use [renovate-config](https://github.com/AndreaCovelli/renovate-config)).

## Shared check action

`.github/actions/check` checks out the repository, skips the work when no
relevant path changed, installs the tools locked in `mise.toml`, and runs
`mise run check`. Use it as a step of one job named `Validate`, the only check
the `main` ruleset requires. Hosted runners bill every job by the started
minute, so one job instead of a check job plus a gate job halves the cost of a
typical run.

On a push to the default branch it also skips the task when the pushed commit
is the squash merge of a pull request whose head had the same tree and passed
`Validate`: that exact code was already checked. It still installs the tools and
seeds a missing dependency cache, because pull requests only read caches.

```yaml
permissions:
  contents: read

concurrency:
  group: ci-${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}

jobs:
  validate:
    name: Validate
    runs-on: ubuntu-26.04
    timeout-minutes: 10
    permissions:
      checks: read
      contents: read
      pull-requests: read
    steps:
      - name: Check
        id: check
        uses: AndreaCovelli/repo-baseline/.github/actions/check@<sha> # vX.Y.Z
        with:
          force: ${{ inputs.force == true }}
          paths: |
            **/*.go
            go.mod
            go.sum
            mise.toml
            mise.lock
            .github/workflows/**
      # Later repository-specific steps:
      # if: steps.check.outputs.relevant == 'true'
```

| Input | Default | Purpose |
|---|---|---|
| `paths` | empty (always run) | paths-filter patterns, one per line; `!pattern` excludes |
| `force` | `false` | run regardless of changed paths and earlier results (release workflows) |
| `reuse` | `true` | skip the task on a default-branch push whose tree a pull request already validated |
| `check-name` | `Validate` | check that must have passed on the pull request head |
| `task` | `check` | mise task to run |
| `setup-task` | empty | mise task to run first, e.g. `setup` for `uv sync --locked` |
| `install-args` | empty (all tools) | subset of mise tools to install |
| `cache-path` | empty (no cache) | dependency cache directories, one per line |
| `cache-key-files` | empty | globs whose contents key the dependency cache |
| `checkout` | `true` | `false` when an earlier step already checked out |

Outputs: `relevant` is `true` when the task ran; `reused` is `true` when a push
skipped it because a pull request already validated the tree. Gate later steps
on `relevant`.

Set `timeout-minutes` on the job from its normal runtime plus headroom: a stalled
tool download otherwise bills until the timeout.

Never put `paths:` on the caller's `pull_request` trigger: a required check that
never reports blocks the pull request.

### Skipping work a pull request already did

Workflows that do not use the check action can call
`.github/actions/tree-validated` and gate their expensive steps or jobs on its
`validated` output. It is `true` only on a push to the default branch whose
commit is a merged pull request's merge commit with the same tree as that pull
request's head, where the head passed `check-name` (default `Validate`). Any API
error yields `false`, so the work runs. The job needs `checks: read`,
`contents: read`, and `pull-requests: read`.

```yaml
      - name: Look for an earlier validation
        id: earlier
        uses: AndreaCovelli/repo-baseline/.github/actions/tree-validated@<sha> # vX.Y.Z
      - name: Run instrumented tests
        if: steps.earlier.outputs.validated != 'true'
        run: ./gradlew connectedCheck
```

### Deprecated reusable workflow

`.github/workflows/check.yml` stays unchanged until v2.0.0. A called workflow's
check is named `<caller job> / Check`, so it needs a separate `Validate` gate
job, which bills an extra minute on every run. Migrate to the check action.

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
