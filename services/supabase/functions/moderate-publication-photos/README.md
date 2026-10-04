# moderate-publication-photos

Prepared service-authenticated POST worker for private photo moderation. SQL
`publication_execution_enabled` and moderation/quota gates remain false. No
scheduler, deployment, publication, note approval or native delivery is enabled.
HTTP callers cannot nominate an owner, operation, source or provider attempt.

`index.ts` verifies service credentials and returns only no-store aggregate
`{claimed,settled}` counts. `db.ts` validates at most ten discovery hints,
claims one exact durable operation, freezes ordered sources and drops private
intake context. SQL uses the original saved IP for admission. `handler.ts` reads
original attempts and finalizes durable outcomes before external work. It
recovers one dispatched attempt (expiry retirement only), cancels one
undispatched reservation after a cohort refusal, or verifies the full ordered
cohort and prepares one photo before quota and one provider invocation. No
successor is automatically created. Unsupported source types can settle before
any provider attempt through the independent default-false source-settlement
gate. Unavailable sources and unattested container failures still back off
without new quota; verified container remediation remains an activation
condition.

A shared 135-second request deadline bounds all awaited I/O. New work/provider
execution stops at 105 seconds, leaving 30 seconds for up to two 12-second
identical completion writes. Finalizer/release afterward are best-effort within
what remains; if their response is lost or the budget expires, durable state and
work expiry own recovery. There is no promise that every upper-bound phase fits
in one request. Admission requires 60 seconds remaining before the provider
cutoff after complete preflight/preparation; dispatch requires at least 27 (12
for its RPC plus 15 for invocation). Actual invocation may be shorter than the
classifier's 90-second policy maximum. The same signal bounds fetching and
response streaming. Completion uses the separate overall deadline so it can save
a result after the provider cutoff.

`photos_approved` means historical provider approval only. Future copy/binding
must require its exact ordered causal leaves, verify bytes/metadata/current
review again and separately moderate immutable notes. CPU/memory qualification,
expired-work operational recovery, exact-source remediation and CDN cache bypass
remain required before activation. See the
[worker API contract](../../../../docs/backend-and-data/05-api-contracts.md#prepared-photo-moderation-execution-worker).
