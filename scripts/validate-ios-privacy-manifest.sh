#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manifest_path="${1:-$repo_root/apps/ios/Merian/Configuration/PrivacyInfo.xcprivacy}"

fail() {
  echo "error: Privacy manifest validation failed: $*" >&2
  exit 1
}

[[ -f "$manifest_path" && ! -L "$manifest_path" ]] \
  || fail "manifest must be a regular, non-symbolic-link file: $manifest_path"
command -v python3 >/dev/null \
  || fail "python3 is required to validate the privacy manifest."

python3 - "$manifest_path" <<'PY'
import plistlib
import sys
from pathlib import Path


class ManifestError(Exception):
    pass


def require_exact_keys(value, expected, context):
    if not isinstance(value, dict):
        raise ManifestError(f"{context} must be a dictionary")
    actual = set(value)
    if actual != expected:
        missing = ", ".join(sorted(expected - actual)) or "none"
        unexpected = ", ".join(sorted(actual - expected)) or "none"
        raise ManifestError(
            f"{context} keys differ; missing=[{missing}]; unexpected=[{unexpected}]"
        )


def require_bool(value, expected, context):
    if type(value) is not bool or value is not expected:
        expected_text = "true" if expected else "false"
        raise ManifestError(f"{context} must be {expected_text}")


def require_unique_strings(value, context):
    if not isinstance(value, list) or not value:
        raise ManifestError(f"{context} must be a non-empty array")
    if any(not isinstance(item, str) or not item for item in value):
        raise ManifestError(f"{context} must contain only non-empty strings")
    if len(value) != len(set(value)):
        raise ManifestError(f"{context} must not contain duplicates")
    return frozenset(value)


EXPECTED_ACCESSED_APIS = {
    "NSPrivacyAccessedAPICategoryFileTimestamp": frozenset({"C617.1"}),
    "NSPrivacyAccessedAPICategoryDiskSpace": frozenset({"E174.1"}),
    "NSPrivacyAccessedAPICategoryUserDefaults": frozenset({"CA92.1"}),
}

APP_FUNCTIONALITY = "NSPrivacyCollectedDataTypePurposeAppFunctionality"
ANALYTICS = "NSPrivacyCollectedDataTypePurposeAnalytics"

EXPECTED_COLLECTED_DATA = {
    "NSPrivacyCollectedDataTypeName": (True, False, frozenset({APP_FUNCTIONALITY})),
    "NSPrivacyCollectedDataTypeEmailAddress": (True, False, frozenset({APP_FUNCTIONALITY})),
    "NSPrivacyCollectedDataTypePreciseLocation": (True, False, frozenset({APP_FUNCTIONALITY})),
    "NSPrivacyCollectedDataTypeCoarseLocation": (
        True,
        False,
        frozenset({APP_FUNCTIONALITY, ANALYTICS}),
    ),
    "NSPrivacyCollectedDataTypePhotosorVideos": (True, False, frozenset({APP_FUNCTIONALITY})),
    "NSPrivacyCollectedDataTypeAudioData": (True, False, frozenset({APP_FUNCTIONALITY})),
    "NSPrivacyCollectedDataTypeCustomerSupport": (True, False, frozenset({APP_FUNCTIONALITY})),
    "NSPrivacyCollectedDataTypeOtherUserContent": (True, False, frozenset({APP_FUNCTIONALITY})),
    "NSPrivacyCollectedDataTypeUserID": (
        True,
        False,
        frozenset({APP_FUNCTIONALITY, ANALYTICS}),
    ),
    "NSPrivacyCollectedDataTypeDeviceID": (True, False, frozenset({APP_FUNCTIONALITY})),
    "NSPrivacyCollectedDataTypePurchaseHistory": (True, False, frozenset({APP_FUNCTIONALITY})),
    "NSPrivacyCollectedDataTypeProductInteraction": (
        True,
        False,
        frozenset({APP_FUNCTIONALITY, ANALYTICS}),
    ),
    "NSPrivacyCollectedDataTypeOtherUsageData": (True, False, frozenset({ANALYTICS})),
    "NSPrivacyCollectedDataTypePerformanceData": (True, False, frozenset({ANALYTICS})),
    "NSPrivacyCollectedDataTypeOtherDiagnosticData": (True, False, frozenset({ANALYTICS})),
    "NSPrivacyCollectedDataTypeOtherDataTypes": (True, False, frozenset({APP_FUNCTIONALITY})),
}


def validate_accessed_apis(entries):
    if not isinstance(entries, list):
        raise ManifestError("NSPrivacyAccessedAPITypes must be an array")

    actual = {}
    expected_keys = {
        "NSPrivacyAccessedAPIType",
        "NSPrivacyAccessedAPITypeReasons",
    }
    for index, entry in enumerate(entries):
        context = f"NSPrivacyAccessedAPITypes[{index}]"
        require_exact_keys(entry, expected_keys, context)
        api_type = entry["NSPrivacyAccessedAPIType"]
        if not isinstance(api_type, str) or not api_type:
            raise ManifestError(f"{context}.NSPrivacyAccessedAPIType must be a non-empty string")
        if api_type in actual:
            raise ManifestError(f"duplicate accessed API category: {api_type}")
        actual[api_type] = require_unique_strings(
            entry["NSPrivacyAccessedAPITypeReasons"],
            f"{api_type}.NSPrivacyAccessedAPITypeReasons",
        )

    if set(actual) != set(EXPECTED_ACCESSED_APIS):
        missing = ", ".join(sorted(set(EXPECTED_ACCESSED_APIS) - set(actual))) or "none"
        unexpected = ", ".join(sorted(set(actual) - set(EXPECTED_ACCESSED_APIS))) or "none"
        raise ManifestError(
            f"accessed API categories differ; missing=[{missing}]; unexpected=[{unexpected}]"
        )
    for api_type, expected_reasons in EXPECTED_ACCESSED_APIS.items():
        if actual[api_type] != expected_reasons:
            raise ManifestError(
                f"{api_type} reasons {sorted(actual[api_type])} do not match "
                f"{sorted(expected_reasons)}"
            )


def validate_collected_data(entries):
    if not isinstance(entries, list):
        raise ManifestError("NSPrivacyCollectedDataTypes must be an array")

    actual = {}
    expected_keys = {
        "NSPrivacyCollectedDataType",
        "NSPrivacyCollectedDataTypeLinked",
        "NSPrivacyCollectedDataTypeTracking",
        "NSPrivacyCollectedDataTypePurposes",
    }
    for index, entry in enumerate(entries):
        context = f"NSPrivacyCollectedDataTypes[{index}]"
        require_exact_keys(entry, expected_keys, context)
        data_type = entry["NSPrivacyCollectedDataType"]
        if not isinstance(data_type, str) or not data_type:
            raise ManifestError(f"{context}.NSPrivacyCollectedDataType must be a non-empty string")
        if data_type in actual:
            raise ManifestError(f"duplicate collected data type: {data_type}")

        linked = entry["NSPrivacyCollectedDataTypeLinked"]
        tracking = entry["NSPrivacyCollectedDataTypeTracking"]
        if type(linked) is not bool:
            raise ManifestError(f"{data_type}.NSPrivacyCollectedDataTypeLinked must be boolean")
        if type(tracking) is not bool:
            raise ManifestError(f"{data_type}.NSPrivacyCollectedDataTypeTracking must be boolean")
        purposes = require_unique_strings(
            entry["NSPrivacyCollectedDataTypePurposes"],
            f"{data_type}.NSPrivacyCollectedDataTypePurposes",
        )
        actual[data_type] = (linked, tracking, purposes)

    if set(actual) != set(EXPECTED_COLLECTED_DATA):
        missing = ", ".join(sorted(set(EXPECTED_COLLECTED_DATA) - set(actual))) or "none"
        unexpected = ", ".join(sorted(set(actual) - set(EXPECTED_COLLECTED_DATA))) or "none"
        raise ManifestError(
            f"collected data types differ; missing=[{missing}]; unexpected=[{unexpected}]"
        )
    for data_type, expected_configuration in EXPECTED_COLLECTED_DATA.items():
        if actual[data_type] != expected_configuration:
            raise ManifestError(
                f"{data_type} configuration {actual[data_type]} does not match "
                f"{expected_configuration}"
            )


manifest_path = Path(sys.argv[1])
try:
    with manifest_path.open("rb") as manifest_file:
        manifest = plistlib.load(manifest_file)
except (OSError, plistlib.InvalidFileException, ValueError, TypeError) as error:
    print(
        f"error: Privacy manifest validation failed: {manifest_path} could not be parsed: {error}",
        file=sys.stderr,
    )
    sys.exit(1)

try:
    require_exact_keys(
        manifest,
        {
            "NSPrivacyTracking",
            "NSPrivacyCollectedDataTypes",
            "NSPrivacyAccessedAPITypes",
        },
        "privacy manifest root",
    )
    require_bool(manifest["NSPrivacyTracking"], False, "NSPrivacyTracking")
    validate_collected_data(manifest["NSPrivacyCollectedDataTypes"])
    validate_accessed_apis(manifest["NSPrivacyAccessedAPITypes"])
except ManifestError as error:
    print(f"error: Privacy manifest validation failed: {error}", file=sys.stderr)
    sys.exit(1)

print(
    "Privacy manifest verified at "
    f"{manifest_path}: tracking=false; "
    f"collectedDataTypes={len(EXPECTED_COLLECTED_DATA)}; "
    f"accessedAPITypes={len(EXPECTED_ACCESSED_APIS)}."
)
PY
