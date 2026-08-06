---
description: Publish a TestFlight beta through Xcode Organizer
---

# Publish Naturebook to TestFlight

Use the repository's canonical
[iOS publishing runbook](../../../../docs/development-guides/14-ios-release-versioning.md).
This file is an agent entry point, not a second deployment procedure.

> **Consent release hold:** `CONSENT-001` through `CONSENT-010` are closed in
> source. Internal TestFlight builds may be archived and distributed after the
> clean hosted exact-SHA iOS gate passes. That does not establish public
> production readiness: **Supabase Candidate Validation** must also pass the
> same immutable SHA, and the external controls remain required by the
> [production consent readiness record](../../../../docs/legal/production-consent-readiness-2026-08-03.md).
> Strict server cutover still waits for old-build expiration, deployed
> verification, App Store 18+, and paid Gemini billing/DPA evidence.
>
> **Privacy-manifest status:** the missing main-app manifest is closed in
> source. The signed archive still needs the aggregate Xcode privacy report and
> reconciled App Store answers required by the
> [privacy manifest contract](../../../../docs/development-guides/16-ios-privacy-manifest.md)
> before promotion beyond internal testing.

The distribution authority is Xcode Organizer, not an agent or GitHub Actions:

1. Update a clean local `main` checkout and run `make xcodegen`,
   `make validate-ios-project`, and `make validate-ios-privacy-manifest`.
2. Require exact-SHA **iOS Build and Test** to pass, including archive evidence
   with `privacy_manifest_valid: true`.
3. In Xcode select **Merian** and **Any iOS Device (arm64)**.
4. Choose **Product → Archive**.
5. Before promotion beyond internal testing, control-click the signed archive,
   choose **Generate Privacy Report**, retain it in the restricted release
   evidence, and reconcile it with SDK manifests, policy, and App Store answers.
6. In Organizer choose **Distribute App → TestFlight & App Store → Upload**.
7. Keep **Manage version and build number** and automatic signing enabled.
8. Record the uploaded version/build, source SHA, privacy-report evidence, and
   App Store privacy reconciliation decision.
9. Promote that same processed build through TestFlight and App Review without
   rebuilding it.

Never increment a build for each beta, run `agvtool`, force an Apple
Distribution identity, or add a second CI/Fastlane upload path.
