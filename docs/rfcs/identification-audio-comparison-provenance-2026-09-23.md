# Fixed-context measurement provenance and audio comparison preparation

Date: 23 September 2026\
Status: Implemented and validated locally; live comparison remains disabled

This slice records the fixed request context introduced by the
[simulator replay work](./identification-fixed-context-replay-2026-09-23.md) and
defines both audio preprocessing arms offline. It adds no live experiment,
provider change or production deployment. Gemini remains the identification
provider. Formal corpus counts remain 0/60 development and 0/240 held-out
groups.

## What a measurement now establishes

Native `identification_app_measurement_v2` adds one allowlisted field:
`contextProfile`, either `audio-minimal-v1` or null. It can be non-null only
when:

1. The Debug simulator foreground request carries the fixed replay profile.
2. Its final serialized body has the exact fixed context, one inline audio item,
   its canonical audio descriptors/timeline and no additional context/evidence.
3. The live pipeline's validator still accepts the attempt and foreground queue
   generation at measurement time, and the task is not cancelled.
4. This is the initial transport attempt, with HTTP 200 and valid fresh backend
   diagnostics. Auth, route, transport and 5xx retries cannot retain the
   profile.

The validator and profile proof stay in memory. Background builders, persisted
queue rows, request JSON and headers do not carry them. Ordinary requests and
device/Release builds retain null. The native record still fits the 1 KiB log
budget, with no request/scan/user identifiers, media content or private context.

The observer strictly accepts both record versions and preserves both versions'
cost projection. `requireFixedAudioMeasurement` rejects v1, null profiles,
missing/mismatched app identities or backend fingerprints, model aliases and
unusable timing spans. Older frozen records remain unchanged.

This is profile-only evidence at the HTTP boundary. It does **not** establish
which WAV/case was sent, which preprocessing arm ran, or whether the result was
successfully persisted and displayed. It is not formal evaluation admission or a
complete billing ledger. Complete sequential observation windows and final UI
outcomes remain separate requirements. The
[measurement guide](../development-guides/21-identification-app-measurement.md#fixed-context-for-foreground-audio-comparisons)
owns the operational contract.

## Two offline arms

| Arm                            | Processing                                                                                                        |
| ------------------------------ | ----------------------------------------------------------------------------------------------------------------- |
| `audio-linear-full-windows-v1` | Historical 20 ms RMS trimming using full windows only, followed by linear interpolation to 16 kHz.                |
| `audio-sinc-partial-tail-v1`   | Current partial-window RMS trimming and bounded Blackman-windowed sinc resampling through `processMultimodalWAV`. |

Both output mono PCM16 WAV at 16 kHz. The historical transforms are isolated in
evaluation scripts; inputs to both arms are restricted to canonical standalone
mono PCM16 44.1 kHz WAVs of at most 15 seconds. This lane does not cover video
companions or mixed evidence. The change being compared includes both alias
suppression and partial-tail retention; it cannot isolate either one's effect on
species identification.

The offline preparation verifies the frozen source manifest and all six source
audio hashes. It uses production request/policy builders with Gemini Pro,
`audio-minimal-v1` synthetic context and identical prompts, schema, generation
and confidence settings. It records source and processed-WAV hashes, format and
sample counts, provider-request hashes, policy/configuration hashes and the
complete local implementation identity. Within each pair, the request hash with
audio bytes removed must match. No raw media or provider body enters the output.

There are twelve prospective assignments: one attempt per case per arm, with the
first arm alternating across the six cases. No selective retries are planned.
Source/implementation drift requires a new preparation and review. The six
animal/control references retain their existing provisional/reviewed status;
this sample cannot qualify a model or prove an accuracy improvement.

Preparation runs with network and environment access denied, uses a new private
output directory, and refuses to overwrite an existing preparation. The
[tooling README](../../services/supabase/scripts/identification_evaluation/README.md#offline-audio-comparison-preparation)
contains the command. Its artifact version deliberately cannot be dispatched by
the current evaluation runner.

## Validation and retained evidence

The sanitized
[preparation](./identification-evaluation-evidence/2026-09-23-audio-comparison-preparation/preparation.json),
[canonical digest](./identification-evaluation-evidence/2026-09-23-audio-comparison-preparation/freeze.json)
and
[verification](./identification-evaluation-evidence/2026-09-23-audio-comparison-preparation/verification.json)
record six source pairs and twelve prospective assignments. The canonical
preparation SHA-256 is
`42350d978486e1a9edb409065be163b45f2d01d1182042b3e48f318e7ed43681`. Reprocessing
matched all six historical output hashes for the legacy arm and all six
previously frozen corrected outputs for the current arm. The preparation
fingerprint matches the final local tooling implementation. Existing-destination
rejection was verified as exclusive creation with unchanged output; changed
source audio and manifest both failed before output creation. No provider was
called.

The private metadata packet is `2026-09-23-audio-comparison-preparation-v1`,
with directory mode 0700 and file mode 0600, retained through 23 October 2026.
Source audio remains in the existing packet under its original 22 October
retention; this preparation makes no new media copies or retention extension.
The checked-in copy contains only sanitized settings, hashes and verification
facts.

The focused native gate passed 46 tests. The complete native unit target passed
**4,302 tests with zero failures or skips**, retained at
`.artifacts/local-ios/4d6e8fef0b7e465d946a9381cfa57dbb.xcresult`. The build
retained the existing `ThreadCheckingAudioPlayer` Sendable warning. The Release
device build passed, retained at
`.artifacts/local-ios/fdbd221857ac46798e52a7ea5b5b5195.xcresult`; its binary
contains neither the fixed profile marker nor the Debug activation identifier.
The three previously recorded unreachable-branch warnings in nonvisual
submission remain. No new native warning was introduced. UI tests and
physical-device execution were not rerun for this measurement-only slice.

The complete Supabase tooling gate passed 374 standard tests, nine isolated
evaluator tests, 39 DTO tests and all seven shell test files, plus TypeScript
checks. Full Deno/Markdown formatting, Deno lint, 101 function configurations
and dependency graphs, SwiftLint, and native
project/event/privacy/transport/migration static checks passed. No Edge runtime
or database schema changed; no hosted or disposable-database validation is
claimed.

An independent read-only cross-surface audit found no additional transport,
retry, recovery or privacy regression within the explicitly profile-only scope.
The configured reviewer agent was unavailable; the project contract auditor
performed that review. Its identified media/case-proof boundary is retained in
the requirements above.

## Next execution step

The ordinary authenticated app route runs the deployed current processor. It
cannot execute the legacy arm, and an offline prepared hash does not attest the
bytes of a later live app request. To preserve the owner's preference for the
existing production account and billing infrastructure, the next implementation
needs a server-owned, bounded arm assignment and per-case source/processed-media
binding, plus complete-outcome admission. It must preserve normal consent,
authentication, quotas, idempotency, accounting and release controls. A
caller-controlled production processor/model override is not part of this plan.

An explicitly selected direct-evaluator experiment would instead use its
existing readiness, pricing and budget controls and would measure a different
execution path. Neither lane is activated by this preparation. No old deployment
is restored to create the comparison, and no new identification-quality result
is claimed.

## Subsequent server assignment slice

The
[server assignment implementation](./identification-audio-comparison-assignment-2026-09-23.md)
adds disabled server-owned slots and actual source/processed/request
verification with fresh durable proof headers. It moves the historical
transforms into a route-private owner shared with offline preparation. The
evidence and original implementation identity above remain historical; native
receipt collection and complete-outcome admission are still pending. No paid
comparison has run.
