# Audio confidence V2 app benchmark

Date: 24 September 2026 (America/Chicago; retained timestamps are UTC)\
Status: six first results and six complete observation windows; exploratory
evidence

Follow-up on 24 September: the
[disputed-reference review](./identification-audio-disputed-reference-review-2026-09-24.md)
verified the robin and pig-frog source/input bindings without resolving audible
species. Its prospective diagnostic-use decision leaves every outcome and
measurement below unchanged.

This is the first fixed-context six-clip pass after the
[audio confidence V2 deployment](../release-evidence/identification-audio-confidence-v2-deployment-2026-09-24.md).
All six fresh responses matched the deployed runtime and the frozen app/model
identity. The
[sanitized benchmark record](./identification-evaluation-evidence/2026-09-24-audio-confidence-v2/app-results.json)
retains every first outcome, its bounded measurement, timing and primary cost
estimate. No clip was retried or relabelled after prediction.

## Method and identity

The owner had already reviewed the exact six clips as audible and distinct,
without speech, spoken labels or personal information, and with no audible
animals in rain or chainsaw. The new packet copied those files byte-for-byte
from the
[prior admitted benchmark](./identification-audio-expansion-app-benchmark-2026-09-24.md).
The four animal species references remain provisional, with zero independent
biological reviewers. The original evidence and results remain unchanged.

The plan froze at `2026-09-24T14:45:06.819Z` after successful deployment, before
any new identification. Cases ran in `c0019`–`c0024` order with one normal app
Identify tap each, no provider override, no manual retries and no overlapping
windows. Each 120-second passive observation window closed normally within the
30-second shutdown grace. Before each case, the same signed app was restarted
and its unchanged identity, current consent/session ownership and exact staged
asset hash were checked privately. No account reset or reinstall occurred.

**Debug replay → Stage audio with fixed context** selected `audio-minimal-v1`.
No reference label, description or image was added as model evidence. These were
ordinary production-billed app requests; the passive observer submitted none. No
direct evaluator calls or comparison slots were used, and no comparison secret
was activated.

The simulator was iPhone 18 Pro / iOS 27.0, running version 1.0.3 build 275:

- Clean app source: `fdfb142b6fcb96e6ae8f3c46a561015064c93cd2`.
- App fingerprint:
  `ebfa958011ec4e61dda121eea6b9d00890b67d23099dedf1612372aa5cbdb3df`.
- Deployed main: `b91e42ded94fe0904a30209b00d6aac8d2151d8c`.
- Expected and observed backend bundle:
  `61b69c048f009b62c45681da4219ea01fc9fef039048a9760fc57ca28b73ccc1`.
- Requested and returned model: `gemini-2.5-pro` in all six responses.

Deployment evidence independently established the exact source before the run;
each fresh response then attested the expected bundle. The older installed app
was intentionally retained: this release changed the backend confidence
contract, with no native runtime change required for this experiment.

## First visible outcomes

| Case    | Source reference                     | First visible result                    | Displayed match | Tap to first frame |
| ------- | ------------------------------------ | --------------------------------------- | --------------- | -----------------: |
| `c0019` | American Robin, _Turdus migratorius_ | Belted Kingfisher, _Megaceryle alcyon_  | Strong match    |           19.696 s |
| `c0020` | Canada Goose, _Branta canadensis_    | Canada Goose, _Branta canadensis_       | Strong match    |           17.974 s |
| `c0021` | Coyote, _Canis latrans_              | Coyote, _Canis latrans_                 | Strong match    |           18.111 s |
| `c0022` | Pig Frog, _Lithobates grylio_        | Pacific Tree Frog, _Pseudacris regilla_ | Strong match    |           19.897 s |
| `c0023` | Rain; reviewed non-biological        | No wildlife detected                    | Non-biological  |           13.738 s |
| `c0024` | Chainsaw; reviewed non-biological    | No wildlife detected                    | Non-biological  |           16.729 s |

Both reviewed non-biological controls returned **No wildlife detected**, with no
species-match badge. Goose and coyote agreed with their provisional source
species. Robin returned Belted Kingfisher and pig frog returned Pacific Tree
Frog; both displayed Strong matches. These disagreements remain in the record,
and their reference species are not treated as independently established truth.

The rain outcome agrees with the owner's pre-prediction review. It differs from
the earlier Snowy Tree Cricket result, but the changed context and single
observation prevent attributing that difference to V2. The bird and frog
observations also show that the deployed contract can still yield Strong species
labels that disagree with source references. No numerical confidence calibration
or reliable rejection rate is established.

## Measurements and estimates

The six windows ran from `2026-09-24T14:45:58.582Z` through
`2026-09-24T15:04:41.671Z`. Every case retained exactly one fresh HTTP 200
response, one canonical measurement-v2 record and four native timing events. All
app, bundle, Gemini model and fixed-context checks passed. Each observer exited
normally with no oversized or rejected proof rows.

| Case    | Provider call | Edge total | App pipeline | Primary estimate, USD |
| ------- | ------------: | ---------: | -----------: | --------------------: |
| `c0019` |     13.4276 s |  16.8081 s |     17.883 s |            $0.0257875 |
| `c0020` |     14.7068 s |  16.0144 s |     17.378 s |            $0.0285400 |
| `c0021` |     14.5867 s |  16.0065 s |     16.953 s |            $0.0243000 |
| `c0022` |     15.1966 s |  17.7361 s |     18.783 s |            $0.0273525 |
| `c0023` |     10.6827 s |  11.9347 s |     13.331 s |            $0.0204500 |
| `c0024` |     13.2810 s |  14.6353 s |     15.800 s |            $0.0242200 |

Tap-to-first-frame ranged from **13.738 to 19.897 seconds**, with median
**18.0425 seconds**. Provider, Edge and pipeline intervals overlap and must not
be added together. The nonvisual path has no visual-preflight marker; that
missing interval is not zero.

Observed primary-attempt estimates total **$0.1506500**. They use the unchanged
reviewed pricing snapshot retrieved at `2026-09-23T22:35:58.637Z`, within seven
days: $2.50 per million input tokens and $15 per million candidate-plus-thinking
output tokens, without a cache discount. These estimates exclude enrichment,
other or unobserved attempts, storage and transport. They are neither a complete
invoice nor a spending cap.

## Interpretation and next step

The earlier ordinary-context run has `contextProfile: null`; this run has
`audio-minimal-v1`. Model outputs can also vary between requests. Therefore this
is not a controlled before/after comparison and supports no causal claim about
accuracy, confidence calibration or latency improvement. A displayed Strong
match is a model estimate, not a calibrated probability. Numerical native
confidence was not exposed by this ordinary replay measurement and remains
unknown.

The infrastructure now verifies fresh V2 routing and records reproducible
operational evidence. It does not establish reliable species identification.
Keep these first outcomes as regression evidence. Independently resolve the
disputed animal references and design a separately frozen, matched-context
repeatability or candidate comparison before changing routing, thresholds or
providers. This run evaluated no alternative service or specialist model.

Formal corpus progress remains **0/60 development and 0/240 held-out groups**.
Public training exposure is unknown. Staged hashes do not attest complete
inference bytes. Displayed labels are manually observed, sequentially associated
with each case and not cryptographically bound to its measurement. This run does
not prove native persistence, compare the compatibility route, measure physical
microphone capture or establish general false-positive rates.

## Evidence and validation

The input freeze retains **38 files**, hash
`100d709c24be3fda2b2502278b66403e75bf54a02b2dc551dec34d628c2cce03`. The
completed private packet retains **79 files**, freeze hash
`a1a4ed2c58c1814476f37ac081f61e31ab2aad7e9d6fe117530b8685e7f5aede`, directory
mode 0700, file mode 0600 and retention through 24 October 2026. The frozen plan
hash is `6e8cf9d70556307fc16f1fbb9ea60da017b90de022cb5fde3d7c5fb241a70b76`.

Per-case offline validation used the repository's canonical fixed-audio
measurement and pricing contracts with network and environment access denied. It
checked complete sequential windows, one response, exact execution identity,
source file bindings and cost projections. The first offline invocation lacked
read permission for its canonical source module; correcting that local read
allowlist revalidated the same retained observation without another app request.
A supplemental offline audit checked each observer-v2 header, pricing and cost
scope, the 120-second window plus 30-second grace, zero automatic submissions,
normal collector signal, and chronological bounded event timestamps. It passed
for all six windows and is retained in the completed freeze and sanitized
benchmark record. Completion validation rechecked all frozen input hashes and
retained case files.

Raw OS logs, provider prose, production response bodies, account/scan
identifiers, credentials and actual app context were not retained. Audio remains
outside Git. The evidence-only documentation update did not rerun native/backend
runtime suites; successful source and deployed-SHA gates are recorded separately
in the release report. This benchmark performed no production configuration
change; no comparison secret was activated for it.
