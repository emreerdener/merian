# Identification bottleneck audit — Slice 1

Date: 27 September 2026

Status: Offline audit complete; retain the current baseline. No new provider
requests, runtime changes or deployments.

## Scope correction — 27 September 2026

The measurements and shared-pipeline findings below remain valid. The original
recommendation to close optimization and proceed directly to OpenAI audio was
too broad: this audit did not evaluate an OpenAI prompt/context candidate
against its baseline. Gemini app timings and Gemini cache counts cannot rule out
an OpenAI-specific improvement.

The
[current optimization plan](./identification-optimization-preserving-results-2026-09-27.md#next-openai-prompt-and-context-review)
keeps instruction clarity, context organization and OpenAI cache reuse open for
an offline review before audio. It supersedes the closure and next-step
recommendations below, while preserving the historical measurements. Explanation
format and detail remain unchanged; the concise experiment stays closed.

## Decision

The model request is the largest measured wait. In the six retained photo app
runs, its median share of each pipeline was **82.2%**. Median provider time was
**14.023 seconds**, versus **17.190 seconds** for the app pipeline. This
identifies where a substantial speed gain would need to come from; it does not
identify a safe new model setting.

Keep the current shared pipeline, prompts, media settings and explanation
format. Suspected duplicate preparation and serial lookups already have reuse or
concurrency. Required admission and durable saving cannot be removed to improve
the number. No new optimization meets the
[current plan's](./identification-optimization-preserving-results-2026-09-27.md)
evidence requirement, so skip a speculative shared-code change in Slice 2.

The strongest existing performance evidence remains the completed OpenAI photo
comparison: **7.10 versus 15.81 seconds** at the provider boundary, a
descriptive **55.1% reduction** on six matched photos. Keep that existing
profile as a qualification candidate under the
[photo integration plan](./identification-openai-photo-integration-2026-09-27.md).
It is not a newly optimized profile or a measured app speedup. OpenAI production
dispatch remains disabled; Gemini remains assigned to production requests.

Retaining the baseline is the result of this audit. Do not repeat the photo
benchmarks or reopen the concise-explanation experiment. The next independent
work is planning OpenAI audio evaluation. Later optimization can use detailed
timings from an otherwise-planned validation, without scheduling another photo
run just to fill this audit's gaps.

## Evidence and source boundary

The primary input is the
[six-photo app benchmark](./identification-source-photo-app-benchmark-2026-09-22.md)
and its
[frozen measurements](./identification-evaluation-evidence/2026-09-22-source-photo-pilot/app-results.json):

- Six first submissions with complete observer windows, fresh HTTP 200 results
  and valid provider/Edge spans; no manual retries.
- Debug app 1.0.3 (275), iPhone 18 Pro simulator, iOS 27.0.
- Dirty app revision `6c7ba02ede0fa0884189f55b726bb4babf5966a5`, fingerprint
  `3ad8e9f3c0e73234a78e743652cd9ac88fb93414f6e348c85148abddf213d812`.
- Backend bundle
  `05aedfe76acc8d8bcee71f5ebf0f9de22590e79715e6cc80f1f4ab6032576558`; requested
  and returned model `gemini-2.5-pro`.
- Evidence-file SHA-256
  `c0b2e2c34e58dfd431a7b646fd99c23136b17ada2dfe92a14f618d6d762a7070`.

Current source was traced at `b943b24ee5506e911eb2508e65fc55c70e2b617a`, after
[PR 90](https://github.com/emreerdener/merian/pull/90) merged with passing
checks. Later permission, provenance, accounting and request-path changes
separate this source from the measured September 22 product. The figures below
are historical observations, not current deployment or release measurements.

The separate
[matched comparison](./identification-gemini-openai-matched-results-2026-09-27.md)
used six identical prepared photos and two descriptions, once per provider, at
source `1b3661706afc057825d7b4657f1b9935de857d44`. It measures provider
execution and normalization, excluding app preparation, admission, moderation in
the dormant production binding, persistence and rendering. Its OpenAI median
cannot be substituted into the older app run to predict end-to-end performance:
the app crops and context are not an identical prepared-request comparison.

## Measured phases

Differences and ratios are calculated **within each case before taking the
median**. These rows overlap; independently calculated medians must not be
added.

| Interval or measure            |   Median |  Observed range | Meaning                                                         |
| ------------------------------ | -------: | --------------: | --------------------------------------------------------------- |
| Total app pipeline             | 17.190 s | 13.882–20.563 s | Pipeline execution, excluding earlier capture/import            |
| Provider await                 | 14.023 s | 11.062–16.921 s | SDK request including transport, not isolated model computation |
| Provider / pipeline            |    82.2% |      79.7–85.3% | Largest observed component in every case                        |
| Other Edge work                |  1.713 s |   1.277–2.599 s | Edge total minus provider; detailed causes not retained         |
| HTTP interval minus Edge total |  0.549 s |   0.476–0.718 s | Transfer and boundary overhead, not pure network latency        |
| Pipeline minus HTTP interval   |  0.535 s |   0.480–0.833 s | Remaining pipeline interval, not isolated media preparation     |
| Postflight                     |  0.295 s |   0.246–0.378 s | Result handling and completion work                             |
| Response to first result state |  0.017 s |   0.012–0.022 s | State publication, not a rendered frame                         |
| Tap to first rendered frame    | 17.241 s | 13.944–20.700 s | Tap-based clock, distinct from pipeline start/end               |

All six visual preflight values are rounded to `0.000 s`. The current marker is
emitted after Base64 encoding and **before** request serialization, recipient
preflight and authenticated request construction, despite its legacy
`encode+auth` label. Capture/import preparation precedes the pipeline. Zero here
does not prove that all preparation is free. The
[measurement guide](../development-guides/21-identification-app-measurement.md)
now describes that boundary explicitly.

A secondary
[sampled-video record](./identification-evaluation-evidence/2026-09-22-media-replay/app-results.json)
contains one `frames_audio` case: 23.565-second pipeline, 16.751-second provider
await and 4.271 seconds of other Edge work. It uses a different dirty app
fingerprint and the same historical backend bundle. It does not isolate media
resolution or establish a video latency distribution. Five sampled images and
companion audio remain complete inference evidence; the movie is playback media.

In the matched provider comparison, normalization medians across all eight cases
were **2.45 ms for Gemini** and **1.06 ms for OpenAI**. Rewriting that small
stage is not supported as a response to a wait measured in seconds. These
development samples do not establish general accuracy, explanation quality,
repeatability, tail percentiles or full billing. No new marketing or cost claim
follows.

## Current path and candidate decisions

| Stage                   | Current owner and finding                                                                                                                                                                                                                                                                                                                                                                      | Decision                                                                    |
| ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| Capture and enqueue     | [Visual submission](../../apps/ios/Merian/Features/Capture/Submission/ViewModels/CaptureWorkspaceViewModel+VisualSubmission.swift) durably enqueues before inference; camera-only context grace is already bounded at 150 ms.                                                                                                                                                                  | Preserve recovery and context; historical timings do not isolate this wait. |
| Media preparation       | [Request service](../../apps/ios/Merian/Core/AI/Inference/Request/InferenceLiveRequestService.swift) uses [processing actor](../../apps/ios/Merian/Core/AI/InferenceProcessingActor.swift) concurrency over already compressed images.                                                                                                                                                         | No repeated JPEG preparation or serial image encoding found on this path.   |
| Request and permission  | [Network builder](../../apps/ios/Merian/Core/Network/Endpoints/MerianNetworkClient+Inference.swift) prepares the complete observation before recipient/auth preflight.                                                                                                                                                                                                                         | Preserve dependency ordering and fresh account/permission state.            |
| Backend dispatch        | [Primary handler](../../services/supabase/functions/identify-multimodal/index.ts) orders replay recovery, ownership, reservation, ingestion claim and committed accounting before dispatch.                                                                                                                                                                                                    | Preserve one admitted invocation and retry/replay behavior.                 |
| Provider construction   | [Gemini](../../services/supabase/functions/_shared/ai/geminiRequest.ts) and [OpenAI](../../services/supabase/functions/_shared/ai/openaiRequest.ts) separate stable instructions from observations; shared schema construction already reuses cached schema data.                                                                                                                              | No evidence supports another cache or changed output instructions.          |
| Backend results         | Primary handler combines dictionary hydration, parallelizes fallback reads and candidate enrichment, and backgrounds optional writes. Success awaits moderation, media promotion and durable finalization.                                                                                                                                                                                     | Preserve the durable success boundary.                                      |
| App results and display | [Result service](../../apps/ios/Merian/Core/AI/Inference/Result/InferenceLiveResultService.swift) persists media/data before publication; [pipeline](../../apps/ios/Merian/Core/AI/Inference/Pipeline/InferenceLivePipelineCoordinator.swift) owns completion; [render probe](../../apps/ios/Merian/Features/Insights/Shell/Components/InsightFirstRenderProbe.swift) records first draw once. | No measured app-side wait justifies changing these boundaries.              |

Current detailed server timings overlap: provider and quota commit are inside
legacy `gemini`; dictionary, enrichment and finalization are inside
`post_gemini`; all are within Edge total. The compact native record retains only
`provider` and `edge_total`. It cannot reconstruct the missing detailed phases.

Ranked priorities are therefore: **provider execution**, then **remaining
backend work**, then **app result processing/normalization**. The existing
OpenAI photo profile is the strongest measured candidate. No new reasoning,
media or prompt setting has been compared while preserving quality and
explanation detail, so none is selected here.

The six photos report one positive cached-token count (`c0001`: 1,343) and five
nulls. This proves native cache reuse occurred, not a one-in-six cache hit rate:
null is unknown, not a miss. Each reports 2,710 prompt tokens; thinking tokens
range from 994 to 1,442. The current Gemini Pro budget is a 5,000-token limit,
not proof that every call spends that many. Neither null cache values nor that
ceiling justify predicting savings from changing them.

One concrete but **unselected** source candidate remains: image and audio R2
resolution are awaited serially in the handler. Overlap could help mixed media,
but retained timings do not isolate either resolver. Image resolution already
has internal concurrency; both resolvers retain media bytes, so more overlap
also needs a bounded-memory review. It would not improve the six photo-only
cases.

## Smallest evidence needed before reopening a code change

During the next otherwise-planned ordinary validation, retain the existing
content-free detailed server timings and matching app/backend source identities.
The backend already emits these numeric fields in `multimodal/latency` and
successful response timing headers. Retain only named numeric fields and source
identity, never raw responses or arbitrary logs. One observation establishes
coverage, not a stable speed gain.

Only if mixed-media resolution becomes the selected target would separate
image/audio resolution durations be needed. Its deterministic acceptance target
would be: after both ownership checks, audio resolution starts before image
resolution finishes, with unchanged ordered evidence, one committed provider
invocation and one durable finalization. Preserve error/ownership behavior and
prove the combined memory bound. A latency claim still requires measurements of
that route; there is no justified percentage target from current evidence.

Do not introduce a parameter sweep or new paid benchmark just to produce an
optimization in this slice. Retain the baseline and plan OpenAI audio next.
Photo activation and iOS distribution retain their existing separate gates.

## Reproduce the main finding

Run from the repository root; this reads the existing sanitized artifact only:

```bash
python3 - <<'PY'
import json
from pathlib import Path
from statistics import median

path = Path('docs/rfcs/identification-evaluation-evidence/'
            '2026-09-22-source-photo-pilot/app-results.json')
rows = json.loads(path.read_text())['cases']
pipeline = [r['appIntervalsSeconds']['total_pipeline_seconds'] for r in rows]
provider = [r['nativeMeasurement']['serverTimingMs']['provider'] / 1000
            for r in rows]
other_edge = [r['nativeMeasurement']['otherEdgeMs'] / 1000 for r in rows]
share = [p / t for p, t in zip(provider, pipeline)]
print('cases:', len(rows))
print('median pipeline/provider/other Edge seconds:',
      *(round(median(v), 3) for v in (pipeline, provider, other_edge)))
print('median within-case provider share percent:', round(100 * median(share), 1))
PY
```

Expected output: six cases; medians `17.19`, `14.023`, `1.713` seconds; provider
share `82.2%`. Historical artifacts remain unchanged.
