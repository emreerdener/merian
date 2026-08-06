# iOS App Privacy Manifest Contract

Last reviewed: August 5, 2026.

## Status and Scope

The main `Merian` iOS application now owns a tracked privacy manifest at
`apps/ios/Merian/Configuration/PrivacyInfo.xcprivacy`. The source manifest,
XcodeGen membership, generated Resources phase, validation archive, and exported
IPA are covered by fail-closed repository checks.

This closes the missing-application-manifest finding **in source**. It does not
by itself make a build ready for production. A release candidate still needs a
green hosted exact-SHA archive, an Xcode-generated aggregate privacy report,
App Store Connect answers reconciled to that report, and the owner/counsel
approvals in the
[production consent readiness record](../legal/production-consent-readiness-2026-08-03.md).

| Control | Current status | Production evidence |
| --- | --- | --- |
| App-owned source manifest | Implemented and locally validated | Commit the final candidate and retain the green source guardrail result. |
| Main-target resource membership | Implemented and locally validated | Hosted project guardrail and exact-SHA archive must pass. |
| Root manifest in the built `.app` | Implemented in the archive validator | Archive evidence must report `privacy_manifest_valid: true`. |
| Root manifest in the exported IPA | Implemented in the IPA validator | Run against the Organizer export used for release evidence, if an IPA is exported. |
| Embedded first-party executable audit | No direct current required-reason API use found in the watch, Explore widget, or Messages extension source paths | Re-audit whenever an embedded target or its shared sources change and confirm the aggregate report. |
| Aggregate app and SDK privacy report | Pending release operation | Generate from the signed Organizer archive and retain the reviewed PDF. |
| App Store privacy answers and ATT conclusion | Pending owner/counsel review | Reconcile the aggregate report, runtime behavior, public policy, and App Store Connect answers. |

This contract covers the main app executable. The August 5 source audit found
no direct required-reason API use in the watch app, Explore widget, or Messages
extension source paths, so this change does not add empty app-owned manifests to
those bundles. Apple requires each executable or dynamic library that directly
uses a required-reason API to carry an applicable manifest in its containing
bundle. The embedded targets and every dependency must therefore remain
independently auditable; the main app's manifest cannot stand in for their
declarations.

## Authoritative Files

| Concern | Authority |
| --- | --- |
| App declarations | `apps/ios/Merian/Configuration/PrivacyInfo.xcprivacy` |
| Target membership | `project.yml`; `Merian.xcodeproj` is generated and committed output |
| Exact declaration policy | `scripts/validate-ios-privacy-manifest.sh` |
| Generated-project membership | `scripts/check-ios-project-resources.sh` |
| Archive bundle validation | `scripts/validate-ios-archive.sh` and `.github/workflows/ios-build-and-test.yml` |
| Exported IPA validation | `scripts/validate-ios-exported-ipa.sh` |
| Adversarial fixtures | `scripts/test-validate-ios-privacy-manifest.sh`, `scripts/test-validate-ios-archive.sh`, and `scripts/test-validate-ios-exported-ipa.sh` |
| Public data-practice disclosure | `apps/web/app/privacy/page.tsx` and `apps/web/app/privacy-choices/page.tsx` |
| Consent release status | `docs/legal/production-consent-readiness-2026-08-03.md` |

The validator intentionally requires the complete reviewed declaration rather
than merely checking that a parseable plist exists. Removing a category,
changing a purpose, enabling tracking, changing a required-reason code, adding
an unexpected key, or producing duplicate declarations fails the contract.

## Tracking, Linking, and Consent Semantics

The current manifest declares:

- `NSPrivacyTracking = false`;
- no tracking domains;
- every declared collected-data category as linked to the user or device; and
- no collected-data category as used for tracking.

The linked-data choice is conservative because Naturebook's service data can be
associated with a Supabase account, anonymous account, device identity, scan,
or subscription. `tracking = false` means current behavior is not intended to
meet Apple's definition of cross-company tracking; it does not mean that the
app collects no data.

A privacy manifest is a disclosure artifact, not runtime authorization.
Optional PostHog analytics remains default-off and must stay behind the current
account-wide grant even though the manifest describes its potential data use.
The manifest also does not replace camera, microphone, Photos, location, Terms,
adult, or Gemini permission and consent flows.

Third-party SDK manifests are additive. The app-level inventory below
conservatively covers collection initiated by first-party product behavior,
including behavior delivered through service providers. RevenueCat, PostHog,
Supabase, Google Sign-In, and other linked SDKs remain responsible for their own
valid manifests. Xcode's aggregate report is the release-time view of the app
and all bundled dependencies.

## Required-Reason API Inventory

| Apple category | Approved reason | Current first-party use | Required boundary |
| --- | --- | --- | --- |
| File timestamps | `C617.1` | Reads metadata for app-owned queued media, imported files, and cached files to calculate local payload state, receipt ordering, and cache freshness. Representative owners include `QueuedScanContext`, `MerianNetworkClient`, `ExternalImageImportStore`, and `LocalImageLoader`. | Access must remain limited to files inside the app container or an app-group container and be used for app functionality. Do not transmit timestamps for fingerprinting or tracking. |
| Disk space | `E174.1` | `OfflineQueueStoragePolicy` reads available capacity before admitting offline media and produces observable low-storage behavior. `ArchiveManager` contains the same API for archive write admission and may be called only for that purpose. | Use only to decide whether there is enough space for a requested write or download. Do not send the capacity off device or derive a device fingerprint. |
| User defaults | `CA92.1` | App-owned preferences, local counters, migration flags, notification state, and non-authoritative retry hints use `UserDefaults.standard`. | Keep Release behavior app-only. No App Group `UserDefaults` suite is present in the reviewed main-target paths; introducing one requires a fresh reason audit and may require `1C8F.1`. |

The August 5, 2026 audit found no first-party use of the System Boot Time or
Active Keyboards required-reason categories in the reviewed main-target source,
so they are not declared. A debug-only preview suite name is not an App Group
store and is excluded from Release. These are audit observations, not permanent
allowlists; Apple changes the covered API list over time.

Never add an approved reason merely to silence a build or upload warning. The
actual code path, data derived from the API, user-visible feature, and declared
reason must agree.

## Collected-Data Inventory

Every row below is currently `linked = true` and `tracking = false`.
`Analytics` means the separately permitted PostHog path; it remains declared
because App Store privacy disclosures describe potential collection even when a
user can turn that collection off.

| Apple data type | Purpose | Product behavior represented |
| --- | --- | --- |
| Name | App functionality | Account and public-profile identity supplied through sign-in or profile editing. |
| Email address | App functionality | Authentication, account handling, support, and user-requested communications. |
| Precise location | App functionality | Optional observation context and the scientific record created for a submitted scan. Public projections apply separate geoprivacy rules. |
| Coarse location | App functionality; Analytics | Approximate observation or regional context and, after analytics grant, coarse locale or region telemetry. |
| Photos or videos | App functionality | Captured, selected, or explicitly shared scan media, profile media, and eligible public/reference imagery. |
| Audio data | App functionality | Wildlife audio, video audio, speech classification, and multimodal identification input. |
| Customer support | App functionality | Support, feedback, account, moderation, and deletion requests. |
| Other user content | App functionality | Descriptions, field notes, comments, reports, tags, and other user-authored product content. |
| User ID | App functionality; Analytics | Supabase account or anonymous-account identity and the pseudonymous identifier used by consented analytics. |
| Device ID | App functionality | Anonymous device identity, installation continuity, push routing, security, and account handoff. |
| Purchase history | App functionality | Subscription, entitlement, purchase, and restore state from Apple and RevenueCat. |
| Product interaction | App functionality; Analytics | Scan, community, progress, settings, and other product activity, plus consented interaction telemetry. |
| Other usage data | Analytics | Coarse, allowlisted usage events sent only after the optional analytics grant. |
| Performance data | Analytics | Consented app and device performance measurements. |
| Other diagnostic data | Analytics | Consented, allowlisted diagnostic outcomes and failure categories. |
| Other data types | App functionality | AI results, taxonomy, consent evidence, observation context, environmental context, and scientific-record fields not represented by a narrower Apple category. |

This table is an engineering mapping, not a substitute for Apple's definitions
or App Store Connect's questionnaire. If counsel or the product owner determines
that a category, linking status, purpose, or tracking classification differs,
update the behavior, manifest, validator, public policy, App Store answers, and
this inventory together.

## Change Contract

Before merging any change that adds a framework, executable, data flow, SDK,
analytics property, file-system API, `UserDefaults` use, disk-capacity check, or
other API Apple may classify as required-reason:

1. Audit the code path against Apple's current required-reason API list and App
   Store data-type definitions. Do not rely on a previous review date.
2. Identify the executable or dynamic library that calls the API. Give each
   affected bundle its own accurate declaration; do not rely on another
   bundle's manifest.
3. Decide whether the change affects collection type, purpose, identity
   linking, tracking, consent, retention, recipient, or public policy. Escalate
   changed legal/product facts for owner and counsel review.
4. Update `PrivacyInfo.xcprivacy`, the exact validator expectations, adversarial
   fixtures, and this inventory in the same pull request.
5. Regenerate the project with `make xcodegen` after any target or resource
   change and commit `project.yml` with the generated project.
6. Review dependency release notes and manifests whenever an SDK version
   changes. A valid app manifest does not cure a missing or invalid SDK
   manifest.

A behavior-neutral correction to a declaration does not need a customer-facing
changelog entry. A change to what the product collects, why it collects it, who
receives it, whether it is linked, or whether it is used for tracking does
require synchronized public policy and release communication review.

## Verification

Run the portable source and fixture contracts from the repository root:

```bash
make xcodegen
make validate-ios-project
make validate-ios-privacy-manifest
make validate-ios-versioning
make test-ios-ci-tooling
```

`make validate-ios-project` proves the manifest appears exactly once in the
main target's Resources phase. `make validate-ios-privacy-manifest` proves the
source plist exactly matches the reviewed declaration. The portable tooling
suite exercises missing, malformed, duplicated, tracking-enabled, wrong-reason,
wrong-purpose, archive, and IPA fixtures.

For the candidate SHA, require **iOS Build and Test / Production readiness**.
The Current-SHA Release archive job must find
`Merian.app/PrivacyInfo.xcprivacy`, validate it, and publish evidence containing:

```json
{
  "privacy_manifest_valid": true
}
```

For an exported Organizer IPA, use the canonical validator with the release
record's expected bundle name, identifier, version, build, source revision, and
source fingerprint:

```bash
bash scripts/validate-ios-exported-ipa.sh \
  /path/to/Naturebook.ipa Merian.app app.merian.Merian \
  VERSION BUILD SOURCE_REVISION SOURCE_FINGERPRINT
```

Before promoting beyond internal testing, control-click the signed archive in
Xcode Organizer, choose **Generate Privacy Report**, save the PDF in the
restricted release evidence, and reconcile it with:

- this app-level inventory;
- every bundled SDK and embedded executable;
- the public Privacy Policy and Privacy Choices page;
- the actual consent and permission behavior; and
- the App Store Connect privacy answers and ATT conclusion.

Any unexpected category, invalid dependency manifest, tracking-domain entry, or
mismatch is a release blocker. Fix the source or declaration and produce a new
archive; do not edit a generated report to match an intended answer.

## Apple References

- [Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
- [Adding a privacy manifest to an app or third-party SDK](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk)
- [Describing data use in privacy manifests](https://developer.apple.com/documentation/bundleresources/describing-data-use-in-privacy-manifests)
- [Describing use of required-reason APIs](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)
- [Required-reason API categories](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)
- [Approved required-reason codes](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons)
- [Collected-data types](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacycollecteddatatypes/nsprivacycollecteddatatype)
- [Collected-data purposes](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacycollecteddatatypes/nsprivacycollecteddatatypepurposes)
- [App privacy details on the App Store](https://developer.apple.com/app-store/app-privacy-details/)
- [App Tracking Transparency](https://developer.apple.com/documentation/apptrackingtransparency)
- [TN3181: Debugging an invalid privacy manifest](https://developer.apple.com/documentation/technotes/tn3181-debugging-invalid-privacy-manifest)
