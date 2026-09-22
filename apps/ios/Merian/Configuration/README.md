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
- `TestExecutionCoordinator.swift` is the sole process-level test detector. It
  centralizes the UI-test environment marker, XCTest configuration marker, and
  loaded-XCTest-runtime fallback used to suppress production side effects and
  admit Debug fixtures. Production consumers call this policy rather than
  reading those process signals directly; the cloud-image repair live adapter is
  one such consumer.
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
