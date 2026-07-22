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
card shows every credited outing/Event, uses objective artwork plus a green
completion badge and `GoalProgressRing`, and forwards only typed destinations
to the Insight shell. It does not load data, cache contribution rows, or trigger
celebration effects.
