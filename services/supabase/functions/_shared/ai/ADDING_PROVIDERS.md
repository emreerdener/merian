# Adding a provider later

The production composition supports Gemini and the exact OpenAI still-photo
binding; the routing catalog remains Gemini until the separate activation. This
procedure describes the implementation and qualification needed for a future
service; changing a provider name or environment variable cannot activate one
today. The
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
2. For production assignment, extend the production attempt/model unions in
   `contracts.ts` and approved profiles in `registry.ts` / `contentRegistry.ts`
   for the qualified variants. The unions and registry include the exact dormant
   OpenAI photo binding. Its production adapter is enabled in source before the
   separate catalog activation; catalog rows still remain Gemini. The separate
   `OpenAIEvaluationSnapshot` and local evaluator profiles do not create
   production authority. Keep the evidence/result contracts independent of the
   new SDK. Reuse `identify/contract.ts` for common validation and add a
   provider-specific schema projection alongside the existing Google projection
   when necessary.
3. Extend authoritative database model/operation admission and the Edge registry
   together. Identification has an exact per-input binding catalog, currently
   assigned only to Gemini, and immutable quota-attempt snapshots, accessed
   through `reserve_identification_quota`; see the
   [admission contract](../../../../../docs/backend-and-data/05-api-contracts.md#provider-bound-identification-reservations).
   The new complete-input admission path derives a profile from normalized
   evidence and uses a processor-neutral private quota core before checking the
   selected recipient. Legacy callers and the current iOS inference gate still
   require Gemini. Backend policy selects the assignment; user permission can
   block its disclosure but never select another provider. The
   [consent infrastructure](../../../../../docs/rfcs/identification-provider-openai-consent-2026-09-26.md)
   is implemented with collection disabled. Adding a catalog row alone cannot
   admit another provider. Recipient-specific denial and saved-scan pause are
   implemented in the
   [client recovery contract](../../../../../docs/backend-and-data/05-api-contracts.md#independent-openai-consent-evidence).
   Route-scoped client compatibility is implemented in
   `20260926200227_add_identification_client_compatibility.sql`: each binding
   carries a minimum, and each fresh attempt snapshots the minimum and
   recognized original-client protocol. All current Gemini minima are zero.
   Internal retries use exact original-attempt evidence, never a worker header.
   The backend
   [recipient preflight](../../../../../docs/backend-and-data/05-api-contracts.md#assigned-recipient-preflight)
   now reports the app-assigned recipient without spending quota. A compatible
   ten-argument reservation rejects a changed expected recipient atomically; its
   optional header never selects a provider or proves permission. Native
   integration must carry that expectation through live and durable retries,
   preserve observations on drift, and recheck current local permission and
   account ownership immediately before dispatch. Complete that integration,
   qualified model admission and explicit permission collection before
   activation. Future admission changes must review all four identification
   overloads; do not patch only the older ones. The new six-argument preflight
   and eleven-argument reservation carry identification capability 4 separately
   from entitlement protocol 3. Preserve original-attempt proof and the global
   minimum for older-client recovery. The separate
   [result-reader boundary](../../../../../docs/backend-and-data/05-api-contracts.md#identification-result-readers)
   now checks the current capability on direct history/public reads and every
   completed-response emission. Release and verify that reader before
   activation, and retain it during rollback while V2 results exist. Marketing
   app versions and consent grants cannot substitute for capability evidence.
   The evaluation OpenAI binding supports only primary multimodal photo/text;
   compatibility and snapshot profiles are not qualified. Before activation,
   extend the versioned
   [durable result provenance](../../../../../docs/rfcs/identification-provider-result-provenance-2026-09-26.md)
   to cover the qualified adapter's generation settings and confidence profile.
   Gemini scans retain this server configuration independently of the quota
   record. The Identify DTO, owner history and V52 local store now retain it;
   unknown present profiles receive neutral native confidence guidance. Public
   community suggestions now suppress unsupported scores, and SQL metric gates
   cover Field Trip credit, public Perfect Lens and reference-image promotion.
   Field Chat now omits unqualified metric values while preserving descriptive
   evidence, and new export snapshots freeze metric qualification for the
   worker. Existing immutable jobs retain their prior interpretation; deploy the
   matching export worker before alternate results can exist. These preserve
   Gemini meanings; they do not qualify an alternate profile. See the
   [chat/export record](../../../../../docs/rfcs/identification-chat-export-metrics-2026-09-26.md).
   Public readers need a compatible minimum app version before alternate results
   become visible; an identification-only protocol gate is insufficient. See the
   [public metric record](../../../../../docs/rfcs/identification-public-metric-compatibility-2026-09-26.md)
   and the
   [client provenance record](../../../../../docs/rfcs/identification-client-result-provenance-2026-09-26.md).
   Public jobs require an approved task/model assignment in their service path
   as well. Do not let the registry override a quota-selected model, accept
   client-selected providers/URLs, or widen the allowlist speculatively.
   Snapshot each admitted attempt; only existing recovery/admission can
   authorize a later attempt under a changed policy.
4. Deploy adapter support in `production.ts` before changing any assignment. The
   OpenAI photo branch is enabled in source; no environment variable or
   credential selects it. The separate catalog activation owns live traffic,
   qualification and recipient authorization. Migrations run before Function
   deployment, so the activating migration must follow a confirmed deployment of
   the enabled adapter. Keep deterministic adapters test-only. Add the new
   SDK/dispatch owner to the reviewed inventory in
   `_tests/aiQuotaCoverage.test.ts`, update dependency pins and graphs, and keep
   deferred consumers explicit.

The primary handler also requires a qualified `multimodalResultPolicy.ts`
profile before commitment. It binds Gemini candidate thresholds and native
media-safety signals to the admitted snapshot, and accepts the exact OpenAI
photo profile with unqualified confidence and native moderation. A new
adapter/binding cannot bypass that boundary. OpenAI's evaluation score is
unqualified, and absent Gemini ratings provide no OpenAI media-safety verdict.
See the
[photo integration plan](../../../../../docs/rfcs/identification-openai-photo-integration-2026-09-27.md)
for slice status. The OpenAI photo adapter requires pinned inline moderation and
has V2 provenance readers. Its exact result policy, capability-aware admission
and promotion are connected to the enabled composition. The beta catalog assigns
still photos to this tuple; deploy the enabled bundle before the separate photo
assignment migration. The quota-policy model is independent of the immutable
provider execution model, so assigning photos cannot reroute audio or frames.

## Complete disclosure, result, and accounting work

Before sending real observation data, complete processor/purpose permission,
processing terms, account settings, region/subprocessor, retention/deletion, and
abuse-log review. Existing `google_gemini` receipts do not authorize another
recipient. The independent OpenAI stream and Settings flow implement local
deny/revoke/account-switch and causal synchronization behavior. Review and
publish the intended disclosure/purpose before enabling collection; a material
copy/purpose change requires a new version and fresh action. Complete
provider-aware inference admission and recovery with the same consent owner; do
not relabel historical Gemini receipts. The current owner-authorized beta photo
policy defers OpenAI-specific collection and enforcement for every beta account,
regardless of historical OpenAI choices. It preserves ordinary required consent
and all immutable receipts; the strict OpenAI receipt validator remains
unchanged. Before public consent enforcement, ship the matching native/backend
policy and a direct disclosure action on every permission-required alert,
returning to the same scan for explicit retry. See the
[bounded beta decision](../../../../../docs/release-evidence/openai-beta-photo-activation-2026-09-28.md).

Qualify confidence interpretation for every affected consumer: candidate bands,
history, queued results, older clients, public projections, SQL decisions, and
review flows. A new model's numeric confidence cannot inherit Gemini thresholds
without evidence. If a wire or persistence change is needed, change the
executable contract, regenerate DTOs, and ship a reviewed
compatibility/migration plan before activation. Completed results keep their
saved interpretation and replay without inference.

Primary identification and shared species-content assignments remain separate.
The three content tasks now use `sharedContent.ts` to require the retained
Gemini baseline before quota commitment and canonical generation; the biology
helpers also check snapshots. A registry change alone cannot qualify another
profile. Existing canonical public content stays reusable under its historical
baseline, without claiming exact model provenance for old rows. In-flight keys
include the baseline namespace, task, species identity and input dimensions.

Before another content provider is enabled, qualify schema/prompt versions,
canonical identities, accepted provenance, locale/taxonomy behavior, lookalike
ranking, group-tag semantics and promotion/invalidation rules. Use private
candidate storage until that decision exists; the public one-row-per-field
provenance table cannot safely hold raw execution configuration or competing
outputs. Changing a binding does not regenerate or revalidate content. Preserve
separate user/public-job attribution. See the
[shared-content record](../../../../../docs/rfcs/identification-shared-content-qualification-2026-09-26.md).

New primary scan ledger entries now copy saved model/provider/binding/policy/
prompt/schema references, with explicit legacy-tier fallback only when
provenance is absent. Admin totals/daily rows expose unknown-price coverage and
bounded provider/model/attribution groups. The writer prevents another provider
borrowing a Gemini tariff through a model-name collision. These changes preserve
historical rows and current Gemini units; they do not add another provider's
pricing. See the
[accounting record](../../../../../docs/rfcs/identification-provider-usage-attribution-2026-09-26.md).

Map usage units and prices explicitly, including cached input, reasoning, tool,
image, and audio components. Missing values remain unknown. Content helpers
currently project normalized counts back into the legacy usage shape for
existing ledger consumers; update that seam if another provider's units differ.
The primary multimodal route now owns one invocation event independently of scan
persistence, with durable unknown coverage and an exact native OpenAI photo
tariff. See the
[current accounting contract](../../../../../docs/backend-and-data/04-database-schema.md#primary-identification-attempt-accounting).
Extend that provider-scoped price identity and usage mapping for a new service;
do not add a second success writer. Compatibility and content routes retain
separate coverage limits. Keep diagnostics bounded and content-free.

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
