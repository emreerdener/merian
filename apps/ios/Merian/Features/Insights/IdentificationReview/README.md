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
