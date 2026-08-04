# iOS Release Versioning and Xcode Organizer Runbook

Last updated: August 3, 2026

## Active Consent Release Hold

Do not archive or distribute the current consent candidate. Close
`CONSENT-001` through `CONSENT-008` and obtain the clean hosted exact-SHA iOS
evidence defined by the
[production consent readiness record](../legal/production-consent-readiness-2026-08-03.md).
Only the corrected replacement build may enter the bounded TestFlight rollout.
Public production also remains blocked on archived App Store 18+ and paid
Gemini billing/DPA evidence. This hold adds prerequisites; it does not change
the Organizer-only distribution authority below.

## Policy

Xcode Organizer is the sole distribution authority for Naturebook iOS builds.
It owns automatic distribution signing, uploaded build-number management, and
delivery to App Store Connect. Apple credentials and private signing material
stay in Xcode and the macOS Keychain; they are not duplicated in GitHub.

GitHub Actions has a separate validation role. It compiles and tests the exact
workflow SHA and creates an unsigned Release archive with
`MERIAN_IOS_VALIDATION_ARCHIVE=1`. That archive proves Release compilation but
is never signed, exported, or uploaded.

Do not add a second publisher through GitHub Actions, Fastlane, command-line
export scripts, or a manually forced distribution identity. Two upload paths
create competing build-number authorities and are the source of the sequential
build failures this policy prevents.

## Version and Build Policy

`project.yml` is the repository source of truth:

- `MARKETING_VERSION` is the customer-visible version, such as `1.0.3`.
- `CURRENT_PROJECT_VERSION` is a positive tracked archive baseline, not the
  next TestFlight build that an operator must increment for every beta.
- Every embedded target inherits both values. The app, Explore widget,
  Messages extension, and watch app must agree.
- The generated `Merian.xcodeproj` must remain synchronized with `project.yml`.

Keep one marketing version for the entire beta train. In Organizer, use
**TestFlight & App Store** and keep **Manage version and build number** enabled.
Xcode then gives each upload an acceptable unique build number and applies it
consistently to the distributable content. Do not run `agvtool`, edit the build
number before every archive, or make build-number-only commits.

Change `MARKETING_VERSION` only when starting the next release train:

1. Edit `MARKETING_VERSION` in `project.yml`.
2. Leave `CURRENT_PROJECT_VERSION` as a valid positive baseline unless there is
   a documented compatibility reason to raise its floor.
3. Run `make xcodegen`.
4. Commit `project.yml` and the generated project together.
5. Run `make validate-ios-versioning`.

## One-Time Xcode Setup

1. Sign in to the Apple account in **Xcode → Settings → Accounts**.
2. Copy `Signing.local.example.xcconfig` to
   `Signing.local.xcconfig` if the local file does not exist.
3. Set `MERIAN_DEVELOPMENT_TEAM` in that ignored local file to the Apple
   Developer team used by the existing App Store Connect app.
4. In **Signing & Capabilities**, keep **Automatically manage signing** enabled
   for Merian, MerianExploreWidget, MerianMessagesExtension, and MerianWatch.
5. Do not set `CODE_SIGN_IDENTITY` to Apple Distribution in project build
   settings. Xcode chooses the correct identity for development and
   distribution while automatic signing is enabled.
6. Confirm the permanent bundle identifiers and capabilities already exist in
   the Apple Developer account.

The production RevenueCat iOS SDK key beginning with `appl_` must resolve in a
Release build. Test Store keys and placeholders are blocked by the archive
preflight.

## Routine TestFlight Upload

### 1. Prepare the source

Use the exact revision you intend to test:

```bash
git switch main
git pull --ff-only
make xcodegen
make validate-ios-project
make validate-ios-versioning
```

The checkout must be clean. Wait for **iOS Build and Test** on that SHA to pass
before distributing a beta. CI's unsigned archive is evidence that Release
compiles; it is not the archive uploaded to Apple.

### 2. Create one local archive

1. Open `Merian.xcodeproj` in Xcode.
2. Select the **Merian** scheme.
3. Select **Any iOS Device (arm64)** or another generic physical iOS device
   destination, not a simulator.
4. Choose **Product → Archive**.
5. Let the Release Versioning Preflight finish. It blocks dirty source,
   mismatched tracked versions, manual signing, a missing team, and non-production
   RevenueCat configuration.

The archive embeds:

- `MERIAN_SOURCE_REVISION`
- `MERIAN_SOURCE_FINGERPRINT`
- `MERIAN_SOURCE_STATE`

The source state must be `clean`.

### 3. Distribute with Organizer

In the Organizer archive window:

1. Select the archive just created.
2. Click **Distribute App**.
3. Choose **TestFlight & App Store**.
4. Choose **Upload** and the recommended distribution options.
5. Keep **Manage version and build number** enabled.
6. Keep automatic signing enabled and allow Xcode to manage distribution
   certificates and provisioning profiles.
7. Review Xcode's validation summary, then upload.
8. Record the marketing version, uploaded build number, source SHA, and archive
   date in the release record.

Do not manually rewrite the build number shown by Organizer. The value that
App Store Connect reports after processing is the authoritative uploaded build.

### 4. Promote without rebuilding

After processing completes in App Store Connect:

1. Confirm the version and build number match the Organizer upload.
2. Complete export-compliance and beta-review fields when requested.
3. Assign that processed build to internal or external TestFlight groups.
4. Collect QA results against that exact build number.
5. Submit the same uploaded binary to App Review when it becomes the release
   candidate.

Internal TestFlight, external TestFlight, and App Review promote the same
uploaded binary. Never rebuild merely to move a tested build to the next stage.

## Archive and Upload Rules

- One archive represents one source/configuration candidate.
- A changed source file, dependency lockfile, build setting, capability, or
  public client configuration requires a new archive and a new upload.
- A failed local archive consumes no App Store Connect build number.
- If Xcode reports upload success, treat the build as uploaded even while it is
  processing.
- If an upload result is ambiguous, check App Store Connect before retrying.
  Do not create parallel uploads from different tools.
- If App Store Connect rejects a build, fix the cause, create a fresh archive,
  and let Xcode manage the next build number.
- Keep Organizer archives until the beta or release train is complete.

## What CI Enforces

The iOS project guardrails verify that:

- `project.yml` and the generated project have matching version values;
- all embedded products inherit the same marketing version and build baseline;
- automatic signing is not combined with a forced distribution identity;
- CI Release archives remain unsigned and validation-only;
- the local archive preflight requires clean source and production client
  configuration;
- no GitHub Actions workflow contains Apple signing credentials or an App Store
  upload implementation; and
- the retired GitHub TestFlight publisher cannot silently return.

Run the complete local tooling contract with:

```bash
make test-ios-ci-tooling
```

## Troubleshooting

### Conflicting provisioning settings

If Xcode says a target is automatically signed but Apple Distribution was
manually specified:

1. Open the target's **Signing & Capabilities** tab.
2. Enable **Automatically manage signing**.
3. Select the correct team.
4. In **Build Settings**, clear any target-level `Code Signing Identity`
   override for Release instead of forcing Apple Distribution.
5. Run `make xcodegen` if a generated setting drifted.

### Archive menu is disabled

Select the Merian scheme and a generic physical-device destination. Xcode does
not archive the app for an iOS Simulator destination.

### Dirty checkout is blocked

Commit the intended changes, remove unintended generated/user-state files, and
archive the committed revision. Do not bypass the preflight; provenance from an
uncommitted snapshot cannot be reconstructed reliably.

### Version is already closed in App Store Connect

Start a new marketing-version train in `project.yml`, regenerate the project,
and archive again. Do not change only the local Xcode target field because it
will be overwritten by XcodeGen.

### Build number is rejected

Verify that **Manage version and build number** was enabled and that Organizer
used **TestFlight & App Store**. Check whether another upload is still
processing. Once its state is known, create a new archive and upload through
the same Organizer path; do not introduce a manual counter.

### Upload succeeds but the build is missing

Processing can take time. Check App Store Connect activity and Xcode's
distribution log. Do not immediately rebuild or upload through another tool.

## Release Record

For every external beta or App Review submission, record:

- marketing version and App Store Connect build number;
- source Git SHA;
- CI **iOS Build and Test** run;
- Organizer archive creation date;
- upload/processing result;
- assigned tester groups;
- QA decision; and
- App Review submission result when applicable.

Never include certificates, private keys, provisioning profiles, passwords, or
private API credentials in the release record.

## Ownership Summary

| Concern | Authority |
|---|---|
| Marketing version and archive baseline | `project.yml` |
| Generated target settings | XcodeGen / `Merian.xcodeproj` |
| Compile and unit-test assurance | GitHub Actions |
| Validation Release archive | GitHub Actions, unsigned only |
| Distribution signing | Xcode automatic signing |
| Uploaded build number | Xcode Organizer / App Store Connect |
| TestFlight groups and App Review promotion | App Store Connect |

This separation keeps the high-frequency Xcode workflow familiar while making
sequential build ownership unambiguous.
