# Alternative identification provider evaluation

The first alternative is `gpt-6-sol` through OpenAI's Responses API. The shared
adapter is implemented for controlled local and hosted evaluation; **production
continues to assign every identification and enrichment task to Gemini**. No
client, environment setting or quota reservation can activate OpenAI in a
deployed endpoint.

The separate dormant `openai_photo_v1` integration binding now adds pinned
inline moderation and V2 result metadata. It is not an evaluation profile and
does not alter the completed baseline requests or their hashes. Its safety and
end-to-end qualification remain pending; see the
[integration plan](../rfcs/identification-openai-photo-integration-2026-09-27.md).

The
[matched comparison](../rfcs/identification-gemini-openai-matched-results-2026-09-27.md)
completed all sixteen scheduled Gemini/OpenAI attempts on 27 September. Earlier
app measurements and this comparison remain development evidence, with their
original inputs and limitations. The
[current optimization plan](../rfcs/identification-optimization-preserving-results-2026-09-27.md)
starts from that evidence and preserves the current explanation format and
detail. It does not require another Gemini-only benchmark campaign or a repeat
of the closed concise-explanation screen. Audio experiments cannot establish
photo/text quality.

## Fixed initial assignment

| Setting                     | Candidate                                                                    |
| --------------------------- | ---------------------------------------------------------------------------- |
| Evaluation profile          | `openai_gpt_6_sol`                                                           |
| Model                       | `gpt-6-sol`                                                                  |
| Transport                   | One synchronous POST to `https://api.openai.com/v1/responses`                |
| Input                       | Prepared photos (JPEG, PNG, WebP) and observation text                       |
| Reasoning / image detail    | `low` / `high`                                                               |
| Output                      | Strict common Identify JSON schema; 8,192 output tokens, including reasoning |
| Deadline / response ceiling | 90 seconds / 512 KiB                                                         |
| Confidence                  | `openai_unqualified_v1`; no Gemini match bands or diagnostic suppression     |

This is an initial candidate configuration, not a demonstrated quality or
latency winner.
[OpenAI's model documentation](https://developers.openai.com/api/docs/models/gpt-6-sol)
was reviewed on 25 September 2026. It documents text/image input and structured
output, and directs API clients to the alias `gpt-6-sol`; no dated snapshot was
listed. Record the returned model and run time. An alias does not establish an
immutable underlying model version. A returned-model mismatch stops the run.

The first slice rejects **the complete observation** when it contains WAV audio,
video frames, video capture metadata, an unsupported image type, or another
task. A five-second video in Naturebook supplies snapshots and may include
companion audio; it is not a native-video model request. Snapshot support can be
qualified later without discarding its accompanying evidence. No observation is
split into extra provider calls or silently reduced to photos.

## Implementation and data boundary

- `_shared/ai/openaiRequest.ts` owns the immutable evaluation binding, ordered
  evidence projection and strict-schema conversion from
  `_shared/identify/contract.ts`. It retains the existing visual/text task
  instructions and adds explicit optional-null and unqualified-score guidance.
- `_shared/ai/openai.ts` owns credentials supplied by the evaluator,
  fixed-origin transport, response-size/deadline enforcement, refusal/error
  decoding and usage. There is no SDK, URL override, retry, remote-media fetch,
  tool use, background job or stored conversation. Preparation performs no
  disclosure; the common executor permits one invocation.
- `scripts/identification_evaluation/providers.ts` selects evaluation profiles.
  Production `production.ts` contains a separate enabled photo composition,
  using `openaiPhoto.ts` and the exact registered binding. Credential lookup
  follows admitted catalog assignment; current catalog rows still select Gemini.
  Deploy the enabled bundle before a separate photo assignment migration.
  Evaluation profiles are not production assignments. The
  [photo integration record](../rfcs/identification-openai-photo-integration-2026-09-27.md)
  owns the implemented admission, safety, provenance and compatible-reader work.
- Required fields, bounds and enums still pass the common Identify parser.
  Provider-required null optionals map back to the domain contract; missing or
  extra provider fields fail. Domain normalization retains OpenAI candidates
  without applying Gemini's diagnostic threshold.
- Artifacts contain bounded decisions, requested/returned model, usage, timing
  and hashes. Prompts, photos, provider prose, reasoning items and error bodies
  are never copied into run results.

`store: false` disables stored Responses state. It does **not** promise zero
provider retention: default abuse monitoring and prompt-cache processing require
separate review. Consult
[OpenAI's data controls](https://developers.openai.com/api/docs/guides/your-data)
for the actual account and region before live disclosure.

## Offline verification

Run from the repository root. The parent directory must be private and outside
Git; the demo creates a new child. This uses invented images/text and fixed
outcomes, with no API key or network access:

```bash
evaluation_parent="$(mktemp -d)"
deno run --frozen --no-prompt --deny-net --deny-env \
  --config services/supabase/functions/deno.json \
  --allow-read="$PWD,$evaluation_parent" --allow-write="$evaluation_parent" \
  --allow-run=git \
  services/supabase/scripts/evaluate_identification.ts \
  demo-providers "$evaluation_parent/providers"
```

The eight assignments compare native Gemini Pro/OpenAI request preparation for
four synthetic photo/text cases. `runs/offline-providers-v1/` contains the
manifest, immutable claims/results and report. Running `offline` again resumes
without repeating claims. `preflight` prepares an explicitly selected provider
spec without dispatch; historical corpus-only preflight remains Gemini-only.
Offline reports prove mechanics, never biological quality, speed or price.

## Credential storage and future deployment

The long-term deployment source is the `NATUREBOOK_OPENAI_API_KEY` environment
secret in `emreerdener/merian` → `Production`, alongside the existing backend
provider credentials. This is the backend environment named exactly
`Production`; the `Production – naturebook` and `Production – naturebook-admin`
environments serve the web applications. Keep a recovery copy in the owner's
password manager. Do not put the key in source, app configuration or artifacts.

The name is intentionally separate from the repository's `OPENAI_API_KEY`, which
is consumed by the unrelated Agent Quality workflow. Storage alone does not run
a comparison, synchronize a Supabase secret or enable the provider. The manual
**Compare identification providers** workflow now reads the Naturebook key in
its protected evaluation steps. The protected production deployment now
synchronizes a configured value into the same-named Supabase Edge secret and
verifies its stored digest. An absent value skips synchronization and leaves any
existing runtime copy untouched.

The first pilot ran locally with a private packet and persistent run ledger. The
subsequent
[hosted comparison procedure](./23-hosted-identification-comparison.md) reuses
the existing public `merian` bucket for owner-approved test exports and durable,
one-shot experiment claims. It preserves provider-scoped credentials and
prevents a fresh GitHub runner from repeating an admitted comparison. No
self-hosted runner or local key retrieval is required for that path.

The local runner requires the same key from the owner's password manager; GitHub
does not provide a way to read a saved secret back. The terminal launcher below
injects it transiently as `OPENAI_EVALUATION_API_KEY`. GitHub is the deployment
source and Supabase is the runtime store. The
[deployment runbook](../backend-and-data/06-supabase-deployment-runbook.md#required-and-optional-github-secrets)
owns the env-backed CLI transport, digest verification and failure handling.
Successful synchronization proves only that the key was copied; it does not
validate provider access or activate OpenAI traffic. The photo composition is
source-enabled ahead of catalog activation; Gemini retains every assignment.
Settings can collect optional permission, while the owner-requested beta opt-in
deferral belongs to the subsequent activation change. Provider qualification,
traffic activation and rollback remain separate decisions.

### Private local key entry

Use `scripts/run_openai_evaluation.sh` under `services/supabase` from a trusted
local terminal on macOS/Linux with Python 3 and the repository-pinned Deno
installed. The launcher uses Python's hidden terminal prompt. It refuses an
unavailable terminal or echoed-input fallback, disables shell tracing, ignores
Python environment/custom user imports, and never saves or prints the key. Do
not paste a credential into chat, a shell command, an environment file or an
editor. It intentionally does not read an inherited key.

For initial readiness preparation, create a new private directory outside Git
and run:

```bash
private_review="$(mktemp -d)"
bash services/supabase/scripts/run_openai_evaluation.sh \
  --credential-fingerprint "$private_review"
```

Paste the existing Naturebook key **only when the hidden prompt appears**. The
only written file is `openai-credential-fingerprint.json` (mode `0600`),
containing a version and SHA-256 hash for the readiness record. No network or
provider call occurs. The file is created exclusively; an existing fingerprint
is never overwritten. This is a credential binding, not proof of valid billing
or input permission. Preserve it privately and bind its hash into the reviewed
readiness record described below; the launcher does not approve or alter that
record.

After the private packet has current pricing, OpenAI input permission, reviewed
readiness and a budget-bound live spec, run:

```bash
bash services/supabase/scripts/run_openai_evaluation.sh --live PRIVATE_RUN_ROOT
```

The directory must already exist outside Git, belong to the operator and have
mode `0700`. The launcher checks that the spec selects only OpenAI and runs the
existing offline preflight before asking for the key. Dependencies must already
be cached: run the offline demo above before handling credentials. The live
child receives only `PATH`, `HOME`, optional `DENO_DIR` and
`OPENAI_EVALUATION_API_KEY`; its Deno environment/network permissions remain the
narrow ones below. Dependency downloads, inherited service credentials, Git
configuration environment overrides and non-OpenAI provider dispatch are
excluded from this entry point.

The existing evaluator remains responsible for every approval, key hash, request
fingerprint, call/budget limit and durable claim. The wrapper never retries a
run or removes its ledger. Its success message means artifacts were written;
inspect the private report for completeness, unknown executions and failures
before interpreting the benchmark. An interruption is resumed only through the
same evaluator/root; never erase claims or create a fresh run to repeat
uncertain calls. Key entry is required again for each launcher invocation. For
an approved OpenAI-only experiment, `--experiment-session PRIVATE_RUN_ROOT`
prompts once and invokes the existing controller for each frozen run in order,
stopping on failure, a durable stop, incomplete state or a changed plan. The key
stays only in memory for that session; no persistent credential store is added.

## First live comparison

Reuse eligible photo/text source packets and labels, preserving prior evidence.
An exploratory packet can retain provisional references and an owner review;
there is no new requirement for a second reviewer. Formal qualification keeps
its existing independent-reference requirements. Freeze the small case list and
budget before execution, then compare identity agreement, unresolved answers,
failures, latency and estimated cost. OpenAI raw scores remain unqualified;
Strong/diagnostic metrics are not estimable until a confidence policy is
qualified.

The executable owners are `runContracts.ts` and `admission.ts`:

1. Use `identification_provider_run_spec_v1`. Offline runs may select Gemini and
   OpenAI together. Each live provider run selects **one profile** so its host,
   credential, pricing and processor approval have a single recipient. Use new
   run IDs for Gemini and OpenAI on the same frozen inputs/source. The existing
   two-profile Gemini specifications remain valid unchanged.
2. Supply `evaluation_openai_processor_v1` with `provider: openai`, the existing
   reviewed project/key, terms, data-use, region, retention and validity fields,
   plus
   `inputPermission: {provider, corpusDigest, caseIds, reviewRef, approved}`.
   That record must explicitly approve OpenAI for the exact corpus and selected
   cases, with `approved: true`. It supplements the corpus's historical
   `gemini_evaluation` curation; it cannot be inferred from it. Its lifetime is
   the enclosing review's expiry, bounded by source retention. Opaque review
   references are operator assertions, not cryptographic proof of permission.
   `dedicatedEvaluationProject` is an explicit boolean: use `false` for a shared
   Naturebook application project and `true` for a dedicated evaluation project.
   The same reviewed OpenAI key may serve the app and these benchmarks; a
   separate test project/key is optional. Shared usage consumes the same project
   limits, and the runner's budget accounts only for its own calls. The legacy
   Gemini `evaluation_processor_v1` remains dedicated-project-only. New Gemini
   runs may use `evaluation_gemini_processor_v1` with `provider: gemini`, an
   explicit project-kind Boolean and the same exact corpus/case permission
   structure naming Gemini. This permits the owner's existing paid application
   project without asserting that it is dedicated; it never approves OpenAI. The
   [Gemini procedure](../../services/supabase/scripts/identification_evaluation/README.md#future-explicitly-approved-gemini-live-use)
   owns credential, review, expiry and execution requirements.
3. Supply `evaluation_openai_pricing_v1`, `provider: openai`, with the model
   page above as `sourceUrl`, USD, `paid_standard_synchronous`, retrieval/review
   references and `includesReasoning: true`. Its single model is `gpt-6-sol`.
   Input rates are `text`, `image`, `cached`, `cacheWrite`; review worst-case
   synchronous rates including long-context/cache-write charges. There are no
   built-in prices. Reserve at least the full 1,050,000-token model context as
   `maxInputTokens` and at least 8,192 as `maxBillableOutputTokens`; the
   deliberately conservative reservation may exceed likely actual cost. Prices
   expire after seven days. Never lower ceilings merely to fit a budget.
4. Bind pricing/readiness digests and a positive explicit USD budget in the
   spec. The named `OPENAI_EVALUATION_API_KEY` must match the reviewed
   credential hash. Keep the key in the process environment, never a command
   argument or artifact. The evaluator checks approval again before each durable
   claim and invocation. A shared application key must still be injected under
   `OPENAI_EVALUATION_API_KEY`; the evaluator does not read `OPENAI_API_KEY`.
   This environment name scopes the runner's access, not the key's vendor-side
   privileges. Creating a key does not enable OpenAI in the production backend.

Use the terminal launcher above after authorization and private preparation.
Internally it executes the existing evaluator with
`--frozen --no-prompt
--cached-only`, read access to the checkout and private
packet, write access to only the packet, and `--allow-run=git`. Its live Deno
permissions grant network access only to `api.openai.com:443` and environment
access only to `OPENAI_EVALUATION_API_KEY`. It explicitly denies `SUPABASE_*`,
`R2_*`, `GOOGLE_*`, `GEMINI_*`, `WS_*` and `OPENAI_API_KEY` with `--deny-env`.
Deno's `--no-prompt` suppresses prompts but does not itself make these
permission states `denied`; the live admission checks require explicit denial.
See
[Deno's permission reference](https://docs.deno.com/runtime/reference/permissions/).
The launcher regression test exercises the actual Deno admission gate with a
synthetic key and no provider invocation. Source fingerprinting uses a Git
subprocess with hooks and filesystem monitoring disabled; that subprocess also
inherits the restricted child environment. This is a trusted local tooling
boundary, not isolation from other processes running as the same
operating-system user.

Broad environment/network permissions, Supabase/storage credentials and Gemini
SDK variables are rejected for OpenAI. The existing Gemini command remains in
the
[evaluator guide](../../services/supabase/scripts/identification_evaluation/README.md).
No changes to hosted secrets, Supabase or the simulator are needed for this
local comparison. This guide does not authorize a paid run.

Provider-run manifests add a validated `transports` catalog; `source.sdk`
retains the repository's Google SDK pin for comparison compatibility, while
`transports.openai` records `openai_responses_https_v1`. Complete source hashes
include the adapter. Existing manifests and audio evidence keep their formats.

Responses usage includes reasoning in `output_tokens`. The adapter separates
visible output from reasoning once, and the estimator charges total output once.
Unknown/malformed usage, model drift, uncertain execution, exhausted budget or
call limit stops further paid calls. No retry or failover occurs. Reports retain
all failures and excluded/unknown states; estimates are not invoice-exact caps.
The formal `compare` command requires matched cases/source/boundaries;
exploratory reports remain provisional and must not be passed off as formal
qualification.

## First live pilot evidence

The
[25 September photo/text pilot](../rfcs/identification-openai-photo-text-pilot-2026-09-25.md)
records seven normalized OpenAI results and one preserved unknown outcome across
eight existing examples. Four species results and both non-biological results
agree with provisional references; the mushroom name could not be scored from
its retained taxonomy mapping. The four untouched cases completed in a separate
bounded continuation without replaying any claimed case. This closes the initial
provider-path check, not production qualification. The dated record owns the
measurements and limitations.

## Shared measurement and planned optimization

Optimization Slice 1 is implemented for new offline exploratory packets:
reviewed canonical/synonym catalogs, explicit mapping states, v2 reports,
rate-aware cost estimates and a separate `compare-exploratory` command. Existing
v1 records keep their original interpretation. The
[tooling guide](../../services/supabase/scripts/identification_evaluation/README.md#shared-measurement-repair-optimization-slice-1)
owns formats, offline commands, missing-measurement rules and compatibility.
OpenAI native usage now includes bounded cache-write counts when reported; old
attempts do not gain those missing values retroactively. Historical attempts
have no explanation assessment; the retained concise candidate contracts require
the private review described below.

The
[current optimization plan](../rfcs/identification-optimization-preserving-results-2026-09-27.md)
records the completed existing-evidence bottleneck audit and OpenAI prompt
review. The isolated explicit-null visual candidate is now implemented for
evaluation; explanation format and detail stay intact. No new owner practice
exercise or Gemini benchmark campaign is required. Live candidate comparison
remains pending a fresh bounded allocation.

The [earlier plan](../rfcs/identification-provider-optimization-plan.md) records
the implemented measurement and experiment controls. Its Slice 2 supplies
immutable baseline descriptors, a frozen experiment plan, shared
allocations/reservations, an exclusive controller and a persistent global stop.
The
[controller contract](../../services/supabase/scripts/identification_evaluation/README.md#reusable-profiles-and-experiment-controls-optimization-slice-2)
owns `experiment-preflight`, `experiment-offline`, `--experiment-live` and
`experiment-report`. The OpenAI hidden-input launcher accepts
`--experiment-live <packet> <runId>` or `--experiment-session <packet>` for one
key entry across the ordered OpenAI runs. The retained
[private candidate workflow](../../services/supabase/scripts/identification_evaluation/README.md#concise-openai-candidate-and-private-review)
adds code-defined uncached control/concise profiles, bounded v3 attempts and
ephemeral explanation assessment. V2 experiments preserve owner calibration; v3
experiments record explicitly delegated AI review without a human practice
exercise. Their v3 reports identify AI assessment and no independent human
validation. The assistant processes only the task-approved corpus and bounded
review fields in its session; evaluator files still exclude explanation prose.
Only candidate live runs add loopback and fixed macOS opener permissions. Any
cache anomaly or missing/failed review stops remaining calls while preserving
completed results and cost. Reports apply the frozen latency/quality gates and
remain unqualified. Standalone candidate dispatch is blocked. Offline synthetic
validation establishes mechanics only. The owner approved the real eight-case,
16-request/$86 comparison on 26 September 2026. Its
[outcome record](../rfcs/identification-openai-concise-screen-2026-09-26.md)
closes the screen as inconclusive after one control result: identification
matched the provisional reference and observed cache counters were zero, but
lookalike claims could not be assessed against the frozen facts. Fifteen
assignments remain unattempted; retain the existing profile and defer the
concise candidate. The single result does not establish general cache support or
qualify production use. These profiles and tests remain available as historical
and regression contracts; their presence does not schedule another comparison.

The v1 controller accepts the two original baseline profiles; v2/v3 remain
specific to the closed concise hypothesis. The separate
[v4 explicit-null contract](../../services/supabase/scripts/identification_evaluation/README.md#openai-explicit-null-candidate)
compares the unchanged OpenAI baseline against four visual-prompt wording
changes, using six photos and twelve calls live. It retains baseline automatic
caching, delegated review and explanation detail; cache observations remain
descriptive, with no speed target or automatic production promotion. New run and
attempt versions preserve historical decoding. Packet JSON cannot select
arbitrary settings or authorize spending; the tooling owner remains
authoritative for admission.

## Later production assignment

The
[matched Gemini/OpenAI photo/text comparison](../rfcs/identification-gemini-openai-matched-comparison-2026-09-27.md)
completed all 16 first attempts on 27 September. Its
[outcome record](../rfcs/identification-gemini-openai-matched-results-2026-09-27.md)
preserves the source, measurements, description failures and cost limitations.
Both configurations agreed with five provisional biological photo references and
the mineral control. OpenAI's observed photo median was 7.10 seconds versus
15.81 seconds for Gemini Pro; this small reused corpus remains unqualified.

The
[photo integration record](../rfcs/identification-openai-photo-integration-2026-09-27.md#provider-infrastructure-closeout--27-september-2026)
records completed infrastructure and verified deployment of the OpenAI key
synchronization. The primary handler prepares a result policy before quota
commitment; the dormant photo binding has separate safety, provenance,
admission, accounting and reader contracts. These implemented boundaries do not
establish OpenAI qualification or activation. All production assignments retain
Gemini, including description-only, audio and sampled-video observations.
Permission collection, released-reader verification, held-out qualification and
explicit activation remain separate follow-up work. TestFlight archive and
released-store upgrade verification also remain separate iOS release work.

The implemented admission slice records an exact Gemini
provider/binding/permission assignment per metered identification attempt and
rejects unqualified recipients before dispatch. See its
[implementation record](../rfcs/identification-provider-production-admission-2026-09-26.md).
The subsequent
[OpenAI consent slice](../rfcs/identification-provider-openai-consent-2026-09-26.md)
implements independent evidence, strict recipient proof and optional Settings
choices with collection disabled in source. Account changes, failed saves,
revocation and causal synchronization are covered locally. Current onboarding,
client inference admission and the underlying quota delegate still require
Gemini. The
[server provenance slice](../rfcs/identification-provider-result-provenance-2026-09-26.md)
now retains successful Gemini provider/model and generation/confidence
configuration with atomic recovery backups. Historical unknown values stay null.
The
[client provenance slice](../rfcs/identification-client-result-provenance-2026-09-26.md)
adds DTO/V52 storage and neutral unknown-profile presentation; the
[native preflight slice](../rfcs/identification-native-recipient-preflight-2026-09-26.md)
carries app-assigned recipient expectations through dispatch and retries. These
implemented controls do not qualify OpenAI's runtime safety or confidence. The
optional concise-prompt screen is closed and is not required to implement these
boundaries. Follow the
[provider onboarding contract](../../services/supabase/functions/_shared/ai/ADDING_PROVIDERS.md).
Photo/text could then receive one provider and audio-containing observations
another, using complete-task capability checks. This slice enables that work
without changing today's production assignment.
