#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_OUTPUT:?Missing GITHUB_OUTPUT}"
: "${GITHUB_STEP_SUMMARY:?Missing GITHUB_STEP_SUMMARY}"
: "${GITHUB_SHA:?Missing GITHUB_SHA}"
: "${GITHUB_REF:?Missing GITHUB_REF}"

# Fail closed even when verification exits before classifying the candidate.
echo "current=false" >> "$GITHUB_OUTPUT"
checked_out_sha="$(git rev-parse HEAD)"
main_sha="$(git rev-parse --verify refs/remotes/origin/main^{commit})"
if [ "$GITHUB_REF" != "refs/heads/main" ]; then
  echo "Production deployment must originate from refs/heads/main." >&2
  exit 1
fi
if [ "$checked_out_sha" != "$GITHUB_SHA" ]; then
  echo "Production hold checkout does not match GITHUB_SHA." >&2
  exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
  echo "Production hold checkout is not clean." >&2
  exit 1
fi
if [ "$checked_out_sha" != "$main_sha" ]; then
  if ! git merge-base --is-ancestor "$checked_out_sha" "$main_sha"; then
    echo "Production hold candidate is not an ancestor of current origin/main." >&2
    exit 1
  fi
  echo "status=superseded" >> "$GITHUB_OUTPUT"
  echo "Production candidate was superseded; deployment is skipped."
  {
    echo "### Production candidate superseded"
    echo
    echo "Validated candidate: $checked_out_sha"
    echo "Current main: $main_sha"
    echo
    echo "A newer main commit includes this candidate. Production deployment was skipped before accessing the Production environment. Follow the newer candidate's validation and release checks."
    echo "This successful no-op is not evidence of a deployment."
  } >> "$GITHUB_STEP_SUMMARY"
  exit 0
fi
echo "current=true" >> "$GITHUB_OUTPUT"
echo "status=current" >> "$GITHUB_OUTPUT"
