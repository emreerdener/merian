#!/usr/bin/env bash
set -euo pipefail

if [[ $# -gt 0 ]]; then
  project_file="$1"
elif [[ -f "Merian.xcodeproj/project.pbxproj" ]]; then
  project_file="Merian.xcodeproj/project.pbxproj"
else
  project_file="merian.xcodeproj/project.pbxproj"
fi

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
