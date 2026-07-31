---
description: Publish an immutable iOS candidate with the serialized GitHub Actions publisher
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

For a real candidate:

1. Use the current protected `main` SHA.
2. Require a successful exact-SHA **iOS Build and Test** run with both macOS
   jobs and **Production readiness** passing.
3. Manually dispatch **iOS TestFlight Publisher** with the runbook's exact
   action, inputs, and confirmations.
4. Record the run, artifact, immutable tags, source fingerprint, archive
   identity, and IPA SHA-256.
5. If uploading later or retrying a definitive failed upload, use the exact
   retained artifact chain. Never rebuild the build number.
6. Promote the same processed binary through internal TestFlight, external
   TestFlight, and App Review.

If any source, dependency, configuration, signing/export setting, or rebuilt
byte changes, create a new candidate and let the publisher allocate a higher
global build. Treat an unknown upload result as consumed until App Store
Connect proves it failed.
