#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

require_literal() {
  local literal="$1"
  local file="$2"
  grep -Fq -- "$literal" "$file" \
    || fail "expected $file to contain: $literal"
}

for retired_file in \
  .github/workflows/ios-testflight-beta.yml \
  .github/workflows/ios-testflight-publisher.yml \
  scripts/publish-ios-beta.sh \
  scripts/export-ios-release.sh \
  scripts/prepare-ios-release.sh \
  scripts/test-ios-publisher-workflow.sh
do
  [[ ! -e "$retired_file" ]] \
    || fail "retired GitHub publisher artifact exists: $retired_file"
done

require_literal 'Product > Archive, then Organizer > Distribute App' Makefile
require_literal 'MERIAN_IOS_VALIDATION_ARCHIVE=1' \
  .github/workflows/ios-build-and-test.yml
require_literal 'CODE_SIGNING_ALLOWED=NO' \
  .github/workflows/ios-build-and-test.yml
require_literal 'bash scripts/validate-ios-privacy-manifest.sh "$privacy_manifest"' \
  .github/workflows/ios-build-and-test.yml
require_literal 'privacyManifest=valid' scripts/validate-ios-archive.sh
require_literal 'privacyManifest=valid' scripts/validate-ios-exported-ipa.sh
require_literal 'CODE_SIGN_STYLE must remain Automatic for Organizer distribution' \
  scripts/check-ios-release-prep.sh
require_literal 'keep Manage version and build number enabled' \
  scripts/check-ios-release-prep.sh
require_literal 'Xcode Organizer is the sole distribution authority' \
  docs/development-guides/14-ios-release-versioning.md
require_literal 'TestFlight & App Store' \
  docs/development-guides/14-ios-release-versioning.md
require_literal 'Manage version and build number' \
  docs/development-guides/14-ios-release-versioning.md
require_literal 'same uploaded binary' \
  docs/development-guides/14-ios-release-versioning.md
require_literal 'not a second deployment procedure' \
  apps/ios/.agents/workflows/deploy_testflight.md

if grep -REq --include='*.yml' --include='*.yaml' \
  '(iTMSTransporter|IOS_DISTRIBUTION_CERTIFICATE|ASC_PRIVATE_KEY)' \
  .github/workflows; then
  fail "GitHub Actions contains a signing or App Store upload implementation."
fi

echo "Xcode Organizer release workflow invariants passed."
