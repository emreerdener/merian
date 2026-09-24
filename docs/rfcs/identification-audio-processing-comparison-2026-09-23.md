# Audio processing comparison — partial benchmark

Date: 23 September 2026 (America/Chicago; retained timestamps are UTC)\
Status: seven of twelve slots admitted; stopped before slot 8; hosted setting
removed and absence verified

The three completed animal pairs do not establish an identification improvement
from the current audio processor. Raven produced different species between arms;
elk and frog produced the same source-label disagreements in both arms. The
current processor returned **No wildlife detected** for stream, but its legacy
pair remains unsubmitted. All seven results used Gemini 2.5 Pro.

The
[sanitized benchmark record](./identification-evaluation-evidence/2026-09-23-audio-processing-comparison/app-results.json)
retains each admitted assignment, execution identity, native outcome, first
visible label, measurement, proof join, observation hash, cost estimate and
control evidence. This is a partial exploratory comparison, not a completed
twelve-slot benchmark or a qualification result.

## Method and execution identity

This run follows the frozen
[assignment plan](./identification-audio-comparison-assignment-2026-09-23.md)
and
[app/observer integration](./identification-audio-comparison-app-integration-2026-09-23.md).
Legacy means `audio-linear-full-windows-v1`; current means
`audio-sinc-partial-tail-v1`. The latter combines anti-alias filtering with
partial-tail measurement, so this experiment cannot isolate those changes.
Ordinary production continues to use the current processor.

The six sources are unchanged from the
[reviewed preparation](./identification-audio-six-preparation-2026-09-22.md).
The owner confirmed no speech, spoken species labels or personal information,
and no audible animals in the three controls. Animal species references remain
provisional. Only the exact frozen WAV was staged, with no source label,
expected species, image or description entered into the identification request.
Both arms use the fixed `audio-minimal-v1` context.

Each submitted slot used Debug replay staging followed by one ordinary Identify
tap after the passive observer reported ready. Slots ran in frozen order, with
one complete 120-second observation window plus collector shutdown per slot.
There were no manual retries or overlapping windows. Each of the seven windows
retained nine projected events, including one fresh HTTP 200 measurement and
matching receipt, finalization and first-render proofs. Every native outcome
reported `saved`; this includes the non-biological stream result.

The admitted app is version 1.0.3, build 275, on iPhone 18 Pro / iOS 27.0:

- App source: `fdfb142b6fcb96e6ae8f3c46a561015064c93cd2`, clean.
- App fingerprint:
  `ebfa958011ec4e61dda121eea6b9d00890b67d23099dedf1612372aa5cbdb3df`.
- Backend bundle:
  `a5939b36fd43dcf1fbfb7f5ee01875d3888a313e66af8756e79fb04f19694b2c`.
- Plan: `fc30d6c938d000b2ecb994509e63b0f8e129bc5dfcb2a914a3517c8cbd4fc213`.
- Preparation:
  `42350d978486e1a9edb409065be163b45f2d01d1182042b3e48f318e7ed43681`.

The control workflow source was `9d7900d25c0f280685d4519554f4ac8fedafdae2`. This
tooling revision shares the same frozen runtime bundle; it is separate from the
admitted installed app identity. Requested and returned models were
`gemini-2.5-pro` throughout.

Closing a result again left Debug replay disabled. Restarting the same app
restored capture before subsequent staging; fresh synchronization verified the
same account and current consent. These restarts did not reset data and are
outside tap-to-result timing. No private account identifier is retained here.

## First visible outcomes

| Slot | Source reference                                | Arm     | First visible result                   | Displayed match | Native confidence | Tap to first frame |
| ---- | ----------------------------------------------- | ------- | -------------------------------------- | --------------- | ----------------: | -----------------: |
| 1    | Common Raven, _Corvus corax_                    | Legacy  | Common Raven, _Corvus corax_           | Strong          |              0.95 |           17.547 s |
| 2    | Common Raven, _Corvus corax_                    | Current | American Crow, _Corvus brachyrhynchos_ | Strong          |              1.00 |           15.181 s |
| 3    | Elk, _Cervus canadensis_                        | Current | Red Fox, _Vulpes vulpes_               | Strong          |              0.95 |           16.880 s |
| 4    | Elk, _Cervus canadensis_                        | Legacy  | Red Fox, _Vulpes vulpes_               | Strong          |              0.95 |           19.390 s |
| 5    | American Green Tree Frog, _Dryophytes cinereus_ | Legacy  | Snow Goose, _Anser caerulescens_       | Strong          |              0.95 |           17.814 s |
| 6    | American Green Tree Frog, _Dryophytes cinereus_ | Current | Snow Goose, _Anser caerulescens_       | Strong          |              0.95 |           19.586 s |
| 7    | Stream; reviewed non-biological                 | Current | No wildlife detected                   | Non-biological  |              1.00 |           13.771 s |

These are first outcomes, preserved without correction or selective retries.
Native numerical confidence comes from the admitted finalization event; it was
not inferred from the UI label. Neither value is a calibrated probability.
Species agreement and disagreement refer only to provisional source labels. The
unpaired stream outcome agrees with its reviewed non-biological class; it does
not establish a general false-positive rate.

## Timing and cost

| Slot | Provider call | Edge total | Primary estimate, USD |
| ---- | ------------: | ---------: | --------------------: |
| 1    |     11.5839 s |  13.1799 s |            $0.0230950 |
| 2    |     11.5020 s |  12.8401 s |            $0.0216700 |
| 3    |     13.1023 s |  14.5686 s |            $0.0245150 |
| 4    |     15.3515 s |  16.8255 s |            $0.0292850 |
| 5    |     14.1121 s |  15.3149 s |            $0.0279175 |
| 6    |     15.0702 s |  16.6815 s |            $0.0306950 |
| 7    |      9.9055 s |  11.7532 s |            $0.0192475 |

Across all seven observations, tap-to-first-frame ranged from **13.771 to 19.586
seconds**, with a median of **17.547 seconds**. The three matched animal pairs
had legacy and current medians of 17.814 and 16.880 seconds respectively.
Current-minus-legacy differences were −2.366 seconds for raven, −2.510 for elk
and +1.772 for frog. These are descriptive observations from one result per arm;
they do not demonstrate a repeatable speed improvement or processing overhead.
The unpaired stream result is excluded from those paired comparisons. Provider,
Edge and app timings overlap and must not be summed as separate stages.

The seven observed primary-attempt estimates sum to **$0.1764250**. They use the
reviewed [Gemini pricing](https://ai.google.dev/gemini-api/docs/pricing)
snapshot retrieved at `2026-09-23T22:35:58.637Z`: a conservative $2.50 per
million input tokens and $15 per million candidate-plus-thinking output tokens.
No cache discount is applied. This is not an invoice or total cost: other
attempts, enrichment, storage and transport are outside the observer's
accounting scope. The tools' `automaticSubmissions: 0` fields describe passive
collection and offline admission; seven actual UI submissions were made.

## Interruption and verified cleanup

The approved second window was `2026-09-24T02:20:08.261Z` through
`2026-09-24T04:20:08.261Z` (9:20–11:20 PM Chicago on 23 September).
[Activation](https://github.com/emreerdener/merian/actions/runs/35946828135)
completed validation and verified the setting active at
`2026-09-24T02:27:22.672Z`. The seven admitted observations ran from
`02:28:11.615Z` through `02:53:05.599Z`.

Slot 8 was staged and its observer became ready, but Identify was never tapped.
That window closed normally at `02:56:51.222Z` with zero projected events.
Inspection then found an empty capture workspace and a replaced app: source
`9d7900d25c0f280685d4519554f4ac8fedafdae2`, dirty, fingerprint
`9dcfe63e78e5cec8b701368f7bad937be1fd4714dec7941952cb0c62fb69248c`. The new
binary does not match the frozen app expectation. No request was submitted from
it, and no result or admission was invented for the empty window. The exact
installation time and initiating process were not established. The unsubmitted
classification uses the preserved no-tap UI/interruption record together with
the empty window; zero projected events alone would not prove zero calls.

The run stopped. The authorized
[deactivation](https://github.com/emreerdener/merian/actions/runs/35949585331)
removed `IDENTIFICATION_AUDIO_COMPARISON_V1` from Supabase project
`qlarqavoqhkuwzmevrmf` and verified absence at `2026-09-24T03:00:26.832Z`:
`status: disabled`, `configurationPresent: false`, `cleanup: verified_absent`,
`failure: null`. The private GitHub configuration is separate from this hosted
setting; verified hosted removal does not claim deletion of the GitHub secret.
Ordinary Gemini routing and audio processing remain unchanged.

An earlier zero-event window, before the first submission, was blocked by the
Mac lock screen. It remains excluded historical evidence. Neither empty window
is a model failure, admitted outcome or consumed comparison assignment.

## Remaining work and interpretation

Slots 1–7 are consumed and must not be repeated. Slots 8–12 remain unsubmitted:
legacy stream, legacy/current thunder and current/legacy car alarm. Preserve
this partial segment and its interruption record. Before any continuation,
reserve a simulator against other installs/tests, restore and verify the exact
frozen app and same authenticated account, reconcile the unused assignments, and
satisfy the runbook's activation and bounded-window requirements. Do not
silently substitute the newly installed binary, reset consumed slots or merge a
later session into an uninterrupted run. A new experiment requires a reviewed
new plan and regenerated bindings.

Keep the deterministic audio-processing correction separate from any claim of
identification improvement. These results do not justify a rollback, prompt or
confidence-threshold change, or a provider selection. Complete the remaining
controls under stable execution conditions, then prioritize independent
reference review and a broader corpus before judging model quality. One raven
pair cannot distinguish processing effects from provider variability; the
repeated elk/frog disagreements warrant investigation of source identity and
model behavior without changing their recorded outcomes.

Formal qualification remains **0/60 development and 0/240 held-out groups**. The
set has three complete pairs and one unpaired control, with unknown
public-source training exposure. It does not measure physical microphone
capture, calibrated confidence, general accuracy or a different provider.

## Retention and verification

The private source packet is retained through 23 October 2026 with directory
mode 0700 and file mode 0600. The sanitized record contains a manifest of the
exact observation, admission, expectation, input and visible-outcome file
hashes. Original observer files and prior benchmarks remain unchanged. The
receipt is an authenticated backend claim joined locally to native finalization
and rendering; it is not independent biological review or a standalone
cryptographic attestation of the provider. Visible species labels are
supplemental slot-labelled UI observations. Their file hashes preserve those
observations, but do not cryptographically join the labels to the admitted
measurement; the authenticated render proof supplies the admission's rendering
evidence.

Each slot passed canonical offline admission when its complete window closed.
Report assembly additionally checked frozen assignments, source hashes, app and
backend identity, nine-event proof completeness, window order, activation
boundaries, token totals and cost arithmetic. The slot-8 empty observation and
successful cleanup are retained separately. The report and JSON are evidence
only; no native or backend runtime suite was rerun for their preparation.

Independent read-only review found no actionable issues in the seven records,
forty-file source manifest, arithmetic, privacy projection or partial-run
claims. Changed Markdown formatting, local link targets and `git diff --check`
passed. Unrelated map work in the shared checkout was preserved.
