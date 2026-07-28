# July 2026 Supabase Edge Route `NOT_FOUND`

**Status (2026-07-28):** Production routing recovered after the observed
incident. Client resilience and the fleet-wide deployment gate are corrected in
the repository and require normal release promotion. Authenticated post-release
Share and Field Chat smoke remains required.

## Summary

Production returned zero-latency `404` responses for both
`/share-scan-to-explore` and `/get-explore-composer-media`. The responses had no
Edge region, execution record, authenticated user, or handler logs. Both
functions were already listed as active, and the composer function had not been
part of the scan owner-row correction.

This was a Supabase Function routing/metadata failure, not an application
`Scan not found` response. It was also separate from the earlier scan owner-row
durability gap. Rescanning cannot repair a platform route that did not reach the
function.

## Evidence and Classification

The relevant UTC sequence was:

| Time         | Evidence                                                                                                                                                                                                          |
| ------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Before 03:43 | A brand-new scan reproduced identify success followed by a marked handler-owned missing-scan response. This occurred before the corrected identify/status/share functions reported their later production update. |
| About 03:43  | Production listed the corrected scan functions as active with new update times.                                                                                                                                   |
| 03:58:56     | `get-explore-composer-media` returned platform `404` with zero latency and no region or execution evidence.                                                                                                       |
| 03:58:59     | `share-scan-to-explore` returned the same platform `404` shape.                                                                                                                                                   |
| About 04:00  | Direct unauthenticated probes reached the Share, composer-media, and Insight Chat handlers. Each failed closed with `401` and `X-Merian-Handler: 1`.                                                              |

The customer logs and attachments include request and observation identifiers.
This incident record deliberately retains only the sequence, route names, and
outcomes.

Merian now uses this boundary:

- **Platform route unavailable:** HTTP `404`, no `X-Merian-Handler: 1`, and
  Supabase's `SB-Error-Code: NOT_FOUND`, official missing-function envelope, or
  gateway-without-execution evidence.
- **Application missing scan:** HTTP `404` with `X-Merian-Handler: 1` and the
  route's normal missing-record payload.

Status code alone is never sufficient to cross that boundary.

## Repository Remediation

### iOS resilience

`MerianNetworkClient` replays only the platform route-unavailable response after
one-, two-, and four-second delays. The request body and idempotency key remain
unchanged. A marked handler response is never replayed by this branch.

If routing remains unavailable, the client throws
`MerianError.edgeFunctionUnavailable` instead of a raw HTTP `404`. Explore shows
temporary-availability copy, and Field Chat does not cache the scan as
deterministically unavailable. The customer can retry the same old or new scan
after routing recovers.

Background `identify-multimodal` responses carry the same selected routing
evidence into the durable queue. Classification now occurs before generic HTTP
handling, so a platform `404` schedules a durable retry instead of stopping a
newly captured scan. The full queue review also makes handler `401`, `408`,
`409`, `425`, and `429` retryable, including bounded `Retry-After` handling.
Other handler `4xx` responses preserve local media for explicit retry/cancel;
only exact `observation_rejected` is terminal.

### Deployment gate

Production deployment now derives the complete Edge Function inventory and
requires every route to answer an `OPTIONS` probe with `X-Merian-Handler: 1`.
Unresolved routes retry together for roughly two and a half minutes, then fail
closed without printing response bodies or request identifiers. The preflight
uses the validated legacy anon JWT only where the two intentional gateway
`verify_jwt = true` routes require authorization before handler execution. It
never sends a publishable key as Bearer and fails closed if the required
execution credential is unavailable.

The following five customer-critical routes receive an additional semantic
authorization probe:

1. `identify-multimodal`;
2. `check-scan-status`;
3. `share-scan-to-explore`;
4. `get-explore-composer-media`; and
5. `insight-chat`.

Each unauthenticated critical-route probe must return fail-closed `401` with the
marker.

These gates prevent a deployment from reporting success while any configured
route is absent and preserve stricter auth evidence on the five affected
customer paths. They do not claim that a later Supabase regional incident is
impossible; the typed client failure keeps that incident retryable and
distinguishable from scan state.

## Review and Validation Evidence

Completed repository evidence includes:

- the complete Edge Function suite: `1238 passed`, `0 failed`;
- migration contracts: `144 passed`, `0 failed`;
- discovery-based Supabase tooling: `96 passed`, `0 failed`, plus `16` DTO and
  `10` Identify wire-contract tests;
- workflow security and documentation contracts: `11 passed` and `8 passed`;
- all `89` function-local deployment graphs checked in isolation;
- Deno format across `656` files and lint across `501` files;
- public-web Edge caller checks: `11 passed`, `0 failed`;
- Swift source parsing for the changed application and test files;
- iOS project resource guardrails; and
- `git diff --check`.

The iOS tests cover exact platform-envelope and header classification,
case-insensitive stable codes, handler-marker precedence, unchanged idempotency
keys across replay, and no replay of handler-owned `404`.

Database-backed Edge cases reported skips because the workspace cannot reach the
disposable PostgreSQL service; production CI supplies an explicit test URL and
fails closed if it is unavailable. Full Xcode compilation remains
environment-limited by the workspace's nested SwiftPM/CoreSimulator
restrictions. The fleet-wide route gate and five stricter authorization probes
have not yet run against the repository changes in production. None of these
limitations is counted as a passing result.

## Required Production Verification

Do not close this incident until:

1. the repository changes pass production CI and are promoted in the matching
   iOS release;
2. the deployment record shows the complete graph-derived route inventory
   reaching marked handlers and all five critical routes failing closed;
3. an authenticated post-release scan immediately reports owner status `found`,
   opens Field Chat, and publishes to Explore;
4. an eligible older local observation repairs through the owner-row recovery
   contract and then supports both actions;
5. a synthetic or observed platform `NOT_FOUND` remains retryable and does not
   set scan-scoped Chat unavailability; and
6. any recurrence with no Edge execution evidence is escalated to Supabase
   support with the affected UTC window and project reference, while customer or
   observation identifiers remain out of repository documentation.

The owner-row correctness work and its separate exit criteria remain in
[July 2026 Scan Owner-Row Durability Gap](./2026-07-scan-owner-row-durability-gap.md).
