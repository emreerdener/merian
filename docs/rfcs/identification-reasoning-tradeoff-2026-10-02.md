# Photo reasoning effort and Gemini Pro tradeoff

Status, 3 October: **completed and closed; medium did not advance**. All 60
attempts normalized and accounted for $2.335830008, with zero outstanding
reservations. Supported outcomes were 10/20 for low, 9/20 for medium and 10/20
for Gemini. Medium remained faster than Gemini but produced no supported gain
and one mapping-dependent regression versus low. Retain the low-reasoning
recommendation; this screen establishes no Gemini superiority or production
accuracy estimate. Production routing, stored scans and identification history
remain unchanged.

## Question and prior evidence

Does `gpt-6-sol` at medium reasoning improve supported photo outcomes while
preserving successful low-effort identifications and a useful speed advantage
over `gemini-2.5-pro` on the same photos?

The [previous reasoning pilot](identification-sol-reasoning-pilot-2026-09-30.md)
measured 6.805 seconds for low and 11.092 seconds for medium, six calls each.
Medium improved one taxonomy mapping but corrected no additional demonstrated
biological error; both efforts misidentified the butterfly. Repeated owner-photo
answers lacked independent reference support. The
[provider comparison](identification-photo-provider-decision-2026-10-01.md)
measured Gemini Pro at 16.092 seconds over a different set. Comparing those
means suggests a hypothesis, not a matched speed or quality result.

This study broadens the low/medium comparison and measures Gemini on identical
inputs. Historical references, scores and decisions remain unchanged. Owner
feedback motivates the question but is not ground truth.

## Reference review and design amendment, 3 October

The initial proposal called for six recent failure photos plus 18 exposed
controls, 24 observations and 72 calls. Simulator intake resolved photo access,
but did not supply six scoreable references or establish which individual scans
were the reported failures. Primary and second assistant review support only two
library species references. Neither review is independent human validation:

- Spider plant, `Chlorophytum comosum`, `gbif:2774846`: striped linear rosette
  leaves and a flowering stolon. The
  [NC State description](https://plants.ces.ncsu.edu/plants/chlorophytum-comosum/)
  supports the visible combination. No cultivar reference.
- Snake plant, `Dracaena trifasciata`, `gbif:11041822`: flat upright leaves with
  transverse bands, supported by the
  [NC State description](https://plants.ces.ncsu.edu/plants/dracaena-trifasciata/).
  No cultivar reference. `Sansevieria trifasciata` remains an existing synonym.

Public GBIF lookup returned exact accepted species matches for both names. Both
entries and their synonyms already existed in the reviewed taxonomy; no alias
was added to repair a model output. The private review retains lookup digests.

The other four groups remain reference holds: a compound-leaved flowering shrub,
a trailing aroid, a cane-forming houseplant and a patterned snake. The available
overviews do not securely resolve their competing identifications. A reviewer's
uncertainty is not a reference answer of biological abstention. Prior UI output
was seen for the shrub, so that review is not outcome-blinded. No new provider
output informed selection.

**Amendment before collection:** use the two reviewed library cases plus all 18
existing controls, **20 observations and 60 calls**. Keep the four holds
recorded and excluded; do not replace them with easier controls or score model
agreement as truth. The library stratum is now only two cultivated plants,
neither an individually confirmed regression. This narrower screen cannot settle
the reported ambiguous-library failures or estimate production accuracy.

## Bounded design

The owner approved a new **$10 ceiling and 60-attempt limit** on 3 October,
after reviewing the prepared comparison. This is a ceiling, not an expected
bill. Previous closed allowances remain closed; the new private authorization
binds this exact inspection manifest, source and separate live packet.

| Arm               | Configuration                                                |
| ----------------- | ------------------------------------------------------------ |
| Low control       | `gpt-6-sol`, low reasoning, current confidence photo request |
| Medium candidate  | Identical OpenAI request except `reasoning.effort: medium`   |
| Gemini comparator | `gemini-2.5-pro`, preserved `identify_vision_v1` request     |

OpenAI retains high image detail, inline moderation, 8,192 output tokens and the
existing explanation/schema. Gemini retains temperature 0.1, seed 42, 8,192
output tokens and 5,000 thinking tokens. Every arm has the existing 90-second
provider deadline. Preparation asserts the actual native settings and proves
low-request parity and the single-field medium difference. No prompt changes,
higher effort arms, retries, image variants or extra identification calls.

Use identical prepared image bytes, empty descriptive text and no location or
month context. Labels, filenames, owner guesses and previous answers never enter
requests. Stored library images are not verified original camera inputs or exact
historical provider payloads; this is a prepared-image comparison. Gemini uses a
different native prompt and safety behavior, so its arm compares product
configurations rather than isolated model weights.

The 18 controls retain the exact image/reference commitments from the versioned
[reference adjudication](identification-reference-adjudication-2026-10-01.md):
five species, six genus, three family, two unresolved biological and two
nonbiological references. Its two historical holds remain excluded. Live and
real inspection preparation verify these 18 references against the pinned
canonical adjudication. All 20 observations are exposed development evidence,
with one image per distinct subject group and explicit rights for both OpenAI
and paid Gemini.

Shuffle sorted case IDs with seed `20261002`. Cycle all six arm-order
permutations three times, followed by permutations 0 and 3: low/medium/Gemini,
then medium/Gemini/low. Each arm appears six or seven times in every position.
Freeze the resulting 60 assignments and execute sequentially without reshuffling
on resume. This balances position effects but does not control provider load or
automatic caches.

## Scoring and development decision

Primary: supported outcome per scheduled observation, using frozen exact
canonical ID/rank or appropriate unresolved/nonbiological state. No automatic
ancestor credit. Unknown mappings receive no credit and remain unverified,
separate from demonstrated biological mistakes. Failed and unattempted slots
remain in scheduled denominators; an incomplete run cannot advance.

Report all arms, paired gains/losses, the two strata and supported-rank/category
diagnostics. Preserve unsupported specificity, false abstention, subject-state
errors, mapping failures, technical failures, named precision/yield and
high-confidence errors. Higher confidence is not a gain.

Every development gate must pass:

1. Medium gains at least two net supported outcomes versus low across 20 cases,
   including at least one of the two library cases.
2. At least one gain corrects a demonstrated biological/rank/state error rather
   than only resolving an unknown mapping. No low-supported case regresses.
3. Medium has at least as many supported outcomes as Gemini in each stratum.
   This observed count condition does not establish statistical equivalence.
4. Medium has no more unsupported-specificity, false-abstention or subject-state
   errors than low in either stratum. All 60 results must normalize with
   complete accounting; a technical failure in any arm prevents advancement.
5. Medium's mean and median provider times are at most 80% of Gemini's matched
   times. Medium's nearest-rank p90 must not exceed Gemini's p90. For 20 calls
   per arm this is the 18th sorted value, a descriptive tail check only.

Use the existing paired discordant Clopper–Pearson/Bonferroni routine for medium
versus low and medium versus Gemini, retaining its two-comparison treatment.
Report the intervals descriptively; the new wrapper makes no confirmatory
superiority claim. No app latency or confidence-calibration claim follows.
Passing supports separate fresh validation only. Failure or ambiguity closes
this screen without automatically escalating to high reasoning.

## Implementation and execution boundary

The new `reasoningTradeoffPreparation.ts`, `reasoningTradeoffRunner.ts` and
`reasoningTradeoffStatistics.ts` reuse existing request builders, parsers,
scoring, usage validation, conservative reservations and exclusive claims. The
CLI is `evaluate_reasoning_tradeoff.ts`; the hidden-key launcher is
`run_reasoning_tradeoff.sh`. The
[evaluator guide](../../services/supabase/scripts/identification_evaluation/README.md#reasoning-effort-and-gemini-tradeoff)
owns packet and command details. Closed pilot/provider-decision runners and
budgets are unchanged.

Real `inspection` packets deny network/environment access and cannot dispatch.
Synthetic `offline` packets alone admit injected test outcomes. `live` mode
requires a clean source snapshot, explicit new authorization, fixed $10 ceiling,
provider-specific credential fingerprints and the exact reviewed packet.
Changing mode/approval requires a separate packet and freeze, never editing an
existing inspection manifest into a paid run.

Each dispatch rechecks prepared media and native request/settings digests before
its durable exclusive claim. The source, references, review, taxonomy, pricing,
ordering, budget and canonical packet path are bound by the manifest. One parent
process holds both keys transiently; each child receives one key and one allowed
API host. Keys and provider prose never enter saved evidence. Reports retain
bounded outcomes, taxon IDs, name digests, usage and provider timings.

An uncertain attempt consumes its slot, retains its reservation and stops. A
known technical failure also stops. Reservations plus settled cost must fit the
cap before the next claim. No retries, replacements, reset, copied-authorization
reuse or automatic continuation after a stop.

Current official
[OpenAI pricing](https://developers.openai.com/api/docs/models/gpt-6-sol),
[Google pricing](https://ai.google.dev/gemini-api/docs/pricing) and
[Gemini limits](https://ai.google.dev/gemini-api/docs/models/gemini-2.5-pro)
were reviewed on 3 October. Private cards use conservative higher-context rates,
include reasoning, omit cache discounts and retain the 10% OpenAI regional
premium. Dispatch requires a review age of at most seven days. Google's current
model page limits 2.5 access to previously active users; existing paid
credentials must still succeed, and an access failure stops the study without
substitution.

## Private intake and retained evidence

Read-only simulator intake used the logged-in iPhone 17 Pro, without rebuilding
the app, reanalysis, store writes, history changes, session extraction or
location reads. The shared store contained 406 scans. The ordinary Documents
directory held 146 images but only 14 distinct hashes, including fixtures; these
were not accepted as current library evidence merely from modification times.

Media references from the most recent 50 scan rows yielded 13 successful public
media downloads and 12 pixel-distinct images. One decoded-pixel duplicate was
skipped; repeated subjects were grouped. Two unrelated interior/background
photos were excluded. Five unavailable items visible in the app were not
recovered. The initial sandboxed download attempt failed; the permitted read
completed. These were inbound media reads, not identification calls.

Library copies are metadata-free RGB PNGs, preserving EXIF-oriented decoded
pixels without cropping or resizing: 768 by 769 or 1024 by 1024. No media URLs,
scan/account IDs, coordinates or provider prose enter retained manifests.

Private intake remains under
`/private/tmp/merian-simulator-photo-intake-20261003/library-network`. New input
preparation is under `/private/tmp/merian-reasoning-tradeoff-20261003`, with the
same 22 October retention limit. The initial materialization stopped because it
expected taxonomy additions that were already present; its incomplete directory
is preserved. The corrected preparation reuses the existing entries unchanged.
The earlier 54-control-request inspection under
`/private/tmp/merian-reasoning-tradeoff-offline-20261002` remains separate
evidence.

The source snapshot uses a new managed `reasoning-tradeoff` worktree because the
old screen checkout preserves historical uncommitted source and the main
checkout is concurrently changing for scan history. No historical packet is
rewritten and no production change is prepared for deployment.

## Verification checkpoint, 3 October

The isolated local source commit is `efa60a43e63704ee0a3fd399a32558964280f11c`,
with implementation digest
`0663bde23e0fbded0ee48b722fdd5dc8298281f99d2cc6bdee0127c4646ed458`. The real
`inspection-v2` packet built all 60 requests with network and environment
denied. Its manifest digest is
`92b6876260442d7c46ef3d1b3b0d5b7b6910a226fac3553f3e3886ffa015d2b9`; attempts,
settled cost and outstanding reservations are all zero.

Validation passed:

- Eight focused preparation, accounting, scoring and inspection-isolation tests;
  four synthetic launcher-isolation/no-retry scenarios.
- The complete Supabase tooling gate on the isolated snapshot, including its
  recursive TypeScript checks, evaluation filesystem suite and shell tests.
- Full function/script formatting and lint; research register validation.
- On the main checkout, 2,304 function tests passed (21 ignored),
  function-config synchronization, isolated dependency-graph validation and
  generated DTO checks. No iOS app build or device inference test was needed for
  these script-only changes. The separate scan-history changes are not part of
  this source snapshot.

The first sandboxed tooling gate reached an existing synthetic hidden-key PTY
failure. The isolated rerun with local terminal permissions passed the complete
gate. No real key or provider was involved in either run.

The private hidden-input command is prepared under
`/private/tmp/merian-reasoning-tradeoff-20261003/credentials.command`. Its
required new owner-authorization receipt was initially absent and its refusal
boundary was checked. Following explicit owner approval, the receipt now enables
hidden credential setup. The script binds both key fingerprints in memory,
creates a separate live packet, freezes it offline and invokes the bounded
launcher. It never changes the inspection manifest or saves raw keys. Terminal
launch succeeded after using the explicit installed app path with local app
permissions; no key was supplied through chat or an agent tool.

Hidden credentials were entered through Terminal and the authorized collection
completed. References, ordering, thresholds and requests stayed frozen. The
final offline report command rebuilt and verified the source/manifest and
accounting without network or environment access. The live manifest digest is
`46733140214c8caf9db36dc481073a48426ba9681d34153110e1f5b05422502f`.

## Completed results, 3 October

The primary endpoint includes appropriate rank, biological abstention and
nonbiological rejection; **these percentages are not species accuracy or
estimated production accuracy**. All 20 cases are exposed development evidence.

| Measurement                                 |  OpenAI low | OpenAI medium | Gemini 2.5 Pro |
| ------------------------------------------- | ----------: | ------------: | -------------: |
| Supported outcomes / scheduled observations | 10/20 (50%) |    9/20 (45%) |    10/20 (50%) |
| Library supported                           |         2/2 |           2/2 |            2/2 |
| Control supported                           |        8/18 |          7/18 |           8/18 |
| Mean provider seconds                       |       6.732 |        10.961 |         15.542 |
| Median provider seconds                     |       6.382 |        10.925 |         15.440 |
| p90 provider seconds                        |       8.148 |        13.545 |         17.492 |
| Accounted USD, 20 calls each                | 0.752785002 |   0.868285005 |    0.714760001 |
| Technical failures                          |           0 |             0 |              0 |

Medium took 62.8% longer than low on mean provider duration. It was 29.5% faster
than Gemini by mean, 29.2% faster by median and had a lower p90, so it passed
the latency gate. These timings exclude preparation, upload outside the provider
request, app coordination and rendering; they are not end-to-end scan timings.
Costs use the frozen conservative rates, not invoices or current price
forecasts.

Medium versus low had **zero gains and one loss**, a -5 percentage-point
observed difference. Medium versus Gemini also had zero gains and one loss. Both
frozen descriptive simultaneous paired intervals were **-30.8 to +22.4
percentage points**, with exact and Bonferroni-adjusted McNemar p = 1. The
method retains at least 95% family coverage for the two comparisons; neither is
a confirmatory superiority test here. The wide intervals do not establish
inferiority, equivalence or overall model superiority. Gemini versus low had one
gain and one loss descriptively, with no net primary difference.

### Identification and mapping diagnostics

| Supported outcome by reference rank/state | Low | Medium | Gemini |
| ----------------------------------------- | --: | -----: | -----: |
| Species, including two library plants     | 6/7 |    6/7 |    7/7 |
| Genus                                     | 2/6 |    1/6 |    1/6 |
| Family                                    | 0/3 |    0/3 |    0/3 |
| Biological unresolved                     | 0/2 |    0/2 |    0/2 |
| Nonbiological rejection                   | 2/2 |    2/2 |    2/2 |

| Supported outcome by category |  Low | Medium | Gemini |
| ----------------------------- | ---: | -----: | -----: |
| Clear                         |  4/5 |    4/5 |    5/5 |
| Lookalike                     |  0/1 |    0/1 |    0/1 |
| Limited evidence              | 2/10 |   1/10 |   1/10 |
| Cultivated library            |  2/2 |    2/2 |    2/2 |
| Nonbiological                 |  2/2 |    2/2 |    2/2 |

All arms named all 18 biological cases, so verified named precision and correct
named yield were each 8/18 for low, 7/18 for medium and 8/18 for Gemini. On the
16 named-reference cases, none falsely abstained. All arms correctly classified
the biological/nonbiological subject state on 20/20. None appropriately
abstained on the two unresolved biological references.

| Diagnostic among 18 biological cases          | Low | Medium | Gemini |
| --------------------------------------------- | --: | -----: | -----: |
| Unmapped names, unverified                    |   4 |      6 |      4 |
| Mapped named errors against frozen references |   6 |      5 |      6 |
| Unsupported specificity                       |   7 |      7 |      7 |

Unsupported specificity overlaps mapping and mapped errors; these rows must not
be added together. Five mapped errors in every arm are species assertions where
the reference supports only genus (three cases) or family (two). The sixth
mapped error in low and Gemini is a named assertion on an unresolved biological
case; medium also names that case but its name is unmapped. Its lower
mapped-error count is therefore **not a supported correction**. The record does
not establish that every over-specific species is biologically false: the
available visual reference supports less specificity.

The only low-to-medium supported loss is control `c0050`: low matched the frozen
genus ID/rank, while medium returned an unmapped named answer. It receives no
credit and remains unverified; no missing name is inferred from its digest.
Gemini is also unmapped there. Conversely, Gemini matched the species reference
on `c0003`, where both OpenAI arms are unmapped. This is mapping-dependent
verified yield, not proof that Gemini corrected a demonstrated biological error.
No taxonomy alias or accepted answer was changed after seeing results.

At the existing diagnostic cutoff of 0.95, low and medium each had one
unverified mapping failure among five named answers and zero demonstrated mapped
errors. Gemini had one mapped unsupported-species answer among eight
high-confidence named answers. Confidence therefore does not supply a substitute
correctness or routing signal; no badge threshold or calibration changed.

### Frozen gate decision

| Gate                                                                                 | Result                        |
| ------------------------------------------------------------------------------------ | ----------------------------- |
| Complete, normalized and accounted 60-slot run                                       | Pass                          |
| At least two net medium gains versus low                                             | Fail: zero gains, one loss    |
| At least one library gain                                                            | Fail: all three arms 2/2      |
| At least one demonstrated biological/rank/state correction                           | Fail: none                    |
| No low-supported regressions                                                         | Fail: one unmapped regression |
| Medium supported count at least Gemini in each stratum                               | Fail: controls 7 versus 8     |
| No increase in specificity, false abstention or subject errors within either stratum | Pass                          |
| Medium mean/median at most 80% Gemini; p90 no worse                                  | Pass                          |

Medium does not advance to fresh validation. This completes the authorized
screen; do not automatically escalate to high reasoning, tune against these
outputs, replace cases or reopen the budget.

## Decision and next justified work

**Keep the released low-reasoning photo recommendation.** The added reasoning
cost and latency bought no supported improvement in this screen. Switching back
to Gemini is also not established by these results: it tied low overall, with
opposing mapping-dependent wins and losses. The earlier larger comparison is
separate evidence and must not be pooled with these reused controls.

This result does not dismiss the owner's reported regressions. Only two clear
cultivated library subjects were admissible, both solved by every arm, and
neither was confirmed as a reported failure. The four ambiguous library groups
remain reference holds. The next evidence need is reference-supported examples
of those actual failures, plus evaluation of whether insufficient distinguishing
visual evidence can be recognized. Do not spend more on reasoning levels or
confidence calibration before resolving that evidence gap. The separately
prepared feature-observation screen remains a proposal with its own collection
prerequisites and authorization.

No production model/prompt change is justified for rollout from this study. The
tested implementation is evaluation tooling and its regression checks; there is
**no measured app accuracy improvement and no deployed change**. A future
selected medium configuration would need an immutable production binding,
compatible provenance/readers, fresh qualification and separate release
authorization; changing only a production effort flag would omit those controls.

## Accounting and closure

Final ledger: **60 attempted slots, 60 claims, 60 result records, zero retries,
zero technical failures, $2.335830008 settled, $0 outstanding reservations**.
The $10 ceiling leaves $7.664169992 unused; the study and remaining allowance
are closed and cannot fund additional calls. The original $20 study and all
other historical budgets remain closed.

The approved private `live` directory retains the manifest, report, claims,
bounded result projections, taxonomy, pricing and reference review under the 22
October retention limit. Source identity is the isolated commit/digest above;
inspection and live manifests remain distinct. Raw credentials, provider prose,
coordinates and account/scan identifiers are not copied into this record.

A separate read-only assistant audit reconciled all 60 claims/results, costs,
paired outcomes, gate failures and confidence diagnostics. This is an accounting
and interpretation review, not independent human reference validation. Closure
updated the catalog, generated registers, research index, benchmark work order
and three exact study-configuration assessments; historical configuration tuples
remain unchanged. Research validation, Agent Quality asset checks, changed
Markdown formatting (46 files), the function/script formatting gate and scoped
diff checks passed. The precollection implementation gates above remain the
software evidence; closure changed only research documentation.
