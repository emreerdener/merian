#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
checker="$repo_root/scripts/check-ios-event-routing.sh"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/merian-event-routing-tests.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
  echo "error: $*" >&2
  exit 1
}

make_fixture() {
  local name="$1"
  local fixture="$tmp_dir/$name/apps/ios/Merian"
  mkdir -p "$fixture/Core/Utilities"
  printf '%s\n' \
    'import Combine' \
    'enum AppEvent {' \
    '  case appDidResumeAfterTimeout' \
    '  case captureGoalContextInvalidated' \
    '  case communityIdentificationRequestChanged' \
    '  case exploreAudioBoostPreferenceChanged' \
    '  case explorePostNeedsRefresh' \
    '  case exploreShareStateChanged' \
    '  case exploreVideoMutePreferenceReset' \
    '  case fieldTripChallengeProgressInvalidated' \
    '  case fieldTripProgressInvalidated' \
    '  case fieldTripScanContributionsInvalidated' \
    '  case foregroundBiologicalScanCompleted' \
    '  case manualAppleRevocationNoticeRequired' \
    '  case publicAuthorIdentityChanged' \
    '  case scanLibraryChanged' \
    '  case scanSearchIndexInvalidated' \
    '}' \
    'final class AppEventPublisher {' \
    '  private let subject = PassthroughSubject<AppEvent, Never>()' \
    '}' > "$fixture/Core/Utilities/AppEventPublisher.swift"
  : > "$tmp_dir/$name/allowlist.txt"
  printf '%s\n' "$fixture"
}

run_check() {
  local fixture="$1"
  local allowlist="$2"
  IOS_EVENT_ROUTING_ALLOWLIST="$allowlist" bash "$checker" "$fixture"
}

assert_fails_with() {
  local expected="$1"
  local fixture="$2"
  local allowlist="$3"
  local output

  if output="$(run_check "$fixture" "$allowlist" 2>&1)"; then
    fail "Expected event-routing guardrail to reject $fixture"
  fi
  grep -Fq -- "$expected" <<<"$output" \
    || fail "Expected rejection containing '$expected', got: $output"
}

bash -n "$checker"
clean_fixture="$(make_fixture clean)"
run_check "$clean_fixture" "$tmp_dir/clean/allowlist.txt"

multiline_fixture="$(make_fixture multiline-default)"
mkdir -p "$multiline_fixture/Feature"
printf '%s\n' \
  'let stream = NotificationCenter' \
  '  .default' \
  '  .publisher(for: ProcessInfo.thermalStateDidChangeNotification)' \
  > "$multiline_fixture/Feature/Multiline.swift"
assert_fails_with \
  'NotificationCenter.default is allowed only at a reviewed framework boundary' \
  "$multiline_fixture" \
  "$tmp_dir/multiline-default/allowlist.txt"

alias_fixture="$(make_fixture alias)"
mkdir -p "$alias_fixture/Feature"
printf '%s\n' \
  'let center = NotificationCenter.default' \
  'center.addObserver(forName: nil, object: nil, queue: nil) { _ in }' \
  > "$alias_fixture/Feature/Alias.swift"
assert_fails_with \
  'NotificationCenter.default is allowed only at a reviewed framework boundary' \
  "$alias_fixture" \
  "$tmp_dir/alias/allowlist.txt"

name_fixture="$(make_fixture string-name)"
printf '%s\n' \
  'extension Notification.Name {' \
  '  static let brittle = Self("brittle")' \
  '}' > "$name_fixture/Core/Utilities/Brittle.swift"
assert_fails_with \
  'Application-defined Notification.Name extensions are forbidden.' \
  "$name_fixture" \
  "$tmp_dir/string-name/allowlist.txt"

typed_name_fixture="$(make_fixture typed-name)"
printf '%s\n' \
  'let brittle: Notification.Name = .init("brittle")' \
  > "$typed_name_fixture/Core/Utilities/Brittle.swift"
assert_fails_with \
  'Application-defined typed Notification.Name declarations are forbidden.' \
  "$typed_name_fixture" \
  "$tmp_dir/typed-name/allowlist.txt"

post_fixture="$(make_fixture multiline-post)"
printf '%s\n' \
  'NotificationCenter' \
  '  .default' \
  '  .post(' \
  '    name: .init("brittle"),' \
  '    object: nil' \
  '  )' > "$post_fixture/Core/Utilities/Post.swift"
assert_fails_with \
  'NotificationCenter.default.post is forbidden for application events.' \
  "$post_fixture" \
  "$tmp_dir/multiline-post/allowlist.txt"

singleton_fixture="$(make_fixture singleton)"
printf '%s\n' \
  'let bus = AppEventPublisher.shared' \
  > "$singleton_fixture/Core/Utilities/Singleton.swift"
assert_fails_with \
  'AppEventPublisher.shared is forbidden' \
  "$singleton_fixture" \
  "$tmp_dir/singleton/allowlist.txt"

feedback_route_fixture="$(make_fixture feedback-route-singleton)"
mkdir -p "$feedback_route_fixture/Core/UI/Modifiers"
printf '%s\n' \
  'let routeCoordinator = AppDIContainer.shared.appRouteCoordinator' \
  > "$feedback_route_fixture/Core/UI/Modifiers/MerianSystemFeedbackModifier.swift"
assert_fails_with \
  'shared feedback host must route through its environment-injected AppRouteCoordinator' \
  "$feedback_route_fixture" \
  "$tmp_dir/feedback-route-singleton/allowlist.txt"

subject_fixture="$(make_fixture duplicate-subject)"
printf '%s\n' \
  'import Combine' \
  'let duplicate = PassthroughSubject<AppEvent, Never>()' \
  > "$subject_fixture/Core/Utilities/Duplicate.swift"
assert_fails_with \
  'Only AppEventPublisher.swift may own a PassthroughSubject' \
  "$subject_fixture" \
  "$tmp_dir/duplicate-subject/allowlist.txt"

route_fixture="$(make_fixture route-in-event)"
printf '%s\n' \
  'import Combine' \
  'enum AppEvent { case requestOpenScansIntent }' \
  'final class AppEventPublisher {' \
  '  private let subject = PassthroughSubject<AppEvent, Never>()' \
  '}' > "$route_fixture/Core/Utilities/AppEventPublisher.swift"
assert_fails_with \
  'Delivery-critical navigation cases belong to AppRoute' \
  "$route_fixture" \
  "$tmp_dir/route-in-event/allowlist.txt"

unapproved_event_fixture="$(make_fixture unapproved-event)"
printf '%s\n' \
  'import Combine' \
  'enum AppEvent { case triggerPaywall }' \
  'final class AppEventPublisher {' \
  '  private let subject = PassthroughSubject<AppEvent, Never>()' \
  '}' > "$unapproved_event_fixture/Core/Utilities/AppEventPublisher.swift"
assert_fails_with \
  'AppEvent cases changed without updating the reviewed invalidation contract.' \
  "$unapproved_event_fixture" \
  "$tmp_dir/unapproved-event/allowlist.txt"

boundary_fixture="$(make_fixture boundary)"
mkdir -p "$boundary_fixture/Core/Hardware"
printf '%s\n' \
  'let stream = NotificationCenter.default.publisher(' \
  '  for: ProcessInfo.thermalStateDidChangeNotification' \
  ')' > "$boundary_fixture/Core/Hardware/ThermalBridge.swift"
printf '%s\n' 'Core/Hardware/ThermalBridge.swift' \
  > "$tmp_dir/boundary/allowlist.txt"
run_check "$boundary_fixture" "$tmp_dir/boundary/allowlist.txt"

allowlisted_post_fixture="$(make_fixture allowlisted-post)"
mkdir -p "$allowlisted_post_fixture/Core/Hardware"
printf '%s\n' \
  'let center = NotificationCenter.default' \
  'center.post(name: .init("still-forbidden"), object: nil)' \
  > "$allowlisted_post_fixture/Core/Hardware/ThermalBridge.swift"
printf '%s\n' 'Core/Hardware/ThermalBridge.swift' \
  > "$tmp_dir/allowlisted-post/allowlist.txt"
assert_fails_with \
  'Posting through an alias of NotificationCenter.default is forbidden.' \
  "$allowlisted_post_fixture" \
  "$tmp_dir/allowlisted-post/allowlist.txt"

# The production scan root intentionally excludes sibling test targets.
excluded_fixture="$(make_fixture excluded-tests)"
mkdir -p "$tmp_dir/excluded-tests/apps/ios/MerianTests"
printf '%s\n' \
  'let testCenter = NotificationCenter.default' \
  > "$tmp_dir/excluded-tests/apps/ios/MerianTests/TestOnly.swift"
run_check "$excluded_fixture" "$tmp_dir/excluded-tests/allowlist.txt"

echo "iOS event-routing guardrail tests passed."
