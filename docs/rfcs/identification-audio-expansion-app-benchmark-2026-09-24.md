# Expanded audio app benchmark

Date: 24 September 2026 (America/Chicago; retained timestamps are UTC)\
Status: six first results and six complete observation windows; exploratory
evidence only

The reviewed **rain control returned Snowy Tree Cricket with a Strong match**.
Chainsaw returned **No wildlife detected**. Among the four animal recordings,
geese and coyote agreed with their provisional source species; robin and pig
frog disagreed. All five biological results displayed Strong matches. These
first outcomes are preserved without retries or reference changes.

All six submissions used the ordinary app and Gemini 2.5 Pro. The
[sanitized benchmark record](./identification-evaluation-evidence/2026-09-24-audio-reference-expansion/app-results.json)
retains the results, bounded measurements, estimates and file bindings. The
[source audit and preparation](./identification-audio-reference-expansion-2026-09-24.md)
and its earlier pending-review freeze remain unchanged. No provider assignment,
prompt, confidence policy or deployment changed.

## Admission and method

The owner listened to the exact 34.153-second reel and confirmed that all six
clips were audible and distinct, contained no speech, spoken labels or personal
information, and contained no audible animals in the rain and chainsaw segments.
The review was recorded at `2026-09-24T05:18:00.501Z` and bound to the reel and
all six case IDs. This completed exploratory media eligibility; it did not
independently verify the four animal species.

A separate admitted packet preserved every prepared input hash. Canonical
offline preflight passed for six audio groups and twelve prepared requests
across the existing Flash and Pro profiles. None of those requests was
dispatched. The ordinary-app plan froze six first submissions, one per case in
`c0019`–`c0024` order, with no model override, manual retries, overlapping
windows or reuse of consumed processing-comparison slots.

Each reviewed WAV was copied to the simulator's ordinary replay inbox. **Debug
replay → Stage audio sample** staged the sole input, and one normal **Identify**
tap followed observer readiness. No source name, expected name, description or
image was entered as evidence. The same app was restarted before each case to
restore the empty capture workspace; private checks verified unchanged app
identity, signature and current session-bound consent after each restart. No
account reset or reinstall occurred. These preparations are outside the measured
tap-to-result interval.

The observed app was version 1.0.3, build 275, on iPhone 18 Pro / iOS 27.0:

- Clean embedded app source: `fdfb142b6fcb96e6ae8f3c46a561015064c93cd2`.
- App fingerprint:
  `ebfa958011ec4e61dda121eea6b9d00890b67d23099dedf1612372aa5cbdb3df`.
- Expected and observed backend bundle:
  `a5939b36fd43dcf1fbfb7f5ee01875d3888a313e66af8756e79fb04f19694b2c`.
- Requested and returned model: `gemini-2.5-pro` for every response.

The backend fingerprint was checked against the earlier completed benchmark and
every fresh response; it is not an independent pre-submission deployment check.
The evaluator checkout identity is retained separately in preflight and does not
attest the installed app.

Ordinary replay retains live submission context and its production transcoder.
Every observed measurement-v2 record has **`contextProfile: null`**. No fixed
context, comparison handle, numbered assignment, authenticated comparison
receipt or comparison-only persistence/render proof is claimed. The hosted
comparison setting was not reactivated.

## First visible outcomes

| Case    | Source reference                               | First visible result                     | Displayed match | Tap to first frame |
| ------- | ---------------------------------------------- | ---------------------------------------- | --------------- | -----------------: |
| `c0019` | American Robin, _Turdus migratorius_           | Northern House Wren, _Troglodytes aedon_ | Strong          |           16.721 s |
| `c0020` | Canada Goose, _Branta canadensis_              | Canada Goose, _Branta canadensis_        | Strong          |           16.939 s |
| `c0021` | Coyote, _Canis latrans_                        | Coyote, _Canis latrans_                  | Strong          |           16.908 s |
| `c0022` | Pig Frog, _Lithobates grylio_                  | Green Frog, _Lithobates clamitans_       | Strong          |           17.194 s |
| `c0023` | Rain; source/owner-reviewed non-biological     | Snowy Tree Cricket, _Oecanthus fultoni_  | Strong          |           14.418 s |
| `c0024` | Chainsaw; source/owner-reviewed non-biological | No wildlife detected                     | Non-biological  |           15.096 s |

The rain result disagrees with a control reviewed before prediction. That
observation remains in the dataset; it was not retried, excluded or relabelled
after seeing the answer. Two controls cannot establish a general false-positive
rate. The animal references remain provisional, so neither their agreements nor
disagreements support an accuracy score. The visible Strong label is not a
calibrated probability, and native numerical confidence remains unknown for
these ordinary replay results.

## Measurements and cost

All six 120-second observation windows closed normally within the 30-second
shutdown grace, with six projected events each and no overlap. They ran from
`05:23:08.349Z` through `05:41:38.176Z` (12:23–12:41 AM Chicago). Every case had
one fresh HTTP 200 response, valid provider/Edge timing, a matching model and
app/backend identity, and one tap-to-first-rendered-frame event. The nonvisual
path emits no visual-preflight marker; that missing interval is not zero.

| Case    | Provider call | Edge total | App pipeline | Primary estimate, USD |
| ------- | ------------: | ---------: | -----------: | --------------------: |
| `c0019` |     13.0022 s |  14.3700 s |     15.700 s |            $0.0228650 |
| `c0020` |     13.3613 s |  14.6727 s |     15.432 s |            $0.0249575 |
| `c0021` |     13.3291 s |  14.5850 s |     16.066 s |            $0.0249025 |
| `c0022` |     13.8063 s |  15.0761 s |     16.470 s |            $0.0249850 |
| `c0023` |     11.1197 s |  12.3417 s |     13.620 s |            $0.0198075 |
| `c0024` |     11.9069 s |  13.1292 s |     14.502 s |            $0.0254375 |

Tap-to-first-frame ranged from **14.418 to 17.194 seconds**, with a median of
**16.8145 seconds**. These are descriptive timings for six different sources.
Provider, Edge and pipeline intervals overlap and must not be added together.

Observed primary-attempt estimates total **$0.1429550**. They use the unchanged
[Gemini pricing](https://ai.google.dev/gemini-api/docs/pricing) snapshot
retrieved at `2026-09-23T22:35:58.637Z`, within the seven-day freshness limit:
$2.50 per million input tokens and $15 per million candidate-plus-thinking
output tokens, without a cache discount. These estimates exclude enrichment,
other or unobserved attempts, storage and transport; they are not a complete
bill or a spending cap. Six UI submissions were made. Zero direct-evaluator
calls and the passive observer's zero automatic-submission counter do not mean
zero paid calls.

## Interpretation and next step

This expands the operational Gemini baseline and adds a reviewed control that
elicited a confident biological answer. Keep the rain case in future candidate
evaluations and review its audio/reference boundary before choosing an audio
rejection or confidence intervention. Independently establish animal references
before scoring species quality. No alternative provider was evaluated.

The earlier raven, elk and tree-frog audit reproduced their inputs exactly but
left species identity unresolved. The new robin and pig-frog disagreements add
questions for reference review; they do not justify selecting a different model,
changing thresholds or claiming a preprocessing improvement. A new paired or
repeatability study requires its own frozen plan and matching context. Do not
pool this ordinary-context run with the prior fixed-context processing arms as
though they were controlled repetitions.

Formal progress remains **0/60 development and 0/240 held-out groups**, with
zero independent biological reviewers. Public training exposure is unknown.
Source hashes verify staged files, not the app's complete inference bytes or
live context. Case association follows sequential UI actions; displayed species
labels are supplemental observations, not cryptographically bound truth. This
run does not measure physical microphone capture or prove native persistence.

## Evidence and verification

The preparation freeze retains 29 files. The admitted input freeze retains 28
files and has hash
`26d64f587217d40714c47891414a843477512746bcb74a17186fec931f0079c2`. The
completed private packet retains 64 files, with freeze hash
`88b76f5e3039a00cf339e7c23b2907cc9436af242f6fa2abace8cef0c2ec474c`, directory
mode 0700, file mode 0600 and retention through 24 October 2026. Earlier packets
retain their original retention dates.

The benchmark record explicitly maps the source audit's file hashes to the
checked-in comparison preparation and completed-results paths. Its canonical
comparison preparation digest remains
`42350d978486e1a9edb409065be163b45f2d01d1182042b3e48f318e7ed43681`; canonical
JSON digests and formatted-file hashes are distinct bindings.

Validation checked the frozen files, unchanged inputs, owner eligibility,
canonical preflight digest, chronological and nonoverlapping windows, first
outcomes, execution identity, token totals and cost arithmetic. The repository's
measurement and pricing parsers revalidated all six observations with network
and environment access denied. The retained records exclude raw OS logs,
provider prose, actual app context, account/scan identifiers and credentials.
Media remains outside Git. No native or backend runtime suite was rerun for this
evidence-only update, and unrelated map work remains untouched.
