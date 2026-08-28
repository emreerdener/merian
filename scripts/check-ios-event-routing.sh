#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_root="${1:-$repo_root/apps/ios/Merian}"
allowlist="${IOS_EVENT_ROUTING_ALLOWLIST:-$repo_root/scripts/config/ios-event-routing-singleton-allowlist.txt}"

source_root="${source_root%/}"

fail() {
  echo "iOS event-routing guardrail failed: $*" >&2
  exit 1
}

[[ -d "$source_root" ]] || fail "Missing Swift source root: $source_root"
[[ -f "$allowlist" ]] || fail "Missing NotificationCenter boundary allowlist: $allowlist"

file_matches() {
  local pattern="$1"
  local checked_file="$2"

  perl -e '
    use strict;
    use warnings;
    my ($pattern, $path) = @ARGV;
    open my $handle, "<", $path or die "Cannot read $path: $!\n";
    local $/;
    my $source = <$handle>;
    exit($source =~ /$pattern/ms ? 0 : 1);
  ' "$pattern" "$checked_file"
}

is_allowlisted_boundary() {
  local relative_path="$1"
  grep -Fqx -- "$relative_path" "$allowlist"
}

is_reviewed_raw_sink_owner() {
  case "$1" in
    Core/Media/MediaPlaybackObservation.swift | \
      Core/Utilities/Publisher+MainActor.swift | \
      Features/Capture/Shell/ViewModels/CaptureWorkspaceViewModel.swift | \
      Features/Scans/Library/ViewModels/ScansManager.swift | \
      Features/Scans/Map/Services/PrivateScanMapStore.swift)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

assert_tree_has_no_match() {
  local pattern="$1"
  local message="$2"
  local swift_file

  while IFS= read -r -d '' swift_file; do
    if file_matches "$pattern" "$swift_file"; then
      fail "$message (${swift_file#"$source_root"/})"
    fi
  done < <(find "$source_root" -type f -name '*.swift' -print0)
}

# Application-defined Notification.Name values and posts are forbidden even in
# framework-boundary files. Cross-module app traffic must use AppEvent/AppRoute.
assert_tree_has_no_match \
  'extension\s+(?:NS)?Notification\s*\.\s*Name\b' \
  'Application-defined Notification.Name extensions are forbidden.'
assert_tree_has_no_match \
  '(?:NS)?Notification\s*\.\s*Name\s*\(' \
  'Application-defined Notification.Name declarations are forbidden.'
assert_tree_has_no_match \
  '(?:let|var)\s+[A-Za-z_][A-Za-z0-9_]*\s*:\s*(?:NS)?Notification\s*\.\s*Name\s*=\s*\.(?:init|init\s*\()' \
  'Application-defined typed Notification.Name declarations are forbidden.'
assert_tree_has_no_match \
  'NotificationCenter\s*\.\s*default\s*\.\s*post\s*\(' \
  'NotificationCenter.default.post is forbidden for application events.'
assert_tree_has_no_match \
  '(?:let|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*NotificationCenter\s*\.\s*default\b.{0,1000}?\b\1\s*\.\s*post\s*\(' \
  'Posting through an alias of NotificationCenter.default is forbidden.'
assert_tree_has_no_match \
  'AppEventPublisher\s*\.\s*shared\b' \
  'AppEventPublisher.shared is forbidden; obtain the scoped bus from AppDIContainer.'

feedback_modifier="$source_root/Core/UI/Modifiers/MerianSystemFeedbackModifier.swift"
if [[ -f "$feedback_modifier" ]] && file_matches \
  'AppDIContainer\s*\.\s*shared\s*\.\s*appRouteCoordinator\b' \
  "$feedback_modifier"; then
  fail "The shared feedback host must route through its environment-injected AppRouteCoordinator."
fi

canonical_bus="$source_root/Core/Utilities/AppEventPublisher.swift"
[[ -f "$canonical_bus" ]] || fail "Missing canonical event bus: ${canonical_bus#"$source_root"/}"

while IFS= read -r -d '' swift_file; do
  if [[ "$swift_file" != "$canonical_bus" ]] \
    && file_matches 'PassthroughSubject\s*<\s*AppEvent\s*,' "$swift_file"; then
    fail "Only AppEventPublisher.swift may own a PassthroughSubject<AppEvent, ...> (${swift_file#"$source_root"/})"
  fi
done < <(find "$source_root" -type f -name '*.swift' -print0)

# Raw Combine sinks are lifetime boundaries. Keep the reviewed set exact so a
# new owner cannot silently introduce a strong capture, discard its
# AnyCancellable, or mutate UI without an actor hop. SwiftUI `onReceive` and the
# typed `sinkOnMainActor` framework bridge remain outside this boundary.
while IFS= read -r -d '' swift_file; do
  if ! file_matches '\.\s*sink\s*(?:\(|\{)' "$swift_file"; then
    continue
  fi

  relative_path="${swift_file#"$source_root"/}"
  if ! is_reviewed_raw_sink_owner "$relative_path"; then
    fail "Raw Combine .sink is allowed only in a reviewed lifetime owner ($relative_path)"
  fi
done < <(find "$source_root" -type f -name '*.swift' -print0)

if file_matches \
  '\bcase\s+[A-Za-z_][A-Za-z0-9_]*(?:Open|Route|Intent|ExternalImageImport)[A-Za-z0-9_]*\b' \
  "$canonical_bus"; then
  fail "Delivery-critical navigation cases belong to AppRoute, not AppEvent."
fi

approved_event_cases="$({
  printf '%s\n' \
    appDidResumeAfterTimeout \
    accountDeletionRecoveryStateChanged \
    captureGoalContextInvalidated \
    communityIdentificationRequestChanged \
    exploreAudioBoostPreferenceChanged \
    explorePostNeedsRefresh \
    exploreShareStateChanged \
    exploreVideoMutePreferenceReset \
    fieldTripChallengeProgressInvalidated \
    fieldTripProgressInvalidated \
    fieldTripScanContributionsInvalidated \
    foregroundBiologicalScanCompleted \
    manualAppleRevocationNoticeRequired \
    publicAuthorIdentityChanged \
    scanLibraryChanged \
    scanSearchIndexInvalidated
} | LC_ALL=C sort)"
actual_event_cases="$(
  perl -e '
    use strict;
    use warnings;
    local $/;
    my $source = <>;
    my ($body) = $source =~ /enum\s+AppEvent(?:\s*:[^{]+)?\s*\{(.*?)\n\}/s;
    die "Cannot locate AppEvent enum\n" unless defined $body;
    while ($body =~ /^\s*case\s+([A-Za-z_][A-Za-z0-9_]*)/mg) {
      print "$1\n";
    }
  ' "$canonical_bus" | LC_ALL=C sort
)"
[[ "$actual_event_cases" == "$approved_event_cases" ]] \
  || fail "AppEvent cases changed without updating the reviewed invalidation contract. Navigation and authoritative payloads are forbidden."

# Any access to the process-global center is a reviewed framework boundary.
# This also catches `let center = NotificationCenter.default` aliases before
# their later use, including multiline formatting.
while IFS= read -r -d '' swift_file; do
  if ! file_matches 'NotificationCenter\s*\.\s*default\b' "$swift_file"; then
    continue
  fi

  relative_path="${swift_file#"$source_root"/}"
  if ! is_allowlisted_boundary "$relative_path"; then
    fail "NotificationCenter.default is allowed only at a reviewed framework boundary ($relative_path)"
  fi
done < <(find "$source_root" -type f -name '*.swift' -print0)

# Fail closed when an allowance becomes stale or is broadened to a directory.
while IFS= read -r allowlisted_path || [[ -n "$allowlisted_path" ]]; do
  [[ -z "$allowlisted_path" || "$allowlisted_path" == \#* ]] && continue
  [[ "$allowlisted_path" != /* && "$allowlisted_path" != *'..'* ]] \
    || fail "Allowlist entries must be exact source-root-relative files: $allowlisted_path"

  allowlisted_file="$source_root/$allowlisted_path"
  [[ -f "$allowlisted_file" ]] || fail "Stale NotificationCenter boundary allowance: $allowlisted_path"
  file_matches 'NotificationCenter\s*\.\s*default\b' "$allowlisted_file" \
    || fail "Allowlisted file no longer accesses NotificationCenter.default: $allowlisted_path"
done < "$allowlist"

echo "iOS event-routing guardrail passed."
