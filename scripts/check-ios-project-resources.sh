#!/usr/bin/env bash
set -euo pipefail

project_file="${1:-merian.xcodeproj/project.pbxproj}"

if [[ ! -f "$project_file" ]]; then
  echo "Missing generated Xcode project file: $project_file" >&2
  exit 1
fi

if grep -nE "[.]md in Resources|README[.]md in Resources" "$project_file"; then
  echo "Markdown documentation must not be bundled into iOS app resources." >&2
  echo "Keep folder docs in the repo, and exclude **/*.md in project.yml target sources." >&2
  exit 1
fi

if ! grep -q "MerianObjCExceptionBridge.m in Sources" "$project_file"; then
  echo "Missing MerianObjCExceptionBridge.m from the Merian target sources." >&2
  exit 1
fi

if ! grep -q "SWIFT_OBJC_BRIDGING_HEADER = \"apps/ios/Merian/Configuration/Merian-Bridging-Header.h\"" "$project_file"; then
  echo "Missing Merian Objective-C bridging header setting from the Merian target." >&2
  exit 1
fi
