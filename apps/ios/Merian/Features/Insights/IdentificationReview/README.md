# Insight Identification Review

The `IdentificationReview` directory manages the confirmation and confidence display of the AI's classification.

## Purpose
This area handles the species header presentation (common name, scientific name) and the visual confidence spectrum (the 3-band visual scale). It also manages the logic for displaying confident pet labels (e.g., dog breeds) while retaining the underlying species-grade taxonomy context.

The confidence explanation uses `PlanCard` with the Results context, so its
complimentary copy comes from the current server snapshot and keeps the daily
Flash allowance separate. Reanalysis and other Pro-only actions require
`canStartProScan`; exhaustion opens the soft paywall without affecting the
current saved result. The full entitlement contract is
[Three Complimentary Pro Scans](../../../../../../docs/backend-and-data/18-complimentary-pro-scans.md).

## Modal action lifecycle

`CandidateSwipeModal` is presentation-only. It records a typed
`CandidateSwipeDismissalRequest` containing the action, scan ID, and engine
presentation generation, then closes through its explicit binding. The owning
`CandidatesCard`, `InsightContentView`, or `ConfidenceExplanationSheet` resumes
that request only from the candidate sheet's real `onDismiss`. Applying an
override or confirming the original result is therefore deferred until UIKit
has released the sheet anchor and the owner has revalidated the captured scan
and generation.

Confidence explanation uses the same pattern for community and refinement
handoffs: nested candidate actions resolve first; actions that leave the
explanation are staged as `ConfidenceExplanationDismissalAction` and executed
by `ConfidenceBadge` after the outer sheet dismisses. Never mutate the engine,
request a sibling route, or sleep for an assumed dismissal animation inside a
presented review surface.
