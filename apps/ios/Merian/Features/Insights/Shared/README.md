# Insight Shared

The `Shared` directory contains reusable components and view models specific to the Insight feature.

## Purpose
Code is placed here when it is utilized across multiple sub-areas of an Insight (e.g., shared between `Content`, `Media`, and `Chat`) but does not represent an app-wide primitive that belongs in `Core`. This includes common data models representing an active insight session or shared visual styling modifiers for insight cards.

## Complimentary result state

`Badges/ModelTierBadge` is the Results-side owner of the complimentary
countdown. For a verified unpaid account it shows the server-reported scans
remaining and opens the soft paywall. After the third usable Pro result, it
shows exhaustion and the upgrade action on that result; it does not hide or
redact the stored Pro content.

The customer-facing pill reads “3 Pro scans remain” or “1 Pro scan remains”; it
never displays the internal word “complimentary.” Once exhausted, the pill
reuses `ModelTierBadge`'s existing upgrade label, which defaults to “Upgrade for
advanced analysis.”

Results and Settings are the only countdown surfaces. Capture and public
profile/Explore badges do not expose complimentary status, and paid accounts do
not see the complimentary prompt. The badge reads versioned
`EntitlementManager` state rather than decrementing local state. See
[Three Complimentary Pro Scans](../../../../../../docs/backend-and-data/18-complimentary-pro-scans.md).
