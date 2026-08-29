# iOS Release Versioning and Xcode Organizer Runbook

Last updated: August 24, 2026

## Active Consent Release Hold

`CONSENT-001` through `CONSENT-012` are closed in source. Internal development
and the causal-consent replacement may be archived/uploaded for processing under
the ordinary gates below, but that build must not be distributed before the
RPC/ACL migration is deployed in the approved maintenance window and every
direct-writing build is expired or suspended. Do not nominate the current
consent candidate for public production or run strict server cutover until the
clean hosted exact-SHA iOS evidence and validation-only **Supabase Candidate
Validation** result are green on the same immutable SHA, as defined by the
[production consent readiness record](../legal/production-consent-readiness-2026-08-03.md).
Only the current-version replacement build may enter the bounded TestFlight
rollout. That build must retain the clean-install first-scan and forced
`ai_consent_required` recovery evidence in the
[first-scan consent-policy incident](../incidents/2026-08-first-scan-consent-policy-retry-loop.md);
source compilation alone is not release proof. Public production also remains
blocked on archived App Store 18+ and paid Gemini billing/DPA evidence. The
app-owned privacy manifest is implemented in source, but the signed archive's
aggregate privacy report and reconciled App Store answers remain release
evidence under the
[iOS App Privacy Manifest Contract](./16-ios-privacy-manifest.md). This hold
adds prerequisites; it does not change the Organizer-only distribution authority
below.

The global ATS exception is also removed. Source and signed archives must retain
ATS defaults and credential-free HTTPS origins under the
[iOS App Transport Security Contract](./17-ios-transport-security.md).

## Policy

Xcode Organizer is the sole distribution authority for Naturebook iOS builds. It
owns automatic distribution signing, uploaded build-number management, and
delivery to App Store Connect. Apple credentials and private signing material
stay in Xcode and the macOS Keychain; they are not duplicated in GitHub.

GitHub Actions has a separate validation role. It compiles and tests the exact
workflow SHA and creates an unsigned Release archive with
`MERIAN_IOS_VALIDATION_ARCHIVE=1`. That archive proves Release compilation but
is never signed, exported, or uploaded.

Backend evidence is likewise validation-only: **Supabase Candidate Validation**
replays the exact SHA into a disposable database without a Production
environment, production secrets, or deployment. Public release nomination
requires its green SHA to match the iOS workflow SHA. The separate Supabase
production job remains an operator-authorized deployment action and is currently
blocked before its GitHub `Production` environment by the checked-in
`species_dictionary_chat_production_hold`. Clearing that hold still requires the
historical V49→V50 physical install-over baseline and the current V50
source-only-rename physical install-over gate in this runbook. Source-created
V49/V50 fixtures prove candidate-self consistency only; physical results remain
release evidence. The Field Chat source controls now include six-table cleanup
and permanent atomic-RPC ownership of conversation insertion, explicit
post-bundle database activation, one executable Swift/Deno prompt-label policy,
a structurally bound protected clearance, and an exact clean mutation-SHA check.
Each live route now exposes a candidate-derived bundle digest, database `ready`
force-selects the chat fleet, activation records the three identities, and
clearance retrieves/recomputes artifacts while checking live protections.
Backend release remains blocked on non-skipped and hosted evidence, accepted
external GitHub control configuration, the V49 install-over, and external
approvals. The canonical requirements are in the
[Supabase hold-exit criteria](../backend-and-data/06-supabase-deployment-runbook.md#species-dictionary-field-chat-hold-exit-criteria).
Author and renew their retained artifacts through the
[release-evidence operations guide](../release-evidence/README.md); a validation
archive or local test result cannot substitute for that protected flow.

Do not add a second publisher through GitHub Actions, Fastlane, command-line
export scripts, or a manually forced distribution identity. Two upload paths
create competing build-number authorities and are the source of the sequential
build failures this policy prevents.

## Version and Build Policy

`project.yml` is the repository source of truth:

- `MARKETING_VERSION` is the customer-visible version, such as `1.0.3`.
- `CURRENT_PROJECT_VERSION` is a positive tracked archive baseline, not the next
  TestFlight build that an operator must increment for every beta.
- Every embedded target inherits both values. The app, Explore widget, Messages
  extension, and watch app must agree.
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
2. Copy `Signing.local.example.xcconfig` to `Signing.local.xcconfig` if the
   local file does not exist.
3. Set `MERIAN_DEVELOPMENT_TEAM` in that ignored local file to the Apple
   Developer team used by the existing App Store Connect app.
4. In **Signing & Capabilities**, keep **Automatically manage signing** enabled
   for Merian, MerianExploreWidget, MerianMessagesExtension, and MerianWatch.
5. Do not set `CODE_SIGN_IDENTITY` to Apple Distribution in project build
   settings. Xcode chooses the correct identity for development and distribution
   while automatic signing is enabled.
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
make validate-ios-privacy-manifest
make validate-ios-transport-security
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
   mismatched tracked versions, manual signing, a missing team, and
   non-production RevenueCat configuration.

The archive embeds:

- `MERIAN_SOURCE_REVISION`
- `MERIAN_SOURCE_FINGERPRINT`
- `MERIAN_SOURCE_STATE`
- the main app's validated `PrivacyInfo.xcprivacy`
- a main-app `Info.plist` with ATS defaults and a resolved credential-free HTTPS
  Supabase origin

The source state must be `clean`.

### 3. Review the aggregate privacy report

Before promoting a build beyond internal testing:

1. Control-click the signed archive in Organizer and choose **Generate Privacy
   Report**.
2. Save the generated PDF in the restricted release evidence. Record its
   filename or evidence identifier; do not add private release records to the
   public repository.
3. Confirm the report has no manifest errors and reconcile every app, embedded
   executable, and SDK declaration with the
   [canonical app inventory](./16-ios-privacy-manifest.md), runtime behavior,
   public Privacy Policy, Privacy Choices page, and consent controls.
4. Have the product owner and counsel approve the matching App Store Connect
   privacy answers and ATT conclusion before public release nomination.

An unexpected data category, tracking domain, required-reason entry, or invalid
dependency manifest blocks promotion. Correct the code, declaration, policy, or
dependency as appropriate and create a new archive. Do not edit the generated
report to match an intended answer.

### 4. Distribute with Organizer

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

Do not manually rewrite the build number shown by Organizer. The value that App
Store Connect reports after processing is the authoritative uploaded build.

### 5. Promote without rebuilding

After processing completes in App Store Connect:

1. Confirm the version and build number match the Organizer upload.
2. Complete export-compliance and beta-review fields when requested.
3. If `CurrentSchema` or startup store-plan selection changed, assign the build
   only to the bounded internal migration-QA group and complete the
   [schema-upgrade acceptance gate](#schema-upgrade-acceptance-gate).
4. After every applicable release gate is green, assign that processed build to
   the intended internal or external TestFlight groups.
5. Collect QA results against that exact build number.
6. Submit the same uploaded binary to App Review when it becomes the release
   candidate.

Internal TestFlight, external TestFlight, and App Review promote the same
uploaded binary. Never rebuild merely to move a tested build to the next stage.

## Schema Upgrade Acceptance Gate

This gate applies whenever `CurrentSchema` advances or startup migration-plan
selection changes for a schema that has shipped. Simulator and CI fixtures are
mandatory implementation proof, but they do not replace installing the exact
processed candidate over a store created by the released application on a
physical device.

For the current source-only repair, both the released source and candidate use
persisted schema V50. The candidate changes the Swift property owner without
changing the stored model. The historical V49→V50 install-over evidence remains
the prerequisite baseline for stores that have not yet crossed that release
boundary:

1. Reserve a dedicated non-production iPhone and account. Keep a genuine V50 App
   Store/TestFlight installation on the device; do not replace it with a locally
   modified V50 build or inject a test-created SQLite store.
2. On V50, create and persist representative offline work: an image queue row, a
   video queue row, and a mixed-media or description-bearing row with their
   media and scheduler records. Terminate and relaunch V50 once to prove the
   source state is durable.
3. Record sanitized source evidence: V50 app/build, device and iOS version,
   source identity when available, current schema, and presence of store
   artifacts. Never copy the raw store or record account identifiers, scan IDs,
   text, coordinates, local paths, or media.
4. Through the bounded internal TestFlight group, install the exact processed
   candidate over V50 without uninstalling or clearing app data.
5. Launch the candidate while collecting public device-console output. Require
   `ModelContainer bootstrap diagnostics` to show `currentSchema=V50` and the
   candidate source identity, and require
   `ModelContainer store-aware migration selection` to show
   `hasStoreArtifacts=true`, `storedSchema=V50`, and `strategy=current-store`.
   Reaching the normal UI with no recovery notice or safe mode is the required
   successful-open evidence. A migration-plan or full-historical selection is a
   failure.
6. If approved internal tooling can retrieve the persisted
   `StartupStoreDiagnostic`, cross-check `currentSchemaMajor: 50`,
   `store.storedSchemaMajorVersion: 50`, `selectedStrategy: current-store`, and
   an `attempts` entry with `name: current-store` and `outcome: success`. Do not
   require snake-case recovery telemetry; the normal-success path does not emit
   that event.
7. Confirm all representative queue rows, media references, retry fields,
   scheduler records, goal hints, collection relationships, and true/false
   collection tombstones survive. A V50 tombstone must remain mapped to the
   `isDeleted` column while the active property is `isPendingDeletion`.
8. Force-quit and relaunch. The second launch must select `current-store`, keep
   the reopened data, and show no recovery notice.
9. Create separate fresh V50 queue rows and verify the goal-hint companion in
   distinct foreground- and background-completion paths, plus relaunch,
   successful progress acknowledgement, and cancellation/orphan cleanup. Verify
   a deleted collection emits `is_deleted: true`, ignores delayed inbound
   upserts, and is purged only after the matching cloud acknowledgement.
10. Add the sanitized source/target builds, device/OS, diagnostic outcomes,
    queue survival result, relaunch result, V50 tombstone/goal-hint result,
    tester, date, and pass/fail decision to the restricted release record.

Any failure blocks wider TestFlight assignment and App Review nomination.
Preserve the device in its failed state for diagnosis; do not uninstall, delete
the store, or count recovery into a fresh library as success. Fix the startup
contract, upload a new candidate, and rerun the complete gate. The diagnostic
meanings and exact V50 source-only-rename expectations are canonical in
[`08-startup-store-recovery.md`](../backend-and-data/08-startup-store-recovery.md#v50-source-only-rename-acceptance).

For future schema bumps, replace the source/target versions and expected recent
plan with the actual released predecessor and candidate, while retaining the
same genuine-store, exact-binary, relaunch, data-survival, privacy, and evidence
requirements.

## Archive and Upload Rules

- One archive represents one source/configuration candidate.
- A changed source file, dependency lockfile, build setting, capability, or
  public client configuration requires a new archive and a new upload.
- A failed local archive consumes no App Store Connect build number.
- If Xcode reports upload success, treat the build as uploaded even while it is
  processing.
- If an upload result is ambiguous, check App Store Connect before retrying. Do
  not create parallel uploads from different tools.
- If App Store Connect rejects a build, fix the cause, create a fresh archive,
  and let Xcode manage the next build number.
- Keep Organizer archives until the beta or release train is complete.

## What CI Enforces

The iOS project guardrails verify that:

- `project.yml` and the generated project have matching version values;
- all embedded products inherit the same marketing version and build baseline;
- automatic signing is not combined with a forced distribution identity;
- CI Release archives remain unsigned and validation-only;
- the generated Merian target bundles the app-owned privacy manifest exactly
  once, with the reviewed collection declarations and required API reasons;
- the final archive contains that manifest at the application-bundle root and
  passes `scripts/validate-ios-privacy-manifest.sh`;
- the final archive rejects every ATS exception or insecure/unresolved Supabase
  origin and records `transport_security: "ats-default"`;
- the local archive preflight requires clean source and production client
  configuration;
- no GitHub Actions workflow contains Apple signing credentials or an App Store
  upload implementation; and
- the retired GitHub TestFlight publisher cannot silently return.

Run the complete local tooling contract with:

```bash
make test-ios-ci-tooling
```

If Organizer produces an IPA for retained release evidence, validate that exact
file using `scripts/validate-ios-exported-ipa.sh` and the version, Xcode-managed
build, source revision, and source fingerprint recorded for the archive. The
validator requires exactly one root app manifest and revalidates its complete
contents. See the
[privacy manifest verification procedure](./16-ios-privacy-manifest.md#verification)
for the command shape.

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
processing. Once its state is known, create a new archive and upload through the
same Organizer path; do not introduce a manual counter.

### Upload succeeds but the build is missing

Processing can take time. Check App Store Connect activity and Xcode's
distribution log. Do not immediately rebuild or upload through another tool.

## Release Record

For every external beta or App Review submission, record:

- marketing version and App Store Connect build number;
- source Git SHA;
- CI **iOS Build and Test** run;
- archive evidence showing `privacy_manifest_valid: true`;
- archive evidence showing `transport_security: "ats-default"`;
- Organizer archive creation date;
- aggregate privacy-report evidence identifier and reconciliation decision;
- App Store privacy-answer and ATT owner/counsel approval status;
- upload/processing result;
- SwiftData source/target schema and genuine-store install-over result when the
  schema or startup plan changed;
- migration device/OS, sanitized selected strategy and normal-open evidence,
  structured attempt when approved diagnostic retrieval was available,
  queue-survival and relaunch results, and new-schema persistence result when
  that gate applied;
- assigned tester groups;
- QA decision; and
- App Review submission result when applicable.

Never include certificates, private keys, provisioning profiles, passwords, or
private API credentials in the release record.

## Ownership Summary

| Concern                                    | Authority                           |
| ------------------------------------------ | ----------------------------------- |
| Marketing version and archive baseline     | `project.yml`                       |
| Generated target settings                  | XcodeGen / `Merian.xcodeproj`       |
| Compile and unit-test assurance            | GitHub Actions                      |
| Validation Release archive                 | GitHub Actions, unsigned only       |
| Distribution signing                       | Xcode automatic signing             |
| Uploaded build number                      | Xcode Organizer / App Store Connect |
| TestFlight groups and App Review promotion | App Store Connect                   |

This separation keeps the high-frequency Xcode workflow familiar while making
sequential build ownership unambiguous.
