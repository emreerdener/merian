# Initial WAV structural validation under IC-1

Status: agreed internal validation contract, October 11, 2026, after local M3
artifact qualification at `3f51748f9`. The pure validator is implemented but
remains unwired; executable closure and initial integration remain open. This is
the next prerequisite already identified by
[IC-1](initial-completion-history-interface-2026-10-11.md) and
[M2](initial-media-verification-interface-2026-10-11.md), not provider readiness
or permission to activate a partial initial lifecycle. History primary remains
sole writer; initial-engine and independent reviewers approve the boundary.

## Actual initial compatibility

The ordinary initial WAV path is `identify-multimodal`, not `identify` or
`identify-describe`. Its ingress accepts up to two recordings, limits each
inline value to 3,600,000 base64 characters before decoding, and limits each raw
source to 2,700,000 bytes. Staged sources use the same byte limit and ownership
checks. See `_shared/identify/media.ts:resolveAudioBuffers` and
`identify-multimodal/index.ts` audio processing.

`_shared/audioProcessing.ts:processWavBuffer` accepts little-endian PCM16
(format 1) and float32 (format 3). It downmixes declared interleaved channels,
trims silence with 20 ms windows, RMS threshold 0.008 and two-window padding,
then bandlimited-resamples to 16 kHz and emits mono PCM16. Preserve the existing
video-companion fallback when trimming alone leaves less than 0.5 seconds. The
final 8,000-sample minimum remains mandatory. Output is bounded by
`floor((2,700,000 - 44) / 2)` samples; the existing resampler also bounds
coefficient allocation and filter operations. Input rate remains a positive
integer, subject to frame/byte arithmetic and existing transformation budgets;
do not add a 44.1 kHz input rule or an arbitrary rate/duration allowlist.

Historical `analysisHistory/audioContainer.ts` validates an already-prepared
44.1 kHz mono profile. It is not the initial input validator. The local M3
artifact proves a measured historical transform on synthetic vectors; it does
not prove raw WAV structure, all initial formats or initial dispatch wiring.

## Closed structural contract

Introduce the internal validator identity `initial-wav-structure-v1` in a new
measured implementation. The first implementation is a pure bounded validator
with focused vectors. It does not replace `audio-spec/wav.ts` or wire itself
into live handlers, `prepareInitialAdmission`, existing admitted configuration
or the historical M3 artifact in the same increment.

The caller checks the raw byte limit and takes a private byte snapshot before
any asynchronous boundary. The synchronous API
`inspectInitialWavStructure(source: Uint8Array<ArrayBuffer>): InitialWavStructure`
consumes exactly that view's offset and length, never the whole `source.buffer`.
Shared backing storage is rejected at runtime. It returns a frozen object with
only these primitive fields: `format`, `bits`, `channels`, `rate`, `blockAlign`,
`byteRate`, `dataOffset`, `dataLength`, `frameCount`. No byte view or source
reference escapes. Offsets are relative to the supplied view. The function never
repairs, strips, reorders or normalizes the source. Its metadata alone cannot
authorize transformation of a separately supplied mutable buffer; later
integration must transform the same caller-owned private snapshot.

Structural acceptance is distinct from transformation admission. A valid rate or
channel count can still exceed existing work/output budgets or fail the
minimum-duration rule. Compatibility tests only compare transformed outputs for
vectors admitted by those existing budgets.

1. Require at least 44 bytes and at most 2,700,000 bytes, `RIFF` and `WAVE`, and
   exact equality between the RIFF declared extent plus its eight-byte header
   and the available source. No bytes outside that extent are accepted.
2. Walk every top-level chunk, including chunks following audio data. Check the
   full eight-byte chunk header, payload extent and required odd-size alignment
   padding before reading payload fields. Every iteration advances by at least
   eight bytes. Iteration count is naturally bounded by the source byte cap; do
   not add an arbitrary chunk-count cap that rejects otherwise valid input.
3. Require exactly one `fmt` chunk before exactly one `data` chunk. Reject
   duplicates and missing required chunks. Unknown chunks are skipped only after
   their outer extent is validated; their payload is opaque metadata, not
   recursively interpreted media. Padding bytes are not audio samples and need
   not have a specific value. A partial trailing chunk header is invalid.
4. `fmt` must contain at least the 16-byte common prefix. Preserve the current
   decoder's compatibility with bounded extra fmt bytes; these bytes remain
   opaque and cannot select a different encoding. Accept only the existing pairs
   `(format 1, 16 bits)` and `(format 3, 32 bits)`. RF64, RIFX, extensible and
   compressed formats remain unsupported; this is not a claim of universal WAV
   conformance.
5. Require nonzero channels and sample rate. Compute bytes per sample, frame
   width and byte rate with safe integer arithmetic. Frame width must fit its
   16-bit field and equal block alignment; sample rate times frame width must
   fit its 32-bit field and equal byte rate. Require nonempty audio data whose
   length is divisible by frame width. This also prevents fractional PCM/float
   samples and silently discarded partial interleaved frames.
6. For float32, check every source sample is finite before downmix/trim, so
   non-finite values cannot disappear in ignored or trimmed portions. Finite
   values outside [-1, 1] retain current transform/clamping behavior; do not
   silently introduce amplitude normalization or a new range restriction.

These are Merian's agreed deterministic safety rules. They intentionally reject
malformed size/alignment/duplicate/non-finite cases that the current permissive
parser can sometimes tolerate. Bounded opaque metadata, existing PCM/float
encodings, valid rates/channels and transform semantics remain compatible.
Microsoft documents the shared
[WAVEFORMATEX frame fields](https://learn.microsoft.com/en-us/windows/win32/api/mmreg/ns-mmreg-waveformatex)
and
[RIFF chunk structure](https://learn.microsoft.com/en-us/windows/win32/multimedia/resource-interchange-file-format-services);
our extension-byte/metadata handling is an explicit local compatibility policy.

## Binding and later integration

`_shared/initialAnalysis/preparation.ts:prepareInitialAdmission` is the existing
consumed-byte binding point: it copies source bytes before awaiting, compares
source length/digest, transforms the exact source with frozen options, and
compares resulting consumed bytes to the immutable declared length/digest. That
contract must remain intact when the new validator is integrated later.

Before integration, build and qualify a new measured closure containing this
validator plus the exact decoder, downmix, trim, resampler, encoder and options
adapter. Give it its own immutable source/archive/configuration/artifact tuple
and selector entry. Preserve the accepted historical archive/artifact and all
previous tuples. A saved tuple never resolves to current sources or a newer
validator. Do not silently strengthen the implementation behind an already
admitted identity, even in the fresh-library alpha.

Validation and transformation must consume the same private snapshot. Admission
must bind its original source identity and exact consumed output, including
ordered media/clip association and short-video policy. An unavailable validator
or missing measured implementation holds before dispatch; a signature-only
receipt cannot authorize processing. No new DTO, accounting owner, retry,
provider invocation or refund mechanism is introduced here.

Other admitted image/video formats remain separately unqualified for structural
and decoded safety. JPEG/PNG and MP4 history validators are profile-specific;
HEIC/WebP need a compatible bounded decoder. `audio/mp4` staging permission does
not make it a supported initial audio transform. Maintain this explicit matrix
until each supported initial format has its own verified validator/decoder.
Current live handlers are unchanged; these holds apply to the inactive new IC-1
path before any future coordinated activation.

## Required boundary vectors

Use a valid WAV subarray surrounded by malicious prefix/suffix bytes to prove
view isolation. Cover RIFF size including the final alignment byte; missing odd
padding on unknown chunks before and after data; valid unknown chunks after
data; a `fmt` payload shorter than 16 bytes; and NaN, positive infinity and
negative infinity in both first and non-first channels, including samples that
trimming could otherwise discard. Source-copy mutation/race tests belong to
later integration; this pure synchronous increment proves exact-view parsing.

## Acceptance matrix

| Row                             | Owner                                  | Pass condition                                                                                                                                                                                                                          |
| ------------------------------- | -------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Initial compatibility           | History primary; initial-engine review | PCM16/float32, mono/stereo/multichannel, representative 8/16/32/44.1/48/96 kHz sources and bounded extra/odd metadata pass structural validation; existing transform output remains byte-identical for accepted vectors.                |
| Structural rejection            | History primary; independent review    | Truncated/overflowing RIFF/chunks/fmt, bad padding extent, duplicate/misordered required chunks, invalid format/channel/rate/frame/byte-rate, fractional/empty data and NaN/Infinity reject deterministically before decode allocation. |
| Work and memory                 | History primary                        | Raw length checked before copy; chunk/sample iteration bounded by source bytes; no unbounded allocation, recursion or rate-derived allocation in the pure validator.                                                                    |
| Source binding                  | History primary                        | Private-copy mutation/race tests; validation and later transform use identical copied bytes, original manifest/options and independently checked consumed digest.                                                                       |
| Measured implementation         | History primary; initial-engine review | New reviewed source/closure/tuple, reproducible artifact and executed vectors; old M3 bytes and saved admission identities unchanged.                                                                                                   |
| Candidate gates                 | History primary; independent re-review | Focused tests plus complete affected Edge/tooling/contract gates for the actual implementation increment, exact hashes and preserved failures.                                                                                          |
| Initial/hosted/device readiness | Separate owners and authorization      | Still open: all required media validators, full S0, dispatch/result/completion/route recovery, installed journeys and hosted qualification; local validator tests cannot close these rows.                                              |

No merge, push, deployment, scheduling of hosted workers, activation, device
installation or distribution is authorized. This thread's continuation heartbeat
may progress the approved internal checkpoints after independent acceptance.
