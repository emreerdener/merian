# Current-baseline explicit-primary development screen — 1 October 2026

Status: completed on 1 October 2026. All 40 authorized calls completed; the
candidate failed the frozen development screen. Accounted cost was $1.541925002,
with no outstanding reservations or retries. Retain the released configuration.
Production routing, confidence thresholds and public response shape are
unchanged. The closed
[provider decision](identification-photo-provider-decision-2026-10-01.md)
remains separate historical evidence; its authorization was not reopened.

## Hypothesis and implementation

The [calibration gap audit](identification-calibration-gap-audit-2026-10-01.md)
identified unsupported specificity and three regressions in the evidence-limit
candidate. The next candidate uses explicit species, genus, family, unresolved
biological, and nonbiological states on the current confidence baseline. It
keeps Sol, low reasoning, image preparation, output budget, moderation, traits,
and explanation format. This is a prompt/schema comparison; it does not isolate
an underlying model improvement.

`openaiPhotoPrimary.ts` owns the request and private identity;
`createOpenAIPhotoPrimaryEvaluationAdapter` owns its bounded transport and
strict primary-state decoder. `developmentProjection.ts` records content-free
diagnostic flags before and after normalization. A declared/catalog rank
conflict earns no identity credit. Unknown names remain unverified. No mapper
aliases or reference answers are changed, and no provider prose or images enter
the result journal.

The existing evaluator supplies asset verification, taxonomy, scoring,
accounting, exclusive claims, file locks, and source digests. The new narrow
orchestration is `photoPrimaryScreenPreparation.ts`,
`photoPrimaryScreenRunner.ts`, and `evaluate_photo_primary_screen.ts`; it is not
a production route.

## Frozen development design

Twenty previously exposed observations receive two new calls each: released
confidence baseline and explicit-primary candidate. The separately authorized
ceiling was 40 attempted calls and $10 additional charges. Conservative
reservations include cache writes, reasoning/output usage and a 10% accounting
margin. At the reviewed prices, each call reserves $5.910168 before sending;
known actual usage releases the unused portion. The budget is a ceiling, not an
instruction to spend it.

The assistant-reviewed selection is:

| Purpose                                                  | Observation IDs                          |
| -------------------------------------------------------- | ---------------------------------------- |
| Prior regressions                                        | c0005, c0006, c0013                      |
| Prior gains to retain                                    | c0007, c0021, c0049, c0050, c0195        |
| All six unresolved biological references                 | c0027, c0031, c0032, c0062, c0135, c0194 |
| Supported species controls across four biological groups | c0003, c0012, c0017, c0112               |
| Nonbiological controls                                   | c0080, c0081                             |

Each observation has one approved still image and no description, location, or
month. All have distinct reviewed subject clusters. The original 200-case
corpus, taxonomy and evidence records are copied unchanged. Historical split
labels remain historical: this entire new selection is exposed development data.
Parent claims and manifest prove exposure; exact released request and snapshot
digests must match the prior study before collection. References were reviewed
by the assistant; this is not independent human validation.

Cases are shuffled with seed 20261002; first-arm order alternates. The manifest
binds source graph, input bytes, request parameters, snapshots, references,
taxonomy, exposure, pricing, plan and all 40 assignments before collection.

The candidate passes this development screen only if all 40 scheduled attempts
complete, all three previous regressions are correct, all five previous gains
remain correct, there is at least one _paired_ gain on an unresolved biological
case, no new subject-classification error, no species-reference loss, and at
least two net additional correct outcomes. At least one gain must be unrelated
to a previous mapping failure. Both arms abstaining correctly is not a gain.

Failures remain in the scheduled denominator. There are no retries, replacement
cases, reference changes, or automatic follow-on study. An interrupted claim or
uncertain accounting stops collection and retains its full reservation.
Operational failures stop; schema/rank failures consume their slot and earn no
credit. The report records paired wins/losses, named yield, specificity,
mapping, subject and category diagnostics. Passing is a development signal,
never a superiority claim.

## Preparation and execution boundary

The private packet is outside Git under
`/private/tmp/merian-primary-screen-20261001/study`, with owner-only permissions
and retention through 22 October. Its initial plan had
`paidServiceApproved: false`; live dispatch rejected that state before
credential access or a claim. After the user approved the stated $10/40-call
screen, the unattempted plan and manifest were preserved as
`pending-approval-plan.json` and `pending-approval-manifest.json`. The approved
plan was frozen against the same reviewed source and unchanged assignments. An
attempted manifest must never be reset or rewritten.

The managed checkout
`/Users/emreerdener/.codex/worktrees/photo-primary-screen/merian` isolates the
archived evaluated graph plus scoped new evaluator changes from concurrent work
in the shared checkout. Its generated bundle identity is regenerated for that
graph. It is not a release candidate for unrelated work in the shared checkout.

Offline `prepare`, `report`, and `next` use denied network/environment
permissions and bounded filesystem/Git access. `run_photo_primary_screen.sh`
preflights the frozen packet and holds one OpenAI key in process memory using
hidden input. Only a paid child receives that key and access to
`api.openai.com:443`. A sibling authorization receipt binds the approved
reference to one packet and manifest; moving the packet does not reset its
budget.

The earlier two-key session had ended. After approving this separate screen, the
user entered the OpenAI key in a new hidden session. The bounded launcher
completed collection and released its in-process key. Gemini was not part of
this screen. No further collection is authorized by the unused budget.

## Verification and next decision

Focused offline checks passed: three request-isolation tests, three adapter
tests, six projection tests, four filesystem/journal tests including a complete
synthetic 40-slot sequence, and four synthetic launcher scenarios. These
establish software behavior only. The complete isolated backend and tooling
gates passed as recorded below; no hosted migration or deployment gate is
implied.

If the screen fails, retain the released configuration and record why. If it
passes, freeze a separate genuinely unexposed validation design before
requesting any further collection. Confidence thresholds require a later
calibration study on the final selected configuration. Neither step is
authorized by this screen.

### Completed offline verification

The final isolated source graph digest is
`8077b461a7125524e999af9903ba19ddb22b6bc690dcb80f4dd69a473a4149ce`. All 13
scoped implementation/test files match the shared checkout. Generated bundle
identities differ between checkouts because the shared checkout includes
concurrent unrelated work; each was regenerated from its own source graph.

- Runtime: 2,242 tests and 343 steps passed; 11 ignored by the existing suite.
- Full tooling: 489 standard tests, 144 evaluator tests, 20 Identify DTO tests,
  21 captured-media DTO tests and all 18 shell suites passed.
- All 103 isolated function entrypoints type-checked; generated dependency
  configs and graphs validated.
- Recursive backend formatter and lint passed in the isolated checkout. The
  shared checkout also passed recursive backend formatting, changed-Markdown
  formatting and `git diff --check`.
- Read-only review confirmed approval gating, paired abstention scoring,
  credential isolation and no-retry behavior after the two review fixes.
- Real-packet preflight passed; an offline attempt to enter the live path with
  approval false was rejected before any durable attempt or credential lookup.

At precollection verification, the frozen approved packet contained 40
assignments for 20 observations and zero attempts or charges. The completed
collection and accounting are recorded below. Private logs are under
`/private/tmp/merian-primary-screen-20261001/`. These results qualify the
isolated evaluation graph, not the concurrent iOS/database changes in the shared
checkout. Disposable-database, hosted CI and deployment checks were not run for
this evaluator-only preparation.

## Completed development result

| Measure                                                | Released confidence baseline | Explicit-primary candidate |
| ------------------------------------------------------ | ---------------------------- | -------------------------- |
| Evidence-supported outcomes per scheduled observation  | 7/20 (35%)                   | 11/20 (55%)                |
| Correct named biological answers                       | 5/18                         | 9/18                       |
| Species-reference outcomes                             | 5/7                          | 5/7                        |
| Genus-reference outcomes                               | 0/5                          | 4/5                        |
| Appropriate unresolved biological outcomes             | 0/6                          | 0/6                        |
| Correct nonbiological rejection                        | 2/2                          | 2/2                        |
| Unverified mappings among named biological answers     | 8/18                         | 5/18                       |
| Unsupported specificity among named biological answers | 8/18                         | 7/18                       |
| Mean provider latency                                  | 7.90 seconds                 | 6.36 seconds               |
| Median provider latency                                | 7.68 seconds                 | 6.30 seconds               |
| Accounted cost including 10% margin                    | $0.758362000                 | $0.783563002               |

There were five candidate-only correct outcomes and one released-only correct
outcome, a net four outcomes (+20 percentage points) on this deliberately
selected, already exposed development set. This is not an estimate of production
accuracy and not a confirmatory superiority result. Descriptive 95% Wilson
intervals for the two observed rates are 18.1–56.7% and 34.2–74.2%; they do not
correct the selection bias or establish population performance. No validation
sample or confidence cutoff was selected from these outputs.

The four additional genus-reference successes are a useful development signal.
However, the candidate failed three required conditions: it did not retain every
prior gain, it did not resolve all prior regression cases without a new species
loss, and it made no paired unresolved gain. Net gain and subject-classification
conditions passed. Do not promote the candidate or start validation
automatically.

### Case-level interpretation

- c0021 is a clear specificity improvement: the released response was a mapped
  species beyond the genus-supported reference; the candidate returned the
  accepted genus. This is the demonstrated gain independent of mapping failures.
- c0049, c0050 and c0195 became accepted genus answers; c0013 became an accepted
  species answer. Their new released responses were unmapped. These are improved
  verified yield, but do not prove the baseline named a biologically wrong
  taxon. Missing names are not reconstructed or credited retrospectively.
- c0006 is the sole paired loss: the released response matched the species
  reference, while the candidate returned a mapped genus and failed the frozen
  species-reference criterion. This is a loss of required specificity, not proof
  of a wrong species name. Species totals stay 5/7 because c0013 offsets this
  loss.
- c0007 failed in both arms: both named a species where the reference supports
  only a genus. Thus only four of the five historical gains were retained.
- All six unresolved biological cases still received named answers in both arms.
  The explicit state vocabulary did not teach reliable abstention. These are
  evidence-limit failures even where the chosen identity is unmapped.
- c0003 remained unmapped at confidence 0.97 in both arms. Both therefore have
  one unverified answer above the 0.95 diagnostic cutoff (1/2 high-confidence
  named answers for released; 1/6 for candidate). This is not proof that
  changing badge thresholds would improve safety or accuracy.

The diagnostic categories overlap: an unmapped named answer on an unresolved
reference is also unsupported. Counts must not be added as disjoint errors.
Subject classification was correct on all 20 cases for both arms. All 40 outputs
normalized successfully; there were no schema, transport, refusal or unknown
execution failures, no explicit/catalog rank conflicts, and no deterministic
subject demotions. One released name was sanitized; the candidate had no name
sanitization changes. The gains are not a demonstrated sanitizer or pet-alias
fix.

### Decision and closure

Retain the released photo configuration. The strongest next research question is
whether an image contains enough distinguishing evidence to support any
identity; this screen shows that adding explicit resolution fields alone does
not solve it. A later development effort should focus on that
evidence-sufficiency decision and independently reviewed answerability labels.
Do not tune again on this closed screen or spend its remaining allowance on
another candidate. Confidence calibration belongs after the final configuration
is selected, using separate unexposed data. Production integration of rank
states would also require its own API, persistence and iOS compatibility work.

Exact accounting: 40/40 attempted calls, 20 per arm; $1.541925002 conservatively
accounted including the 10% margin; $0 outstanding reservations; zero retries,
replacements or additional calls. The $8.458074998 difference from the ceiling
is unused and closed, not permission for another study. This amount is evaluated
usage pricing plus margin, not an invoice reconciliation.

Final manifest digest:
`dcbeb341def4ee12fbcffce0ea5d830fbf0802bf88c4ec22604be9d69c87047b`. The approved
source graph remained
`8077b461a7125524e999af9903ba19ddb22b6bc690dcb80f4dd69a473a4149ce`. Final
offline report reconstruction verified all claims, results, source, requests,
inputs and accounting. No runtime code changed after its completed qualification
gates.

The private completed packet, exact evaluated source, analysis and validation
logs are retained under
`/Users/emreerdener/Developer/merian-evaluation/2026-10-01-photo-primary-screen-v1`
through 22 October. The archive preserves the original root binding and is not a
new runnable authorization. No credentials or provider response prose are saved.
