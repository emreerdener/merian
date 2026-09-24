# Audio processing comparison — completed benchmark

Date: 23 September 2026 (America/Chicago; retained timestamps are UTC)\
Status: all twelve slots admitted across two execution segments; hosted
comparison setting removed and absence verified

The six paired sources are complete. Stream, thunder and car alarm returned **No
wildlife detected** with both processors. The animal results do not establish an
identification improvement: the raven pair differed, while both processors
returned the same source-label disagreements for elk and frog. All requests used
Gemini 2.5 Pro.

The
[completed sanitized record](./identification-evaluation-evidence/2026-09-23-audio-processing-comparison/completed-results.json)
contains all twelve admitted outcomes and their evidence bindings. The original
[partial report](./identification-audio-processing-comparison-2026-09-23.md) and
[seven-result record](./identification-evaluation-evidence/2026-09-23-audio-processing-comparison/app-results.json)
remain unchanged. This completes the frozen exploratory comparison; it does not
qualify a model or establish general accuracy.

## Method and continuation

The
[frozen assignment plan](./identification-audio-comparison-assignment-2026-09-23.md)
compares `audio-linear-full-windows-v1` (legacy) with
`audio-sinc-partial-tail-v1` (current). The current arm combines anti-alias
filtering with partial-tail measurement; this experiment cannot isolate their
individual effects. The source WAV, minimal request context, model, policy and
confidence settings remained fixed by each assignment. No species label,
description or image was added to the request.

Slots 1–7 ran in the original segment. After an unexpected app replacement, the
run stopped before submitting slot 8 and the hosted setting was removed. The
continuation restored the exact frozen app from a clean isolated worktree:

- App version 1.0.3, build 275; iPhone 18 Pro simulator, iOS 27.0.
- App source: `fdfb142b6fcb96e6ae8f3c46a561015064c93cd2`, clean.
- App fingerprint:
  `ebfa958011ec4e61dda121eea6b9d00890b67d23099dedf1612372aa5cbdb3df`.
- Backend bundle:
  `a5939b36fd43dcf1fbfb7f5ee01875d3888a313e66af8756e79fb04f19694b2c`.
- Plan: `fc30d6c938d000b2ecb994509e63b0f8e129bc5dfcb2a914a3517c8cbd4fc213`.
- Preparation:
  `42350d978486e1a9edb409065be163b45f2d01d1182042b3e48f318e7ed43681`.

The restored Debug build and signature checks passed. A normal launch recovered
the existing authenticated session and freshly synchronized consent. A private,
read-only check tied that account to all seven completed reserved jobs, verified
their original observation timestamps, and found no jobs for slots 8–12. The
same check ran before each subsequent slot and verified all twelve completed
jobs at the end. Only counts and equality checks are retained; private account
and scan identifiers are omitted. No uninstall, account reset or replay of a
consumed assignment was performed.

The continuation submitted only slots 8–12, in frozen order. Every submitted
slot had one ordinary Identify tap after the passive observer reported ready, a
full 120-second observation window, nine projected events and successful offline
admission. Each had one fresh HTTP 200 measurement, matching receipt,
finalization and first-render proofs, and native persistence `saved`. There were
no manual retries or overlapping observation windows. App restarts between
completed slots restored the replay control, verified the same account and
current consent, and occurred outside tap-to-result timing.

The two segments are explicitly retained. In particular, the stream pair spans
the interruption and restoration; it is not an uninterrupted paired session. The
earlier empty lock-screen and pre-submission slot-8 windows remain excluded
historical evidence, not additional model outcomes.

## First visible outcomes

Animal references below are provisional source labels. The owner reviewed the
three controls as containing no animals, and all six sources as containing no
speech, spoken labels or personal information.

| Slot | Source reference         | Arm     | First visible result                   | Displayed match | Native confidence | Tap to first frame |
| ---- | ------------------------ | ------- | -------------------------------------- | --------------- | ----------------: | -----------------: |
| 1    | Common Raven             | Legacy  | Common Raven, _Corvus corax_           | Strong          |              0.95 |           17.547 s |
| 2    | Common Raven             | Current | American Crow, _Corvus brachyrhynchos_ | Strong          |              1.00 |           15.181 s |
| 3    | Elk                      | Current | Red Fox, _Vulpes vulpes_               | Strong          |              0.95 |           16.880 s |
| 4    | Elk                      | Legacy  | Red Fox, _Vulpes vulpes_               | Strong          |              0.95 |           19.390 s |
| 5    | American Green Tree Frog | Legacy  | Snow Goose, _Anser caerulescens_       | Strong          |              0.95 |           17.814 s |
| 6    | American Green Tree Frog | Current | Snow Goose, _Anser caerulescens_       | Strong          |              0.95 |           19.586 s |
| 7    | Stream                   | Current | No wildlife detected                   | Non-biological  |              1.00 |           13.771 s |
| 8    | Stream                   | Legacy  | No wildlife detected                   | Non-biological  |              1.00 |           16.344 s |
| 9    | Thunder                  | Legacy  | No wildlife detected                   | Non-biological  |              1.00 |           14.933 s |
| 10   | Thunder                  | Current | No wildlife detected                   | Non-biological  |              1.00 |           13.902 s |
| 11   | Car alarm                | Current | No wildlife detected                   | Non-biological  |              1.00 |           17.295 s |
| 12   | Car alarm                | Legacy  | No wildlife detected                   | Non-biological  |              1.00 |           11.387 s |

The first outcomes were preserved without correction or selective retries.
Native confidence is the admitted finalization value; neither it nor the
displayed match is a calibrated probability. Agreement with the three reviewed
controls does not establish a general false-positive rate. The provisional
animal labels do not support an accuracy score.

## Timing and observed cost

Tap-to-first-frame ranged from **11.387 to 19.586 seconds**, with an overall
median of **16.612 seconds**. Legacy and current medians were **16.9455** and
**16.0305 seconds** respectively. These are descriptive measurements from one
outcome per source and arm, not a repeatable speed claim.

| Source                  | Current minus legacy, tap to first frame | Current minus legacy, primary estimate |
| ----------------------- | ---------------------------------------: | -------------------------------------: |
| Raven                   |                                 −2.366 s |                            −$0.0014250 |
| Elk                     |                                 −2.510 s |                            −$0.0047700 |
| Frog                    |                                 +1.772 s |                            +$0.0027775 |
| Stream, across segments |                                 −2.573 s |                            −$0.0067050 |
| Thunder                 |                                 −1.031 s |                            −$0.0025350 |
| Car alarm               |                                 +5.908 s |                            +$0.0099325 |

The median paired timing difference was **−1.6985 seconds**. Four current-arm
observations were faster and two were slower; provider variability, the small
sample and the stream session gap prevent attributing these differences to audio
processing. Provider, Edge and app timings overlap and must not be added as
separate stages. Each underlying timing and token count is in the completed
record.

The twelve observed primary-attempt estimates total **$0.2952300**: $0.1764250
from the original segment and $0.1188050 from the continuation. They use the
unchanged [Gemini pricing](https://ai.google.dev/gemini-api/docs/pricing)
snapshot retrieved at `2026-09-23T22:35:58.637Z`: $2.50 per million input tokens
and $15 per million candidate-plus-thinking output tokens, without a cache
discount. This is an estimate of observed primary attempts, not an invoice or
total cost; other attempts, enrichment, storage and transport are outside its
scope. The passive tools' zero automatic-submission counters do not mean zero
paid calls: twelve UI submissions were made.

## Activation and verified removal

The continuation used control source `fc8995430b6251ffaf8fc17c866181e470c6f8d0`.
The protected
[activation workflow](https://github.com/emreerdener/merian/actions/runs/35954744408)
passed complete exact-candidate validation and verified the deployed source
`9d7900d25c0f280685d4519554f4ac8fedafdae2` against the unchanged frozen backend
bundle. These control and deployment revisions are separate from the admitted
frozen app identity.

The same owner, plan and stable assignments received a two-hour continuation
window, `2026-09-24T04:13:19.210Z` through `06:13:19.210Z`. Activation was
verified at `04:19:33.261Z`. The five continuation observation windows ran from
`04:20:29.767Z` through `04:35:12.863Z` (11:20–11:35 PM Chicago on 23
September). The seven consumed assignments were never reset or repeated.

The
[deactivation workflow](https://github.com/emreerdener/merian/actions/runs/35956296002)
removed `IDENTIFICATION_AUDIO_COMPARISON_V1` from Supabase project
`qlarqavoqhkuwzmevrmf` and verified absence at `2026-09-24T04:35:52.631Z`:
`status: disabled`, `configurationPresent: false`, `cleanup: verified_absent`,
`failure: null`. The cleanup evidence binds the same plan, bundle and window as
activation. The separate private GitHub configuration was not deleted. Ordinary
Gemini routing and current production audio processing remain unchanged.

## Interpretation and next milestone

Keep the current deterministic audio-processing correction. This comparison does
not establish a quality benefit or justify a rollback, provider switch, prompt
change or confidence-threshold change. Both processors recognized these three
non-animal controls, but the animal disagreements remain unresolved.

The next useful milestone is an independently verified audio reference set:
resolve the raven, elk and frog labels, then broaden the corpus under a new
reviewed plan before comparing model quality. Preserve these first outcomes as
the baseline. A future repeatability experiment needs new assignments and a
predefined repetition policy; consumed slots must not be reused to seek better
answers. Provider flexibility can use this evidence pipeline when another
service is ready, but no other provider was evaluated here.

Formal qualification remains **0/60 development and 0/240 held-out groups**. Six
paired clips are six source groups, not twelve independent groups. Public
training exposure is unknown. This simulator replay does not measure physical
microphone capture, calibrated confidence or general identification accuracy.

## Retention and verification

The completed record preserves the original seven results verbatim, binds the
original record's file hash, and lists a 77-file private source manifest across
the original, continuation and continuation-control packets. Retention remains
through 23 October 2026, with directory mode 0700 and file mode 0600. No private
owner or scan identifiers, auth state, raw coordinates, media or provider
response bodies are published.

Each slot passed the canonical offline admission command. Report assembly
verified the canonical frozen-plan digest, original forty-file manifest,
unchanged expectations and pricing, assignments, source and observation hashes,
app/backend identities, nine-event proof completeness, window order, activation
and cleanup bindings, token totals and cost arithmetic. Visible labels are
supplemental UI observations; their hashes preserve those observations but do
not cryptographically bind biological labels to the admitted measurement. The
authenticated receipt joins measurement to native finalization and rendering; it
is not independent biological review.

The exact frozen Debug simulator rebuild and protected full backend candidate
gate passed during restoration and activation. No additional native or backend
runtime suite was rerun for this evidence-only report.

Independent read-only review found no actionable issues in the completed
records, 77-file manifest, evidence joins, arithmetic, privacy projection or
interpretation. Changed Markdown formatting, local link targets and
`git diff --check` passed. Unrelated map work in the shared checkout was
preserved.
