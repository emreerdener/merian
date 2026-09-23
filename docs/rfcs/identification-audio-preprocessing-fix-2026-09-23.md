# Audio preprocessing correction

Date: 23 September 2026\
Status at implementation: Implemented and validated locally; deployment and
identification comparison pending

> **Deployment follow-up — 23 September 2026:** The owner's subsequent main push
> passed exact-SHA candidate validation, production deployment and automated
> smoke/health checks, completing at 14:45 UTC. See the
> [deployment record](../release-evidence/identification-audio-preprocessing-deployment-2026-09-23.md)
> for the exact commit, actual full-fleet plan and remaining measurement work.
> The local evidence and original next-comparison plan below remain historical;
> no new identification-quality result is claimed.

The shared audio processor now filters before changing sample rate and measures
the final partial silence window. This addresses the defects established by the
[audio-path investigation](./identification-audio-path-verification-2026-09-22.md).
Gemini, its prompts and generation settings, confidence rules, and the 16 kHz
mono PCM16 representation remain unchanged. No provider calls or production
deployment occurred in this slice.

The result is a better-controlled input signal. It does not establish better
species identification or explain the earlier three Strong disagreements. Those
answers and their provisional references remain in the immutable
[six-audio benchmark](./identification-audio-six-app-benchmark-2026-09-22.md).
Formal corpus counts remain 0/60 development and 0/240 held-out groups.

## Implementation

[`audioProcessing.ts`](../../services/supabase/functions/_shared/audioProcessing.ts)
remains the shared decode, mono conversion, trimming, resampling and encoding
entry point for both audio handlers and evaluation preparation.

- [`resample.ts`](../../services/supabase/functions/audio-spec/resample.ts)
  replaces linear interpolation with Blackman-windowed sinc resampling. A radius
  of 32 samples at the lower rate, cutoff at 90% of its Nyquist frequency and
  128 interpolated fractional phases provide a bounded low-pass filter. Each
  phase has unity DC gain; there is no signal loudness normalization. Endpoint
  replication supplies samples outside the clip. The output length remains the
  floor of the rate-scaled input length, without an added delay or tail;
  equal-rate inputs bypass the filter.
- [`wav.ts`](../../services/supabase/functions/audio-spec/wav.ts) now computes
  RMS for every window, including a final partial window using its actual sample
  count. The 20 ms window, 0.008 threshold and two padding windows are
  unchanged. A quiet tail can still be removed after measurement.
- Source/output byte limits and coefficient/convolution limits reject excessive
  expansion or filter work before allocation/convolution. Both handlers return
  `413 payload_too_large` before admission. A low-rate WAV may now exceed the
  output ceiling despite fitting the source ceiling. The
  [API contract](../backend-and-data/05-api-contracts.md) owns the exact limits.
- Timeline-validated sparse video companions retain their source context when
  trimming leaves less than 0.5 seconds. A standalone clip whose only sound is a
  very short final window now correctly fails the existing post-trim minimum; it
  cannot pass by having that sound missed and the full mostly-silent source
  retained. Malformed and genuinely short sources still fail.

The method follows the standard bandlimited interpolation approach described by
Julius O. Smith III in
[Windowed Sinc Interpolation](https://www.dsprelated.com/freebooks/pasp/Windowed_Sinc_Interpolation.html).
The 16 kHz output still loses source frequencies above 8 kHz and attenuates its
transition band below that. Preserving more biological bandwidth is a separate
experiment requiring provider, payload and runtime assessment.

## Offline evidence

The
[reproducible analysis](./identification-evaluation-evidence/2026-09-23-audio-preprocessing-fix/analyze.ts)
runs the actual shared processor and multimodal preparation helper with network
and environment access denied. It verifies all 44 source-packet files and all
nine previous investigation files against their frozen hashes before comparing
outputs. It asserts the shared and route helpers produce identical WAV bytes,
and verifies the audio routing, provider builder and Gemini request projection
source files are unchanged. The
[measurements](./identification-evaluation-evidence/2026-09-23-audio-preprocessing-fix/analysis.json)
retain source/derived hashes, durations, runtime samples and processor hashes.
No expected labels, private capture context or production responses enter the
processor or new evidence.

All source clips are 44.1 kHz mono PCM16; all outputs remain 16 kHz mono PCM16.
Durations below are seconds, rounded to three decimals.

| Case    | Previous output | Candidate output | Additional retained source frames |
| ------- | --------------: | ---------------: | --------------------------------: |
| `c0013` |           5.720 |            5.720 |                                 0 |
| `c0014` |           9.060 |            9.060 |                                 0 |
| `c0015` |           9.960 |            9.979 |                               828 |
| `c0016` |           4.900 |            4.900 |                                 0 |
| `c0017` |          10.000 |           10.000 |                                 0 |
| `c0018` |           9.960 |            9.979 |                               828 |

The restored partial tails are approximately 18.78 ms each. No human listening
assessment of these newly derived outputs is claimed.

The same two-second, amplitude-0.5 synthetic tone method used in the previous
investigation gives:

| Source tone | Measured output component | Previous amplitude | Candidate amplitude |
| ----------- | ------------------------- | -----------------: | ------------------: |
| 1 kHz       | 1 kHz                     |           0.499123 |            0.499970 |
| 12 kHz      | 4 kHz alias               |           0.389439 |          0.00000656 |

This is sine/cosine projection across the entire PCM16 output, including
boundary transients, on the same 500–7,500 Hz grid. The candidate 12 kHz input's
largest component on that grid is approximately 0.00000720 at 7.5 kHz. These
finite measurements demonstrate suppression of the tested artifact, not zero
aliasing at every frequency. Independent signal tests require at least 60 dB
rejection of tested 8.2–20 kHz tones and less than 0.3% RMS error for tested
0.1–6 kHz passband tones. Those tests exclude boundary transients and cover
several source rates, upsampling, DC, silence and invalid/budget-limited inputs.

## Local processing cost

Measurements use Deno 2.9.4 on macOS ARM64, `performance.now`, one warm-up and
five recorded repetitions. They measure the full shared processor through WAV
encoding and base64, without provider/network work. They are wall-clock times,
not hosted CPU measurements or end-to-end identification latency.

| Work                                          |         Median | Maximum recorded |
| --------------------------------------------- | -------------: | ---------------: |
| Individual reviewed clips                     |   34.5–71.1 ms |          78.6 ms |
| Two 15-second, 44.1 kHz clips                 |       211.0 ms |         211.9 ms |
| Two source-byte-limit clips at 44.1/48/96 kHz | 390.9–425.0 ms |         430.8 ms |
| Two 8 kHz clips expanding to the output limit |       515.9 ms |         582.3 ms |

These local checks provide useful headroom evidence, but they do not prove the
hosted budget. Supabase currently documents a two-second active CPU limit per
request, excluding asynchronous I/O; hosted validation must include the rest of
the handler's work. See the official
[Edge Function limits](https://supabase.com/docs/guides/functions/limits).

## Verification and retention

The
[check record](./identification-evaluation-evidence/2026-09-23-audio-preprocessing-fix/verification.json)
records the final local gates and their limits. Focused tests passed (25 tests,
118 steps), as did the complete backend suite against a disposable local
database (2,066 tests, 198 steps; no ignored tests). Catalog checks passed all
388 assertions in 52 files. Database lint found no schema errors. Security and
performance advisors passed the repository's error-level gate, with 105 and 80
warnings respectively on the unchanged migration set; warnings are not claimed
resolved by this audio change. Tooling, DTO parity, function graph checks,
recursive type checks, lint and formatting also passed.

No Swift, schema, dependency or wire-field shape changes were made. Native tests
were not rerun in this backend-only slice; the previous investigation retains
its native evidence. The generated identification bundle digest was refreshed
and checked. An independent read-only audit verified DSP bounds, sparse-video
behavior and both real-handler 413 tests without an outstanding material
finding. The database was created under a separate project ID and port; it is
local validation, not hosted exact-SHA candidate release evidence.

The private packet `2026-09-23-audio-preprocessing-fix-v1` retains six derived
WAVs, the analysis script and the two JSON records. Its
[nine-file manifest](./identification-evaluation-evidence/2026-09-23-audio-preprocessing-fix/freeze.json)
has SHA-256 `caed001977718c109018ba88226c29c0d9145cdaa35817deae400cd64c1943b4`
and retention through 23 October 2026. Earlier packets remain unchanged. To
reproduce, run the checked-in analysis script from this source revision with the
two frozen source-packet directories and a new destination directory; it refuses
to overwrite an existing destination.

## Next comparison

1. Submit this candidate through the normal exact-SHA backend validation and
   release controls. Deployment requires an explicit request naming the
   operation and target; local validation does not authorize it. Confirm hosted
   resource behavior before interpreting live identification results.
2. Reuse the six frozen clips and the same Gemini Pro profile. A simple
   post-release six-case app replay checks operational behavior, but comparison
   with the historical six results remains exploratory because their full
   location/time context was not retained.
3. A causal preprocessing comparison needs two fresh, versioned arms with the
   same reviewed context policy, prompts, generation settings and frozen input
   media. Propose one first attempt per clip per arm (12 total), bounded by the
   approved account/run budget, with no selective retries. Record source and
   processed-media hashes, pipeline version, timing, usage and normalized
   outcomes without logging private context or raw responses. Current app replay
   does not yet supply that fixed-context comparison; resolve that measurement
   requirement before executing it. Do not bypass existing evaluator
   incompatibility or provider-readiness checks.
4. Keep animal references provisional and score the three reviewed negative
   controls separately. Record label/confidence changes descriptively; this
   six-case experiment cannot qualify a provider or establish an accuracy
   improvement. Broader reviewed cases remain necessary before model, confidence
   or sample-rate tuning.
