---
description: Use the explicitly authorized Merian release workflow
---

# TestFlight compatibility pointer

Use [`$merian-release`](../../../../skills/merian-release/SKILL.md) only after
an explicit upload or distribution request. Then follow the
[canonical iOS publishing runbook](../../../../docs/development-guides/14-ios-release-versioning.md).

This compatibility entry point is not a second deployment procedure. Xcode
Organizer remains the sole signing and distribution authority, and each release
action remains scoped to its explicit authorization and exact-SHA evidence.
