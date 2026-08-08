# First-Scan Consent-Policy Retry Loop

**Date:** 2026-08-07 local / 2026-08-08 UTC\
**Severity:** Release-blocking\
**Affected flow:** First-time onboarding → saved observation → foreground or
background Identify → Scan Library recovery\
**Repository status:** Remediated in source\
**Production status:** Open until a matching iOS build completes the exact-SHA
new-account and recovery verification below

## Summary

A first-time user completed onboarding and saved an observation, but the scan
remained in a scanning state while also presenting **Retry now**. Every retry
failed. The database routine named `reserve_ai_quota` rejected each attempt,
but this was **not** quota exhaustion: the stable failure was
`ai_consent_required`, raised by the legal-consent prerequisite before
entitlement selection, quota reservation, or Google Gemini dispatch.

The client had accepted cached local synchronization markers as cloud proof.
When the authoritative account rows were missing or no longer current, the
database correctly failed closed. The client then treated the exact policy
rejection like an ordinary recoverable HTTP failure, so it neither repaired the
account consent state nor stopped the retry loop.

## Customer Impact

- A valid first observation remained saved but could not complete analysis.
- The UI combined an active-looking scanning state with a manual retry action,
  even though retrying the unchanged request could never satisfy consent.
- Repeated attempts consumed network and background work without reaching
  Gemini.
- The error could be mistaken for a new account having no scans available
  because the rejecting database function contains `quota` in its name.
- Relaunch did not durably route the affected account back to the required
  disclosure, so the same invalid recovery state survived.

The affected account and observation identifiers are intentionally omitted.

## Runtime Evidence

The supplied Supabase export contains six paired failures:

| UTC timestamp              | Boundary                               | Result                |
| -------------------------- | -------------------------------------- | --------------------- |
| 2026-08-08 00:24:04.994    | `reserve_ai_quota` consent prerequisite | `ai_consent_required` |
| 2026-08-08 00:24:20.369    | `reserve_ai_quota` consent prerequisite | `ai_consent_required` |
| 2026-08-08 00:24:42.045    | `reserve_ai_quota` consent prerequisite | `ai_consent_required` |
| 2026-08-08 00:24:58.959    | `reserve_ai_quota` consent prerequisite | `ai_consent_required` |
| 2026-08-08 00:25:20.769    | `reserve_ai_quota` consent prerequisite | `ai_consent_required` |
| 2026-08-08 00:28:37.231    | `reserve_ai_quota` consent prerequisite | `ai_consent_required` |

The export contains no `pro_required`, `ai_quota_daily_exceeded`, user/IP rate
limit, or payment failure for this sequence. Gemini/provider dispatch never
began. The negative provider signal is decisive: the failure occurred before
the entitlement and inference portions of the reservation boundary.

The supplied 17.015-second HEVC recording is 444 × 960 and includes AAC audio.
The managed analysis environment could read its metadata but could not decode
frames (`AVFoundation -11821`, underlying `-12911`). The reported scanning plus
**Retry now** state is therefore treated as reporter evidence; the database
sequence and code path establish the technical cause independently.

## Why a New User Can Reach This Boundary

“First-time app user” is not authorization evidence. Naturebook creates or
restores an anonymous Supabase account, and the backend may authorize Gemini
only when that exact account owns:

1. the current adult self-attestation;
2. the current Terms receipt; and
3. a current Google Gemini grant that is also the greatest accepted event in
   the provider-wide consent stream.

Onboarding first writes those actions to a durable local ledger. The client
must then bind them to the active anonymous account, upload pending rows, and
fetch the authoritative account state. The server must never infer consent from
account age, an onboarding-complete preference, a local `syncedUserId`, an
available Pro scan, or a free daily Flash allowance.

Under the product contract, a new account is not supposed to begin with zero
ordinary scan capacity. The separate entitlement system resolves paid Pro,
included Pro scans, and eligible daily Flash fallback. None of those paths can
bypass missing consent, and a consent rejection is not evidence that any of
them is exhausted.

## Root Cause

Three client boundaries combined into an unrecoverable state:

1. `ConsentManager` retained locally synchronized evidence when a newly fetched
   remote state was empty and allowed persisted `syncedUserId` markers to stand
   in for a fresh authoritative cloud proof.
2. `MerianNetworkClient` did not map the exact handler-owned
   `403 ai_consent_required` response to the disclosure state machine.
3. `OfflineQueueManager` classified the response with generic `4xx`
   needs-attention behavior. The row stayed manually retryable, but no retry
   changed the missing account evidence.

The backend behavior was correct. `internal.require_current_ai_consent(...)`
runs inside both service-only `reserve_ai_quota(...)` overloads before provider
admission. It must continue to fail closed when evidence is absent, stale, or
revoked.

## Resolution

### Authoritative first-scan preflight

Before an Identify request body is constructed, `MerianNetworkClient` now
awaits `ConsentManager.ensureCloudConsentForInference()`. The manager:

1. resolves the active Supabase session;
2. pushes pending adult, Terms, and Gemini evidence for that account;
3. fetches the current adult and Terms rows plus the all-version Gemini stream
   head;
4. persists the identity- and generation-fenced merge; and
5. opens a process-local cloud-ready gate only when the fetched state itself is
   authoritative.

Persisted local synchronization markers alone cannot open inference. A failed
fetch, empty proof, account change, canceled generation, or failed ledger write
leaves the gate closed.

### Exact policy transition

`MerianNetworkClient` recognizes only handler-owned HTTP `403` with stable code
`ai_consent_required` as `MerianError.aiConsentRequired`. Generic `403`
responses retain ordinary authorization/error handling.

Foreground request preparation and background response handling converge on
the same policy transition:

- fence the active account in memory immediately;
- persist that account ID in the local consent ledger;
- invalidate cloud-ready proof and required switches;
- route a completed user to the Ready disclosure after authoritative
  restoration resolves;
- preserve the queued observation and its media in needs-attention; and
- return without automatic inference backoff or redispatch.

The foreground engine also classifies this policy transition before its generic
transport fallback. It uses **Approval needed / Scan saved** if the Insight
sheet remains visible during root routing and does not increment the shared
network circuit breaker. Repeated consent rejection therefore cannot impose a
15-minute connectivity cooldown after fresh approval.

The process-local gate remains closed even when the durable fence write fails.

### Fresh reapproval

The affected user must explicitly approve the current disclosure again. That
action creates new adult, Terms, and Gemini evidence instead of replaying the
cached rows. The new Gemini grant names the authoritative provider stream head
fetched after rejection as its causal parent. A later grant cannot overwrite an
unseen cross-device revocation, and another authoritative fetch is required
before the saved observation may retry.

The durable fence is account-scoped, survives relaunch, decodes safely from
legacy ledgers that lack the field, and moves with a confirmed ghost-to-
permanent account handoff without affecting another account.

## Product and Support Classification

Use the stable code, not the database function name:

| HTTP / code                          | Meaning                                | Customer path                                      |
| ------------------------------------ | -------------------------------------- | -------------------------------------------------- |
| `403 ai_consent_required`            | Required legal/provider evidence absent or revoked | Return to disclosure; preserve media; no automatic retry |
| `402 pro_required`                   | Requested capability requires Pro     | Present the existing upgrade path                  |
| `429 ai_quota_daily_exceeded`        | Daily provider allowance exhausted     | Present daily-limit recovery and honor retry delay |
| `429 ai_user_rate_limit_exceeded`    | Per-user burst protection              | Temporary bounded retry                            |
| `429 ai_ip_rate_limit_exceeded`      | Per-network burst protection           | Temporary bounded retry                            |

Support must not tell a user that they ran out of scans when the stable code is
`ai_consent_required`. Retrying the unchanged scan is not remediation.

## Verification

Repository regressions cover:

- foreground pre-dispatch refusal when required consent is absent;
- foreground mapping of exact handler-owned `403 ai_consent_required`;
- visual and nonvisual foreground policy failures staying out of the network
  circuit breaker while publishing saved-scan recovery copy;
- background classification of the exact code as `.consentRequired` while a
  different `403` remains `.needsAttention`;
- durable relaunch routing back to Ready;
- fresh evidence IDs and provider-head causal ancestry;
- legacy-ledger decode without an accidental fence;
- per-account fence isolation; and
- authoritative proof from freshly fetched adult, Terms, and Gemini stream-head
  rows for the same account.

The complete iOS production and unit-test source sets type-check in the source
environment. Runtime XCTest could not run because CoreSimulatorService was
unavailable. Source validation is necessary but does not close production.

## Required Release Verification

Do not close this incident until one matching Release/TestFlight SHA retains
all of the following evidence:

1. A clean install creates a new anonymous account, completes Ready, uploads
   the three required evidence rows to that same account, and fetches them back
   before the first Identify request.
2. A normal first single-image scan produces exactly one provider dispatch and
   one usable saved result; it does not present a paywall or needs-attention.
3. Forced missing cloud consent produces exactly one
   `403 ai_consent_required`, no provider dispatch, no automatic redispatch, and
   no consumed included-Pro or daily-Flash allowance.
4. The rejected observation remains present with all source media across
   backgrounding and relaunch.
5. Relaunch routes the same account to Ready. Fresh approval extends the
   post-rejection authoritative Gemini head, and manual retry of the original
   scan ID succeeds after another cloud proof.
6. Switching accounts does not transfer either the fence or evidence.
7. Real entitlement exhaustion continues to use `402 pro_required` or the
   applicable `429` code and its existing upgrade/daily-limit experience; it is
   never routed through consent disclosure.

## Related Contracts

- [Onboarding and Consent](../features-and-hardware/04-onboarding.md)
- [API Contracts](../backend-and-data/05-api-contracts.md)
- [Database Schema](../backend-and-data/04-database-schema.md)
- [Three Included Pro Scans](../backend-and-data/18-complimentary-pro-scans.md)
- [Error Handling](../development-guides/06-error-handling.md)
- [Testing Strategy](../development-guides/08-testing-strategy.md)
