# Code Ownership and Refactoring

This guide is the durable policy for Merian code-hygiene and organization work.
The completed [codebase cleanup RFC](../rfcs/codebase-cleanup.md) is the
historical implementation record; this guide owns the rules for future changes.

The objective is not the smallest file. It is the smallest set of cohesive,
well-named owners that preserves behavior and makes change impact easy to reason
about and test.

## Ownership model

Choose the narrowest honest owner:

- `apps/ios/Merian/Features/<Feature>/` owns one product area's views,
  presentation state, feature policies, and feature-specific services.
- `apps/ios/Merian/Core/` owns domain-neutral infrastructure with multiple real
  consumers. A generic name alone does not make code shared.
- `apps/ios/Merian/Models/` owns persistent model and schema declarations.
- `services/supabase/` owns database and Edge behavior.
- `apps/web/` and `apps/admin/` own their separate public and privileged web
  projections.
- `docs/` owns current contracts, runbooks, and historical records according to
  the
  [documentation ownership matrix](../CONTRIBUTING.md#documentation-ownership).

Large iOS features should remain product-area first. Within a real subdomain,
use `Models`, `Services`, `ViewModels`, `Views`, and focused `Components`
folders when they clarify responsibility. Do not create every bucket in advance
or move feature-specific code into `Shared` merely to shorten an import path.

## Decision table

| Situation                                                                       | Preferred action                                                                 |
| ------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| One file owns unrelated state, policy, I/O, and multiple view families          | Split by existing responsibility and lifecycle owner                             |
| Two views implement the same invariant and differ only by typed endpoint/action | Normalize the shared presentation behavior; keep thin typed adapters             |
| A helper is used by one file and has no independent state or tests              | Keep it private and colocated                                                    |
| An extracted file contains one pass-through value or closure                    | Recombine it with the closest cohesive owner unless it isolates a real boundary  |
| A component has several feature consumers but neutral semantics                 | Move it to the nearest feature-shared or Core owner after auditing all consumers |
| A service isolates an SDK, process, filesystem, persistence, or wire boundary   | Keep the boundary small and independently testable even when the file is short   |
| A large residual owner is cohesive and the next split adds indirection only     | Stop and record the reviewed exception                                           |

Line ceilings are review guards, not architecture. Do not widen access, create
one-value files, or add pass-through wrappers solely to satisfy a number.

## Required pre-change inventory

Before structural edits, record:

1. every declaration and extension in scope,
2. every production and test consumer,
3. direct network, SDK, persistence, route, and singleton dependencies,
4. existing docs and test matrices that name the owner,
5. public and internal initializer signatures that callers rely on,
6. baseline file count and affected production lines.

Use repository-wide searches. An apparently private UI component may be used by
another feature, extension target, or preview. If ownership or execution flow
remains unclear, use the read-only `merian_explorer`; the primary agent retains
all writes.

## Behavioral and visual parity

A hygiene-only change preserves:

- endpoint actions, payloads, persistence, feature flags, and schema behavior,
- navigation routes and presentation ordering,
- initializer and completion signatures used across the module,
- visible copy, layout, typography, accessibility identifiers and values,
- loading, empty, refresh, pagination, retry, and error states,
- focus, scroll, animation, media playback, and cancellation timing,
- lifecycle effects and idempotency.

Keep UI-only selection, gallery, focus, highlight, and scroll-proxy state in the
view when moving it would change SwiftUI identity or timing. Views and reusable
components must not perform direct networking. `@MainActor` view models own
presentation and interaction state; services own I/O. Inject narrow dependency
closures or existing interfaces rather than introducing a singleton or broad
speculative protocol.

## Extraction and encapsulation

- Preserve `private` and `fileprivate` scope. If a file split would expose
  mutable player, observer, task, cache, or generation state, create a contained
  state owner or keep the code with its lifecycle owner.
- Separate policy from mechanism when each changes independently. Do not split a
  pure value from the only policy that consumes it.
- Consolidate duplicate formatting, filtering, image rendering, or interaction
  logic only after proving the variants share the same invariant.
- Keep wire DTO names and semantics at the backend contract boundary even when
  UI language differs. Translate in a presentation/domain model instead of
  renaming the payload.
- Remove unused declarations and duplicate extensions only after all-target and
  test searches prove there are no consumers.

## Measuring progress

Every slice should report the **affected production delta**:

- production lines added and removed,
- production files added and removed,
- largest remaining owners,
- direct dependencies removed or narrowed,
- duplicates or obsolete declarations eliminated,
- intentionally retained exceptions and why they are cohesive.

Gross repository lines can rise when tests and documentation improve. That is
not evidence of production bloat. Conversely, moving the same production lines
into more files is not evidence of better ownership. Review the dependency and
responsibility delta alongside the counts.

## Verification and integration audit

Run focused tests while moving each owner. When source files or groups change,
regenerate from `project.yml` with `make xcodegen` and verify project/source
membership. Then run the feature's complete relevant target and repository
guardrails described in the [testing strategy](./08-testing-strategy.md).

Before leaving a top-level feature or Core domain, perform an integration audit:

1. search for stale paths, names, duplicated owners, widened access, direct I/O
   in UI, hidden singleton resolution, and unused files,
2. compare current routes, copy, accessibility, lifecycle, and persistence
   behavior with the declared parity contract,
3. review concurrency and cancellation at every extracted state boundary,
4. reconcile tests and documentation with their new owner,
5. inspect the generated-project diff and affected production delta,
6. implement review findings and rerun the affected gates.

## Stop conditions

Stop the slice when the remaining code is cohesive and further extraction would
not improve correctness, dependency direction, isolation, navigation,
testability, or discoverability. Also stop and re-scope when a mechanical move
requires behavior changes, crosses an unplanned feature boundary, or causes
tests to be rewritten merely to follow filenames.

A completed audit may legitimately recommend no further split. Document that
decision and move to the next meaningful product or infrastructure boundary
instead of generating redundant files.
