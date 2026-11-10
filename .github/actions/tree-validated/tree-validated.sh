#!/usr/bin/env bash
# Decide whether a pushed commit's tree was already validated by a pull request.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: tree-validated.sh

Print `validated=true` when the commit GITHUB_SHA is the merge commit of a pull
request whose head commit has the same tree and a successful CHECK_NAME check
run, otherwise `validated=false`. Append the result to GITHUB_OUTPUT when set.

Any API error prints `validated=false`, so the caller runs its checks.

Environment:
  GH_TOKEN           token with contents, pull-requests, and checks read access
  GITHUB_REPOSITORY  owner/name
  GITHUB_SHA         pushed commit
  CHECK_NAME         required check that must have passed (default: Validate)
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

: "${GITHUB_REPOSITORY:?}" "${GITHUB_SHA:?}"
check_name="${CHECK_NAME:-Validate}"
repo="$GITHUB_REPOSITORY"
sha="$GITHUB_SHA"

result() {
  echo "validated=$1"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "validated=$1" >>"$GITHUB_OUTPUT"
  fi
  if [[ "$1" == true ]]; then
    echo "::notice::$2"
  else
    echo "$2" >&2
  fi
  exit 0
}

tree=$(gh api "repos/$repo/git/commits/$sha" --jq .tree.sha 2>/dev/null) ||
  result false "Cannot read commit $sha; running checks"

pulls=$(gh api "repos/$repo/commits/$sha/pulls" 2>/dev/null) ||
  result false "Cannot list pull requests for $sha; running checks"
head=$(jq -r --arg sha "$sha" \
  'first(.[] | select(.merged_at != null and .merge_commit_sha == $sha) | .head.sha) // empty' \
  <<<"$pulls")
[[ -n "$head" ]] || result false "No merged pull request has merge commit $sha; running checks"

head_tree=$(gh api "repos/$repo/git/commits/$head" --jq .tree.sha 2>/dev/null) ||
  result false "Cannot read pull request head $head; running checks"
[[ "$head_tree" == "$tree" ]] ||
  result false "Tree differs from pull request head $head; running checks"

passed=$(gh api -X GET "repos/$repo/commits/$head/check-runs" \
  -f check_name="$check_name" -f filter=latest \
  --jq '[.check_runs[] | select(.conclusion == "success")] | length' 2>/dev/null) ||
  result false "Cannot read check runs of $head; running checks"
[[ "$passed" -gt 0 ]] ||
  result false "$check_name did not pass on pull request head $head; running checks"

result true "Tree $tree already passed $check_name on pull request head $head; skipping checks"
