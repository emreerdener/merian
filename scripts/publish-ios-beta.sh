#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="${MERIAN_PROJECT_ROOT:-$(cd "$script_dir/.." && pwd)}"
repo_root="$(cd "$repo_root" && pwd -P)"

project_yml="${PROJECT_YML:-$repo_root/project.yml}"
fingerprint_script="$script_dir/ios-release-source-fingerprint.sh"
archive_validator="$script_dir/validate-ios-archive.sh"
ipa_validator="$script_dir/validate-ios-exported-ipa.sh"
export_script="$script_dir/export-ios-release.sh"
xcodebuild_command="${XCODEBUILD_COMMAND:-xcodebuild}"
curl_command="${CURL_COMMAND:-curl}"
ruby_command="${RUBY_COMMAND:-ruby}"
xcrun_command="${XCRUN_COMMAND:-xcrun}"
publisher_git_token="${PUBLISHER_GITHUB_TOKEN:-}"
unset PUBLISHER_GITHUB_TOKEN

mode="plan"
evidence_input=""
ipa_override=""
confirm_external_state="0"
confirm_upload="0"
confirm_failed_upload="0"

fail() {
  echo "error: iOS beta publisher: $*" >&2
  exit 1
}

note() {
  echo "$*" >&2
}

usage() {
  cat <<'USAGE'
Usage:
  publish-ios-beta.sh --dry-run
  publish-ios-beta.sh --candidate --confirm-external-state
  publish-ios-beta.sh --upload --confirm-external-state --confirm-upload
  publish-ios-beta.sh --upload-existing EVIDENCE_JSON --confirm-upload [--ipa IPA_PATH]
  publish-ios-beta.sh --retry-upload EVIDENCE_JSON --confirm-upload --confirm-failed-upload [--ipa IPA_PATH]

The dry run allocates nothing, creates no Git refs, archives nothing, and uploads
nothing. Candidate/upload modes are supported only inside the serialized manual
publisher workflow. An upload retry always reuses and revalidates the exact IPA.
USAGE
}

while (( $# > 0 )); do
  case "$1" in
    --dry-run)
      mode="plan"
      ;;
    --candidate)
      mode="candidate"
      ;;
    --upload)
      mode="upload"
      ;;
    --upload-existing)
      shift
      (( $# > 0 )) || fail "--upload-existing requires an evidence JSON path."
      mode="upload_existing"
      evidence_input="$1"
      ;;
    --retry-upload)
      shift
      (( $# > 0 )) || fail "--retry-upload requires an evidence JSON path."
      mode="retry_upload"
      evidence_input="$1"
      ;;
    --ipa)
      shift
      (( $# > 0 )) || fail "--ipa requires a path."
      ipa_override="$1"
      ;;
    --confirm-external-state)
      confirm_external_state="1"
      ;;
    --confirm-upload)
      confirm_upload="1"
      ;;
    --confirm-failed-upload)
      confirm_failed_upload="1"
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
  shift
done

extract_project_setting() {
  local key="$1"
  awk -v key="$key" '$1 == key ":" { print $2; found = 1; exit } END { if (!found) exit 1 }' "$project_yml"
}

is_nonnegative_int() {
  [[ "$1" =~ ^(0|[1-9][0-9]*)$ ]]
}

max_int() {
  local first="$1"
  local second="$2"
  if (( first > second )); then
    printf '%s\n' "$first"
  else
    printf '%s\n' "$second"
  fi
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 is unavailable."
}

git_with_publisher_auth() {
  local encoded_credentials

  if [[ -z "$publisher_git_token" ]]; then
    command git "$@"
    return
  fi
  [[ -x /usr/bin/base64 ]] || fail "/usr/bin/base64 is unavailable."
  encoded_credentials="$(printf 'x-access-token:%s' "$publisher_git_token" | /usr/bin/base64)"
  GIT_CONFIG_COUNT=1 \
  GIT_CONFIG_KEY_0=http.https://github.com/.extraheader \
  GIT_CONFIG_VALUE_0="AUTHORIZATION: basic ${encoded_credentials}" \
    command git "$@"
}

have_asc_credentials() {
  [[ -n "${ASC_APP_ID:-}" && -n "${ASC_ISSUER_ID:-}" && -n "${ASC_KEY_ID:-}" && -n "${ASC_PRIVATE_KEY_PATH:-}" ]]
}

require_asc_credentials() {
  have_asc_credentials \
    || fail "ASC_APP_ID, ASC_ISSUER_ID, ASC_KEY_ID, and ASC_PRIVATE_KEY_PATH are required."
  [[ -f "$ASC_PRIVATE_KEY_PATH" && ! -L "$ASC_PRIVATE_KEY_PATH" && -r "$ASC_PRIVATE_KEY_PATH" ]] \
    || fail "ASC_PRIVATE_KEY_PATH must be a readable, non-symbolic-link regular file."
  [[ "${ASC_APP_ID}" =~ ^[0-9]+$ ]] || fail "ASC_APP_ID must be numeric."
  [[ "${ASC_KEY_ID}" =~ ^[A-Z0-9]+$ ]] || fail "ASC_KEY_ID is malformed."
  [[ "${ASC_ISSUER_ID}" =~ ^[0-9a-fA-F-]{36}$ ]] || fail "ASC_ISSUER_ID is malformed."
}

make_app_store_connect_jwt() {
  "$ruby_command" - "$ASC_KEY_ID" "$ASC_ISSUER_ID" "$ASC_PRIVATE_KEY_PATH" <<'RUBY'
require "base64"
require "json"
require "openssl"

key_id, issuer_id, private_key_path = ARGV

def base64url(data)
  Base64.urlsafe_encode64(data).delete("=")
end

def fixed_width_integer(integer)
  hexadecimal = integer.to_i.to_s(16)
  hexadecimal = "0#{hexadecimal}" if hexadecimal.length.odd?
  bytes = [hexadecimal].pack("H*")
  abort("ES256 signature integer exceeds 32 bytes") if bytes.bytesize > 32
  bytes.rjust(32, "\0")
end

issued_at = Time.now.to_i
header = { "alg" => "ES256", "kid" => key_id, "typ" => "JWT" }
payload = {
  "iss" => issuer_id,
  "iat" => issued_at,
  "exp" => issued_at + 1200,
  "aud" => "appstoreconnect-v1"
}
signing_input = "#{base64url(header.to_json)}.#{base64url(payload.to_json)}"
private_key = OpenSSL::PKey.read(File.binread(private_key_path))
sequence = OpenSSL::ASN1.decode(private_key.sign(OpenSSL::Digest::SHA256.new, signing_input))
signature = sequence.value.map { |part| fixed_width_integer(part.value) }.join
puts "#{signing_input}.#{base64url(signature)}"
RUBY
}

parse_latest_build_response() {
  "$ruby_command" -rjson -e '
    document = JSON.parse(STDIN.read)
    builds = document["data"]
    abort("response data is not an array") unless builds.is_a?(Array)
    values = builds.map do |build|
      abort("invalid build resource") unless build.is_a?(Hash) && build["type"] == "builds"
      value = build.dig("attributes", "version")
      abort("invalid build version") unless value.is_a?(String) && value.match?(/\A[1-9][0-9]*\z/)
      value.to_i
    end
    puts(values.max || 0)
  '
}

fetch_latest_app_store_connect_build() {
  require_asc_credentials
  require_command "$curl_command"
  require_command "$ruby_command"

  local jwt
  local body_file
  local header_file
  local http_code
  local curl_status
  local latest

  jwt="$(make_app_store_connect_jwt)"
  body_file="$(mktemp "${TMPDIR:-/tmp}/merian-asc-builds.XXXXXX")"
  header_file="$(mktemp "${TMPDIR:-/tmp}/merian-asc-auth.XXXXXX")"
  chmod 600 "$header_file"
  printf 'Authorization: Bearer %s\n' "$jwt" > "$header_file"

  set +e
  http_code="$(
    "$curl_command" --silent --show-error \
      --proto '=https' \
      --get \
      --data-urlencode "filter[app]=${ASC_APP_ID}" \
      --data-urlencode 'limit=1' \
      --data-urlencode 'sort=-version' \
      --data-urlencode 'fields[builds]=version' \
      --connect-timeout 5 \
      --max-time 20 \
      --retry 2 \
      --retry-delay 1 \
      --retry-all-errors \
      --max-filesize 1048576 \
      -o "$body_file" \
      -w '%{http_code}' \
      -H "@${header_file}" \
      'https://api.appstoreconnect.apple.com/v1/builds'
  )"
  curl_status="$?"
  set -e

  if (( curl_status != 0 )); then
    rm -f "$body_file" "$header_file"
    fail "App Store Connect build lookup transport failed (curl $curl_status)."
  fi
  if [[ ! "$http_code" =~ ^2[0-9]{2}$ ]]; then
    rm -f "$body_file" "$header_file"
    fail "App Store Connect build lookup failed with HTTP $http_code."
  fi
  if ! latest="$(parse_latest_build_response < "$body_file")"; then
    rm -f "$body_file" "$header_file"
    fail "App Store Connect returned a malformed build-list response."
  fi
  rm -f "$body_file" "$header_file"
  is_nonnegative_int "$latest" || fail "App Store Connect returned an invalid build number."
  printf '%s\n' "$latest"
}

latest_allocation_from_tags() {
  local latest="0"
  local tag
  local value
  local remote_output=""

  while IFS= read -r tag; do
    [[ -n "$tag" ]] || continue
    value="${tag#ios-build-allocations/}"
    [[ "$value" =~ ^[1-9][0-9]*$ ]] || fail "malformed allocation tag: $tag"
    (( value > latest )) && latest="$value"
  done < <(git -C "$repo_root" tag --list 'ios-build-allocations/*')

  if ! remote_output="$(git_with_publisher_auth -C "$repo_root" ls-remote --refs origin 'refs/tags/ios-build-allocations/*')"; then
    fail "could not read remote iOS build allocations."
  fi
  while IFS= read -r tag; do
    [[ -n "$tag" ]] || continue
    tag="${tag#refs/tags/}"
    [[ "$tag" =~ ^ios-build-allocations/[1-9][0-9]*$ ]] \
      || fail "remote contains a malformed iOS allocation tag."
    value="${tag#ios-build-allocations/}"
    (( value > latest )) && latest="$value"
  done < <(awk '{ print $2 }' <<<"$remote_output")

  printf '%s\n' "$latest"
}

write_plan() {
  local output="$1"
  local stage="$2"
  local state_writes="$3"
  local live_preconditions="$4"
  local generated_at

  generated_at="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  "$ruby_command" -rjson -e '
    keys = %w[path mode stage version selected_build asc_latest tracked_baseline allocation_baseline repository_baseline source_revision source_fingerprint source_state serialized green_sha green_run_id state_writes live_preconditions generated_at]
    values = keys.zip(ARGV).to_h
    document = {
      "schema_version" => 1,
      "kind" => "merian-ios-beta-publisher-plan",
      "mode" => values["mode"],
      "stage" => values["stage"],
      "version" => values["version"],
      "build" => Integer(values["selected_build"]),
      "allocation" => {
        "formula" => "max(app_store_connect_latest, repository_baseline) + 1",
        "app_store_connect_latest" => Integer(values["asc_latest"]),
        "tracked_current_project_version_baseline" => Integer(values["tracked_baseline"]),
        "durable_allocation_tag_baseline" => Integer(values["allocation_baseline"]),
        "repository_baseline" => Integer(values["repository_baseline"]),
        "allocation_tag" => "ios-build-allocations/#{values["selected_build"]}"
      },
      "source" => {
        "revision" => values["source_revision"],
        "fingerprint" => values["source_fingerprint"],
        "state" => values["source_state"]
      },
      "green_gate" => {
        "sha" => values["green_sha"],
        "workflow_run_id" => values["green_run_id"],
        "proven" => values["live_preconditions"] == "true"
      },
      "publisher" => {
        "serialized" => values["serialized"] == "1",
        "external_state_authorized" => values["state_writes"] == "true"
      },
      "archive" => {
        "planned_invocations" => 1,
        "distributable" => true
      },
      "export" => {
        "manageAppVersionAndBuildNumber" => false,
        "planned_ipa_validation" => true
      },
      "upload" => {
        "planned" => ["plan", "upload", "upload_existing", "retry_upload"].include?(values["mode"]),
        "authorized" => values["mode"] == "upload" && values["state_writes"] == "true",
        "will_execute" => values["mode"] == "upload",
        "rebuild" => false,
        "promotion_policy" => "promote this same uploaded build through internal TestFlight, external TestFlight, and App Review"
      },
      "live_preconditions_met" => values["live_preconditions"] == "true",
      "generated_at" => values["generated_at"]
    }
    File.binwrite(values["path"], JSON.pretty_generate(document) + "\n")
  ' "$output" "$mode" "$stage" "$version" "$selected_build" "$asc_latest" "$tracked_baseline" "$allocation_baseline" "$repository_baseline" "$source_revision" "$source_fingerprint" "$source_state" "${MERIAN_PUBLISHER_SERIALIZED:-0}" "${MERIAN_GREEN_SHA:-}" "${MERIAN_GREEN_RUN_ID:-}" "$state_writes" "$live_preconditions" "$generated_at"
}

write_evidence() {
  local output="$1"
  local status="$2"
  local archive_path="$3"
  local archive_identity="$4"
  local ipa_path="$5"
  local ipa_sha256="$6"
  local evidence_tag="$7"
  local generated_at

  generated_at="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  "$ruby_command" -rjson -e '
    path, status, version, build, source_revision, source_fingerprint, archive_path, archive_identity, ipa_path, ipa_sha256, allocation_tag, evidence_tag, green_run_id, generated_at = ARGV
    document = {
      "schema_version" => 1,
      "kind" => "merian-ios-beta-evidence",
      "status" => status,
      "version" => version,
      "build" => Integer(build),
      "source_revision" => source_revision,
      "source_fingerprint" => source_fingerprint,
      "source_state" => "clean",
      "archive_path" => archive_path,
      "archive_identity" => archive_identity,
      "archive_invocations" => 1,
      "ipa_path" => ipa_path,
      "ipa_sha256" => ipa_sha256,
      "manageAppVersionAndBuildNumber" => false,
      "allocation_tag" => allocation_tag,
      "evidence_tag" => evidence_tag,
      "green_workflow_run_id" => green_run_id,
      "retry_policy" => {
        "identical_ipa_after_definitive_failed_upload" => "allowed",
        "rebuild_or_source_or_configuration_change" => "allocate_new_build",
        "gaps" => "allowed"
      },
      "promotion_policy" => "same_uploaded_binary_only",
      "generated_at" => generated_at
    }
    File.binwrite(path, JSON.pretty_generate(document) + "\n")
  ' "$output" "$status" "$version" "$selected_build" "$source_revision" "$source_fingerprint" "$archive_path" "$archive_identity" "$ipa_path" "$ipa_sha256" "$allocation_tag" "$evidence_tag" "${MERIAN_GREEN_RUN_ID:-}" "$generated_at"
}

evidence_value() {
  local key="$1"
  local path="$2"
  "$ruby_command" -rjson -e '
    key, path = ARGV
    document = JSON.parse(File.binread(path))
    abort("invalid evidence") unless document.is_a?(Hash) && document["kind"] == "merian-ios-beta-evidence"
    value = document[key]
    abort("missing evidence field #{key}") if value.nil?
    abort("unsupported evidence field type") unless value.is_a?(String) || value.is_a?(Integer)
    puts value
  ' "$key" "$path" 2>/dev/null
}

compact_evidence_tag_message() {
  "$ruby_command" -rjson -e '
    version, build, source_revision, source_fingerprint, archive_identity, ipa_sha256 = ARGV
    puts JSON.generate({
      "version" => version,
      "build" => Integer(build),
      "source_revision" => source_revision,
      "source_fingerprint" => source_fingerprint,
      "source_state" => "clean",
      "archive_identity" => archive_identity,
      "ipa_sha256" => ipa_sha256,
      "manageAppVersionAndBuildNumber" => false,
      "promotion_policy" => "same_uploaded_binary_only"
    })
  ' "$version" "$selected_build" "$source_revision" "$source_fingerprint" "$archive_identity" "$ipa_sha256"
}

reserve_build() {
  local push_output

  if git -C "$repo_root" show-ref --verify --quiet "refs/tags/$allocation_tag"; then
    fail "allocation tag $allocation_tag already exists; a rebuild must allocate a new number."
  fi
  git -C "$repo_root" tag "$allocation_tag" "$source_revision"
  if ! push_output="$(git_with_publisher_auth -C "$repo_root" push --porcelain origin "refs/tags/$allocation_tag:refs/tags/$allocation_tag" 2>&1)"; then
    fail "could not reserve $allocation_tag; no archive was started."
  fi
  grep -Eq '^\*[[:space:]]' <<<"$push_output" \
    || fail "$allocation_tag was not newly created remotely; no archive was started."
  note "Reserved durable build allocation: $allocation_tag"
}

publish_evidence_tag() {
  local message
  message="$(compact_evidence_tag_message)"
  if git -C "$repo_root" show-ref --verify --quiet "refs/tags/$evidence_tag"; then
    fail "evidence tag $evidence_tag already exists; use --upload-existing instead of rebuilding."
  fi
  git -C "$repo_root" tag -a "$evidence_tag" -m "$message" "$source_revision"
  git_with_publisher_auth -C "$repo_root" push origin "refs/tags/$evidence_tag:refs/tags/$evidence_tag" \
    || fail "could not publish immutable build evidence; the IPA was not uploaded."
  note "Published immutable build evidence: $evidence_tag"
}

verify_ipa_hash() {
  local path="$1"
  local expected="$2"
  local actual
  actual="$(shasum -a 256 -- "$path" | awk 'NR == 1 { print $1 }')"
  [[ "$actual" == "$expected" ]] || fail "IPA hash does not match immutable evidence."
}

verify_evidence_tag() {
  local expected_tag="ios-builds/${version}-${selected_build}"
  local tagged_revision
  local tag_message

  [[ "$evidence_tag" == "$expected_tag" ]] \
    || fail "evidence tag name does not match version/build identity."
  git -C "$repo_root" show-ref --verify --quiet "refs/tags/$evidence_tag" \
    || fail "immutable evidence tag $evidence_tag is unavailable."
  tagged_revision="$(git -C "$repo_root" rev-list -n 1 "$evidence_tag")"
  [[ "$tagged_revision" == "$source_revision" ]] \
    || fail "immutable evidence tag points to a different source revision."
  tag_message="$(git -C "$repo_root" for-each-ref --format='%(contents)' "refs/tags/$evidence_tag")"
  printf '%s' "$tag_message" | "$ruby_command" -rjson -e '
    version, build, revision, fingerprint, archive_identity, ipa_sha256 = ARGV
    document = JSON.parse(STDIN.read)
    abort("tag version mismatch") unless document["version"] == version
    abort("tag build mismatch") unless document["build"] == Integer(build)
    abort("tag revision mismatch") unless document["source_revision"] == revision
    abort("tag fingerprint mismatch") unless document["source_fingerprint"] == fingerprint
    abort("tag source state mismatch") unless document["source_state"] == "clean"
    abort("tag archive mismatch") unless document["archive_identity"] == archive_identity
    abort("tag IPA mismatch") unless document["ipa_sha256"] == ipa_sha256
    abort("tag export policy mismatch") unless document["manageAppVersionAndBuildNumber"] == false
    abort("tag promotion mismatch") unless document["promotion_policy"] == "same_uploaded_binary_only"
  ' "$version" "$selected_build" "$source_revision" "$source_fingerprint" "$archive_identity_from_evidence" "$ipa_sha256" \
    || fail "immutable evidence tag does not match candidate evidence."
}

mark_upload_attempt() {
  local evidence_path="$1"
  local attempted_at

  attempted_at="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  "$ruby_command" -rjson -e '
    path, attempted_at = ARGV
    document = JSON.parse(File.binread(path))
    abort("invalid candidate evidence") unless document.is_a?(Hash) && document["kind"] == "merian-ios-beta-evidence"
    document["status"] = "upload_attempted"
    document["upload_attempted_at"] = attempted_at
    File.binwrite(path, JSON.pretty_generate(document) + "\n")
  ' "$evidence_path" "$attempted_at" || fail "could not record upload-attempt evidence."
}

upload_ipa() {
  local path="$1"
  local upload_log="$2"
  local evidence_path="$3"
  local upload_work_dir
  local private_key_dir
  local private_key_copy
  local upload_ipa_copy
  local upload_status
  local upload_log_status
  local upload_pipeline_status

  require_asc_credentials
  [[ "$confirm_upload" == "1" ]] \
    || fail "upload requires --confirm-upload."
  require_command "$xcrun_command"
  require_command shasum
  [[ -f "$path" && ! -L "$path" ]] || fail "upload IPA must be a regular, non-symbolic-link file."
  path="$(cd "$(dirname "$path")" && pwd -P)/$(basename "$path")"

  upload_work_dir="$(mktemp -d "${TMPDIR:-/tmp}/merian-ios-upload.XXXXXX")"
  private_key_dir="$upload_work_dir/private_keys"
  private_key_copy="$private_key_dir/AuthKey_${ASC_KEY_ID}.p8"
  upload_ipa_copy="$upload_work_dir/Merian-${version}-${selected_build}.ipa"
  set +e
  (
    set -euo pipefail
    cleanup_upload_credentials() {
      rm -f -- "$private_key_copy" "$upload_ipa_copy"
      rmdir -- "$private_key_dir" 2>/dev/null || true
      rmdir -- "$upload_work_dir" 2>/dev/null || true
    }
    trap cleanup_upload_credentials EXIT
    trap 'exit 130' HUP INT TERM
    mkdir -m 700 "$private_key_dir"
    install -m 600 "$ASC_PRIVATE_KEY_PATH" "$private_key_copy"
    verify_ipa_hash "$path" "$ipa_sha256"
    install -m 600 "$path" "$upload_ipa_copy"
    verify_ipa_hash "$upload_ipa_copy" "$ipa_sha256"
    mark_upload_attempt "$evidence_path"
    note "Uploading the evidence-verified IPA with Transporter API-key authentication."
    cd "$upload_work_dir"
    set +e
    "$xcrun_command" iTMSTransporter \
      -m upload \
      -assetFile "$upload_ipa_copy" \
      -apiKey "$ASC_KEY_ID" \
      -apiIssuer "$ASC_ISSUER_ID"
    transporter_status="$?"
    set -e
    (( transporter_status == 0 )) || exit "$transporter_status"
    verify_ipa_hash "$upload_ipa_copy" "$ipa_sha256"
  ) 2>&1 | tee "$upload_log"
  upload_pipeline_status=("${PIPESTATUS[@]}")
  upload_status="${upload_pipeline_status[0]}"
  upload_log_status="${upload_pipeline_status[1]}"
  set -e

  (( upload_log_status == 0 )) \
    || fail "upload receipt log failed; determine App Store Connect status before any retry."
  (( upload_status == 0 )) \
    || fail "upload failed; retry only after App Store Connect definitively reports Failed, and reuse this exact evidence/IPA."
}

verify_upload_tag() {
  local upload_tag="$1"
  local existing_upload_revision
  local existing_upload_message

  existing_upload_revision="$(git -C "$repo_root" rev-list -n 1 "$upload_tag")"
  [[ "$existing_upload_revision" == "$source_revision" ]] \
    || fail "existing upload receipt tag points to a different source revision."
  existing_upload_message="$(git -C "$repo_root" for-each-ref --format='%(contents)' "refs/tags/$upload_tag")"
  printf '%s' "$existing_upload_message" | "$ruby_command" -rjson -e '
    version, build, revision, ipa_sha256, evidence_tag = ARGV
    document = JSON.parse(STDIN.read)
    abort("upload tag version mismatch") unless document["version"] == version
    abort("upload tag build mismatch") unless document["build"] == Integer(build)
    abort("upload tag source mismatch") unless document["source_revision"] == revision
    abort("upload tag IPA mismatch") unless document["ipa_sha256"] == ipa_sha256
    abort("upload tag evidence mismatch") unless document["evidence_tag"] == evidence_tag
  ' "$version" "$selected_build" "$source_revision" "$ipa_sha256" "$evidence_tag" \
    || fail "existing upload receipt tag does not match immutable candidate evidence."
}

record_upload() {
  local evidence_path="$1"
  local upload_log="$2"
  local uploaded_at
  local receipt_sha256
  local upload_tag
  local message

  uploaded_at="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  receipt_sha256="$(shasum -a 256 -- "$upload_log" | awk 'NR == 1 { print $1 }')"
  upload_tag="ios-uploads/${version}-${selected_build}"
  message="$("$ruby_command" -rjson -e 'puts JSON.generate({"version"=>ARGV[0],"build"=>ARGV[1].to_i,"source_revision"=>ARGV[2],"ipa_sha256"=>ARGV[3],"evidence_tag"=>ARGV[4],"transporter_receipt_sha256"=>ARGV[5],"uploaded_at"=>ARGV[6]})' "$version" "$selected_build" "$source_revision" "$ipa_sha256" "$evidence_tag" "$receipt_sha256" "$uploaded_at")"

  if git -C "$repo_root" show-ref --verify --quiet "refs/tags/$upload_tag"; then
    verify_upload_tag "$upload_tag"
  else
    git -C "$repo_root" tag -a "$upload_tag" -m "$message" "$source_revision"
    git_with_publisher_auth -C "$repo_root" push origin "refs/tags/$upload_tag:refs/tags/$upload_tag" \
      || fail "upload succeeded, but durable upload receipt tag $upload_tag could not be pushed."
  fi

  "$ruby_command" -rjson -e '
    path, uploaded_at, receipt = ARGV
    document = JSON.parse(File.binread(path))
    document["status"] = "uploaded"
    document["uploaded_at"] = uploaded_at
    document["transporter_receipt_sha256"] = receipt
    File.binwrite(path, JSON.pretty_generate(document) + "\n")
  ' "$evidence_path" "$uploaded_at" "$receipt_sha256"
  note "Upload recorded without rebuilding: $upload_tag"
}

release_local_lock() {
  [[ -n "${local_lock:-}" ]] || return 0
  rm -f -- "$local_lock/owner"
  rmdir -- "$local_lock" 2>/dev/null || true
}

acquire_local_lock() {
  mkdir -p "$repo_root/build"
  local_lock="$repo_root/build/.ios-publisher.lock"
  if ! mkdir "$local_lock" 2>/dev/null; then
    fail "another local publisher holds $local_lock."
  fi
  printf '%s\n' "pid=$$" > "$local_lock/owner"
  trap release_local_lock EXIT
  trap 'exit 130' HUP INT TERM
}

run_existing_upload() {
  local retry="$1"
  local archive_path_from_evidence
  local archive_identity_from_evidence
  local evidence_ipa_path
  local upload_dir
  local upload_log
  local evidence_status
  local upload_tag

  [[ "${MERIAN_PUBLISHER_SERIALIZED:-0}" == "1" ]] \
    || fail "existing artifact uploads require the workflow concurrency lock."
  [[ "$confirm_upload" == "1" ]] || fail "existing artifact upload requires --confirm-upload."
  if [[ "$retry" == "true" && "$confirm_failed_upload" != "1" ]]; then
    fail "retry requires --confirm-failed-upload after a definitive Failed status."
  fi
  [[ -f "$evidence_input" && ! -L "$evidence_input" ]] \
    || fail "evidence JSON must be a regular, non-symbolic-link file."

  version="$(evidence_value version "$evidence_input")" || fail "evidence version is invalid."
  selected_build="$(evidence_value build "$evidence_input")" || fail "evidence build is invalid."
  source_revision="$(evidence_value source_revision "$evidence_input")" || fail "evidence source revision is invalid."
  source_fingerprint="$(evidence_value source_fingerprint "$evidence_input")" || fail "evidence source fingerprint is invalid."
  archive_path_from_evidence="$(evidence_value archive_path "$evidence_input")" || fail "evidence archive path is invalid."
  archive_identity_from_evidence="$(evidence_value archive_identity "$evidence_input")" || fail "evidence archive identity is invalid."
  evidence_ipa_path="$(evidence_value ipa_path "$evidence_input")" || fail "evidence IPA path is invalid."
  ipa_sha256="$(evidence_value ipa_sha256 "$evidence_input")" || fail "evidence IPA hash is invalid."
  evidence_tag="$(evidence_value evidence_tag "$evidence_input")" || fail "evidence tag is invalid."
  evidence_status="$(evidence_value status "$evidence_input")" || fail "evidence status is invalid."
  ipa_path="${ipa_override:-$evidence_ipa_path}"

  [[ "$version" =~ ^[1-9][0-9]*\.[0-9]+\.[0-9]+$ ]] || fail "evidence version is malformed."
  [[ "$selected_build" =~ ^[1-9][0-9]*$ ]] || fail "evidence build is malformed."
  [[ "$source_revision" =~ ^[0-9a-f]{40,64}$ ]] || fail "evidence source revision is malformed."
  [[ "$source_fingerprint" =~ ^[0-9a-f]{64}$ ]] || fail "evidence source fingerprint is malformed."
  [[ "$archive_identity_from_evidence" =~ ^[0-9a-f]{64}$ ]] || fail "evidence archive identity is malformed."
  [[ "$ipa_sha256" =~ ^[0-9a-f]{64}$ ]] || fail "evidence IPA hash is malformed."
  [[ -f "$ipa_path" && ! -L "$ipa_path" ]] || fail "evidence IPA is missing."

  verify_evidence_tag
  verify_ipa_hash "$ipa_path" "$ipa_sha256"
  if [[ -d "$archive_path_from_evidence" ]]; then
    current_archive_identity="$(bash "$script_dir/hash-ios-archive.sh" "$archive_path_from_evidence")"
    [[ "$current_archive_identity" == "$archive_identity_from_evidence" ]] \
      || fail "archive identity no longer matches immutable evidence."
  fi

  MERIAN_PLISTBUDDY_COMMAND="${MERIAN_PLISTBUDDY_COMMAND:-/usr/libexec/PlistBuddy}" \
    bash "$ipa_validator" "$ipa_path" "Merian.app" "${IOS_APP_BUNDLE_ID:-app.merian.Merian}" "$version" "$selected_build" "$source_revision" "$source_fingerprint" >/dev/null

  acquire_local_lock
  upload_tag="ios-uploads/${version}-${selected_build}"
  if [[ "$retry" == "true" ]]; then
    [[ "$evidence_status" == "upload_attempted" || "$evidence_status" == "uploaded" ]] \
      || fail "retry evidence has no prior upload attempt; use upload-existing for an untouched candidate."
    if git -C "$repo_root" show-ref --verify --quiet "refs/tags/$upload_tag"; then
      verify_upload_tag "$upload_tag"
    fi
  else
    [[ "$evidence_status" == "candidate" ]] \
      || fail "first upload requires untouched candidate evidence; use retry-upload only after a definitive Failed status."
    if git -C "$repo_root" show-ref --verify --quiet "refs/tags/$upload_tag"; then
      fail "$upload_tag already records an accepted upload; use retry-upload only after App Store Connect definitively reports Failed."
    fi
  fi
  upload_dir="$(cd "$(dirname "$evidence_input")" && pwd -P)"
  upload_log="$upload_dir/upload-$(date -u +'%Y%m%dT%H%M%SZ')-$$.log"
  [[ ! -e "$upload_log" ]] || fail "upload receipt path already exists; evidence is never overwritten."
  upload_ipa "$ipa_path" "$upload_log" "$evidence_input"
  record_upload "$evidence_input" "$upload_log"
  note "The exact IPA ${ipa_sha256} is ready for same-binary promotion in App Store Connect."
}

if [[ "$mode" == "upload_existing" ]]; then
  run_existing_upload "false"
  exit 0
elif [[ "$mode" == "retry_upload" ]]; then
  run_existing_upload "true"
  exit 0
fi

[[ -f "$project_yml" ]] || fail "missing project.yml."
[[ -f "$fingerprint_script" ]] || fail "missing source fingerprint script."
[[ -f "$archive_validator" ]] || fail "missing archive validator."
[[ -f "$ipa_validator" ]] || fail "missing IPA validator."
[[ -f "$export_script" ]] || fail "missing export script."
require_command git
require_command "$ruby_command"
require_command shasum

version="$(extract_project_setting MARKETING_VERSION)" || fail "could not read MARKETING_VERSION."
tracked_baseline="$(extract_project_setting CURRENT_PROJECT_VERSION)" || fail "could not read CURRENT_PROJECT_VERSION baseline."
[[ "$version" =~ ^[1-9][0-9]*\.[0-9]+\.[0-9]+$ ]] || fail "tracked MARKETING_VERSION is malformed."
[[ "$tracked_baseline" =~ ^[1-9][0-9]*$ ]] || fail "tracked CURRENT_PROJECT_VERSION baseline is malformed."

source_revision="$(git -C "$repo_root" rev-parse HEAD)"
source_fingerprint="$(MERIAN_PROJECT_ROOT="$repo_root" bash "$fingerprint_script")"
source_state="clean"
[[ -n "$(git -C "$repo_root" status --porcelain --untracked-files=normal)" ]] && source_state="dirty"
[[ "$source_revision" =~ ^[0-9a-f]{40,64}$ ]] || fail "Git returned a malformed source revision."
[[ "$source_fingerprint" =~ ^[0-9a-f]{64}$ ]] || fail "source fingerprint is malformed."

if [[ -n "${LATEST_ASC_BUILD:-}" ]]; then
  is_nonnegative_int "$LATEST_ASC_BUILD" || fail "LATEST_ASC_BUILD must be a nonnegative integer."
  if [[ "$mode" != "plan" && "${MERIAN_PUBLISHER_TESTING:-0}" != "1" ]]; then
    fail "live allocation must query App Store Connect; LATEST_ASC_BUILD is dry-run only."
  fi
  asc_latest="$LATEST_ASC_BUILD"
  asc_source="operator_supplied_dry_run_anchor"
elif have_asc_credentials; then
  asc_latest="$(fetch_latest_app_store_connect_build)"
  asc_source="app_store_connect"
else
  fail "provide App Store Connect credentials, or LATEST_ASC_BUILD=N for --dry-run."
fi

allocation_baseline="$(latest_allocation_from_tags)"
repository_baseline="$(max_int "$tracked_baseline" "$allocation_baseline")"
selected_build="$(( $(max_int "$asc_latest" "$repository_baseline") + 1 ))"
allocation_tag="ios-build-allocations/${selected_build}"
evidence_tag="ios-builds/${version}-${selected_build}"

live_preconditions="false"
if [[ "$source_state" == "clean" && "${MERIAN_PUBLISHER_SERIALIZED:-0}" == "1" && "${MERIAN_GREEN_SHA:-}" == "$source_revision" && "${MERIAN_GREEN_RUN_ID:-}" =~ ^[1-9][0-9]*$ ]]; then
  live_preconditions="true"
fi

if [[ "$mode" == "plan" ]]; then
  mkdir -p "$repo_root/build/ios-publisher/plans"
  plan_path="${PUBLISHER_PLAN_PATH:-$repo_root/build/ios-publisher/plans/${version}-${selected_build}-${source_revision:0:12}-$$.json}"
  [[ ! -e "$plan_path" ]] || fail "plan output already exists: $plan_path"
  write_plan "$plan_path" "dry_run_complete" "false" "$live_preconditions"
  note "Dry-run only; no build number was reserved or consumed."
  note "Allocation: max(ASC ${asc_latest}, repository baseline ${repository_baseline}) + 1 = ${selected_build}"
  note "Would reserve: $allocation_tag"
  note "Would archive exactly once from: $source_revision"
  note "Would export with manageAppVersionAndBuildNumber=false, validate every embedded target, and hash the IPA."
  note "Would upload only with explicit authorization, then promote that same binary without rebuilding."
  note "Plan: $plan_path"
  printf '%s\n' "$plan_path"
  exit 0
fi

[[ "$mode" == "candidate" || "$mode" == "upload" ]] || fail "internal mode error."
[[ "$confirm_external_state" == "1" ]] \
  || fail "$mode requires --confirm-external-state because it pushes durable allocation/evidence tags."
[[ "${MERIAN_PUBLISHER_SERIALIZED:-0}" == "1" ]] \
  || fail "$mode requires the workflow concurrency lock."
[[ "$source_state" == "clean" ]] || fail "$mode requires a clean checkout."
[[ "${MERIAN_GREEN_SHA:-}" == "$source_revision" ]] \
  || fail "the green iOS gate SHA must equal the exact publisher source SHA."
[[ "${MERIAN_GREEN_RUN_ID:-}" =~ ^[1-9][0-9]*$ ]] \
  || fail "the successful iOS gate workflow run ID is required."
[[ "$mode" != "upload" || "$confirm_upload" == "1" ]] \
  || fail "upload requires --confirm-upload."
require_asc_credentials
[[ "${ASC_TEAM_ID:-}" =~ ^[A-Z0-9]{10}$ ]] || fail "ASC_TEAM_ID must be a ten-character Apple team ID."

require_command "$xcodebuild_command"

if [[ "${PUBLISHER_SKIP_REPOSITORY_GATES:-0}" == "1" ]]; then
  [[ "${MERIAN_PUBLISHER_TESTING:-0}" == "1" ]] \
    || fail "PUBLISHER_SKIP_REPOSITORY_GATES is a fixture-only test hook."
  note "Fixture mode: repository gates are supplied by the focused publisher test."
else
  MERIAN_PROJECT_ROOT="$repo_root" bash "$script_dir/validate-ios-versioning.sh"
fi
acquire_local_lock
reserve_build

release_parent="$repo_root/build/ios-publisher"
release_dir="$release_parent/${version}-${selected_build}-${source_revision:0:12}"
mkdir -p "$release_parent"
mkdir "$release_dir" || fail "release output already exists; do not rebuild build $selected_build."
archive_path="$release_dir/Merian.xcarchive"
derived_data="$release_dir/DerivedData"
result_bundle="$release_dir/archive.xcresult"
archive_log="$release_dir/archive.log"
plan_path="$release_dir/plan.json"
write_plan "$plan_path" "build_reserved" "true" "true"

if [[ -n "${XCODE_PROJECT:-}" ]]; then
  xcode_project="$XCODE_PROJECT"
elif [[ -d "$repo_root/Merian.xcodeproj" ]]; then
  xcode_project="$repo_root/Merian.xcodeproj"
else
  xcode_project="$repo_root/merian.xcodeproj"
fi
[[ -d "$xcode_project" ]] || fail "missing generated Xcode project."

archive_command=(
  "$xcodebuild_command" archive
  -scheme Merian
  -project "$xcode_project"
  -configuration Release
  -destination "generic/platform=iOS"
  -archivePath "$archive_path"
  -resultBundlePath "$result_bundle"
  -derivedDataPath "$derived_data"
  -onlyUsePackageVersionsFromResolvedFile
  -disableAutomaticPackageResolution
  -skipPackageUpdates
  -allowProvisioningUpdates
  -authenticationKeyPath "$ASC_PRIVATE_KEY_PATH"
  -authenticationKeyID "$ASC_KEY_ID"
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"
  "DEVELOPMENT_TEAM=$ASC_TEAM_ID"
  "MARKETING_VERSION=$version"
  "CURRENT_PROJECT_VERSION=$selected_build"
  MERIAN_RELEASE_PUBLISHER=1
  MERIAN_PUBLISHER_SERIALIZED=1
  "MERIAN_EXPECTED_MARKETING_VERSION=$version"
  "MERIAN_EXPECTED_BUILD_NUMBER=$selected_build"
  "MERIAN_EXPECTED_SOURCE_REVISION=$source_revision"
  "MERIAN_EXPECTED_SOURCE_FINGERPRINT=$source_fingerprint"
  COMPILER_INDEX_STORE_ENABLE=NO
)

note "Archiving ${version} (${selected_build}) exactly once from green SHA ${source_revision}."
set +e
"${archive_command[@]}" 2>&1 | tee "$archive_log"
archive_pipeline_status=("${PIPESTATUS[@]}")
archive_status="${archive_pipeline_status[0]}"
archive_log_status="${archive_pipeline_status[1]}"
set -e
(( archive_log_status == 0 )) \
  || fail "archive log could not be retained; $allocation_tag remains reserved and this archive is not publishable."
(( archive_status == 0 )) \
  || fail "the sole archive invocation failed; $allocation_tag remains reserved and every rebuild must allocate a new number."

archive_validation_output="$(
  MERIAN_PLISTBUDDY_COMMAND="${MERIAN_PLISTBUDDY_COMMAND:-/usr/libexec/PlistBuddy}" \
    bash "$archive_validator" "$archive_path" "${IOS_APP_BUNDLE_ID:-app.merian.Merian}" "$version" "$selected_build" "$source_revision" "$source_fingerprint"
)"
archive_identity="$(awk -F= '$1 == "archive_identity" { print $2 }' <<<"$archive_validation_output")"
[[ "$archive_identity" =~ ^[0-9a-f]{64}$ ]] || fail "archive validator returned no identity."

export_path="$release_dir/export"
IOS_PUBLISHER_PLAN="$plan_path" \
MERIAN_RELEASE_PUBLISHER=1 \
MERIAN_PUBLISHER_SERIALIZED=1 \
ARCHIVE_PATH="$archive_path" \
EXPORT_PATH="$export_path" \
TEAM_ID="$ASC_TEAM_ID" \
ASC_KEY_ID="$ASC_KEY_ID" \
ASC_ISSUER_ID="$ASC_ISSUER_ID" \
ASC_PRIVATE_KEY_PATH="$ASC_PRIVATE_KEY_PATH" \
MERIAN_EXPECTED_MARKETING_VERSION="$version" \
MERIAN_EXPECTED_BUILD_NUMBER="$selected_build" \
MERIAN_EXPECTED_SOURCE_REVISION="$source_revision" \
MERIAN_EXPECTED_SOURCE_FINGERPRINT="$source_fingerprint" \
  bash "$export_script"

archive_identity_after_export="$(bash "$script_dir/hash-ios-archive.sh" "$archive_path")"
[[ "$archive_identity_after_export" == "$archive_identity" ]] \
  || fail "archive changed during export."

shopt -s nullglob
ipa_candidates=("$export_path"/*.ipa "$export_path"/*/*.ipa)
shopt -u nullglob
(( ${#ipa_candidates[@]} == 1 )) || fail "publisher expected exactly one IPA."
ipa_path="${ipa_candidates[0]}"
ipa_validation_output="$(
  MERIAN_PLISTBUDDY_COMMAND="${MERIAN_PLISTBUDDY_COMMAND:-/usr/libexec/PlistBuddy}" \
    bash "$ipa_validator" "$ipa_path" "Merian.app" "${IOS_APP_BUNDLE_ID:-app.merian.Merian}" "$version" "$selected_build" "$source_revision" "$source_fingerprint"
)"
ipa_sha256="$(awk -F= '$1 == "ipa_sha256" { print $2 }' <<<"$ipa_validation_output")"
[[ "$ipa_sha256" =~ ^[0-9a-f]{64}$ ]] || fail "IPA validator returned no SHA-256."

evidence_path="$release_dir/evidence.json"
write_evidence "$evidence_path" "candidate" "$archive_path" "$archive_identity" "$ipa_path" "$ipa_sha256" "$evidence_tag"
publish_evidence_tag

if [[ "$mode" == "candidate" ]]; then
  note "Beta candidate created without upload."
  note "Evidence: $evidence_path"
  note "Upload this exact IPA later with --upload-existing; do not rebuild it."
  printf '%s\n' "$evidence_path"
  exit 0
fi

upload_log="$release_dir/upload.log"
upload_ipa "$ipa_path" "$upload_log" "$evidence_path"
record_upload "$evidence_path" "$upload_log"
note "Uploaded beta ${version} (${selected_build}) with IPA SHA-256 ${ipa_sha256}."
note "Promote this exact uploaded binary through internal TestFlight, external TestFlight, and App Review; never rebuild it for promotion."
printf '%s\n' "$evidence_path"
