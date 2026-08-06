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

project_spec="${2:-project.yml}"
if [[ ! -f "$project_spec" ]]; then
  echo "Missing XcodeGen project specification: $project_spec" >&2
  exit 1
fi

if grep -qE '^[[:space:]]+CODE_SIGN_IDENTITY:' "$project_spec" \
  || grep -qE 'CODE_SIGN_IDENTITY = "?Apple Distribution"?;' "$project_file"; then
  echo "Automatic signing must not force a code-signing identity in project.yml or the generated project." >&2
  echo "Remove CODE_SIGN_IDENTITY; Xcode selects development signing locally and distribution signing for archives." >&2
  exit 1
fi

if ! grep -q 'minimumXcodeGenVersion: 2.45.4' "$project_spec" \
  || ! grep -q 'xcodeVersion: "26.6"' "$project_spec"; then
  echo "project.yml must pin XcodeGen 2.45.4 and Xcode 26.6 generation metadata." >&2
  exit 1
fi

privacy_manifest="apps/ios/Merian/Configuration/PrivacyInfo.xcprivacy"
privacy_manifest_validator="scripts/validate-ios-privacy-manifest.sh"
if [[ ! -f "$privacy_manifest_validator" ]]; then
  echo "Missing iOS privacy manifest validator: ${privacy_manifest_validator}." >&2
  exit 1
fi
bash "$privacy_manifest_validator" "$privacy_manifest"

if grep -q 'SystemCapabilities = "' "$project_file"; then
  echo "Generated SystemCapabilities metadata must not be serialized as a string." >&2
  exit 1
fi

if ! grep -q 'CODE_SIGN_ENTITLEMENTS = apps/ios/Merian/Configuration/Merian.entitlements;' "$project_file" \
  || ! grep -q 'APS_ENVIRONMENT = development;' "$project_file" \
  || ! grep -q 'APS_ENVIRONMENT = production;' "$project_file"; then
  echo "Missing generated Merian push-notification entitlement or APS environment settings." >&2
  exit 1
fi

native_targets_section="$(
  awk '
    /\/\* Begin PBXNativeTarget section \*\// {
      in_section = 1
      next
    }
    /\/\* End PBXNativeTarget section \*\// {
      in_section = 0
    }
    in_section {
      print
    }
  ' "$project_file"
)"

merian_target_count="$(
  grep -cE '/\* Merian \*/ = \{$' <<<"$native_targets_section" || true
)"
if [[ "$merian_target_count" -ne 1 ]]; then
  echo "Generated project must contain exactly one Merian native target; found ${merian_target_count}." >&2
  exit 1
fi

merian_target_block="$(
  awk '
    /\/\* Begin PBXNativeTarget section \*\// {
      in_section = 1
      next
    }
    /\/\* End PBXNativeTarget section \*\// {
      in_section = 0
    }
    in_section && /\/\* Merian \*\/ = \{$/ {
      capture = 1
    }
    capture {
      print
    }
    capture && /^[[:space:]]*};$/ {
      exit
    }
  ' "$project_file"
)"

merian_build_phases="$(
  awk '
    /buildPhases = \(/ {
      capture = 1
      next
    }
    capture && /^[[:space:]]*\);$/ {
      exit
    }
    capture {
      print
    }
  ' <<<"$merian_target_block"
)"

merian_resources_phase_id="$(
  awk '
    /\/\* Resources \*\// {
      print $1
    }
  ' <<<"$merian_build_phases"
)"
if [[ ! "$merian_resources_phase_id" =~ ^[A-F0-9]+$ ]]; then
  echo "Generated Merian target must contain exactly one Resources build phase." >&2
  exit 1
fi

merian_resources_phase_block="$(
  awk -v phase_id="$merian_resources_phase_id" '
    /\/\* Begin PBXResourcesBuildPhase section \*\// {
      in_section = 1
      next
    }
    /\/\* End PBXResourcesBuildPhase section \*\// {
      in_section = 0
    }
    in_section && $1 == phase_id && /= \{$/ {
      capture = 1
    }
    capture {
      print
    }
    capture && /^[[:space:]]*};$/ {
      exit
    }
  ' "$project_file"
)"
privacy_manifest_target_count="$(
  grep -Fc 'PrivacyInfo.xcprivacy in Resources' \
    <<<"$merian_resources_phase_block" || true
)"
privacy_manifest_global_count="$(
  grep -Fc 'PrivacyInfo.xcprivacy in Resources' "$project_file" || true
)"
if [[ "$privacy_manifest_target_count" -ne 1 \
  || "$privacy_manifest_global_count" -ne 2 ]]; then
  echo "PrivacyInfo.xcprivacy must be bundled exactly once and only by the Merian target." >&2
  exit 1
fi

shell_phase_id() {
  local phase_name="$1"
  awk -v phase_name="$phase_name" '
    /\/\* Begin PBXShellScriptBuildPhase section \*\// {
      in_section = 1
      next
    }
    /\/\* End PBXShellScriptBuildPhase section \*\// {
      in_section = 0
    }
    in_section && index($0, "/* " phase_name " */ = {") {
      print $1
    }
  ' "$project_file"
}

shell_phase_block() {
  local phase_id="$1"
  awk -v phase_id="$phase_id" '
    /\/\* Begin PBXShellScriptBuildPhase section \*\// {
      in_section = 1
      next
    }
    /\/\* End PBXShellScriptBuildPhase section \*\// {
      in_section = 0
    }
    in_section && $1 == phase_id && /= \{$/ {
      capture = 1
    }
    capture {
      print
    }
    capture && /^[[:space:]]*};$/ {
      exit
    }
  ' "$project_file"
}

phase_position() {
  local phase_name="$1"
  grep -nF "/* ${phase_name} */" <<<"$merian_build_phases" \
    | cut -d: -f1 \
    || true
}

validate_main_target_shell_phase() {
  local phase_name="$1"
  local expected_script="$2"
  local phase_id
  local phase_definition
  local target_reference_count
  local all_target_reference_count
  local always_out_of_date_line
  local shell_path_line
  local shell_script_line
  local expected_shell_script_line

  phase_id="$(shell_phase_id "$phase_name")"
  if [[ ! "$phase_id" =~ ^[A-F0-9]+$ ]]; then
    echo "Generated project must define exactly one ${phase_name} shell phase." >&2
    exit 1
  fi

  target_reference_count="$(
    grep -cE "^[[:space:]]*${phase_id}[[:space:]]" <<<"$merian_build_phases" || true
  )"
  all_target_reference_count="$(
    grep -cE "^[[:space:]]*${phase_id}[[:space:]]" <<<"$native_targets_section" || true
  )"
  if [[ "$target_reference_count" -ne 1 || "$all_target_reference_count" -ne 1 ]]; then
    echo "${phase_name} must be attached exactly once and only to the Merian target." >&2
    exit 1
  fi

  phase_definition="$(shell_phase_block "$phase_id")"
  always_out_of_date_line="$(
    grep -E '^[[:space:]]*alwaysOutOfDate = ' <<<"$phase_definition" \
      | sed 's/^[[:space:]]*//' \
      || true
  )"
  shell_path_line="$(
    grep -E '^[[:space:]]*shellPath = ' <<<"$phase_definition" \
      | sed 's/^[[:space:]]*//' \
      || true
  )"
  shell_script_line="$(
    grep -E '^[[:space:]]*shellScript = ' <<<"$phase_definition" \
      | sed 's/^[[:space:]]*//' \
      || true
  )"
  expected_shell_script_line="shellScript = \"bash \\\"\${SRCROOT}/${expected_script}\\\"\\n\";"
  if [[ "$always_out_of_date_line" != "alwaysOutOfDate = 1;" \
    || "$shell_path_line" != "shellPath = /bin/sh;" \
    || "$shell_script_line" != "$expected_shell_script_line" ]]; then
    echo "${phase_name} must remain always-out-of-date and invoke only ${expected_script}." >&2
    exit 1
  fi
}

validate_main_target_shell_phase \
  "Release Versioning Preflight" \
  "scripts/check-ios-release-prep.sh"
validate_main_target_shell_phase \
  "Embed Build Provenance" \
  "scripts/embed-ios-build-provenance.sh"

preflight_position="$(phase_position "Release Versioning Preflight")"
provenance_position="$(phase_position "Embed Build Provenance")"
swiftlint_position="$(phase_position "SwiftLint Validation")"
if [[ "$preflight_position" != "1" ]]; then
  echo "Release Versioning Preflight must be the first Merian build phase." >&2
  exit 1
fi

for prerequisite_phase in \
  "Sources" \
  "Resources" \
  "Frameworks" \
  "Embed Foundation Extensions" \
  "Embed Watch Content"; do
  prerequisite_position="$(phase_position "$prerequisite_phase")"
  if [[ ! "$prerequisite_position" =~ ^[0-9]+$ ]] \
    || (( prerequisite_position >= provenance_position )); then
    echo "Embed Build Provenance must run after Merian ${prerequisite_phase}." >&2
    exit 1
  fi
done

phase_count="$(
  sed -n 's/.*\/\* .* \*\/,.*/phase/p' <<<"$merian_build_phases" \
    | wc -l \
    | tr -d '[:space:]'
)"
if [[ ! "$provenance_position" =~ ^[0-9]+$ \
  || ! "$swiftlint_position" =~ ^[0-9]+$ ]]; then
  echo "Embed Build Provenance and SwiftLint Validation must each appear exactly once in the Merian build phases." >&2
  exit 1
fi
if (( provenance_position + 1 != swiftlint_position )) \
  || (( swiftlint_position != phase_count )); then
  echo "Embed Build Provenance must be the final product-mutating Merian phase, immediately before SwiftLint Validation." >&2
  exit 1
fi

for provenance_script in \
  scripts/embed-ios-build-provenance.sh \
  scripts/ios-release-source-fingerprint.sh; do
  if [[ ! -x "$provenance_script" ]]; then
    echo "Missing executable iOS provenance script: ${provenance_script}." >&2
    exit 1
  fi
done

app_info_plist="apps/ios/Merian/Configuration/Info.plist"
for provenance_key in \
  MERIAN_SOURCE_REVISION \
  MERIAN_SOURCE_FINGERPRINT \
  MERIAN_SOURCE_STATE; do
  if ! grep -q "<key>${provenance_key}</key>" "$app_info_plist"; then
    echo "Missing ${provenance_key} from ${app_info_plist}." >&2
    exit 1
  fi
done
