# Native identification recipient preflight — 26 September 2026

Status: implemented and locally verified; awaiting authorized release. All
current assignments remain Gemini.

## Delivered behavior

The native app checks the backend's assigned processing recipient before sending
an identification request. The app owns provider assignment; end users may grant
or refuse processing permission, with no provider chooser. A denied check keeps
the observation available for recovery.

This integrates the
[backend contract](./identification-recipient-preflight-2026-09-26.md) into both
native identification endpoints and both live and durable dispatch. The request
body remains unchanged. Shape metadata is derived off-main from its final
serialization, including image snapshots from video and any companion audio. The
RPC sends only operation, complete-input profile, Flash eligibility, original
client scan UUID and protocol; no observation media, description, location or
explicit account selector. Auth supplies identity.

The response must be one bounded row with a known decision and the exact
requested profile. Ready carries a closed recipient; recovery-only can retrieve
or wait for existing work but cannot authorize a new provider call.
Permission-required and client-update-required stop preparation.
Unknown/malformed/unavailable responses fail closed. There is no cached
readiness or headerless retry fallback.

Prepared background requests retain `X-Merian-Identification-Recipient`.
Foreground requests reconstruct it on every authentication or transport retry.
Local account and recipient permission are checked again at dispatch, including
pending OpenAI withdrawal; the exact live attempt validator survives
asynchronous preparation. The visual upload fail-safe starts only after
preflight readiness. Background recovery checks server completion first, then
current queue generation, account ownership and permission after preparation,
task enumeration and durable activation. A late permission denial saves
needs-attention before releasing the durable owner; persistence failure keeps
the unresumed task and owner for recovery.

Changed assignments return `409 ai_identification_preflight_changed`. The saved
scan retries through preparation with a new check. Permission denial pauses it,
and `426 client_update_required` pauses with an update prompt. These policy
responses do not count as network circuit failures. No SwiftData schema or
Identify response DTO changes are needed.

## Scope and release ordering

Existing required Gemini age/Terms/consent synchronization remains the first
gate. The native protocol remains 3, OpenAI collection is disabled, and every
admitted production binding remains Gemini. This slice alone cannot activate
OpenAI or make its consent sufficient for general app onboarding.

The additive backend preflight migration and admission callers must be deployed
and verified before distributing this client. A missing RPC blocks
identification while retaining the scan. Existing installed clients retain the
prior headerless backend path. Publish/deploy only under the canonical exact-SHA
release controls and explicit operation/target authorization.

Remaining activation work is coordinated provider-specific permission
collection, qualified client capability/protocol, confidence interpretation,
candidate qualification and a controlled assignment rollout. The optional
concise-prompt experiment stays deferred. No paid inference, hosted mutation or
provider activation belongs to this native slice.

## Verification

- Simulator build-for-testing compiled the app and tests for arm64 and x86_64.
- The complete `merianTests` run passed all 1,366 XCTest cases. Its 2,984 Swift
  Testing cases completed with two obsolete source-inventory assertions; all
  behavior tests passed. Both inventories were corrected, and all 11 tests in
  those two suites passed on rerun. The complete suite was not repeated after
  these test-only corrections.
- Project generation, event routing, privacy manifest, transport security,
  versioning, migration guardrails and generated Edge DTO gates passed.
  Generated Xcode membership contains only the five added Swift files.
- Markdown formatting, the exact recursive Edge/scripts formatting gate and
  `git diff --check` passed.
- Independent review found a late background permission-denial requeue race.
  Saving needs-attention before durable-owner retirement fixed it; follow-up
  review found no remaining blocker.

These are local simulator checks, with no paid inference or hosted changes.
Existing backend validation evidence remains in the backend preflight record.

## Benchmarks

This slice does not create new benchmark results. Existing Gemini and OpenAI
pilot results use different observations and timing boundaries, so they do not
prove a quality or speed winner. The concise screen remains inconclusive. The
next selection milestone is a matched comparison of qualified candidates; see
[the benchmark checkpoint](./identification-provider-client-compatibility-2026-09-26.md#benchmark-checkpoint).
