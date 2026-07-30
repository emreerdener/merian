# iOS Release Versioning

Naturebook uses semantic app versions and globally increasing TestFlight build
numbers. The Xcode project, scheme, targets, and build artifacts intentionally
retain the Merian engineering identity:

- `MARKETING_VERSION` is the public app version, for example `1.0.1`.
- `CURRENT_PROJECT_VERSION` is the build number uploaded to App Store Connect.
- `project.yml` is the tracked source of truth for both values.

The iOS app, Explore widget, Messages extension, and watch app must inherit
these values through build settings. Do not hardcode version strings in
`Info.plist` files or update only `Merian.xcodeproj`; XcodeGen will overwrite
generated-project-only changes.

## Daily Development

Local debug builds do not increment the version or build number. Regenerate the
project after changing project structure or build settings:

```bash
make xcodegen
make validate-ios-versioning
```

Use `agvtool` only as a read-only sanity check if needed. It must not be the
release updater because it writes generated Xcode project state instead of the
tracked XcodeGen source.

## TestFlight Release Prep

External testing is intentionally moving from the approved `1.0.0` version
train to `1.0.2`. Keep `MARKETING_VERSION` at `1.0.2` and increase only
`CURRENT_PROJECT_VERSION` for subsequent uploads on this train. The first
external `1.0.2` build requires Beta App Review because it starts a new
TestFlight version train.

Before archiving for TestFlight, choose the next semantic version and prepare a
fresh build number from the repo root:

```bash
make prepare-ios-release VERSION=1.0.2
```

Release prep permits the checked-in semantic version or a higher one and
rejects a downgrade.

The RevenueCat key is a public iOS SDK key, not a backend-only secret. If you
are ready to use production RevenueCat, pass the real production key to release
prep to write or update the ignored `Config.local.xcconfig` override:

```bash
REVENUECAT_API_KEY=appl_... make prepare-ios-release VERSION=1.0.2
```

Placeholder values such as the literal `appl_...` are blocked. If no production
key is configured yet, release prep and Xcode Archive warn but continue; app
export/upload should use the production key.

With App Store Connect credentials present, the script asks the sortable global
build-list endpoint, scoped by the exact app resource ID, for the numerically
highest uploaded build and writes the next higher number. The app relationship
endpoint is not used because it does not support sorting. Query names such as
`filter[app]` and `fields[builds]` are URL-encoded instead of being placed
literally in a curl URL, where brackets would be interpreted as URL globbing.
The lookup is sorted by build version rather than upload date, so an older,
out-of-order upload cannot be missed behind the endpoint's 200-item page limit.
Transport retries and timeouts are bounded, response size is capped, and an
unknown successful response shape fails closed instead of being treated as an
empty account:

```bash
export ASC_APP_ID=1234567890
export ASC_ISSUER_ID=00000000-0000-0000-0000-000000000000
export ASC_KEY_ID=ABC123DEFG
export ASC_PRIVATE_KEY_PATH=/path/to/AuthKey_ABC123DEFG.p8
make prepare-ios-release VERSION=1.0.2
```

If credentials are not available, provide a one-time App Store Connect anchor:

```bash
LATEST_ASC_BUILD=421 make prepare-ios-release VERSION=1.0.2
```

For an emergency manual override, provide the exact build number. The script
still refuses values that are not higher than the checked-in repo build, and it
checks against App Store Connect when credentials are present:

```bash
BUILD=422 make prepare-ios-release VERSION=1.0.2
```

The command warns when the resolved RevenueCat key is still development-only,
then updates `project.yml`, regenerates `Merian.xcodeproj`, and writes
`build/ios-release-prep.json`. The marker is intentionally ignored by git and
exists only to prove that the local archive was deliberately prepared. It
records a SHA-256 fingerprint of every tracked or nonignored source file and
file mode present after preparation. This makes the snapshot stable when an
intended new file or deletion is committed. Commit the complete prepared tree
before archiving: the archive preflight requires a clean checkout and requires
its current fingerprint to match the marker. A marker from an earlier source
tree cannot authorize an archive after code changes, even when the version and
build settings are unchanged.

Fingerprinting also requires a complete, ordinary Git index. Any tracked path
marked `assume-unchanged` or `skip-worktree` is rejected before hashing. Clear
those flags and disable sparse checkout before release preparation; otherwise
Git can conceal local or omitted source from its normal clean-checkout report.

The local marker also records `prepared_from_sha`, the exact commit on which
release preparation began. It intentionally differs from the final release
commit because the version, generated project, and any other prepared changes
must be committed afterward. Archive preflight requires this field to be a
valid commit and an ancestor of the final clean checkout. Rebasing, amending,
or transplanting the prepared tree onto unrelated history requires a fresh
release-prep marker; matching bytes alone do not preserve its preparation
lineage.

Release preparation requires XcodeGen `2.45.4`, matching the exact version
declared in `project.yml`; using another generator version is blocked to prevent
silent generated-project or scheme drift. Upgrade the script pin, project
metadata, and generated project together in a reviewed change.

Commit the tracked `project.yml` and generated-project changes, push them, and
wait for `iOS Build and Test / Production readiness` to pass on that exact
commit before creating the signed distribution archive. A green run for an
earlier commit, even with the same semantic version, is not release evidence.
The repository ruleset and merge queue should require that final check.

Build `1.0.2 (235)` was already successfully distributed to beta testers. Any
binary containing later remediation must use a globally higher App Store
Connect build number; another local archive labeled `235` does not replace or
verify the previously uploaded TestFlight binary.

A local archive audit at `2026-07-30T02:13:13Z` inspected all 417 retained local
`.xcarchive` bundles. Forty-one were labeled `1.0.2 (235)`, and zero archives
contained `MERIAN_SOURCE_REVISION`, `MERIAN_SOURCE_FINGERPRINT`, or
`MERIAN_SOURCE_STATE`. No retained local archive can therefore prove or export
the current remediated source; `scripts/export-ios-release.sh` rejects each one
before signing because the embedded provenance is absent.

RevenueCat product configuration is a separate release gate. Open the paywall
with the production SDK key and confirm the dashboard-selected current offering
returns packages mapped to both `pro_week` and `pro_annual`. The client logs an
operational error for no current offering, an empty current offering, or a
missing required product, but it cannot create App Store products or repair
RevenueCat package mappings from the repository. A successful RevenueCat login
only verifies identity linking; it does not verify StoreKit product loading.

The committed shared scheme does not currently bind a `.storekit` file. For
routine simulator purchase QA, use the RevenueCat Test Store with a Debug
`test_` key, or deliberately add and attach a StoreKit configuration following
the testing matrix in
[`02-revenue-and-identity.md`](../features-and-hardware/02-revenue-and-identity.md#prelaunch-purchase-testing).
TestFlight must use the production `appl_` key and App Store Connect products;
a local StoreKit success does not replace the TestFlight purchase/restore and
webhook smoke tests.

Before that TestFlight smoke, the backend release must have applied
`20260723201500_secure_revenuecat_webhook_delivery.sql` and synchronized the
three required RevenueCat server credentials. Follow the
[RevenueCat webhook release gate](../backend-and-data/06-supabase-deployment-runbook.md#revenuecat-webhook-release-gate);
an iOS archive with the correct public `appl_` key does not prove signed webhook
delivery, authoritative reconciliation, or durable ordering.

`FeatureFlag.unlimitedFreeScans.defaultValue` is `false` for every shipped
configuration. DEBUG may bypass only the advisory local meter; TestFlight and
Release ignore persisted overrides and remain subject to the database quota.
Run `UsageManagerTests`, `FieldTripsAvailabilityTests`, and a physical
free/Pro endpoint smoke before release. A `DEBUG OVERRIDE ACTIVE` startup
warning must never appear in a Release/TestFlight build. Pro removes the normal
one-scan product cap but still has server-side fair-use/rate ceilings.

## Archive Guardrail

Xcode calls `scripts/check-ios-release-prep.sh` during Release archives. The
check is quiet for normal Debug builds and non-archive Release builds. During an
archive, it parses the marker as typed JSON and blocks if the marker is missing,
if its version/build does not match `project.yml`, if its local preparation base
is malformed or outside the final commit's ancestry, if the checkout is dirty,
or if the exact tracked source fingerprint no longer matches the marker. The
CI-only marker instead requires `ci_validation_only: true` and an exact
`source_sha` matching the checked-out workflow revision. A malformed identity
field cannot silently disable either check. Preflight warns, but does not block,
if the resolved `REVENUECAT_API_KEY` is missing, still begins with RevenueCat's
`test_` Test Store prefix, or does not look like an iOS production SDK key
beginning with `appl_`. Set
`MERIAN_REQUIRE_PRODUCTION_REVENUECAT_KEY=1` for export/release checks that
should fail on non-production RevenueCat config.

Every built app embeds three support-safe provenance values in its processed
`Info.plist`:

- `MERIAN_SOURCE_REVISION`: exact Git revision;
- `MERIAN_SOURCE_FINGERPRINT`: exact release-source snapshot fingerprint; and
- `MERIAN_SOURCE_STATE`: `clean` or `dirty` at build time.

The startup `ModelContainer bootstrap diagnostics` notice exposes the same
values as `source`, `sourceFingerprint`, and `sourceState`. Record them with
every TestFlight trace. A release candidate must report the intended revision
and fingerprint with `sourceState=clean`; version/build alone is not sufficient
binary provenance.

The embed phase treats the processed product plist as a scoped build artifact,
not an arbitrary write target. `INFOPLIST_PATH` must be relative and
traversal-free, every parent resolves inside the canonical
`TARGET_BUILD_DIR`, and the final `Info.plist` must be a single-link regular
file. Symbolic links and multiple hard links are rejected before `PlistBuddy`
can write through them. The release-tooling fixture proves both escapes fail
and an ordinary product plist receives all three provenance keys.

Release-preparation markers are JSON and are validated with the same strict,
typed Ruby parser on Ubuntu and macOS. Production provenance embedding defaults
to the absolute Apple `/usr/libexec/PlistBuddy` path. The portable test fixture
explicitly injects a narrow Python `plistlib` editor because the Apple binary is
not present on Ubuntu; macOS runs additionally test the real default tool. The
override is for fixture execution, not release configuration.

Generated-project validation binds both release scripts to the main `Merian`
target rather than accepting a matching phase elsewhere in the project. The
preflight must be attached exactly once as the target's first build phase.
Provenance embedding must also be attached exactly once, run after sources,
resources, frameworks, app extensions, and watch content, and remain the last
product-mutating phase immediately before SwiftLint. Both shell definitions
must be always out of date and invoke only their canonical checked-in script.
Run `make test-ios-project-resources` to exercise detached, duplicated,
misordered, and wrong-command adversarial project fixtures.

### Current-SHA CI Archive Gate

`.github/workflows/ios-build-and-test.yml` independently archives the exact
`GITHUB_SHA` with Release optimization on the generic iOS device destination.
It uses Xcode 26.6, resolves only the checked-in `Package.resolved` versions,
and disables signing because distribution credentials do not belong on
untrusted pull-request runners. The job verifies the app version/build,
embedded widget, Messages extension, watch app, main binary, and matching dSYM
UUIDs. It also requires the archive's embedded revision to equal `GITHUB_SHA`,
the embedded release-source fingerprint to equal the checked-out source, and the
embedded source state to be `clean`. Its evidence JSON records the source SHA,
source fingerprint, source state, and binary hash.

CI creates an ephemeral version/build marker solely to exercise the same
archive preflight. That marker has `ci_validation_only: true`, is stored as
workflow evidence, and contains an exact `source_sha` that preflight requires
to match `GITHUB_SHA`. It does not satisfy the ignored local
`build/ios-release-prep.json` requirement. The unsigned CI archive is retained
for seven days after successful `main` and manual runs for inspection only. It
cannot prove distribution signing, provisioning, APNs entitlements, StoreKit,
physical camera behavior, or App Store export, and it must never be submitted
to App Store Connect.

Before TestFlight/App Store export, require all of the following for the exact
release commit:

1. `iOS Build and Test / Production readiness` is green; its Full iOS unit
   tests job passed the complete unit target and exact queued-scan completion UI
   smoke, and its Current-SHA Release archive job succeeded.
2. `make prepare-ios-release VERSION=x.y.z` produced the matching local prep
   marker and all tracked version/project changes are committed.
3. A fresh locally signed archive from that clean commit passes the signing,
   entitlement, RevenueCat, physical-device, and purchase smoke gates below.

Require only the unconditional Production readiness job in GitHub repository
rules. The two macOS jobs are conditional and are expected to report skipped
for unrelated pull requests. The exact repository-rule setup and verification
procedure is documented in the
[compiled iOS CI gate](./08-testing-strategy.md#repository-rule-setup).

If the intended release SHA contains no iOS build input and the two macOS jobs
were skipped, manually dispatch `iOS Build and Test` on that ref. A green
out-of-scope Production readiness decision is safe for merging, but it is not
current-SHA archive evidence and does not satisfy the release checklist above.

For archive failures, use the job summary first. The
`ios-release-archive-evidence-<run>-attempt-<attempt>` artifact contains the
source/toolchain and verification record; failed runs also publish
`ios-release-archive-failure-<run>-attempt-<attempt>` with package-resolution
and `xcodebuild` logs. Do not treat either artifact as a signed distribution
archive.

If Xcode only shows `Command PhaseScriptExecution failed with a nonzero exit
code`, expand the `Release Versioning Preflight` log. A missing marker means the
archive was started before release prep; run `REVENUECAT_API_KEY=appl_...
make prepare-ios-release VERSION=x.y.z` with the intended next semantic version
when you also want to install the production RevenueCat key, or use `BUILD=N
make prepare-ios-release VERSION=x.y.z` for the documented manual build-number
fallback.

If the expanded log warns that the RevenueCat key is invalid, either copy
`Config.local.example.xcconfig` to `Config.local.xcconfig` and set:

```xcconfig
REVENUECAT_API_KEY = appl_...
```

`Config.local.xcconfig` is ignored by git and is included after the tracked
development defaults, so it can safely override the local archive key without
committing environment-specific config. You can also let release prep write the
override for you by substituting the real key:

```bash
REVENUECAT_API_KEY=appl_... make prepare-ios-release VERSION=x.y.z
```

## Push Entitlement and Signing

`project.yml` is the source of truth for the main app's Push Notifications
entitlement. `Merian.entitlements` uses
`aps-environment = $(APS_ENVIRONMENT)`; XcodeGen resolves it to `development`
for Debug and `production` for Release. Regenerate `Merian.xcodeproj` after any
project setting change, and do not hardcode one environment in the generated
project or entitlement file.

Before distributing a Release archive:

1. Confirm the Apple Developer explicit App ID `app.merian.Merian` has the Push
   Notifications capability enabled.
2. Confirm the selected distribution provisioning profile includes the
   production APS entitlement.
3. Inspect the signed archive and verify `aps-environment` is `production`:

```bash
codesign -d --entitlements :- \
  /path/to/Merian.xcarchive/Products/Applications/Merian.app
```

A simulator build can verify the Release build setting and compile-time wiring,
but it does not prove APNs registration or distribution signing. Complete one
physical-device smoke test that registers a token and receives an Explore push
before TestFlight rollout. If logs report a missing valid `aps-environment`,
inspect the signed entitlements and provisioning capability first.

## Archive Export

If Xcode Organizer times out while fetching apps for team `TA8S64ST9W`, the
archive can still be checked without that screen:

```bash
make export-ios-release
```

The export step validates that the newest archive matches the prepared
version/build, checked-out revision, release-source fingerprint, and clean build
state, then runs App Store Connect export signing. By default it uses the Apple
account state in Xcode. If Xcode reports `No Accounts`, an invalid keychain
credential, or a missing `iOS Distribution` certificate, fix Xcode > Settings >
Accounts for the team or provide App Store Connect API key authentication:

```bash
export ASC_ISSUER_ID=00000000-0000-0000-0000-000000000000
export ASC_KEY_ID=ABC123DEFG
export ASC_PRIVATE_KEY_PATH=/path/to/AuthKey_ABC123DEFG.p8
make export-ios-release
```

The exported `.ipa`, `exportOptions.plist`, and Xcode export log are written to
`build/ios-export/`.

The helper canonicalizes its output paths before deleting any previous export.
`EXPORT_PATH` must resolve to a child of this repository's `build/` directory,
and `EXPORT_OPTIONS_PLIST` must resolve inside that export directory. Symlink
escapes and lexical `.`/`..` components—including traversal hidden behind a
not-yet-created directory—are rejected before prep validation, archive
selection, directory creation, or file removal.

After uploading, confirm App Store Connect places the processed build under the
expected semantic version and build number.

## Naturebook Apple Distribution Metadata Gate

For the public rebrand release, update the existing app listing; do not create a
new App Store Connect app record or bundle identifier. In Apple Developer
Certificates, Identifiers & Profiles, ensure there is exactly one explicit App
ID for `app.merian.Merian`, with description `Naturebook iOS (Merian)`. Register
it if it does not exist; otherwise edit only its description. The description
is not an App Store Connect metadata field.

Confirm these App Store Connect values before submitting:

| Field | Required value |
|---|---|
| Public app name | Naturebook |
| Bundle ID | `app.merian.Merian` |
| Primary category | Reference |
| Secondary category | Education |
| Marketing URL | `https://naturebook.earth` |
| Support URL | `https://naturebook.earth/support` |
| Privacy policy URL | `https://naturebook.earth/privacy` |
| Subscription/IAP localization | Naturebook Pro |

Do not change product IDs, entitlement IDs, RevenueCat offering identifiers, or
the App Store Connect app record. Confirm the canonical domains, direct AASA
responses with exact Explore/species paths, support mailbox, and export sender
are live before releasing the renamed binary. Use
[`15-naturebook-rebrand-rollout.md`](./15-naturebook-rebrand-rollout.md) as the
release checklist and
[`08-public-brand-compatibility.md`](../system-architecture/08-public-brand-compatibility.md)
as the permanent identifier contract.
