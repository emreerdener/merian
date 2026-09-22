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
The maximum window is 300 seconds plus a five-second collector shutdown grace;
the maximum retained event count is 100. It creates a new mode-0600 JSONL file,
flushes every event and records final observer status. Existing output files are
never overwritten. Collector failures return a nonzero command status. It
performs zero submissions and requires no provider key.

The first line identifies the observation window and optional pricing snapshot;
subsequent lines contain independently validated measurements and optional cost
estimates. The last line records completion, count or collector failure. A
missing final line indicates an interrupted observer. Zero events does not
establish that the app made zero calls. Case association follows the observed
sequential UI actions; the file contains no scan identifier for automatic joins.

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
responses. Parser/cost/streaming tests run without network or environment
access. Use the complete native and backend gates in the
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
