#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="${MERIAN_PROJECT_ROOT:-$(cd "$script_dir/.." && pwd)}"
fingerprint_script="$script_dir/ios-release-source-fingerprint.sh"

PROJECT_YML="${PROJECT_YML:-project.yml}"
PROJECT_FILE="${PROJECT_FILE:-Merian.xcodeproj/project.pbxproj}"
MARKER_FILE="${IOS_RELEASE_PREP_MARKER:-build/ios-release-prep.json}"
RUN_XCODEGEN="${RUN_XCODEGEN:-1}"
REQUIRED_XCODEGEN_VERSION="${REQUIRED_XCODEGEN_VERSION:-2.45.4}"
XCODEGEN_COMMAND="${XCODEGEN_COMMAND:-xcodegen}"
CONFIG_XCCONFIG="${CONFIG_XCCONFIG:-Config.xcconfig}"
LOCAL_CONFIG_FILE="${LOCAL_CONFIG_FILE:-Config.local.xcconfig}"

fail() {
  echo "error: $*" >&2
  exit 1
}

note() {
  echo "$*" >&2
}

print_revenuecat_release_help() {
  echo "Production/TestFlight builds should use the ignored local release config:" >&2
  echo "  cp Config.local.example.xcconfig Config.local.xcconfig" >&2
  echo "  # edit Config.local.xcconfig: REVENUECAT_API_KEY = appl_..." >&2
  echo "Or let release prep write the ignored override:" >&2
  echo "  REVENUECAT_API_KEY=appl_... make prepare-ios-release VERSION=x.y.z" >&2
}

fail_revenuecat() {
  echo "error: $*" >&2
  print_revenuecat_release_help
  exit 1
}

warn_revenuecat() {
  echo "warning: $*" >&2
  print_revenuecat_release_help
}

is_placeholder_revenuecat_key() {
  case "$1" in
    "appl_..." | appl_replace* | appl_your* | appl_live_key)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

extract_project_setting() {
  local key="$1"
  local file="$2"
  awk -v key="$key" '
    $1 == key ":" {
      print $2
      found = 1
      exit
    }
    END {
      if (!found) {
        exit 1
      }
    }
  ' "$file"
}

is_positive_int() {
  [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

is_semantic_version() {
  [[ "$1" =~ ^[1-9][0-9]*\.[0-9]+\.[0-9]+$ ]]
}

semantic_version_is_at_least() {
  local candidate="$1"
  local baseline="$2"
  local candidate_major
  local candidate_minor
  local candidate_patch
  local baseline_major
  local baseline_minor
  local baseline_patch

  IFS=. read -r candidate_major candidate_minor candidate_patch <<<"$candidate"
  IFS=. read -r baseline_major baseline_minor baseline_patch <<<"$baseline"

  if (( 10#$candidate_major != 10#$baseline_major )); then
    (( 10#$candidate_major > 10#$baseline_major ))
    return
  fi
  if (( 10#$candidate_minor != 10#$baseline_minor )); then
    (( 10#$candidate_minor > 10#$baseline_minor ))
    return
  fi
  (( 10#$candidate_patch >= 10#$baseline_patch ))
}

max_int() {
  local a="$1"
  local b="$2"
  if (( a > b )); then
    echo "$a"
  else
    echo "$b"
  fi
}

have_asc_credentials() {
  [[ -n "${ASC_APP_ID:-}" && -n "${ASC_ISSUER_ID:-}" && -n "${ASC_KEY_ID:-}" && -n "${ASC_PRIVATE_KEY_PATH:-}" ]]
}

make_app_store_connect_jwt() {
  [[ -r "$ASC_PRIVATE_KEY_PATH" ]] || fail "ASC_PRIVATE_KEY_PATH is not readable: $ASC_PRIVATE_KEY_PATH"

  ruby - "$ASC_KEY_ID" "$ASC_ISSUER_ID" "$ASC_PRIVATE_KEY_PATH" <<'RUBY'
require "base64"
require "json"
require "openssl"

key_id, issuer_id, private_key_path = ARGV

def base64url(data)
  Base64.urlsafe_encode64(data).delete("=")
end

def fixed_width_integer(integer)
  bytes = integer.to_s(2)
  bytes = bytes.byteslice(-32, 32) if bytes.bytesize > 32
  bytes.rjust(32, "\0")
end

header = {
  "alg" => "ES256",
  "kid" => key_id,
  "typ" => "JWT"
}

issued_at = Time.now.to_i
payload = {
  "iss" => issuer_id,
  "iat" => issued_at,
  "exp" => issued_at + 1200,
  "aud" => "appstoreconnect-v1"
}

encoded_header = base64url(header.to_json)
encoded_payload = base64url(payload.to_json)
signing_input = "#{encoded_header}.#{encoded_payload}"

private_key = OpenSSL::PKey.read(File.read(private_key_path))
signature_der = private_key.sign(OpenSSL::Digest::SHA256.new, signing_input)
signature_sequence = OpenSSL::ASN1.decode(signature_der)
raw_signature = signature_sequence.value.map { |part| fixed_width_integer(part.value) }.join

puts "#{signing_input}.#{base64url(raw_signature)}"
RUBY
}

parse_latest_build_from_response() {
  ruby -rjson -e '
    document = JSON.parse(STDIN.read)
    builds = document["data"]
    abort("response data is not an array") unless builds.is_a?(Array)

    versions = builds.map do |build|
      unless build.is_a?(Hash) && build["type"] == "builds"
        abort("response contains an invalid build resource")
      end

      attributes = build["attributes"]
      version = attributes["version"] if attributes.is_a?(Hash)
      unless version.is_a?(String) && version.match?(/\A[1-9][0-9]*\z/)
        abort("response contains an invalid build version")
      end
      version.to_i
    end

    puts(versions.max || 0)
  '
}

fetch_latest_app_store_connect_build() {
  command -v curl >/dev/null 2>&1 || fail "curl is required for App Store Connect lookup"
  command -v ruby >/dev/null 2>&1 || fail "ruby is required for App Store Connect JWT signing"

  local jwt
  local body_file
  local curl_status
  local http_code
  local latest_build
  local request_url

  jwt="$(make_app_store_connect_jwt)"
  body_file="$(mktemp)"
  request_url="https://api.appstoreconnect.apple.com/v1/builds"

  if http_code="$(
    curl --silent --show-error \
      --proto '=https' \
      --get \
      --data-urlencode "filter[app]=${ASC_APP_ID}" \
      --data-urlencode 'limit=1' \
      --data-urlencode 'sort=-version' \
      --data-urlencode 'fields[builds]=version' \
      --connect-timeout 5 \
      --max-time 15 \
      --retry 2 \
      --retry-delay 1 \
      --retry-all-errors \
      --max-filesize 1048576 \
      -o "$body_file" \
      -w "%{http_code}" \
      -H "Authorization: Bearer ${jwt}" \
      "$request_url"
  )"; then
    :
  else
    curl_status="$?"
    rm -f "$body_file"
    fail "App Store Connect build lookup transport failed (curl ${curl_status})"
  fi

  if [[ ! "$http_code" =~ ^2[0-9]{2}$ ]]; then
    sed 's/^/App Store Connect: /' "$body_file" >&2
    rm -f "$body_file"
    fail "App Store Connect build lookup failed with HTTP ${http_code}"
  fi

  if latest_build="$(parse_latest_build_from_response < "$body_file")"; then
    :
  else
    rm -f "$body_file"
    fail "App Store Connect returned a malformed build-list response"
  fi
  rm -f "$body_file"
  if [[ -z "$latest_build" ]]; then
    latest_build="0"
  fi
  is_positive_int "$latest_build" || [[ "$latest_build" == "0" ]] || fail "App Store Connect returned an invalid latest build: $latest_build"

  printf '%s\n' "$latest_build"
}

write_project_versions() {
  local version="$1"
  local build="$2"
  local file="$3"
  local tmp_file

  tmp_file="${file}.tmp.$$"

  if ! awk -v version="$version" -v build="$build" '
    $1 == "MARKETING_VERSION:" && !wrote_version {
      sub(/MARKETING_VERSION:.*/, "MARKETING_VERSION: " version)
      wrote_version = 1
    }
    $1 == "CURRENT_PROJECT_VERSION:" && !wrote_build {
      sub(/CURRENT_PROJECT_VERSION:.*/, "CURRENT_PROJECT_VERSION: " build)
      wrote_build = 1
    }
    { print }
    END {
      if (!wrote_version || !wrote_build) {
        exit 2
      }
    }
  ' "$file" > "$tmp_file"; then
    rm -f "$tmp_file"
    fail "Could not update MARKETING_VERSION/CURRENT_PROJECT_VERSION in $file"
  fi

  mv "$tmp_file" "$file"
}

write_release_marker() {
  local version="$1"
  local build="$2"
  local anchor_source="$3"
  local anchor_build="$4"
  local source_fingerprint="$5"
  local prepared_from_sha="$6"
  local marker="$7"
  local anchor_build_json="null"

  if [[ -n "$anchor_build" ]]; then
    anchor_build_json="$anchor_build"
  fi

  mkdir -p "$(dirname "$marker")"
  {
    printf '{\n'
    printf '  "version": "%s",\n' "$version"
    printf '  "build": %s,\n' "$build"
    printf '  "anchor_source": "%s",\n' "$anchor_source"
    printf '  "anchor_build": %s,\n' "$anchor_build_json"
    printf '  "source_fingerprint": "%s",\n' "$source_fingerprint"
    printf '  "prepared_from_sha": "%s",\n' "$prepared_from_sha"
    printf '  "generated_at": "%s"\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    printf '}\n'
  } > "$marker"
}

read_xcconfig_key() {
  local key="$1"
  local file="$2"

  [[ -f "$file" ]] || return 1
  awk -v key="$key" '
    /^[[:space:]]*\/\// { next }
    /^[[:space:]]*#/ { next }
    {
      line = $0
      sub(/[[:space:]]*\/\/.*/, "", line)
      if (line ~ "^[[:space:]]*" key "[[:space:]]*=") {
        sub("^[[:space:]]*" key "[[:space:]]*=[[:space:]]*", "", line)
        sub(/[[:space:]]+$/, "", line)
        print line
      }
    }
  ' "$file" | tail -n 1
}

validate_release_revenuecat_key() {
  local key="$1"
  local source="$2"

  [[ -n "$key" ]] || fail_revenuecat "Release REVENUECAT_API_KEY is missing from ${source}."
  case "$key" in
    test_*)
      fail_revenuecat "Release REVENUECAT_API_KEY resolves to a RevenueCat Test Store key from ${source}."
      ;;
    appl_*)
      if is_placeholder_revenuecat_key "$key"; then
        fail_revenuecat "Release REVENUECAT_API_KEY from ${source} is still a placeholder. Use the real RevenueCat production iOS SDK key."
      fi
      ;;
    *)
      fail_revenuecat "Release REVENUECAT_API_KEY from ${source} must be a RevenueCat iOS production key beginning with appl_."
      ;;
  esac
}

release_revenuecat_key_warning() {
  local key="$1"
  local source="$2"

  if [[ -z "$key" ]]; then
    echo "Release REVENUECAT_API_KEY is missing from ${source}."
    return
  fi

  case "$key" in
    test_*)
      echo "Release REVENUECAT_API_KEY resolves to a RevenueCat Test Store key from ${source}."
      ;;
    appl_*)
      if is_placeholder_revenuecat_key "$key"; then
        echo "Release REVENUECAT_API_KEY from ${source} is still a placeholder. Use the real RevenueCat production iOS SDK key."
      fi
      ;;
    *)
      echo "Release REVENUECAT_API_KEY from ${source} should be a RevenueCat iOS production key beginning with appl_."
      ;;
  esac
}

write_local_revenuecat_key() {
  local key="$1"
  local file="$2"
  local tmp_file

  mkdir -p "$(dirname "$file")"
  if [[ ! -f "$file" ]]; then
    if [[ "$file" == "Config.local.xcconfig" && -f "Config.local.example.xcconfig" ]]; then
      cp "Config.local.example.xcconfig" "$file"
    else
      {
        printf '// Machine-local client config overrides. Ignored by git.\n'
        printf '// Public client values in this file are embedded in local app builds.\n'
      } > "$file"
    fi
  fi

  tmp_file="${file}.tmp.$$"
  if grep -qE '^[[:space:]]*REVENUECAT_API_KEY[[:space:]]*=' "$file"; then
    awk -v key="$key" '
      /^[[:space:]]*REVENUECAT_API_KEY[[:space:]]*=/ {
        if (!wrote) {
          print "REVENUECAT_API_KEY = " key
          wrote = 1
        }
        next
      }
      { print }
    ' "$file" > "$tmp_file"
  else
    {
      cat "$file"
      printf '\nREVENUECAT_API_KEY = %s\n' "$key"
    } > "$tmp_file"
  fi
  mv "$tmp_file" "$file"
}

prepare_release_revenuecat_key() {
  local key
  local source
  local warning

  if [[ -n "${REVENUECAT_API_KEY:-}" ]]; then
    validate_release_revenuecat_key "$REVENUECAT_API_KEY" "REVENUECAT_API_KEY"
    write_local_revenuecat_key "$REVENUECAT_API_KEY" "$LOCAL_CONFIG_FILE"
    note "Wrote RevenueCat release key override to ${LOCAL_CONFIG_FILE}."
    return
  fi

  key="$(read_xcconfig_key REVENUECAT_API_KEY "$LOCAL_CONFIG_FILE" || true)"
  source="$LOCAL_CONFIG_FILE"
  if [[ -n "$key" ]]; then
    if [[ "${MERIAN_REQUIRE_PRODUCTION_REVENUECAT_KEY:-0}" == "1" ]]; then
      validate_release_revenuecat_key "$key" "$source"
    else
      warning="$(release_revenuecat_key_warning "$key" "$source")"
      [[ -z "$warning" ]] || warn_revenuecat "$warning"
    fi
    return
  fi

  key="$(read_xcconfig_key REVENUECAT_API_KEY "$CONFIG_XCCONFIG" || true)"
  source="$CONFIG_XCCONFIG"
  if [[ "${MERIAN_REQUIRE_PRODUCTION_REVENUECAT_KEY:-0}" == "1" ]]; then
    validate_release_revenuecat_key "$key" "$source"
  else
    warning="$(release_revenuecat_key_warning "$key" "$source")"
    [[ -z "$warning" ]] || warn_revenuecat "$warning"
  fi
}

require_release_xcodegen() {
  if [[ "$RUN_XCODEGEN" == "0" ]]; then
    return 0
  fi

  command -v "$XCODEGEN_COMMAND" >/dev/null 2>&1 \
    || fail "xcodegen is required. Install with: brew install xcodegen"

  local installed_xcodegen_version
  installed_xcodegen_version="$("$XCODEGEN_COMMAND" --version | awk '{ print $NF }')"
  if [[ "$installed_xcodegen_version" != "$REQUIRED_XCODEGEN_VERSION" ]]; then
    fail "xcodegen ${REQUIRED_XCODEGEN_VERSION} is required for reproducible release generation; found ${installed_xcodegen_version}"
  fi
}

cd "$repo_root" || fail "Could not enter project root: $repo_root"
[[ -f "$PROJECT_YML" ]] || fail "Missing project.yml at $PROJECT_YML"
require_release_xcodegen

target_version="${VERSION:-}"
[[ -n "$target_version" ]] || fail "VERSION is required. Example: make prepare-ios-release VERSION=1.0.2"
is_semantic_version "$target_version" || fail "VERSION must be semantic x.y.z with a positive major version, got: $target_version"

repo_version="$(extract_project_setting MARKETING_VERSION "$PROJECT_YML")" || fail "Could not read MARKETING_VERSION from $PROJECT_YML"
repo_build="$(extract_project_setting CURRENT_PROJECT_VERSION "$PROJECT_YML")" || fail "Could not read CURRENT_PROJECT_VERSION from $PROJECT_YML"
is_semantic_version "$repo_version" || fail "MARKETING_VERSION must be semantic x.y.z in $PROJECT_YML, got: $repo_version"
semantic_version_is_at_least "$target_version" "$repo_version" \
  || fail "VERSION $target_version must not be lower than repo version $repo_version"
is_positive_int "$repo_build" || fail "CURRENT_PROJECT_VERSION must be a positive integer in $PROJECT_YML, got: $repo_build"

anchor_build=""
anchor_source=""
target_build=""

if [[ -n "${BUILD:-}" ]]; then
  is_positive_int "$BUILD" || fail "BUILD must be a positive integer, got: $BUILD"
  target_build="$BUILD"
  anchor_source="manual_build"

  if [[ -n "${LATEST_ASC_BUILD:-}" ]]; then
    is_positive_int "$LATEST_ASC_BUILD" || [[ "$LATEST_ASC_BUILD" == "0" ]] || fail "LATEST_ASC_BUILD must be a non-negative integer, got: $LATEST_ASC_BUILD"
    anchor_build="$LATEST_ASC_BUILD"
    anchor_source="manual_build_checked_against_latest_asc_build"
  elif have_asc_credentials; then
    note "Checking App Store Connect before accepting manual BUILD=${BUILD}..."
    anchor_build="$(fetch_latest_app_store_connect_build)"
    anchor_source="manual_build_checked_against_app_store_connect"
  fi
else
  if [[ -n "${LATEST_ASC_BUILD:-}" ]]; then
    is_positive_int "$LATEST_ASC_BUILD" || [[ "$LATEST_ASC_BUILD" == "0" ]] || fail "LATEST_ASC_BUILD must be a non-negative integer, got: $LATEST_ASC_BUILD"
    anchor_build="$LATEST_ASC_BUILD"
    anchor_source="latest_asc_build"
  elif have_asc_credentials; then
    note "Looking up latest App Store Connect build for app ${ASC_APP_ID}..."
    anchor_build="$(fetch_latest_app_store_connect_build)"
    anchor_source="app_store_connect"
  else
    fail "Cannot auto-select a TestFlight build number without App Store Connect credentials, LATEST_ASC_BUILD=N, or BUILD=N"
  fi

  target_build="$(( $(max_int "$repo_build" "$anchor_build") + 1 ))"
fi

is_positive_int "$target_build" || fail "Selected build must be a positive integer, got: $target_build"
if (( target_build <= repo_build )); then
  fail "Selected build $target_build must be higher than repo build $repo_build"
fi
if [[ -n "$anchor_build" && "$anchor_build" != "0" ]] && (( target_build <= anchor_build )); then
  fail "Selected build $target_build must be higher than App Store Connect anchor build $anchor_build"
fi

prepare_release_revenuecat_key

write_project_versions "$target_version" "$target_build" "$PROJECT_YML"

if [[ "$RUN_XCODEGEN" != "0" ]]; then
  "$XCODEGEN_COMMAND" generate
fi

if [[ "$RUN_XCODEGEN" != "0" && -n "$PROJECT_FILE" && ! -f "$PROJECT_FILE" ]]; then
  fail "Expected generated Xcode project file after xcodegen: $PROJECT_FILE"
fi

[[ -f "$fingerprint_script" ]] || fail "Missing source fingerprint script: $fingerprint_script"
source_fingerprint="$(
  MERIAN_PROJECT_ROOT="$repo_root" bash "$fingerprint_script"
)"
[[ "$source_fingerprint" =~ ^[0-9a-f]{64}$ ]] \
  || fail "Source fingerprint is malformed: $source_fingerprint"

prepared_from_sha="$(git -C "$repo_root" rev-parse HEAD)"
[[ "$prepared_from_sha" =~ ^[0-9a-f]{40,64}$ ]] \
  || fail "Git returned an invalid source revision: $prepared_from_sha"

write_release_marker \
  "$target_version" \
  "$target_build" \
  "$anchor_source" \
  "$anchor_build" \
  "$source_fingerprint" \
  "$prepared_from_sha" \
  "$MARKER_FILE"

note "Prepared Merian ${target_version} (${target_build}) for TestFlight."
note "Release source fingerprint: ${source_fingerprint}"
note "Release prep marker: ${MARKER_FILE}"
