---
description: Publish a TestFlight beta through Xcode Organizer
---

# Publish Naturebook to TestFlight

Use the repository's canonical
[iOS publishing runbook](../../../../docs/development-guides/14-ios-release-versioning.md).
This file is an agent entry point, not a second deployment procedure.

> **Consent release hold:** Do not archive or distribute the current consent
> candidate. First close `CONSENT-001` through `CONSENT-008` and obtain the clean
> hosted exact-SHA iOS result required by the
> [production consent readiness record](../../../../docs/legal/production-consent-readiness-2026-08-03.md).
> The corrected replacement build may then enter the bounded TestFlight rollout;
> strict server cutover still waits for old-build expiration and deployed
> verification. Public production additionally requires archived App Store 18+
> and paid Gemini billing/DPA evidence.

The distribution authority is Xcode Organizer, not an agent or GitHub Actions:

1. Update a clean local `main` checkout and run `make xcodegen`.
2. Require exact-SHA **iOS Build and Test** to pass.
3. In Xcode select **Merian** and **Any iOS Device (arm64)**.
4. Choose **Product → Archive**.
5. In Organizer choose **Distribute App → TestFlight & App Store → Upload**.
6. Keep **Manage version and build number** and automatic signing enabled.
7. Record the uploaded version/build and source SHA.
8. Promote that same processed build through TestFlight and App Review without
   rebuilding it.

Never increment a build for each beta, run `agvtool`, force an Apple
Distribution identity, or add a second CI/Fastlane upload path.
