---
name: merian-release
description: "Prepare, review, or execute Merian release operations for TestFlight/App Store, Supabase production, Edge Functions, database rollout, RevenueCat, secrets, cleanup, rollback, or rollout readiness. Use only when the user explicitly invokes $merian-release or explicitly requests a named release/deployment operation and target; validation or implementation alone never triggers it."
---

# Merian release

This skill is an explicit authorization boundary. It never converts a green
build, implementation request, or request for evidence into permission to mutate
production or publish externally.

## Confirm scope before action

1. Read `AGENTS.md`, inspect `git status`, and read
   [authorized-release.md](references/authorized-release.md) completely.
2. Restate the exact requested operation, target, immutable source SHA, and
   whether the user authorized preparation only or external execution.
3. Resolve the canonical runbook and current target from checked-in evidence.
   Unknown or ambiguous targets remain read-only.
4. Require all prerequisite exact-SHA checks and external approvals. A candidate
   validation run is evidence, not deployment authorization.
5. Stop before any operation outside the explicit scope or when a required
   approval, credential owner action, rollback path, or evidence artifact is
   missing.

## Execute through reviewed authorities

- TestFlight/App Store: Xcode Organizer and the canonical iOS publishing
  runbook; do not create an agent-driven signing/upload path.
- Supabase production: the reviewed GitHub `Production` workflow on the exact
  SHA; do not substitute local CLI, MCP SQL, dashboard edits, or ad-hoc pushes.
- RevenueCat/App Store products: preserve existing app, bundle, product,
  entitlement, offering, customer identity, and webhook contracts unless the
  explicit change includes their coordinated migration.
- Cleanup, reset, rollback, or secret rotation: use the guarded canonical tool,
  dry run first when supported, bound the target, and retain redacted evidence.

## Close the release loop

Capture source SHA, target, approvals, preflight results, action outcome,
post-deploy positive and negative checks, monitoring window, and rollback status
without secrets or user data. Update durable operational documentation only for
a changed procedure or contract; do not commit transient release status as a
permanent instruction.
