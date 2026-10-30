#!/bin/sh
# clean-artifacts.sh <name> - in a GitHub Actions run, deletes the artifacts with this name left
# by previous runs, so only the newest copy counts against the account's Actions storage quota.
# Artifacts of runs still in progress are kept (a later job of that run may still download them).
# Needs GH_TOKEN with "actions: write". Never fails the job: a cleanup error only prints a warning.
N=$1
[ -n "$N" ] && [ -n "$GITHUB_REPOSITORY" ] && [ -n "$GITHUB_RUN_ID" ] || { echo "usage: $0 <name> (in Actions)"; exit 0; }
gh api --paginate "repos/$GITHUB_REPOSITORY/actions/artifacts?name=$N&per_page=100" \
  -q ".artifacts[] | select(.workflow_run.id != $GITHUB_RUN_ID) | \"\(.id) \(.workflow_run.id) \(.size_in_bytes)\"" |
while read -r id run size; do
  st=$(gh api "repos/$GITHUB_REPOSITORY/actions/runs/$run" -q .status 2>/dev/null)
  if [ -n "$st" ] && [ "$st" != completed ]; then
    echo "kept $N ($id): run $run is $st"
    continue
  fi
  if gh api -X DELETE "repos/$GITHUB_REPOSITORY/actions/artifacts/$id" >/dev/null; then
    echo "deleted $N ($id, $((size / 1048576)) MB)"
  else
    echo "::warning::artifact $N ($id) not deleted"
  fi
done
exit 0
