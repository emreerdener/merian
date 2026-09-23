# Recording identification measurements from the app

The app can record which Gemini model handled a fresh identification, the app
source/build identity, the identification Function's source fingerprint, token
counts and separate provider/Edge timings. This is passive diagnostic
instrumentation. It neither submits identifications nor changes model selection.

The
[first two-photo benchmark](../rfcs/identification-production-app-benchmark-2026-09-22.md)
predates this instrumentation. Its missing metadata remains unknown. A new
production measurement requires the updated backend and app to be deployed or
installed through their ordinary, separately authorized procedures.

## What is recorded

`identify-multimodal` adds `X-Merian-Identification` only after a fresh primary
attempt reaches the existing durable success boundary. The
[API contract](../backend-and-data/05-api-contracts.md#latency-and-authentication-contract)
owns its bounded format. No JSON Identify body or generated DTO changes.

`IdentificationBenchmarkRecord` in Core Network parses that header and existing
`Server-Timing`, then emits one content-free JSON Debug log per observed
identification HTTP response through `AuthenticatedRequestExecutor`. It records:

- Requested model and provider-returned model separately; missing values remain
  null. The requested model comes from the admitted backend attempt.
- App version, build, source revision, fingerprint and clean/dirty state from
  the built app, never inferred from the current checkout.
- `backendBundleSha256`, the generated fingerprint of this Function's local
  runtime dependency graph, root/route Deno configuration and dependency lock.
  It is not a Git SHA, database revision, environment/secret fingerprint or
  independent proof of deployment.
- Prompt, candidate, thinking, total, cached and tool token counts when
  reported. Missing or invalid counts are null.
- `provider` time for the awaited SDK call including transport, `edge_total` for
  the successful Edge request interval including authentication, and
  `otherEdgeMs = edge_total - provider` when both spans are valid and ordered.
  The legacy `gemini` span includes quota commit. Detailed spans overlap and
  must not be summed as a partition.

The native record retains only `provider` and `edge_total` from the timing
header to stay within a compact log budget; the other spans remain available in
the HTTP response. A maximum-size fixture checks that the full record plus log
marker fits within 1,024 UTF-8 bytes.

New app records also include `timingStatus`: `valid`, `absent`, `oversized`,
`too_many_metrics`, `invalid_syntax`, `unknown_metric`, `duplicate_metric` or
`invalid_duration`. Only these fixed reasons are retained, never header text or
unknown metric names. The parser bounds the entire header to 2,048 UTF-8 bytes
and 32 entries, recognizes quoted commas and escaped quotes, and validates only
the retained `provider` and `edge_total` metrics. Unrelated names, parameters
and descriptions are discarded. Duplicate or malformed retained metrics reject
the projection; rejected headers still yield empty spans and null other Edge
time. `valid` means the projection parsed; it does not guarantee that both
required spans were present. Older app builds rejected any unrecognized metric
and enforced thirteen comma-separated entries; their `unknown_metric` and
`too_many_metrics` records remain readable. The recorder also accepts older
records without the optional status field and leaves their rejection reason
unknown.

Stored/reconstructed responses report `delivery: replay`, without claiming new
provider usage. Failures, old/malformed diagnostic headers and unknown versions
report unavailable metadata. No missing value becomes a zero. The source
projection excludes request/scan/user IDs, species, media, locations, region,
credentials, provider prose and arbitrary header fields. Background transfers
outside this executor are not covered by this native log path. HTTP failures are
recorded before retry/error handling with null provider diagnostics; a transport
failure or cancellation with no observed HTTP response has no response record.
The observer is not a complete request or billing ledger.

### Pipeline markers depend on the input path

The photo path can emit seven projected events. Description-only submissions can
now emit six: HTTP timing, native diagnostics, response-to-first-result state,
postflight, total pipeline time and tap-to-first-rendered-frame time. Immediate
Describe passes its original submission tap clock through `submitDescribeSolo`
and nonvisual submission; a staged description uses the later Identify tap. The
first-render probe remains correlated to the active scan and records at most
once.

`preflight_seconds` logs visual encode/auth work in
`InferenceLiveRequestService.dispatchVisual`; the nonvisual path has no
equivalent marker. The earlier description pilot used a build that omitted the
immediate Describe clock and emitted five events. Its absent preflight and
first-render values remain null. No missing value can be reconstructed from
other spans or treated as zero. A complete observer window does not mean every
input path has the same instrumentation coverage.

## Controlled audio and video replay in the simulator

Debug simulator builds expose **Debug replay** on the empty **Scan** page. This
interactive tool stages a local sample; **Identify** still owns submission,
consent, admission, durable queueing and the normal Gemini selection. Replay
does not submit automatically, even when scan confirmation is off. It has no
launch argument, network client, provider override, XCTest seed or Release/
physical-device implementation. Automated tests use synthetic local media and
injected preparation results without making identification requests.

Use only reviewed, rights-cleared samples without personal information, speech,
answer-bearing text or sensitive metadata. Keep source provenance, hashes and
case records outside Git with the evaluation packet's access and retention
controls. Install the current Debug app through the normal local build flow,
then copy the reviewed files into its private simulator inbox:

```bash
replay_device="SIMULATOR-UUID"
replay_container="$(xcrun simctl get_app_container "$replay_device" app.merian.Merian data)"
replay_inbox="$replay_container/Documents/IdentificationReplay"
mkdir -p "$replay_inbox"
cp "/absolute/path/to/reviewed-audio.wav" "$replay_inbox/audio.wav"
cp "/absolute/path/to/reviewed-video.mp4" "$replay_inbox/video.mp4"
```

Copy only the modality being exercised if the other is unavailable. These are
regular files, not symlinks; the inbox itself must also be a regular directory.
The app preserves each inbox source and prepares a uniquely owned copy. Replace
the source only between completed attempts, and remove the inbox files when
their retention period ends. Removing a staged item cleans its prepared files,
not the inbox source.

- Audio must be nonempty, no longer than 15 seconds and at most 2,700,000 bytes.
  `InferenceAudioPreparer` produces the same canonical mono 44.1 kHz PCM16 WAV
  accepted by the ordinary inference queue.
- Video requires ordinary Pro video access, a video track, a positive duration
  no longer than 5 seconds and at most 12 MiB. The existing video preparer
  samples five frames, prepares playback and extracts audio. Replay rejects a
  partial frame set or missing extraction when the source has an audio track.
  Silent source video is allowed. For a five-second clip the existing sample
  positions are 0.5, 1.5, 2.5, 3.5 and 4.5 seconds. Identification receives
  those images and any companion WAV; the movie remains playback media.
- Preparation requires an empty workspace with no recording, pending audio,
  description draft, crop, admission check or refinement. Leaving Scan,
  backgrounding, clearing capture or transferring presentation ownership cancels
  uncommitted replay work. Generation and account/session fences reject late
  results and clean their owned files.

Choose **Stage audio sample** or **Stage video sample**, inspect the staged
media, start the observer below and wait for `observer_ready`, then tap the
normal **Identify** button once. Record the visible outcome independently.
Replay preparation happens before that tap, so these measurements do not cover
file import, microphone/camera recording or physical-device behavior. Imported
video frames are marked as gallery input and do not fabricate capture context.
**Stage audio sample** retains ordinary audio submission context. Source hashes
alone do not attest to the prepared inference bytes or complete request context.

### Fixed context for foreground audio comparisons

**Debug replay → Stage audio with fixed context** selects the versioned
`audio-minimal-v1` profile for one audio sample. The menu displays **Replay:
fixed context** while that item is staged. The setting belongs to the staged
item and its foreground request, not the device or account. Clearing/removing
the item removes it; adding another item or refinement context makes the fixed
submission invalid. Profile changes during admission invalidate the snapshot.
Normal Identify still owns admission, durable enqueue and provider dispatch.

The synthetic test context uses `deviceLocale: en`, `deviceTimeZone: UTC`,
`currentMonth: 1` and `timeOfDay: 12:00 PM`; these are fixed experimental
conditions, not source capture facts or a context-free prompt. It omits region,
GPS/elevation, location names, weather, timestamp, depth, zoom, size,
observation text and preferred goals. Authentication, scan identity and the
owner's geoprivacy preference retain their ordinary owners. This plain
fixed-context option adds no request field or provider/model override. These
Debug simulator types and activation paths are absent from Release and
physical-device builds.

Fixed replay cancels and clears stale context prefetch before preparation, skips
the live location lookup before queue admission, and creates no deferred context
task. Cancellation cannot undo a lookup started by an earlier ordinary capture,
but its result cannot enrich this fixed request or its queued row.

The queue still owns recovery. The profile is deliberately not persisted, so
offline submission, foreground failure, interruption and any later background or
stored/reconstructed result are **excluded from controlled comparisons**.
Pre-dispatch queue fallbacks display that exclusion. A late pipeline failure
uses ordinary queued/error presentation; it is still excluded. Recovery may
produce a new provider result using ordinary date/locale/timezone handling. The
historical measurement-v1 `delivery: fresh` flag alone does not prove that a
result used this profile. The current `identification_app_measurement_v2` record
adds `contextProfile`: `audio-minimal-v1` or null. A non-null value requires the
final serialized body to match the fixed scalars, exactly one inline audio item,
and its canonical audio descriptors/timeline, with no extra context or evidence
fields. A process-local validator must still accept the original foreground
attempt and queue generation when the HTTP response is measured. Only an initial
HTTP 200 with fresh diagnostic metadata can carry the profile; transport, Auth,
route and 5xx retries cannot. Background request builders never attach the
validator. The field remains null in device/Release builds.

`requireFixedAudioMeasurement` validates v2, the profile, fresh delivery, usable
provider/Edge timings, complete matching app identity, the reviewed backend
bundle fingerprint and exact requested/returned model. The observer retains
strict v1 compatibility and cost estimates for both versions. V1 records cannot
be promoted by adding a run annotation. The native record remains within its 1
KiB log budget and retains no request, scan, user or media identifier.

This is **profile-only evidence at the HTTP response boundary**. It does not
attest the particular WAV/case, processing arm, successful persistence/display,
complete observation window, or total billed cost. Case association still uses
one sequential UI submission per complete window; a cancelled, queued, failed or
unobserved final outcome remains excluded. The offline two-arm preparation below
does not turn app records into a paired dataset. See the
[provenance and arm definitions](../rfcs/identification-audio-comparison-provenance-2026-09-23.md)
for the remaining execution requirements and the earlier
[replay implementation](../rfcs/identification-fixed-context-replay-2026-09-23.md)
for request construction.

The
[server assignment follow-up](../rfcs/identification-audio-comparison-assignment-2026-09-23.md)
implements a disabled twelve-slot gate and `X-Merian-Audio-Comparison` proof on
fresh durable success. The subsequent
[app integration](../rfcs/identification-audio-comparison-app-integration-2026-09-23.md)
adds **Debug replay → Stage comparison slot**. Each numbered slot selects a
generated frozen assignment. Comparison preparation validates the source copy's
complete WAV hash/length and canonical mono 44.1 kHz Int16 format, then
preserves its bytes without re-encoding. Core Audio can add container padding
even when PCM samples are unchanged, which would invalidate a frozen assignment.
Duration and copy-cleanup checks still apply. Ordinary replay retains its
transcoder. Staging and request serialization check the actual bytes again. The
request uses the slot's fixed queue UUID and only the server-owned
`{planSha256, slot}` handle. Existing queued/saved IDs and non-foreground
admission are rejected before funding or file copying. The server remains
authoritative for source, arm, request and settings bindings. No app setting
changes a model or processing policy.

The native transport compares every receipt field with the generated table and
rechecks current-attempt ownership on the same main-actor turn that adopts it.
Separate compact **Audio comparison** records carry the plan, slot and SHA-256
of the exact logged measurement JSON. They record receipt adoption, exact
durable queue finalization, and the matching UIKit first-draw callback.
Finalization carries the result service's actual `saved` or
`completed_without_record` outcome, a 0–1 confidence score and biological flag.
No species names, provider prose, media, auth state or scan/user IDs are
retained. The measurement-v2 record remains unchanged and each additional record
fits the 1 KiB log limit.

The passive observer now writes observation-v2 envelopes with the exact
measurement hash and rejected-proof count. The offline admission command
requires one fresh fixed-context Pro response, matching reviewed app/backend
identity, all three slot-bound proofs, one first-render timing, and a normally
closed bounded window. Missing/duplicate proof, extra HTTP responses, rejected
or oversized proof logs, interruption and old observation-v1 files cannot
qualify. Native draw and queue finalization may finish in either order.
Unprojected unrelated timing rows are counted but not retained; this is still
not a complete billing ledger.

The reusable **Control identification audio comparison** workflow owns
inspection, bounded activation and deactivation of
`IDENTIFICATION_AUDIO_COMPARISON_V1`; follow the
[activation and recovery procedure](../backend-and-data/06-supabase-deployment-runbook.md#audio-comparison-activation-hold).
The infrastructure stays installed between runs. Each activation requires the
reviewed account, plan, deployed bundle and a window of at most two hours;
expiry stops comparison requests even if cleanup is interrupted. A stored
expired value is inactive, and verified deactivation separately proves removal.
Deployment and paid observations still require their named authorization. Local
implementation and synthetic tests do not constitute a paid experiment. Old
artifacts remain immutable; never add proof fields by hand. This evidence binds
an observed native outcome to an authenticated response claim, not a standalone
signed artifact or a species accuracy judgment. The integration record gives the
offline admission command.

The
[offline audio-path verification](../rfcs/identification-audio-path-verification-2026-09-22.md)
adds synthetic sample-preservation tests through preparation, replay,
persistence and intercepted request serialization, plus exact processed-WAV
handoff checks at the backend adapter. It also measures trimming and
downsampling of the six frozen source clips and documents an aliasing defect.
This verifies the current local implementation; historical live request bytes
and context remain unattested. Controlled comparisons should hold location/time
context constant because replay retains the ordinary audio submission policy.

The subsequent
[audio preprocessing correction](../rfcs/identification-audio-preprocessing-fix-2026-09-23.md)
adds anti-alias filtering and partial-window measurement, with frozen offline
outputs and local processing timings for the same six clips. Its
[production deployment](../release-evidence/identification-audio-preprocessing-deployment-2026-09-23.md)
passed exact-SHA candidate validation and automated deployment, smoke and health
checks. No fresh identification with the deployed fingerprint or new quality
comparison has been recorded. Those smoke probes do not measure paid provider
execution or hosted audio-processing CPU headroom.

Preserve the historical app results. A new controlled comparison needs explicit
pipeline versions and the same reviewed context policy in both arms. Ordinary
replay still obtains live context; the fixed-profile option above now supplies a
separate foreground request path through the same submission owners. Two fresh
versioned processing arms and recorded profile provenance are now implemented
behind the disabled assignment gate. Reviewed deployment, activation and live
observations remain prerequisites for a controlled run. The
[evaluation SRD](../rfcs/identification-evaluation-srd.md) owns that next slice.

This provides a repeatable input path. Benchmark claims require reviewed cases
to be submitted and their observations retained. The
[first controlled video run](../rfcs/identification-replay-app-benchmark-2026-09-22.md)
records that boundary; its included audio was digitally silent, and standalone
audio remained pending listening review. After the owner's confirmation, the
[first audio run](../rfcs/identification-audio-app-benchmark-2026-09-22.md)
completed that remaining case and retained its disagreement with the source
label.

## Observe a simulator session

Use approved examples and the ordinary app UI, with one submission in flight.
Observe and label completed result screens separately; a timing event or HTTP
200 alone is not a visible-result or correctness assertion. Do not combine
overlapping observation windows or infer provider-call counts from app submits.

Create a private evidence directory outside Git, then run from the repository
root, replacing the placeholders with a concrete simulator and new output file:

```bash
deno run --frozen --no-prompt --deny-net --deny-env \
  --config services/supabase/functions/deno.json \
  --allow-run=xcrun --allow-write=/private/tmp/measurement-evidence \
  services/supabase/scripts/observe_identification_app.ts \
  --device SIMULATOR-UUID --seconds 120 \
  --output /private/tmp/measurement-evidence/observation.jsonl
```

The observer reads only the bounded Merian benchmark log projection. It captures
the new response record plus existing numeric HTTP and app pipeline intervals.
It discards raw OS log rows, unknown messages and oversized/truncated records.
The requested window is at most 300 seconds, with a bounded 30-second collector
shutdown grace. Simulator `log stream --timeout` can exit on a later polling
interval: a synthetic 120-second request closed normally after 128 seconds. The
grace permits that normal drain; a watchdog kill still fails the window. The
maximum retained event count is 100. It creates a new mode-0600 JSONL file,
flushes every event and records final observer status. Existing output files are
never overwritten. Collector failures return a nonzero command status. It
performs zero submissions and requires no provider key.

Wait for `observer_ready` on the console before submitting a scan. It is emitted
after the collector's stream banner or first validated event and is also saved
as a `readyAt` line. This confirms reader startup, not completeness of OS
logging.

The first line identifies the requested window, shutdown grace and optional
pricing snapshot; measurement lines contain independently validated events and
optional cost estimates. The last line records completion, event count,
readiness, collector exit code/signal, stop reason and counts of unprojected or
oversized rows. No discarded row content is retained. A missing final line
indicates an interrupted observer. Zero events does not establish that the app
made zero calls. Case association follows the observed sequential UI actions;
the file contains no scan identifier for automatic joins.

## Optional cost estimates

Add `--pricing /private/tmp/measurement-evidence/pricing.json` and grant read
permission to that exact file. It uses the existing `evaluation_pricing_v1`
contract in the
[evaluation tooling](../../services/supabase/scripts/identification_evaluation/README.md).
Supply a reviewed dated pricing snapshot; no dollar rates are hard-coded here.
The snapshot is retained in the observation header.

The shared `estimateCost` charges the highest reviewed input rate without a
cache discount and includes thinking/output. An estimate requires a pricing
snapshot no more than seven days old at observation, an exact returned/requested
model match and consistent required usage. Missing/stale pricing, model-version
aliases without a reviewed price mapping, missing usage and replayed results
retain null cost and a fixed reason code.

`estimatedPrimaryUpperUsd` covers only the observed primary attempt. It excludes
optional enrichment, unobserved or uncertain calls, other attempts, storage and
transport costs. It is neither the total scan cost nor an invoice or budget cap.
Do not sum known estimates into a claimed complete bill when coverage is
missing.

## Source identity and validation

After changing the Function's runtime inputs, format them and regenerate:

```bash
deno run --allow-read=services/supabase \
  --allow-write=services/supabase/functions/identify-multimodal/deploymentIdentity.ts \
  services/supabase/scripts/generate_identification_deployment_identity.ts --write
```

The generated file excludes itself from the digest. The discovery-based
`make test-supabase-tooling` gate checks freshness and determinism. Field Chat
uses the same digest implementation and retains its existing identity format.
This adds no hosted activation or release-control bypass.

`project.yml` declares the processed app Info.plist as an input to **Embed Build
Provenance**. This orders stamping after `ProcessInfoPlistFile`; PBX phase order
alone did not prevent Xcode from overwriting it. The project-resource gate locks
that dependency, and `IdentificationBenchmarkRecordTests` checks the final
native test host's source fields as well as privacy, bounds, replays and old
responses. Parser/cost/streaming and subprocess-lifecycle tests run without
network or environment access. Lifecycle tests cover late records, watchdog
failure, unavailable collectors, the event cap, rejected rows and write-failure
cleanup. Full thirteen-span timing fixtures cover both the backend auth wrapper
and native projection. Extended-header fixtures cover unrelated metrics, quoted
description injection, escaped quotes, the 32-entry bound and duplicate retained
metrics. Use the complete native and backend gates in the
[testing strategy](./08-testing-strategy.md) before handoff.

### Local verification checkpoint — 22 September 2026

The complete native unit target passed 4,277 tests with no failures or skips;
its XCResult is retained locally at
`.artifacts/local-ios/db03390f43f94bf5b9ae991903bc33fd.xcresult`. The complete
Edge suite passed 2,047 tests with six database-dependent cases skipped because
no disposable database was configured. Supabase tooling, native build tooling,
DTO parity, dependency/configuration validation, formatting and lint checks
passed. This does not establish database or hosted candidate validation.

A one-second passive simulator observer smoke test completed with zero events
and zero submissions. An unavailable-device check returned a nonzero exit status
and retained a sanitized failure record. Both evidence files used mode 0600.
These checks validate the recorder, not identification quality or live provider
measurements. No deployment or new paid identification was performed.

### Live measurement checkpoint — 22 September 2026

The subsequent
[two-photo repeat](../rfcs/identification-measured-app-benchmark-2026-09-22.md)
used the deployed backend and a clean-source simulator build. Both scans reached
finished results. The cat retained Gemini 2.5 Pro identity, token usage, source
fingerprints and app timings; the flower retained only preflight timing. Both
live windows ended with `observer_stopped_or_unavailable`. A separate synthetic
seven-event window passed, but did not explain or repair those failures. The
cat's provider/Edge timing spans were also unavailable. Treat the retained data
as partial observations; investigate these gaps before expanding paid
benchmarks.

### Recorder repair checkpoint — 22 September 2026

The [recorder repair](../rfcs/identification-recorder-repair-2026-09-22.md)
reproduced premature shutdown with a 120-second synthetic window. A longer,
bounded shutdown grace allowed the repaired window to retain all seven events
and close normally. This establishes collector lifecycle behavior separately
from the earlier missing flower events and live timing-header question.

### Live capture verification — 22 September 2026

The subsequent
[bounded two-photo verification](../rfcs/identification-timing-capture-verification-2026-09-22.md)
retained all seven expected events per case and closed both recorder windows
normally. The flower exposed `too_many_metrics` under the old thirteen-entry
parser. After the bounded, quote-aware parser change, the cat retained valid
provider and total Edge spans. The flower was not retried, and its missing spans
remain unknown. The complete updated native target passed 4,281 tests. These
observations establish successful capture for the exercised paths, not complete
billing coverage, verified accuracy or a latency distribution.

### Source-backed photo pilot — 22 September 2026

The
[six-photo app benchmark](../rfcs/identification-source-photo-app-benchmark-2026-09-22.md)
then completed six sequential first submissions with unchanged app/backend
identities and normal Gemini selection. Every observer closed normally with
seven events, fresh Gemini 2.5 Pro diagnostics and valid provider/Edge spans.
All five biological outcomes agreed with provisional references; the mineral
control was labeled non-biological. The report preserves per-case timings and
primary-attempt estimates without claiming verified accuracy, repeatability or
total billed cost. No runtime code changed during this run.

### Description pilot — 22 September 2026

The
[two-description benchmark](../rfcs/identification-description-app-benchmark-2026-09-22.md)
completed both first submissions and non-overlapping observer windows. Each
retained the five expected Describe events, fresh Gemini 2.5 Pro diagnostics and
valid provider/Edge spans. One result agreed with a provisional genus reference
while naming a more specific species; the non-biological-source control received
a Strong biological answer from ambiguous text. The report preserves that
mismatch and the missing timing fields. Audio/video files have no normal-app
import route, and this observer uses simulator logging; physical-device capture
does not inherit these measurements. No audio/video case or new runtime change
was included.

### Describe timing and replay infrastructure — 22 September 2026

The native implementation now forwards the immediate Describe start clock and
provides the controlled simulator replay path above. The focused selection
passed 94 tests, and the complete native unit target passed 4,293 tests with no
failures or skips. The full XCResult is retained locally at
`.artifacts/local-ios/2fd99182d0a0403dbf4560b3fcc1e379.xcresult`. XcodeGen
regeneration, generated-project validation/resource tests, Markdown formatting
and diff checks also passed.

The arm64 Release simulator build passed. Its executable contained none of the
`IdentificationReplay`, `Stage audio sample` or `Stage video sample` markers;
the Debug app's executable/dylib scan found all three as a positive control.
This establishes the checked build's compile-time exclusion, not an App Store
archive, physical-device or hosted release validation.

A staging-only UI smoke check used one second of synthetic tone audio. The Debug
menu staged the clip, the normal Identify button remained available without
automatic submission, and cancellation returned to the empty workspace. The
inbox source hash was unchanged after cancellation; the synthetic input was then
removed. Identify was never tapped. This check made no identification request
and is not a biological benchmark or latency sample.

At this implementation checkpoint, live verification and curated replay
measurements were still pending. The follow-up below preserves earlier benchmark
files and their unknown values.

### Describe and controlled video verification — 22 September 2026

The
[controlled replay benchmark](../rfcs/identification-replay-app-benchmark-2026-09-22.md)
completed one exact Describe repeat and one first video submission through the
ordinary app. Both observer windows closed normally. Describe emitted six
events, including the repaired first-render metric at 23.136 seconds; its visual
preflight field remains null. Video emitted seven events and recorded 24.108
seconds to first rendered frame. Both retained fresh Gemini 2.5 Pro diagnostics,
valid provider/Edge spans and genus-level agreement with provisional references.

The five-second replay retained five ordered snapshots and its actual companion
audio track, whose 220,500 decoded samples were all zero. This is a video-path
measurement, not evidence for meaningful acoustic/visual fusion. The prepared
standalone audio case was not submitted because its listening review was still
open at that checkpoint. Import/preparation and physical capture precede the
Identify clock and are excluded from these timings. No provider switch,
deployment or formal accuracy claim follows from these observations.

### First controlled audio verification — 22 September 2026

The [audio benchmark](../rfcs/identification-audio-app-benchmark-2026-09-22.md)
followed the owner's listening confirmation and a fresh frozen packet. Its one
ordinary-app submission produced six events and a normally completed observer
window. First render took 19.022 seconds; Gemini 2.5 Pro identity and valid
provider/Edge spans were retained. The visual preflight marker remains null on
this nonvisual path. The Strong-match Wood Thrush answer disagreed with the
provisional Northern Cardinal source label; that is a reference disagreement,
not an independently verified accuracy result.

Before staging, the Debug replay control was unavailable after the previous
result was dismissed. Relaunching the unchanged app restored it; no scan was
retried and the relaunch preceded the observer window. The cause is undiagnosed.
Physical microphone capture, final request/context attestation and exhaustive
billing remain outside this measurement.
