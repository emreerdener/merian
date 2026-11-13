# Incident: Private evidence signing dropped request cancellation

- **Date detected:** 2026-11-11
- **Status:** Exact candidate deployed; actual-byte runtime verification pending
- **Affected version:** Deployed backend
  b6bd9fed8adbf87030be22f8dce4fee05eaa8966
- **Affected surface:** Private evidence upload, verified read and erasure
- **Current contract:**
  [Private evidence request cancellation](../backend-and-data/05-api-contracts.md#private-evidence-request-cancellation)

## Summary and impact

Preparation for actual-byte cleanup qualification found that the real private
storage signer dropped the request cancellation signal. Its default retry loop
also used non-abortable exponential backoff. The ten-second request deadline and
caller cancellation therefore did not reliably reach outgoing fetches. Existing
injected-transport tests bypassed the affected signing path.

The deployed cleanup worker is active, but its last accepted evidence had no
private objects or outstanding obligations. No actual lost data, stuck request
or leaked bytes were observed. The defect is reproduced locally against the
deployed source, not inferred from a production failure. Scope here is the
private History storage owner; this does not claim all other R2 clients fixed.

## Detection and reproduction

Completion347's signing-only diagnostic used frozen b6 and the cached pinned
aws4fetch 1.0.20, with synthetic values and zero network requests. For both HEAD
and PUT, the input became aborted while the signed request did not. A regression
then exercised the default storage client with the real signer and synthetic
fetch: all ten caller/deadline cases failed before correction.

## Root cause and mitigation

`AwsClient.sign(Request)` copies method, URL, headers and body but omits signal.
`PrivateHistoryEvidenceStorage` previously passed the deadline-bearing Request
without explicit init options. It now forwards `signal: request.signal` as well.
Its dedicated configuration sets SDK retries to zero; shared `getS3Client` and
unrelated storage consumers remain unchanged. Durable owners preserve recovery
through the original receipt/claim. No database, HTTP payload, entitlement,
object identity or marker lifecycle changed.

Explicit signal propagation covers native fetch cancellation. Hashing, signing
and body cloning remain non-preemptive. This fix does not establish a whole
operation wall-clock or resource SLA. Operator code must use the reviewed
private configuration, not inject an arbitrary client with default retries.

## Regression coverage and candidate validation

Focused suite: 18 tests and 12 steps passed. Ten steps cover caller/deadline
propagation for upload PUT/HEAD, verified GET, and erasure PUT/HEAD through the
actual signer. Two steps prove 429/503 make one PUT and never a subsequent HEAD
or hidden retry. Synthetic fetch rejection proves propagation and sequencing,
not real network abort latency or a measured ten-second expiry.

Engine independently confirmed the defect, correction and strengthened outbound
source audit. Evidence plus outbound audit passes 21 tests / 12 steps. All 125
isolated function type checks and dependency graphs, strict lint and recursive
formatting pass. The full local Edge run reported 3,837 passed / 1,180 steps, 37
failed / 2 steps and 532 ignored. One failure was the old source audit; its
corrected call-offset-bound matcher and bypass mutations now pass. The remaining
36 parent failures are database suites against the existing local catalog,
including missing newer columns/routines and assertion mismatches; they remain
unqualified and are not declared fixed by this transport change.

Complete tooling stopped in the unchanged Gemini baseline CLI test at synthetic
hidden key entry. Its source matches deployed b6; original causality remains
unresolved. The full repository Markdown gate still fails on the unrelated
generated `apps/web/AGENTS.md`; changed Markdown is formatted. The first
recursive type-check invocation rejected unsupported `--cached-only`; the
corrected repository command passed all 125 entrypoints. Retain all original
logs. Exact successor CI against a freshly migrated disposable runner database
remains necessary. No test bypass or limit increase was made.

## November 11 candidate validation update

CI533 attempt 1 passed on exact successor
`13dcc59a221de823ed8207503b7475833a6f1862`, including Candidate readiness.
Complete tooling and Edge tests passed in the fresh runner environment. Retained
evidence reconciles 18 C1 suites / 301 checks and 22 private-handoff suites /
1,043 checks, matching source/migration hashes and expected database disposal.
This supersedes the pending-CI status above, while preserving all original local
failures and their unresolved causality. Synthetic resource evidence does not
qualify production timing or physical-device behavior.

## Production deployment and runtime verification

**Deployment completed; actual-byte runtime verification pending.** Authorized
exact13dcc deployment1866 and its metadata postconditions passed as recorded
below. The local frozen b6 checkout remains preserved; beta now serves13dcc.
Existing cleanup/monitor and closed user-facing History gates were retained.
Actual-byte storage cleanup, phone installation and the all-media walkthrough
remain open behind the separate correlation defect.

## Data recovery and privacy

No affected user records have been established and no data repair was performed.
Keep unknown PUT outcomes and original obligations intact. Evidence contains
synthetic data and aggregate results only; no real keys, sessions, media or
account identifiers. No hosted credential use or network storage calls occurred.

## Exit criteria

- [x] Root cause reproduced and bounded to the reviewed private owner.
- [x] Regression and correction independently reviewed.
- [x] Exact successor completes all applicable candidate gates.
- [x] Authorized successor deployment and metadata postconditions verified.
- [ ] Actual-byte cleanup and original marker acknowledgement verified.
- [ ] Full-flow device acceptance completed; no inferred data recovery closure.

## November 11 deployment readback

Authorized deployment1866 attempt1 completed successfully on exact
`13dcc59a221de823ed8207503b7475833a6f1862` to beta `qlarqavoqhkuwzmevrmf`.
Runtime logs report twelve planned functions and an up-to-date database; all six
jobs passed. All125 endpoints remain active. No new migrations or History
admission changes occurred. Readback preserved the original held cleanup request
and observed no private objects or pending erasure obligations.

This deploys the cancellation correction; it does not qualify actual-byte
cancellation or cleanup. The independent
[dispatch correlation incident](2026-11-private-evidence-dispatch-correlation.md)
blocks that next check. Function version changes during credential sync are not
evidence that all125 bundles were deployed.
