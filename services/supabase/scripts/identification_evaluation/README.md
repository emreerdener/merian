# Identification evaluation tooling

Slices 1–3 of the
[PRD](../../../../docs/product/04-identification-evaluation-prd.md) and
[SRD](../../../../docs/rfcs/identification-evaluation-srd.md) are implemented
here as local, offline tooling. The production route and tooling reuse the same
pure normalization helper. No production function imports these scripts modules.
The CLI runs offline by default and has a separate, explicitly gated live mode.
No formal reviewed corpus has been collected and no paid direct-evaluator run
has occurred. The first two-photo exploratory corpus passed local preflight; its
[experiment record](../../../../docs/rfcs/identification-exploratory-benchmark-2026-09-22.md)
retains scope and limits. A subsequent
[six-photo source packet](../../../../docs/rfcs/identification-source-photo-pilot-2026-09-22.md)
also passed offline preflight with provisional references and no model calls.
Its completed
[six-photo app benchmark](../../../../docs/rfcs/identification-source-photo-app-benchmark-2026-09-22.md)
records ordinary-app outcomes and passive measurements separately from the
direct evaluator's dry schedule. Gemini remains the only live provider; video
evidence is ordered snapshots and included WAV audio, never a playback video.

The later
[description app benchmark](../../../../docs/rfcs/identification-description-app-benchmark-2026-09-22.md)
adds two source-derived descriptions, one provisional genus agreement and one
biological assertion on an ambiguous non-biological-source description. Offline
preflight prepared four requests without dispatch; the separate ordinary-app
pass retained two complete five-event windows. Missing Describe timing markers
remain null in that run; its app build had no controlled audio/video import
route. No formal counts or direct-evaluator readiness gates changed.

The subsequent
[controlled replay app check](../../../../docs/rfcs/identification-replay-app-benchmark-2026-09-22.md)
verified Describe's first-render metric on a repeat and measured one first video
result through Debug simulator staging and normal manual Identify. Both windows
completed. The video packet passed offline preflight with five ordered snapshots
and its actual, digitally silent companion WAV. This does not establish useful
audio fusion. After the owner's listening review, the
[first audio app check](../../../../docs/rfcs/identification-audio-app-benchmark-2026-09-22.md)
completed one first submission and a six-event window. Its Wood Thrush Strong
match disagreed with the provisional Northern Cardinal source label. The new
single-group packet passed offline preflight without dispatch; earlier packets
remain frozen. The direct evaluator still has no paid run, and formal counts
remain unchanged.

## Owners and use

| File                                   | Responsibility                                                                                                                                                     |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| [contracts.ts](./contracts.ts)         | Versioned corpus, input, reference, curation, normalized prediction, and aggregate score-report types. These are internal evaluation records, not public API DTOs. |
| [validation.ts](./validation.ts)       | Runtime validation of corpus/input/prediction records, approval assertions, split/duplicate checks, media relationships, and content-free error codes.             |
| [evidence.ts](./evidence.ts)           | Allowlisted evidence projection, existing production capture-context formatting, and canonical SHA-256 fingerprints.                                               |
| [scoring.ts](./scoring.ts)             | Pure point estimates over normalized predictions, using current Gemini confidence thresholds. No provider invocation or real-output normalization.                 |
| [normalization.ts](./normalization.ts) | Validates input records and passes actual media-presence/tier facts into the shared production normalizer. No copied identification policy or I/O.                 |
| [fixtures.ts](./fixtures.ts)           | Twelve invented cases across all six input groups, with invented taxonomy IDs, asset descriptors, and normalized outcomes. No actual media files.                  |

Additional owners:

- `assets.ts` loads prepared evidence and reuses the production multimodal
  builder.
- `profiles.ts` resolves production profiles and fingerprints native parameters;
  the pure shared `functions/_shared/ai/geminiRequest.ts` avoids SDK
  initialization.
- `runContracts.ts` validates specifications, pricing, readiness, manifests,
  durable claims and bounded attempt records.
- `admission.ts` binds live corpus, taxonomy, project/key review and
  permissions.
- `files.ts` owns private files, exclusive OS locks and flushed writes.
- `runner.ts` owns preflight, single-call execution, immutable resume and
  budgets.
- `projection.ts` maps normalized decisions/usage without persisting model
  prose.
- `reports.ts` regenerates metrics, intervals, timing/cost and paired
  comparisons.
- `offline.ts` builds invented PNG/WAV fixtures for local mechanics tests.
- `exploratory.ts` owns the separate provisional corpus and shared run-corpus
  helpers; it does not relax the formal corpus contract.
- `exploratoryReport.ts` records operational outcomes and provisional reference
  agreement without admitting exploratory evidence into formal scores.
- `preflight.ts` prepares and fingerprints a supplied corpus without claims, a
  key or network access.
- `appObservation.ts` validates content-free native measurements, projects
  bounded numeric logs and reuses `profiles.ts` for optional conservative
  primary-attempt estimates. `appObserver.ts` owns collector readiness, bounded
  shutdown, event limits and content-free exit diagnostics.
  `../observe_identification_app.ts` passively records a bounded simulator
  window into a new private JSONL file. It submits no requests and has no
  network or provider-key access. Its artifacts are observations, not runner
  reports or formal quality scores. See the
  [app measurement guide](../../../../docs/development-guides/21-identification-app-measurement.md).
- `../evaluate_identification.ts` is the thin CLI; importing it performs no I/O.

`parseEvaluationCorpus(unknown)` validates and copies a complete corpus record.
`projectEvaluationEvidence(input)` accepts only the input record; passing an
entire case or adding reference fields fails. Its result preserves observation
text, ordered asset/clip descriptors, and the production context projection,
including `Context: no telemetry.`. It is a loader input, not an SDK request.
Only coarse two-letter region and month are currently allowed as context.

`fingerprintCorpus` freezes all corpus records, including references and
curation. `fingerprintEvidence` hashes only the projected evidence. Object key
order does not affect either hash; ordered arrays do. Declared asset hashes are
included. `prepareEvidence` verifies contained regular files, rejects symlinks
and hardlinks, bounds reads, checks actual bytes/hashes, and enforces the
current route media budgets. The exact native request is separately
fingerprinted. Image checks validate JPEG/PNG/WebP containers, dimensions and
metadata rules; they are **not full pixel decoding**. Curation must decode and
visually/privacy review final prepared files before hashing. Unknown metadata,
EXIF/XMP/comments and animated WebP are rejected. Prepared WAV must be PCM16,
one or two channels, 8–96 kHz, with consistent lengths/rates and no extra
metadata chunks; the actual production WAV parser, mono/resampling and trimming
then run. These restrictions are evaluation preparation rules, not changes to
production upload admission.

The shared processor includes partial-window silence measurement and bounded
windowed-sinc resampling to 16 kHz. Evaluator preparation inherits the same
output/work ceilings; a processing-budget failure cannot dispatch a provider
request. See the
[audio preprocessing comparison](../../../../docs/rfcs/identification-audio-preprocessing-fix-2026-09-23.md)
for the offline evidence. Historical run fingerprints remain frozen; a new
processor requires a new run rather than overwriting a prior baseline.

### Offline audio comparison preparation

`prepare_audio_preprocessing_comparison.ts` verifies the frozen six-audio
packet's manifest and source hashes, then prepares exactly two arms per case:
`audio-linear-full-windows-v1` (historical floor-window trimming and linear
resampling) and `audio-sinc-partial-tail-v1` (the current multimodal audio
helper). Both transforms now belong to the route-private
`functions/identify-multimodal/comparison/` owner, with canonical standalone
mono PCM16 44.1 kHz inputs bounded to 15 seconds before processing. The
historical transform is used only by offline preparation and the default-off,
server-owned comparison gate. Ordinary identification and evaluator runs retain
current DSP.

Both arms use `audio-minimal-v1` synthetic context and the current Gemini Pro
request builders. A non-audio request hash must match within each pair. The
preparation records source, processed-WAV, provider-request, policy and
confidence hashes, output format/length, model/prompt/schema/generation and the
complete local implementation fingerprint. It retains no raw media or request
bodies. Twelve prospective first-attempt assignments alternate the first arm by
case; there are no selective retries. A changed implementation requires a new
preparation and review, even if its arm name is unchanged.

From the repository root, use a new private destination (replace `SOURCE` and
`OUTPUT` with absolute paths):

```bash
deno run --frozen --no-prompt --deny-net --deny-env \
  --config services/supabase/functions/deno.json \
  --allow-read=.,SOURCE,OUTPUT --allow-run=git --allow-write=OUTPUT \
  services/supabase/scripts/prepare_audio_preprocessing_comparison.ts SOURCE OUTPUT
```

This emits `preparation.json` and a canonical-JSON digest in `freeze.json` using
exclusive creation and private permissions. It refuses changed source media or
an existing destination. It reads no provider key and enables no live dispatch.
The preparation version is intentionally incompatible with evaluator RunSpecs.
The app can run only the currently deployed arm. The
[server assignment slice](../../../../docs/rfcs/identification-audio-comparison-assignment-2026-09-23.md)
adds disabled request/media binding and a fresh durable proof header; Debug app
assignment/receipt collection and complete-outcome admission remain pending. V2
app `contextProfile` attests only fixed context on the initial active foreground
HTTP response. `requireFixedAudioMeasurement` enforces that profile and reviewed
execution identities; it is not a per-case or formal-qualification gate. See the
[preparation record](../../../../docs/rfcs/identification-audio-comparison-provenance-2026-09-23.md).

The runtime comparison table is generated only from the previously frozen
preparation. To verify or regenerate it offline:

```bash
deno run --frozen --no-prompt --deny-net --deny-env \
  --config services/supabase/functions/deno.json \
  --allow-read=docs,services/supabase/functions/identify-multimodal/comparison \
  services/supabase/scripts/generate_audio_comparison_plan.ts --check
```

For generation, use `--write` and grant write access only to
`services/supabase/functions/identify-multimodal/comparison/plan.ts`. Regenerate
the normal identification deployment identity after runtime edits. Neither
command enables configuration or authorizes live dispatch. Existing frozen
preparations remain immutable; record the new runtime fingerprint separately.

`scoreEvaluation(corpus, predictions, { profile, split, inputGroup?, caseIds? })`
returns the typed `identification_scores_v1` report. Supply predictions for one
profile and split. Unknown cases, foreign splits, duplicate attempts, malformed
scores, and extra raw-output fields fail. Missing cases become `unattempted`;
repeated attempts cannot inflate sample size. The optional input-group filter
produces group-specific scores from that same split. The aggregate is unweighted
across cases and is not an estimate of production traffic.

The scorer expects normalized identities mapped to the frozen taxonomy version.
A named prediction with `taxon: null` means unresolved mapping and still counts
as an offered, unverified answer. `normalizeEvaluationDraft` parses an unknown
provider draft through the same production domain rules, before dictionary
hydration. It returns domain data, audio disposition, client candidates/life
stage, and in-memory diagnostics; it is **not** a durable prediction record.
`projectOutcome` discards prose/diagnostics and retains bounded IDs, decisions,
confidence, candidate presence, numeric usage and durations. A frozen taxonomy
map accepts exact names/synonyms ignoring case; there are no fuzzy or live
lookups. Genus/family answers earn credit only when expressly allowed at that
rank; a guessed species cannot earn credit from an allowed ancestor.

The normalization bridge requires the loader to verify that every declared asset
reached the actual request. It may not silently drop failed images or audio.
Device region and month do not establish the GPS or semantic location used by
the current invasive-status rule. No coordinates or identity enter the
normalizer. Server candidate presence is before dictionary hydration and is not
the final iOS candidate-review visibility decision.

Version 1 evaluates ranks from kingdom through species. Finer reference or
prediction ranks require an explicit mapping to an approved species identity
before admission; this contract does not silently infer taxonomy ancestry or
exclude finer-rank cases from the species denominator.

False biological assertions are measured against known non-biological subjects
and synthetic human-only cases. Indeterminate subjects have a separate
unsupported-biological-assertion rate: insufficient reference evidence must not
be presented as proof that a biological classification is factually false. Named
guesses on these cases still count in offered precision, specificity, and
confident-error metrics.

Every report has `verdict: measurement_only`, an explicit synthetic/reference
evidence kind, and complete/incomplete status. A complete report can contain
only failures; it is not a passing result. The original pure point-score object
retains `performance: not_measured` and `intervals: not_computed`. The
run-report wrapper separately supplies timings, cost estimates and confidence
intervals from durable records. Compatibility and paired comparisons are
implemented; qualification decisions and numerical acceptance criteria remain
Slice 5.

## Curation rubric and intake

Use the
[pilot collection packet](../../../../docs/development-guides/20-identification-evaluation-pilot.md)
for the proposed 60-slot coverage plan and blank case/reviewer forms. Completed
forms stay outside Git; pending intake records are not approved corpus JSON.

The
[solo phone/computer workflow](../../../../docs/development-guides/20-identification-evaluation-pilot.md#start-here-when-you-are-working-alone)
supports collecting examples and checking the app without independent reviewers.
Its records can now enter the separate exploratory mode described below, with
provisional or absent references and actual eligibility review. They cannot be
passed as independently reviewed or synthetic evidence. The formal corpus and
stage requirements below still apply to independently reviewed evaluation.

**Real-corpus progress: 0 of 60 development groups; 0 of 240 held-out groups.**
The fixtures below are not reviewed biological examples and do not count toward
these targets. Product and a biological reference reviewer own collection;
Backend owns format and preparation checks.

1. Create the working corpus outside Git in controlled storage. Assign opaque
   case/group IDs (`c0001`, `g0001`) and asset IDs (`a0001`). Put all views,
   frames, audio, and derived descriptions of one observation in one group.
   Version 1 admits one primary case per group. Preserve source provenance in a
   controlled curation record, referenced by an opaque token.
2. Establish that source rights cover sending the material to Gemini for this
   evaluation purpose. Exclude production observation exports, identifiable
   human imagery/speech, personal information, precise coordinates, credentials,
   and revealing metadata. Evaluation rights do not grant model-training rights.
3. Record observable evidence without copying taxonomy, answer-bearing
   filenames, or reference notes into prompts. Prepared asset paths have the
   exact form `assets/a0001.webp`, `.jpg`, `.png`, or `.wav`. WebP matches the
   current primary route's default. All visuals within a case use one MIME type,
   preserving that route's single image-MIME parameter. Preserve supplied frame
   indexes and clip/audio relationships. A partial frame set is allowed when its
   declared frame count and retained indexes remain honest; included audio
   cannot vanish.
4. Obtain two independent reviews, identified by different opaque role IDs
   (`r0001`, `r0002`). Verify the reference against independent evidence and
   record a reference-record token. Use `agreed` or document adjudication as
   `resolved`. Model output, a name lookup, or unverified user confirmation
   cannot establish truth. Do not lower the review requirement to fill a quota.
5. Label subject class and resolution separately. A biological subject can be
   unresolved. For named results, record the most specific supported rank and
   every acceptable canonical taxon/rank pair. For unresolved results, use a
   null supported rank and an empty acceptable-taxa list. Known source identity
   must not force species-level certainty from insufficient supplied evidence.
6. Review exact and near duplicates before splitting. The validator rejects
   repeated case/group IDs, cross-split groups, reused media hashes across
   groups, and repeated nonempty normalized observation text across any input
   groups. Absent text is not a duplicate; identical generic context on
   independent observations is conservatively rejected and should be omitted
   when it adds no evidence. The validator cannot detect all near duplicates or
   verify that different reviewer IDs represent different people.
7. Assemble ten development cases per input group, covering clear positives,
   lookalikes, degraded evidence, appropriate unknowns, and relevant negatives.
   Cover disagreement/incidental organisms in combined-media groups. Freeze the
   detailed coverage matrix after the pilot, then curate forty held-out groups
   per input group without tuning against their answers.
8. Record corpus approval, accountable role, retention date,
   taxonomy/preparation versions, split seed and membership. Retain the exact
   corpus digest. Any label, evidence, split, or curation change produces a new
   digest and report version; retain prior reports when corrections require
   consistent rescoring.

A reference corpus requires `approval` and `curation.kind: reviewed` on every
case, approved Gemini-evaluation rights, exclusion/review assertions, distinct
reviewer references, and resolved labels. Synthetic corpora require null
approval and synthetic curation. These fields are assertions for a controlled
intake, not cryptographic proof of permission, reviewer identity, or biological
correctness. Passing validation does not authorize a live run. For real
execution, the implemented runner also requires asset preflight, reviewed
processor/account readiness, an approved digest and budget, durable dispatch,
and explicit live selection. The user must authorize the concrete paid run.

## Automated exploratory runs

This mode supports a solo owner before a reviewed biological corpus is
available. It uses `identification_exploratory_corpus_v1`, not the formal corpus
version. `kind` is `exploratory`; `evidenceOrigin` is `real` or `synthetic`.
There are one to twelve unique development groups. Each case contains the
existing strict `input`, a `provisionalReference` (the existing reference shape
or null), and separate `curation`. Reference values and provenance never enter a
request.

For real evidence, `eligibility` identifies a record token, opaque reviewer ID,
`reviewerKind: owner | automated`, and retention date. Each case requires
`curation.kind: eligibility_reviewed`, source and optional reference-record
references, `permission: gemini_evaluation`, and completed rights, personal-data
exclusion and near-duplicate assertions. A reference record is present exactly
when the provisional reference is non-null. Review the actual decoded media and
source permission before asserting these checks. One automated eligibility
review does not create independently verified biological truth. Synthetic
records instead require null eligibility and synthetic curation.

A real run uses `identification_exploratory_run_spec_v1`, `stage: exploratory`,
all selected corpus groups, one repeat, and both existing Gemini profiles. The
maximum is twelve groups and twenty-four calls. It retains every live gate
below: dedicated reviewed project/key, processor readiness, fresh reviewed
pricing, retention, exact immutable inputs/source, a positive authorized USD
budget, durable claims and no automatic retry of unknown executions. Synthetic
evidence cannot run live, and real evidence cannot be executed by the offline
fixture transport. The formal corpus/scorer and its two-reviewer requirement are
unchanged.

Use the same permissions as the offline example below:

```bash
# Create and execute an invented exploratory experiment in a fresh directory.
deno run --frozen --no-prompt --deny-net --deny-env \
  --allow-read="$PWD,$evaluation_parent" --allow-write="$evaluation_parent" \
  --allow-run=git --config services/supabase/functions/deno.json \
  services/supabase/scripts/evaluate_identification.ts demo-exploratory "$evaluation_parent/exploratory"

# Check a supplied corpus, taxonomy and prepared assets without inference.
deno run --frozen --no-prompt --deny-net --deny-env \
  --allow-read="$PWD,$evaluation_parent" --allow-write="$evaluation_parent" \
  --allow-run=git --config services/supabase/functions/deno.json \
  services/supabase/scripts/evaluate_identification.ts preflight "$evaluation_parent/exploratory"
```

First initialize the private `evaluation_parent` with the `mktemp` commands
below. Preflight writes `preflight.json`: hashes, covered groups, profile
assignments and planned call count. A current `pricing.json` additionally
supplies conservative reservations; absent pricing leaves cost unknown. It never
creates dispatch claims or authorizes a paid run. Configure the real corpus's
`spec.json` and `readiness.json` under the live requirements before selecting
`--live`.

`report DIRECTORY RUN_ID` selects `identification_exploratory_report_v1` for
these records. All outcomes contribute to operational counts; null references
are excluded from every provisional quality denominator. A confident name on an
unverified example is not automatically correct or wrong. Every report states
zero independently reviewed labels, `measurement_only`, untested input groups,
and provisional evidence status. Unknown/unattempted calls leave the report
incomplete. Synthetic runs additionally state `synthetic_mechanics_only` and
supply no measured Gemini quality, latency or spend. Formal reporting and paired
`compare` reject exploratory corpora. Keep source/media and detailed curation
outside Git; retain sanitized run summaries with their exact hashes.

## Hand-worked fixture expectations

Each input group appears twice. All twelve cases are development fixtures; there
is deliberately no synthetic held-out accuracy claim.

| Cases           | Reference and normalized outcome                                                               |
| --------------- | ---------------------------------------------------------------------------------------------- |
| 1, 4            | Correct species, scores 0.99 and 0.90.                                                         |
| 2               | Genus-only evidence receives an unsupported species answer at 0.99.                            |
| 3, 5, 7, 11, 12 | Refusal, invalid output, operational failure, unknown execution, and unattempted respectively. |
| 6               | Non-biological evidence receives a biological species answer at 0.99.                          |
| 8               | Expected-unresolved biology receives a named species at 0.97.                                  |
| 9, 10           | Appropriate unresolved biological and non-biological outcomes.                                 |

For Flash, `N = 12`, biological cases `B = 10`, species-answerable cases
`S = 7`. There are five named answers and two correct identities:

| Metric                                                | Expected value                                     |
| ----------------------------------------------------- | -------------------------------------------------- |
| Exact species correctness                             | 2 / 7                                              |
| Offered-answer precision                              | 2 / 5                                              |
| Biological answer coverage / correct-answer yield     | 4 / 10 and 2 / 10                                  |
| Appropriate unresolved outcomes                       | 2 / 4; provider failure is not uncertainty credit. |
| False biological assertions on negatives              | 1 / 2                                              |
| Strong errors, all cases / Strong named cases         | 3 / 12 and 3 / 4                                   |
| Diagnostic errors, all cases / diagnostic named cases | 2 / 12 and 2 / 3                                   |
| Strong reliability / mean reported score              | 1 / 4 and 0.985                                    |

Pro's current Strong threshold also includes case 4: Strong errors become 3 / 5
and Strong correctness 2 / 5. This tests policy interpretation, not a measured
difference between Gemini models. Diagnostic is a reported subset of Strong, not
a fourth disjoint bin. Empty denominators return `not_estimable` with a null
value. The unattempted case makes both reports incomplete.

## Local CLI and artifacts

Use Deno `2.9.4` and the existing frozen dependency graph. A private directory
outside Git holds `corpus.json`, `taxonomy.json`, `spec.json`, and `assets/`.
Offline runs also need `fixtures.json` bound to the synthetic corpus digest.
These files are parsed strictly; unknown fields fail. Root and run directories
must be private (mode 0700) on a local filesystem supporting exclusive file
locks and file/directory fsync. A failed flush blocks dispatch. Do not use a
shared or cloud-synchronized run directory.

Create an invented demo from the repository root:

```bash
evaluation_parent="$(mktemp -d "${TMPDIR:-/tmp}/merian-evaluation.XXXXXX")"
evaluation_parent="$(cd -- "$evaluation_parent" && pwd -P)"
deno run --frozen --no-prompt --deny-net --deny-env \
  --allow-read="$PWD,$evaluation_parent" --allow-write="$evaluation_parent" \
  --allow-run=git --config services/supabase/functions/deno.json \
  services/supabase/scripts/evaluate_identification.ts demo "$evaluation_parent/demo"
```

The default command is `offline DIRECTORY` (or simply `DIRECTORY`). `demo`
requires a fresh directory and produces deliberately wrong/refused/failed and
uncertain synthetic cases as well as valid results. Its incomplete verdict is
intentional. `report DIRECTORY RUN_ID` rebuilds artifacts from saved records,
corpus and frozen taxonomy, without media loading, a key or inference. Use the
same denied network/environment flags; report generation needs no Git process.

`runs/RUN_ID/` contains an immutable `manifest.json`, permanent `.lock` inode,
`claims/KEY.json`, terminal `results/KEY.json`, `summary.json`, and `report.md`.
The latter two are deterministic for the same saved records. Never delete claims
to retry a case. A claimed attempt without a result becomes `unknown_execution`
and stops the run; even a crash between claim and invocation spends that
attempt. A changed spec, source digest, pricing, corpus or request cannot resume
the same run. A new run and explicit spend decision are required to retry
uncertainty.

The manifest records both full-schedule reservations and the approved
call/budget limits through its assignments/spec. Source identity covers commit,
dirty state, the functions/scripts TypeScript/config/lock/shell graph and exact
SDK version. Live rates and token ceilings are supplied through reviewed files,
never inferred from code defaults. Each call reserves the full reviewed model
input/output ceiling, including thinking, at worst-case modality rates. This
deliberately conservative bound can stop before a small budget is exhausted.
Usage estimates also use worst-case rates without a cache discount;
missing/contradictory usage stops further calls. Known components are estimates,
not invoice lower bounds.

`compare DIRECTORY LEFT_RUN RIGHT_RUN LEFT_PROFILE RIGHT_PROFILE` is an explicit
assignment comparison. Both runs must match corpus, selected groups, split,
stage, seed/order, taxonomy, scorer, preparation, measurement boundary and
source. Same-profile configuration/request drift and unexplained returned models
fail. Different named profiles are an explicit opt-in and their complete
differences are listed. Incomplete/unknown runs cannot compare. Missing usage
may leave quality measurable but blocks cost comparability. Every verdict
remains `measurement_only`; numerical qualification criteria belong to Slice 5.

Formal reports include fixed-population denominators, every failure/unattempted
case, confidence reliability, subject/resolution matrices, and scoring flags.
Proportions use Wilson 95% intervals. Paired differences use 3,000 seeded
observation-group bootstrap draws (one case per group), nearest-rank percentile
bounds and seed `20260922`. Any zero-denominator draw makes that interval
`not_estimable`. Repeats stay separate. Timings exclude upload, hydration and
app rendering; the adapter does not distinguish timeout causes from other
unknown executions. Offline durations and costs supply no live performance
evidence.

## Future explicitly approved live use

Only `--live DIRECTORY` can select paid execution. Before using it, approve an
eligible real reference or exploratory corpus, its exact digest and both
profiles, a dedicated evaluation project/key, call cap and USD budget in
`spec.json`. `readiness.json` binds that corpus to opaque
project/credential/review references, a SHA-256 credential fingerprint,
review/expiry dates, paid service eligibility and reviewed terms, purpose, data
use, regional/subprocessor and retention/abuse-log treatment. This attestation
is not a programmatic proof of the vendor's billing settings. `pricing.json`
must be at most seven days old and cover both exact models, synchronous USD
rates across modalities/context tiers, thinking and reviewed model token
ceilings. The spec binds both files by canonical digest. Their parsers in
`runContracts.ts` are the authoritative field definitions.

Read the dedicated key only from `GEMINI_PAID_API_KEY`; never put it in a
command argument or file. Grant only `generativelanguage.googleapis.com:443` for
network, the controlled directory/repository for reads, controlled directory for
writes, and Git for source identity. Do not grant broad environment or network
access. Explicitly deny environment access to `SUPABASE_URL`,
`SUPABASE_SERVICE_ROLE_KEY`, `R2_ACCESS_KEY_ID` and
`GOOGLE_APPLICATION_CREDENTIALS`. Besides the key, the pinned Node SDK needs the
exact `SDK_ENVIRONMENT` allowlist in `admission.ts` to be readable but
**unset**; it covers backend/base-URL/key overrides, debug logging and WebSocket
optional module switches. The runner checks these before SDK import. Preserve
`--no-prompt` and the frozen config. No live command is implied by local
testing.

Working identification in the simulator establishes access through the ordinary
authenticated Supabase app path. Its provider key stays on the backend; the
app's scan allowance does not give this local runner a Gemini credential or a
USD run budget. Connect the reviewed evaluation project/key to the local runner
and retain any already granted user spend authorization. Do not extract
simulator session state or describe the production key as an evaluation
credential.

Live preparation and each dispatch recheck the actual key, corpus and readiness
validity. All assets preflight before the first call, and request hashes are
rechecked immediately before dispatch. The CLI has no alternative adapter/host
flag and live mode rejects test dependency injection. It performs sequential,
standard synchronous calls with production settings and no retries. It stops on
every operational failure because the adapter combines 400 and 429 outcomes;
this stricter rule ensures rate-limit/authentication failures cannot be retried.
Unknown execution, model drift, missing usage, or the call/spend guard also stop
the run. Budget changes require a new spec/run rather than changing a resume.

## Verification and next slice

From the repository root, the focused tests need no network, environment,
filesystem, or subprocess permission:

```bash
deno test --frozen --config services/supabase/functions/deno.json \
  --deny-net --deny-env \
  services/supabase/scripts/identification_evaluation_contract_test.ts \
  services/supabase/scripts/identification_evaluation_scoring_test.ts \
  services/supabase/scripts/identification_evaluation_normalization_test.ts \
  services/supabase/scripts/identification_evaluation_run_contract_test.ts \
  services/supabase/functions/_shared/identify/normalizeIdentification_test.ts
```

Tests live at the scripts root so the existing `make test-supabase-tooling`
discovery includes them and type-checks their complete imported module graph.
Keep future tests discoverable; nested `*_test.ts` files alone are not selected
by that shell gate. Recursive repository formatting and lint include this
folder.

The tooling gate additionally runs `identification_evaluation_runner_test.ts` in
an isolated private temporary directory with network/environment denied. It
grants that directory read/write and repository reads, with `git` for the actual
CLI's source fingerprint plus `deno` and `ln` subprocesses to test cross-process
locks and rejected symlinks. Crash boundaries, immutable resume, complete media,
caps, sanitized artifacts, report regeneration and comparison are exercised
there. The main tooling suite also explicitly denies network and environment
access.

Slice 4 is next: curate and approve the 60-group development corpus, exact
processor/pricing records and bounded run, then explicitly authorize that paid
pilot. Held-out evaluation and decision qualification remain later work. No
synthetic result establishes biological accuracy or a provider cost/latency win.
