# Adding a provider later

The current production composition enables only Gemini. This procedure describes
the implementation and qualification needed for a future service; changing a
provider name or environment variable cannot activate one today. The
[PRD](../../../../../docs/product/03-identification-foundation-prd.md) and
[SRD](../../../../../docs/rfcs/identification-foundation-srd.md#8-infrastructure-release-and-later-provider-changes)
own scope and acceptance. Existing tasks, admission, persistence, and recovery
remain the integration points.

## Define the qualified assignment

Choose an exact task, model/API version, and accepted input set. Record a matrix
covering description, still images, ordered sampled frames, audio, and combined
images/audio. A five-second capture normally contributes five image snapshots
and may include companion WAV audio. An images-only assignment can cover inputs
without audio; included audio must be supported by the selected complete task
binding. Playback video is not model evidence. Do not silently drop evidence or
split one observation into additional model calls.

Supporting `species_overview`, `lookalikes`, and `group_tags` tasks can receive
their own qualified assignments. Each retains its separate quota/cache
lifecycle. Public jobs remain limited to claimed public species facts; private
observation jobs retain user authority even when a service invokes the worker.

## Implement the boundary

1. Add the adapter beside `gemini.ts`. Keep credentials, allowlisted transport,
   schema conversion, provider errors, file cleanup, usage parsing, and SDK
   types inside that implementation. `prepare` must perform no disclosure; local
   unsupported/configuration failures happen before quota commitment. `invoke`
   executes once and distinguishes refusal, unusable output, operational
   failure, and uncertain execution. Preserve caller-owned timeouts and
   recovery.
2. Extend the explicit unions in `contracts.ts` and approved profiles in
   `registry.ts` / `contentRegistry.ts` for the qualified variants. The current
   provider/model/configuration unions intentionally contain only Gemini values.
   Keep the evidence/result contracts independent of the new SDK. Reuse
   `identify/contract.ts` for common validation and add a provider-specific
   schema projection alongside the existing Google projection when necessary.
3. Extend authoritative database model/operation admission and the Edge registry
   together. Public jobs require an approved task/model assignment in their
   service path as well. Do not let the registry override a quota-selected
   model, accept client-selected providers/URLs, or widen the allowlist
   speculatively. Snapshot each admitted attempt; only existing
   recovery/admission can authorize a later attempt under a changed policy.
4. Update `production.ts` only when qualification and disclosure prerequisites
   below are met. Keep deterministic adapters test-only. Add the new
   SDK/dispatch owner to the reviewed inventory in
   `_tests/aiQuotaCoverage.test.ts`, update dependency pins and graphs, and keep
   deferred consumers explicit.

## Complete disclosure, result, and accounting work

Before sending real observation data, complete processor/purpose permission,
processing terms, account settings, region/subprocessor, retention/deletion, and
abuse-log review. Existing `google_gemini` receipts do not authorize another
recipient. Implement deny/revoke/account-switch/replay behavior with the actual
consent owner; do not relabel historical Gemini receipts.

Qualify confidence interpretation for every affected consumer: candidate bands,
history, queued results, older clients, public projections, SQL decisions, and
review flows. A new model's numeric confidence cannot inherit Gemini thresholds
without evidence. If a wire or persistence change is needed, change the
executable contract, regenerate DTOs, and ship a reviewed
compatibility/migration plan before activation. Completed results keep their
saved interpretation and replay without inference.

Review shared species caches before mixing providers: schema/prompt versions,
canonical identities, accepted provenance, and invalidation rules must be
compatible. Changing the binding alone does not regenerate or revalidate cached
content. Preserve separate user and public-job attribution.

Map usage units and prices explicitly, including cached input, reasoning, tool,
image, and audio components. Missing values remain unknown. Content helpers
currently project normalized counts back into the legacy usage shape for
existing ledger consumers; update that seam if another provider's units differ.
Preserve one accounting owner per call and document failed/uncertain-attempt
coverage. Keep diagnostics bounded and content-free.

## Qualify and activate

Run the common contract and actual-handler suites with deterministic adapters,
then qualify the real candidate on eligible, independently verified held-out
examples. Freeze quality, accepted/unknown coverage, confidence, safety,
latency, failure, and cost limits before comparison. Cover actual snapshots plus
audio where accepted; native-video results do not qualify this input path. Test
refusal, partial output, quota failure, deletion/account fences, uncertain
execution, durable replay, dependent content, and a return to a still-eligible
Gemini binding.

Use the existing exact-SHA
[candidate and deployment procedure](../../../../../docs/backend-and-data/06-supabase-deployment-runbook.md).
Any staged traffic selector must itself be reviewed; this infrastructure does
not provide a percentage-routing control. Require explicit operation/target
authorization before deployment or live disclosure. Do not introduce automatic
cross-provider retries after refusal or unknown execution. A later compatible
switch can become a reviewed server binding change once all these prerequisites
are already implemented and qualified.
