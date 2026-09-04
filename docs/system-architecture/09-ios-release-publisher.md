# Xcode Organizer iOS Release Architecture

Last updated: August 24, 2026

## Decision

Naturebook uses Xcode Organizer as its only signed distribution path. Xcode and
the local Keychain hold Apple account access, distribution certificates, and
provisioning state. GitHub Actions does not receive Apple signing or App Store
Connect upload credentials.

The architecture separates assurance from distribution:

```text
project.yml ──XcodeGen──> Merian.xcodeproj
      │                         │
      ├── GitHub Actions ───────┤ compile, test, unsigned Release archive
      │                         │
      └── clean main checkout ──┴──> Xcode Archive
                                      │ automatic signing
                                      ▼
                              Xcode Organizer
                                      │ managed build number
                                      ▼
                              App Store Connect
                                      │
                         TestFlight groups / App Review
```

CI's archive and Organizer's archive have different purposes. The CI archive is
deliberately unsigned and validation-only. It cannot become a beta. The
Organizer archive is created after exact-SHA CI succeeds and is the only object
eligible for distribution.

## Authority Boundaries

| Component         | Responsibility                                                                                          | Explicitly does not do            |
| ----------------- | ------------------------------------------------------------------------------------------------------- | --------------------------------- |
| `project.yml`     | Marketing version, positive build baseline, automatic-signing policy                                    | Allocate every beta build         |
| XcodeGen          | Generate synchronized target settings                                                                   | Upload to Apple                   |
| GitHub Actions    | Compile, test, validate an unsigned Release archive                                                     | Sign, renumber, export, or upload |
| Release preflight | Prove clean source, synchronized versions, automatic signing, team, and production client configuration | Store Apple credentials           |
| Xcode Organizer   | Archive distribution UI, automatic signing, managed uploaded build number                               | Decide product readiness          |
| App Store Connect | Processing, tester groups, beta review, App Review                                                      | Rebuild binaries                  |

## Sequential Build Ownership

`CURRENT_PROJECT_VERSION` is a tracked archive baseline. It remains synchronized
across the app and embedded targets, but operators do not increment it for each
TestFlight iteration. During **TestFlight & App Store** distribution, Xcode's
**Manage version and build number** option owns the unique uploaded build
number. App Store Connect is authoritative after upload.

There is therefore one writer for each layer:

- repository authors write product versions;
- Xcode writes distribution-time build numbers; and
- App Store Connect records accepted builds.

The removed GitHub publisher, reservation tags, command-line exporter, and
Transporter uploader are intentionally not fallback paths. Restoring one would
reintroduce a second build-number/signing authority and requires a new
architecture decision.

## Source Identity

The Release prebuild phase rejects a dirty checkout and verifies the tracked
version baseline. The postbuild phase embeds these values in the app:

- `MERIAN_SOURCE_REVISION`
- `MERIAN_SOURCE_FINGERPRINT`
- `MERIAN_SOURCE_STATE`

The fingerprint covers nonignored source files and rejects hidden Git index
state and tracked Xcode user data. Organizer distribution may manage the
uploaded `CFBundleVersion`, but it does not change the embedded Git source
identity.

## Signing Model

All distributable targets use `CODE_SIGN_STYLE=Automatic` and inherit the local
team through the ignored `Signing.local.xcconfig`. No tracked setting forces an
Apple Distribution identity. This lets Xcode choose development signing for
local work and distribution signing for Organizer without contradictory target
settings.

GitHub passes `CODE_SIGNING_ALLOWED=NO`, `CODE_SIGNING_REQUIRED=NO`, an empty
identity, and an empty development team to its validation archive. The
`MERIAN_IOS_VALIDATION_ARCHIVE=1` preflight branch verifies that CI cannot
silently create a signed release.

## Privacy Manifest Contract

The main application owns `apps/ios/Merian/Configuration/PrivacyInfo.xcprivacy`.
XcodeGen adds it exactly once to the Merian Resources phase, which places it at
the root of the built application bundle. It declares app collection practices
consistent with the published privacy policy, declares no tracking, and records
`CA92.1` for app-only `UserDefaults` access plus `C617.1` for app-container and
app-group file metadata access. It also records `E174.1` for the user-visible
storage admission checks that prevent new offline media writes when free space
is insufficient. Dependency manifests are additive and do not replace this
application-owned declaration.

`scripts/validate-ios-privacy-manifest.sh` is the executable policy contract.
Fast project guardrails validate the source manifest and generated target
membership. The exact-SHA Release archive validates the bundled copy, and the
Organizer export verifier validates the root manifest inside the final IPA.
Final App Store privacy answers and counsel approval remain separate release
controls. The complete declaration inventory, change rules, verification
commands, and release-evidence boundary are canonical in the
[`iOS App Privacy Manifest Contract`](../development-guides/16-ios-privacy-manifest.md).

## Transport Security Contract

The main application retains App Transport Security defaults. It has no broad,
media, web-content, local-network, or domain exception, and app-configured or
backend-supplied remote URLs must be credential-free HTTPS before reaching a
network/media framework. `SecureTransportPolicy` owns the shared application
boundary; ATS remains an independent operating-system backstop.

Release Supabase connections also require ordinary platform trust plus a
matching certificate-chain pin on the exact `supabase.co` domain boundary.
Untrusted, unreadable, or unmatched chains cancel. The archive's
`transport_security: "ats-default"` evidence proves plist policy only, so the
exact candidate must also compile the Release TLS branch and pass the focused
transport/architecture suites.

`scripts/validate-ios-transport-security.sh` parses both the configured source
plist and the final built `Info.plist`. Project guardrails, the exact-SHA
Release archive, and the Organizer IPA verifier all fail closed on an exception,
HTTP/credentialed Supabase origin, or unresolved archived build setting. Archive
evidence records `transport_security: "ats-default"`. The full change and
evidence contract is canonical in the
[`iOS App Transport Security Contract`](../development-guides/17-ios-transport-security.md).

## Promotion Model

The processed App Store Connect build selected for QA is immutable. Internal
TestFlight, external TestFlight, and App Review promote the same uploaded
binary. Source or configuration changes create a new Organizer archive and a new
Xcode-managed build number; stage changes do not.

When a released SwiftData schema or its startup-plan selection changes, the
processed binary may first enter only a bounded internal migration-QA group. A
physical device carrying a genuine released predecessor store must install that
same candidate without deleting application data, prove the source-isolated plan
and data survival, and relaunch as a current store. External TestFlight and App
Review remain blocked until that evidence is green. A simulator-created store,
local development binary, rescue into a fresh store, or different upload cannot
substitute for this acceptance gate.

The operational procedure lives in
[`14-ios-release-versioning.md`](../development-guides/14-ios-release-versioning.md).
