---
description: Publish a TestFlight beta with the serialized GitHub Actions publisher
---

# Publish Naturebook to TestFlight

Use the repository's canonical
[iOS publishing runbook](../../../../docs/development-guides/14-ios-release-versioning.md).
This file is an agent entry point, not a second deployment procedure.

Never increment a release build locally, archive with Organizer, run `agvtool`,
invoke a Fastlane beta lane, prepare a versioning commit, or export whichever
archive happens to be newest.

For a read-only local estimate:

```bash
make plan-ios-beta LATEST_ASC_BUILD=275
```

For a routine TestFlight beta:

1. Use the current protected `main` SHA.
2. Ensure exact-SHA **iOS Build and Test** is queued, running, or successful.
   The publisher waits up to 30 minutes and still requires both macOS jobs plus
   **Production readiness** to pass.
3. Manually dispatch the zero-input **TestFlight Beta** workflow.
4. Record the run, artifact, immutable tags, source fingerprint, archive
   identity, and IPA SHA-256.
5. For a retained candidate, existing upload, or definitive-failure retry, use
   **iOS TestFlight Publisher (Advanced)** and the exact retained artifact chain.
   Never rebuild the build number.
6. Promote the same processed binary through internal TestFlight, external
   TestFlight, and App Review.

If any source, dependency, configuration, signing/export setting, or rebuilt
byte changes, create a new candidate and let the publisher allocate a higher
global build. Treat an unknown upload result as consumed until App Store
Connect proves it failed.
