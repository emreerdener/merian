---
name: merian-feature-delivery
description: "Plan substantial Merian features and manage integration checkpoints against observable user journeys, dependencies, applicable evidence, blockers and forecasts. Use for feature planning, milestone readiness or delivery recovery; not routine single-file edits, standalone code review or release authorization."
---

# Merian Feature Delivery

Keep the next useful user journey visible while preserving the approved scope,
architecture and full safety, reliability and acceptance requirements. A first
working journey is an intermediate outcome, not permission to reduce delivery.
Follow [AGENTS.md](../../AGENTS.md), the owning implementation skills and the
[testing strategy](../../docs/development-guides/08-testing-strategy.md); this
skill does not replace their mandatory gates or authorize external operations.

## Connect work to a journey

Map the next observable outcome through existing owners and required integration
dependencies. Consult approved intent with `$merian-notion` when relevant; Git
remains the authority for implementation and technical contracts. For each newly
discovered prerequisite, record the concrete acceptance invariant, its
responsible existing owner, why it blocks the journey and whether broader
generalization can safely wait. Preserve mature foundations and required safety
work; do not introduce a new owner or rewrite merely to simplify a plan.

## Use coherent integration checkpoints

At natural checkpoints, batch related implementation, necessary compilation,
focused behavior tests and appropriate independent boundary review. Small
commits do not automatically require another full Release build and review.
Preserve mandatory intermediate and final affected-surface gates from the owning
skills and contracts. Check environment and storage readiness before expensive
validation; avoid accumulating substantial untested persistence work. Preserve
active builds, source/product freezes and sole-writer ownership.

Verify the actual selected methods, cases, skips and applicable database target;
exit zero alone is not coverage. Reuse passing evidence only while its source,
dependencies and environment remain applicable. Record that reuse; rerun checks
invalidated by changes or findings and retain failures and exclusions. Prefer
existing deterministic validation tools to prose-only claims or new process
tooling. Surface known required human actions promptly and continue independent
authorized work while blocked operations wait.

## Keep current state and forecasts honest

Maintain one compact current entry in existing continuation or acceptance
records: working outcome, next observable outcome, blockers, applicable evidence
and remaining checks. Distinguish source implementation, compilation, runtime
qualification, usable app behavior, deployment and release. Helper or test
counts do not establish app readiness. Preserve historical forecasts against the
same named outcome; revisions state assumptions, confidence and new
dependencies. Unknown durations stay unknown; do not sum overlapping work as
elapsed delivery time.

Use existing receipts to assess time to the first working journey, necessary
discovery versus avoidable rework, validation turnaround, blocked intervals,
escaped defects and estimate accuracy. Bound investigations to findings that can
change a decision. Do not add dashboards or a retrospective for every edit.
Review this skill's effectiveness after a real milestone; adoption alone is not
evidence that delivery improved.
