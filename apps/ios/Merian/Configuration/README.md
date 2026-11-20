## November 13 — normal OAuth History configurations

`HistoryNormalOAuthConfiguration.swift` owns the `HistoryTesting` and main-app
`Release` build capability and primary identity/backend validation. It enables
live History composition without changing primary OAuth, and selects the
non-destructive `preservesExistingLibrary` startup policy. Default Debug routes
stay inactive; the separate `HistoryQualification` Auth controls below remain
intact. `MERIAN_HISTORY_LOCAL_DIAGNOSTICS` is compiled only in HistoryTesting;
it does not gate composition. Both testing configurations retain archive denial.
Local Release enablement is preparation, not distribution or functional
acceptance. See the
[current testing contract](../../../../docs/development-guides/24-identification-history-device-review.md#november-12--history-with-normal-oauth).

## November 8 CST — primary-app qualification preparation

Completion269 follows the user's primary-app testing decision. The qualification
configuration reuses ordinary app/companion identities, data containers and
Google registration while retaining its compiled target/account gates and
internal Auth transaction journal. Ordinary SDK session bytes remain untouched;
no refresh token is cloned. Sign-out and inherited sign-out recovery hold before
destructive effects. Auth-failure cleanup also holds before primary Keychain,
SDK session or purchase cleanup. Failed store startup cannot
quarantine/rescue/recreate the primary library in qualification. Implementation
and local checks do not establish signed install-over or rollback compatibility;
the device-review guide owns those remaining gates. The revised unsigned
four-product build passed (1.0.3/275) with primary identifiers and existing
Google callback verified; private activation inputs remain empty.

# iOS application configuration

This directory owns main-app build resources and process-wide configuration.
`project.yml` remains authoritative for including the sources, entitlements,
Info.plist, privacy manifest, and bridging header in the `Merian` target.

The **Embed Build Provenance** phase explicitly consumes the processed product
Info.plist before stamping `MERIAN_SOURCE_REVISION`, `MERIAN_SOURCE_FINGERPRINT`
and `MERIAN_SOURCE_STATE`. This prevents later plist processing from restoring
the checked-in `unavailable` fallbacks. The benchmark parser reads only those
bounded fields plus app version/build; unknown values stay null. A native test
asserts that the final built test host retains its source identity.

## Runtime configuration

- `MerianEnvironment.swift` validates and projects the client-safe values
  bundled through Info.plist and the process environment. It does not make
  network requests or own server secrets.
- `HistoryQualificationIdentityEvidence.swift` validates a dormant private
  evidence packet against the existing approved scope: approval, exact host,
  Google provider, exactly one approved-account fingerprint, subject/provenance
  digests and separate mapping/server-refusal observation and expiry times.
  Timestamps are canonical positive Unix seconds through year 9999; expiry is
  exclusive. Empty, malformed, mismatched, future-observed and expired packets
  are refused. This validates local metadata only and does not establish trusted
  mapping or hosted refusal. The Google consumer requires a current packet
  before presentation, checks the exact subject before completion and again at
  the service exchange, then checks the non-anonymous returned account before
  adoption and atomic storage acceptance. The existing qualification Auth
  storage fences pending SDK writes and retains an exact accepted-session
  receipt; only that receipt can resolve an uncertain acceptance. Public build
  substitutions stay empty, so these consumers deny use. Activation requires the
  separately reviewed private evidence and exact operation authorization in the
  [device-review contract](../../../../docs/development-guides/24-identification-history-device-review.md).
  Composition startup and stored-session checks retain their existing scope; no
  private evidence is bundled by the repository. Its local Google-subject
  matcher hashes the exact UTF-8 bytes with the
  `Merian.HistoryQualification.GoogleSubject/` prefix used by the reviewed
  mapping inspector and requires both evidence windows to remain current. It
  neither normalizes the subject nor authenticates an ID token; missing,
  malformed, stale or mismatched runtime packets deny presentation and exchange.
  Linking, Apple, callback exchange and anonymous creation remain
  unconditionally denied in qualification builds.
- `TestExecutionCoordinator.swift` is the sole process-level test detector. It
  centralizes the UI-test environment marker, XCTest configuration marker, and
  loaded-XCTest-runtime fallback used to suppress production side effects and
  admit Debug fixtures. Production consumers call this policy rather than
  reading those process signals directly; the cloud-image repair live adapter is
  one such consumer. Its narrow `isXCTestRuntimeLoaded` proof also serves the
  recovery-presentation fixture gate, which still rejects environment markers
  alone and requires an eligible temporary on-disk store.
- `FeatureFlags.swift` is the single registry for app-wide client-build flags:
  product release gates plus the advisory local scan-meter bypass. Each
  `FeatureFlag.defaultValue` is the value shipped by Release builds. DEBUG
  builds may persist device-local overrides under the installed
  `Merian.DebugFeatureFlag.<rawValue>` keys; Release builds never read them.

The installed registry contains `.fieldTrips`, `.dwcaExports`, and
`.unlimitedFreeScans`. Field Trips is released, DwC-A export presentation stays
default-off behind its separate server release control, and the local-meter
bypass stays default-off. Adding, removing, or renaming a case changes the
installed DEBUG preference-key contract and requires the focused configuration,
consumer, and rollout-contract tests to move together.

Feature flags control client-side availability and advisory behavior only. They
do not grant backend authorization, replace server-side release controls, or
create account-specific allowlists. Feature-specific product policy stays with
its narrowest feature owner. In particular, Field Trips owns standard-outing
sharing availability in
`Features/Explore/FieldTrips/Models/FieldTripSharingAvailability.swift`, not the
app-wide flag registry.

## Tests

`MerianTests/Configuration/FeatureFlagsTests.swift` freezes the complete flag
registry, production defaults, installed DEBUG override keys, and the absence of
a retired Events gate. `FeatureFlagsArchitectureTests.swift` enforces the sole
configuration owner, the Field Trips-local sharing owner, retired Utilities
paths, bounded source files, and the effect boundary.

`MerianTests/Configuration/MerianEnvironmentTests.swift` owns the existing
production-endpoint warning matrix. It was separated from the retired mixed Core
Utilities policy suite; runtime configuration behavior is unchanged.

`MerianTests/Configuration/TestExecutionCoordinatorTests.swift` freezes every
accepted process signal, the fail-closed non-test case, the coordinator's sole
Configuration owner, and the absence of duplicate raw process-signal reads in
production sources.

The `--swift-qualification` mode of `scripts/test-ios-device-review-schemes.py`
compiles the actual environment and identity-evidence sources under both
ordinary and qualification markers. It checks synthetic packet binding,
missing/malformed fields, validity boundaries, single-account binding and
provider/installed-account checks. Parsing a synthetic packet never installs it
as runtime evidence; the actual qualification consumer still refuses exchange
with the repository's absent private inputs. These host-Swift checks do not
qualify an iOS product, provider exchange or server configuration.
