# Xcode Export Build-Number Rewrite

**Status:** Superseded on 2026-07-31 by the Xcode-only distribution decision.
The command-line exporter and GitHub publisher described in the initial
remediation are retired. This report preserves the original facts; operators
must follow the current Xcode Organizer runbook linked below.

**Observed:** 2026-07-30

## Summary

A clean signed archive passed every repository pre-export identity check as
Naturebook `1.0.2 (236)`. Xcode's App Store Connect distribution pipeline then
changed the exported IPA to build `272`. The source revision, source
fingerprint, and clean state stayed the same, so this was not an accidental
source or archive selection problem. It was a post-archive build-number
mutation.

The export helper generated an App Store Connect `exportOptions.plist` without
`manageAppVersionAndBuildNumber`. Xcode 26.6 documents that option's default as
`YES`. Xcode had cached App Store Connect build `271` and selected `272`
automatically. The helper validated the archive before export but did not
reopen the IPA afterward, then incorrectly described that unverified artifact
as TestFlight-ready.

## Evidence

| Artifact or observation | Verified value |
|---|---|
| Reviewed repository revision | `6ce1a56a47aea1deb05353a7714c3f0518aabfac` |
| Reviewed release-source fingerprint | `5c02aec4af0b40f131f127d1d55469f23bf503cb236a4029e87dd1b1946c3b76` |
| Local archive identity | `1.0.2 (236)` |
| Local archive source state | `clean` |
| Archive main binary/dSYM UUID | `3B424B1F-002D-3428-9480-FC675B7C36B2` |
| Xcode App Store Connect cache | latest build `271` |
| Distribution-pipeline IPA identity | `1.0.2 (272)` |
| IPA source revision/fingerprint | unchanged from the reviewed archive |
| IPA embedded app builds | main app, Explore widget, Messages extension, and watch app all `272` |
| IPA distribution entitlements | production APS, `beta-reports-active=true`, `get-task-allow=false` |
| Retained IPA SHA-256 | `ed6d6fabc3c595488d463dce84a23e68c8ac4058308778e984a9a045faffa1f4` |
| Content Delivery result | all `62,122,682` bytes uploaded; `UPLOAD SUCCEEDED with no errors` |
| App Store Connect acceptance | `1.0.2 (272)`, no errors or warnings, entered `PROCESSING` at `2026-07-30T19:59:06-05:00` |

The production-style entitlements and Store provisioning profile show that the
artifact was genuinely processed through App Store export signing. Its retained
source provenance shows that Xcode mutated metadata rather than substituting a
different code checkout. Retained Content Delivery logs also close the upload
ambiguity: build `272` reached App Store Connect and is definitively consumed.

## Impact

- `CURRENT_PROJECT_VERSION` no longer guaranteed the number in the exported
  artifact despite being the tracked release source of truth.
- A reviewed archive and an exported IPA could have different build identities.
- Exact-SHA CI and archive provenance remained valid, but support could not map
  a TestFlight build number back to the prepared release without inspecting the
  IPA.
- A later release prep based on stale build `235` could collide with the actual
  global App Store Connect sequence.
- The prior “TestFlight-ready” success message was stronger than the evidence
  warranted.

This issue did not alter scan data or application source code inside the
artifact. It did weaken the release provenance chain used to decide which scan,
offline queue, Field Chat, and Explore fixes beta testers actually received.

## Root Cause

There were two coupled omissions:

1. `scripts/export-ios-release.sh` did not write
   `manageAppVersionAndBuildNumber=false`, so Xcode's documented default allowed
   it to choose a different build during App Store Connect export.
2. The helper checked the archive before signing and checked only that some IPA
   existed afterward. It did not validate the artifact's version, build, or
   embedded provenance.

Signing success is not metadata-integrity evidence. Both preventive
configuration and postcondition validation are required.

## Initial Remediation (Historical)

The first repository remediation created an export path that:

1. writes `manageAppVersionAndBuildNumber=false`;
2. requires exactly one regular, non-symlinked IPA;
3. reopens the ZIP without extracting arbitrary paths;
4. rejects duplicate entries and requires exactly one root app
   `Info.plist`;
5. checks the root app bundle ID, package type, semantic version, build, source
   revision, source fingerprint, and `sourceState=clean` against the archive;
6. checks every first-party widget/Messages `.appex` and watch app carries the
   same semantic version and build; and
7. hashes the IPA before and after metadata inspection, rejects concurrent
   mutation, reports the stable SHA-256, and calls the artifact TestFlight-ready
   only after every postcondition passes.

`scripts/test-ios-versioning.sh` includes generated IPA fixtures for a valid
export, the observed build rewrite, dirty or mismatched provenance, a
first-party component mismatch, missing provenance, duplicate ZIP entries, and
multiple root apps. Its integration fixture drives the complete export helper
with a fake Xcode export and proves a renumbered output is rejected.

### Superseded Systemic Prevention

Fixing export metadata alone still left build allocation, local archive
selection, signing, and upload as separable operations. The repository briefly
used one manually dispatched **iOS TestFlight Publisher** as the sole
distributable writer. That path:

1. requires protected `main` and a successful exact-SHA compiled iOS gate;
2. serializes every candidate with a global workflow concurrency group;
3. queries the authoritative App Store Connect sequence and combines it with
   the tracked floor and immutable repository reservations;
4. pushes `ios-build-allocations/<build>` before the only archive invocation;
5. leaves the checkout unchanged and injects the build only into that archive;
6. validates and hashes the archive before and after export;
7. validates and hashes the final signed IPA before upload;
8. records annotated candidate and upload tags plus retained structured
   evidence; and
9. permits a retry only for the identical IPA after App Store Connect
   definitively reports `Failed`.

This design was removed after it proved operationally heavier than the existing
Xcode workflow and required duplicate Apple credentials. It is not an
available recovery or fallback path.

## Safe Recovery

Build `272` is consumed: Content Delivery uploaded the package successfully and
App Store Connect accepted it for processing. For a successor, wait for the
exact-SHA iOS gate, archive a clean checkout with Xcode, and use Organizer
**TestFlight & App Store** with **Manage version and build number** enabled.
Treat the processed App Store Connect number as authoritative. Do not relabel
an IPA, reuse archive `236`, or upload from another tool.

## Closure Gates

The replacement architecture is validated for a release candidate when one
exact revision has all of:

1. a green hosted complete unit target, both exact critical scan XCUI smokes,
   and current-SHA unsigned Release validation archive;
2. a clean Xcode Organizer archive with the intended revision and fingerprint;
3. a successful Organizer upload whose Xcode-managed version/build matches the
   processed App Store Connect build; and
4. the physical TestFlight scan submission/analysis, reconnecting offline
   queue, Field Chat, existing/new Explore sharing, push, and purchase smokes
   required by the release runbooks.

## Related Documentation

- [iOS release versioning](../development-guides/14-ios-release-versioning.md)
- [Xcode Organizer release architecture](../system-architecture/09-ios-release-publisher.md)
- [Testing strategy](../development-guides/08-testing-strategy.md)
- [Queued Insight handoff incident](./2026-07-queued-insight-same-id-handoff-regression.md)
- [Failed retryable scan incident](./2026-07-failed-retryable-scan-status-upload-deadlock.md)
