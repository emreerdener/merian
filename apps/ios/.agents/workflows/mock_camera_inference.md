---
description: Use the canonical Merian iOS fixture workflow
---

# Simulator capture compatibility pointer

Use [`$merian-ios`](../../../../skills/merian-ios/SKILL.md) and its
[capture, performance, and fixture rules](../../../../skills/merian-ios/references/capture-performance-and-fixtures.md).

Exercise post-capture UI through existing Debug/UI-test seeds or protocol-backed
fixtures. Do not patch the production camera pipeline, force unwrap fixture
assets, call inference delegates out of sequence, or add static coordinates.
