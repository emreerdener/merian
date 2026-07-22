# Insight Content

The `Content` directory handles the display of the core ecological data within an Insight sheet.

## Purpose
This area is responsible for rendering the detailed biological text, including
the primary ecological description, toxicity warnings, conservation statuses
(IUCN Red List), and the diagnostic visual comparison against confusing
lookalike species.

`BiologicalView` also owns the persistent `FieldTripProgressCard`. It appears
after toxicity and identification-review content and before Field notes and
educational cards when the view model has server-backed contribution rows. The
card shows every credited outing/Event under the visible **Field trips** header.
The heading reuses `InsightCardHeader`; its undivided rows use an uppercase
**GOAL COMPLETE** eyebrow, headline-sized goal name, enlarged objective
artwork/check badge, experience-only subtitle, and a prominent trailing
`GoalProgressRing`. The full row is tappable without a redundant chevron and
forwards a card-specific overview destination that deliberately omits Capture's
checklist-item focus. The card does not load data, cache contribution rows, or
trigger celebration effects.
