# Xcode Organizer iOS Release Architecture

Last updated: August 5, 2026

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

CI's archive and Organizer's archive have different purposes. The CI archive
is deliberately unsigned and validation-only. It cannot become a beta. The
Organizer archive is created after exact-SHA CI succeeds and is the only object
eligible for distribution.

## Authority Boundaries

| Component | Responsibility | Explicitly does not do |
|---|---|---|
| `project.yml` | Marketing version, positive build baseline, automatic-signing policy | Allocate every beta build |
| XcodeGen | Generate synchronized target settings | Upload to Apple |
| GitHub Actions | Compile, test, validate an unsigned Release archive | Sign, renumber, export, or upload |
| Release preflight | Prove clean source, synchronized versions, automatic signing, team, and production client configuration | Store Apple credentials |
| Xcode Organizer | Archive distribution UI, automatic signing, managed uploaded build number | Decide product readiness |
| App Store Connect | Processing, tester groups, beta review, App Review | Rebuild binaries |

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

The main application owns
`apps/ios/Merian/Configuration/PrivacyInfo.xcprivacy`. XcodeGen adds it exactly
once to the Merian Resources phase, which places it at the root of the built
application bundle. It declares app collection practices consistent with the
published privacy policy, declares no tracking, and records `CA92.1` for
app-only `UserDefaults` access plus `C617.1` for app-container and app-group file
metadata access. It also records `E174.1` for the user-visible storage admission
checks that prevent new offline media writes when free space is insufficient.
Dependency manifests are additive and do not replace this application-owned
declaration.

`scripts/validate-ios-privacy-manifest.sh` is the executable policy contract.
Fast project guardrails validate the source manifest and generated target
membership. The exact-SHA Release archive validates the bundled copy, and the
Organizer export verifier validates the root manifest inside the final IPA.
Final App Store privacy answers and counsel approval remain separate release
controls. The complete declaration inventory, change rules, verification
commands, and release-evidence boundary are canonical in the
[`iOS App Privacy Manifest Contract`](../development-guides/16-ios-privacy-manifest.md).

## Promotion Model

The processed App Store Connect build selected for QA is immutable. Internal
TestFlight, external TestFlight, and App Review promote the same uploaded
binary. Source or configuration changes create a new Organizer archive and a
new Xcode-managed build number; stage changes do not.

The operational procedure lives in
[`14-ios-release-versioning.md`](../development-guides/14-ios-release-versioning.md).
