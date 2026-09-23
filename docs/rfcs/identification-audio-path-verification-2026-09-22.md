# Audio-path verification

Date: 22–23 September 2026 (America/Chicago; retained timestamps are UTC)\
Status: Offline investigation; production behavior unchanged

The app's tested replay path preserves canonical audio samples. The backend
deliberately changes those samples before Gemini: it trims edges and converts
44.1 kHz mono PCM16 WAV to 16 kHz mono PCM16 WAV. Its linear downsampler has no
anti-alias filter. A synthetic tone test demonstrates substantial aliasing. That
is a signal-processing defect worth addressing before another model comparison;
it does **not** establish why the earlier species answers disagreed with their
provisional references.

The
[sanitized measurements](./identification-evaluation-evidence/2026-09-22-audio-path-verification/analysis.json)
retain input/output hashes, durations, sample counts, RMS/peak measurements,
processor source hashes and synthetic diagnostics. This investigation made no
provider calls, changed no production code and preserved the
[six-audio benchmark](./identification-audio-six-app-benchmark-2026-09-22.md).

## What was verified

| Boundary                   | Implementation and evidence                                                                                                                                                                                                                                                                                                                                |
| -------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Replay staging             | `CaptureDebugReplayPreparer.prepare` copies the reviewed inbox WAV before calling the normal audio preparer. The integration test uses this real simulator-only entry point.                                                                                                                                                                               |
| Native preparation         | `InferenceAudioPreparer.prepareLocalFile` converts through Core Audio to 44.1 kHz, mono, signed PCM16. New tests compare every decoded PCM byte in non-silent full-range synthetic inputs of 128, 253,440 and 441,000 frames. All samples and lengths survive. Container padding may differ.                                                               |
| Durable file ownership     | The integration test calls `OfflineCaptureFileStore.persistFiles`; the complete prepared file remains byte-identical after moving into Documents and re-admitting its relative filename. It does not claim to exercise every SwiftData queue state or R2 recovery path.                                                                                    |
| Live request serialization | The test calls the real `MerianNetworkClient.identifyMultiModal` with the Documents-relative filename and an intercepted transport. Decoded `audioBase64s[0]` equals the persisted WAV exactly; there are no image, observation-text or staged-audio-key fields. No HTTP request leaves the mock.                                                          |
| Backend preparation        | Each of the six frozen clips is processed locally by the actual `processMultimodalWAV` and `processWavBuffer`; their outputs agree. All become nonempty mono PCM16 16 kHz WAVs.                                                                                                                                                                            |
| Adapter handoff            | The handler test now starts with non-silent 44.1 kHz audio and compares provider-bound audio against the direct processor result. Two distinguishable clips verify byte ordering and input indexes, alongside WAV MIME checks. Existing SDK interception tests verify exact ordered inline data, prompt, schema and model projection into Gemini requests. |

The native tests use synthetic data, not the historical live payloads. The
six-file analysis starts with frozen prepared source WAVs, not files recovered
from the historical app requests. These complementary checks establish current
implementation behavior; they cannot retroactively attest the exact bytes or
private contextual fields sent in those six live submissions.

Relevant owners are
[`InferenceAudioPreparer.swift`](../../apps/ios/Merian/Core/Media/InferenceAudioPreparer.swift),
[`CaptureDebugReplayPreparer.swift`](../../apps/ios/Merian/Features/Capture/Scan/Debug/CaptureDebugReplayPreparer.swift),
[`MerianNetworkClient+Inference.swift`](../../apps/ios/Merian/Core/Network/Endpoints/MerianNetworkClient+Inference.swift),
[`audioProcessing.ts`](../../services/supabase/functions/_shared/audioProcessing.ts),
[`wav.ts`](../../services/supabase/functions/audio-spec/wav.ts), and
[`geminiRequest.ts`](../../services/supabase/functions/_shared/ai/geminiRequest.ts).
The [API contract](../backend-and-data/05-api-contracts.md) remains
authoritative for transport and processing behavior.

## Changes to the six clips

All inputs are 44.1 kHz, mono PCM16; all outputs are 16 kHz, mono PCM16.
Durations below are seconds, rounded to three decimal places. Exact sample
counts and hashes are in the measurement record.

| Case    | Source    |  Input | Output | Leading removed | Trailing removed |
| ------- | --------- | -----: | -----: | --------------: | ---------------: |
| `c0013` | Raven     |  5.747 |  5.720 |           0.020 |            0.007 |
| `c0014` | Elk       | 10.000 |  9.060 |           0.940 |            0.000 |
| `c0015` | Tree frog |  9.979 |  9.960 |           0.000 |            0.019 |
| `c0016` | Stream    |  5.068 |  4.900 |           0.040 |            0.128 |
| `c0017` | Thunder   | 10.000 | 10.000 |           0.000 |            0.000 |
| `c0018` | Car alarm |  9.979 |  9.960 |           0.000 |            0.019 |

The trimmer uses 20 ms RMS windows, a 0.008 threshold and two padding windows.
It examines only complete windows, so a partial final window can be discarded
even without proving that tail is silent. The measurements establish removed
intervals, not whether those intervals contain useful identification evidence.
No audible-content assessment of the derived outputs is claimed.

Downsampling is linear interpolation with no preceding low-pass filter. A
two-second, 44.1 kHz synthetic 12 kHz sine wave with amplitude 0.5 produces a
strong 4 kHz component with amplitude **0.38944** after the actual pipeline. The
positive control, a 1 kHz tone of the same amplitude, remains 1 kHz with
amplitude **0.49912**. These measurements use sine/cosine projection over the
entire output on a declared 500–7,500 Hz grid, in 500 Hz steps. They demonstrate
aliasing without relying on a model answer or visual interpretation of a plot.

The PCM16 decoder divides by 32,768 and the encoder scales by 32,767; this also
allows approximately one least-significant-bit quantization differences before
accounting for resampling. There is no gain normalization in this path. The 16
kHz target is a current Merian implementation choice; this investigation does
not establish it as a Gemini requirement.

## Context and interpretation

A fresh audio-only request does not load a prior scan answer, species dictionary
or enrichment before provider dispatch. It does include caller-supplied
observation text when present and normal capture context. Replay preserves the
ordinary audio submission policy, including current device location/time context
when available. The six cases supplied no description or expected label, but
their complete contextual fields were not retained.

Location and season can therefore be uncontrolled influences when a public
recording was made elsewhere. This is a potential confound, not evidence that a
particular field caused a particular answer. A later controlled comparison
should hold a reviewed context policy constant, alongside identical media,
prompt, model and generation settings. Do not reconstruct or publish private
coordinates to explain these results.

## Next slice

Address the demonstrated downsampling defect in an isolated audio-processing
change, with passband and alias-rejection tests. Also cover preservation of a
partial final window and short/sparse audio. Decide whether to retain the
existing 16 kHz representation with proper filtering or preserve more source
bandwidth only after checking provider support, payload and runtime budgets.

After local validation, prepare a bounded paired comparison using these same
frozen inputs, a fixed context policy and the same Gemini profile. Keep this
preprocessing question separate from prompt, provider or confidence tuning.
Deployment and any new paid run require their own concrete execution plan; this
record grants neither. Animal references remain provisional and formal corpus
counts remain 0/60 development and 0/240 held-out groups.

## Verification and retention

The source packet's freeze SHA-256 is
`415a055676d36ae0bf93aa8856a2b86d67188c97ea51f5c42e20400909489c8c`; all 44
listed files were verified unchanged before analysis. The separate local packet
`2026-09-22-audio-path-verification-v1` retains the type-checked analysis
script, six derived WAVs and measurements. Its analysis runs with network and
environment access denied. No source labels enter processing, and no production
responses, credentials or personal context enter the new evidence.

The new packet freezes nine files with manifest SHA-256
`95c4c3e05b80b90f91bcaeba42b148c27107823f5c8f025a61079b6d1abaad94`, retained
through 22 October 2026. Its verification metadata is also available in the
[sanitized check record](./identification-evaluation-evidence/2026-09-22-audio-path-verification/verification.json).

Checks completed:

- Xcode generation and project validation passed with no generated changes.
- The complete `merianTests` target passed **4,295 tests**. After the final test
  refinement for Documents-relative filenames, the three affected suites were
  rebuilt and rerun: **23 tests passed**, including sample preservation,
  relative-path serialization and file cleanup. Production code and shared test
  fixtures were unchanged by that refinement.
- Focused backend processing, handler and Gemini SDK tests passed **12 tests and
  78 steps**, without network permission. The complete Deno task reported
  **2,048 passed, 196 steps, zero failures and six ignored**. Database
  integration checks self-skipped because local database connections were
  unavailable; those self-skips are included in Deno's reported pass count. This
  is not a passed disposable-database candidate gate.
- Recursive Deno formatting and lint, Supabase tooling tests, DTO parity, all
  101 function configurations/dependency graphs and the affected entrypoint's
  recursive type check passed. The private analysis script type-check passed.
- Markdown formatting, local report links and `git diff --check` passed.
  Existing unrelated edits were verified unchanged.

No physical-microphone capture, new paid comparison or deployment was performed.
The tests establish byte handling and measured processing behavior, not
biological accuracy or model ingestion behavior after the provider receives the
request.
