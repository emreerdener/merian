#!/usr/bin/env bash
set -euo pipefail

PROJECT_YML="${PROJECT_YML:-project.yml}"
PROJECT_FILE="${PROJECT_FILE:-Merian.xcodeproj/project.pbxproj}"
MARKER_FILE="${IOS_RELEASE_PREP_MARKER:-build/ios-release-prep.json}"
RUN_XCODEGEN="${RUN_XCODEGEN:-1}"

fail() {
  echo "error: $*" >&2
  exit 1
}

note() {
  echo "$*" >&2
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
  if command -v ruby >/dev/null 2>&1; then
    ruby -rjson -e '
      data = JSON.parse(STDIN.read)
      builds = data.fetch("data", []).map do |build|
        version = build.dig("attributes", "version").to_s
        version =~ /\A[1-9][0-9]*\z/ ? version.to_i : nil
      end.compact
      puts(builds.max || 0)
    '
  else
    tr ',' '\n' | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([1-9][0-9]*\)".*/\1/p' | sort -n | tail -n 1
  fi
}

fetch_latest_app_store_connect_build() {
  command -v curl >/dev/null 2>&1 || fail "curl is required for App Store Connect lookup"
  command -v ruby >/dev/null 2>&1 || fail "ruby is required for App Store Connect JWT signing"

  local jwt
  local body_file
  local http_code
  local latest_build

  jwt="$(make_app_store_connect_jwt)"
  body_file="$(mktemp)"

  http_code="$(
    curl -sS \
      -o "$body_file" \
      -w "%{http_code}" \
      -H "Authorization: Bearer ${jwt}" \
      "https://api.appstoreconnect.apple.com/v1/apps/${ASC_APP_ID}/builds?limit=200&sort=-uploadedDate&fields[builds]=version,uploadedDate,processingState"
  )"

  if [[ ! "$http_code" =~ ^2 ]]; then
    sed 's/^/App Store Connect: /' "$body_file" >&2
    rm -f "$body_file"
    fail "App Store Connect build lookup failed with HTTP ${http_code}"
  fi

  latest_build="$(parse_latest_build_from_response < "$body_file")"
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
  local marker="$4"

  mkdir -p "$(dirname "$marker")"
  {
    printf '{\n'
    printf '  "version": "%s",\n' "$version"
    printf '  "build": %s,\n' "$build"
    printf '  "anchor_source": "%s",\n' "$anchor_source"
    printf '  "generated_at": "%s"\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    printf '}\n'
  } > "$marker"
}

[[ -f "$PROJECT_YML" ]] || fail "Missing project.yml at $PROJECT_YML"

target_version="${VERSION:-}"
[[ -n "$target_version" ]] || fail "VERSION is required. Example: make prepare-ios-release VERSION=1.0.1"
is_semantic_version "$target_version" || fail "VERSION must be semantic x.y.z with a positive major version, got: $target_version"

repo_version="$(extract_project_setting MARKETING_VERSION "$PROJECT_YML")" || fail "Could not read MARKETING_VERSION from $PROJECT_YML"
repo_build="$(extract_project_setting CURRENT_PROJECT_VERSION "$PROJECT_YML")" || fail "Could not read CURRENT_PROJECT_VERSION from $PROJECT_YML"
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

write_project_versions "$target_version" "$target_build" "$PROJECT_YML"

if [[ "$RUN_XCODEGEN" != "0" ]]; then
  command -v xcodegen >/dev/null 2>&1 || fail "xcodegen is required. Install with: brew install xcodegen"
  xcodegen generate
fi

if [[ "$RUN_XCODEGEN" != "0" && -n "$PROJECT_FILE" && ! -f "$PROJECT_FILE" ]]; then
  fail "Expected generated Xcode project file after xcodegen: $PROJECT_FILE"
fi

write_release_marker "$target_version" "$target_build" "$anchor_source" "$MARKER_FILE"

note "Prepared Merian ${target_version} (${target_build}) for TestFlight."
note "Release prep marker: ${MARKER_FILE}"
