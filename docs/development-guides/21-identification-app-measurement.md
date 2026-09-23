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
