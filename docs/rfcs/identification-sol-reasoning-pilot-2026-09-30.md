# Sol low versus medium reasoning

Status: all twelve calls and assistant reviews completed on September 30 local
time (October 1 UTC). The result is mixed and does not support promoting medium
reasoning from this pilot. Retain Sol-low for both Free and Pro. No production
profile or confidence threshold changed.

Follow-up recorded 3 October: the separate
[matched reasoning-effort comparison](identification-reasoning-tradeoff-2026-10-02.md)
completed 60 calls on 20 photos. Medium was faster than Gemini but had zero
supported gains and one unmapped regression versus low; it did not advance. This
pilot and its budget remain closed and its findings below are unchanged. The
[research index](../research/identification/README.md) owns the current research
decision and next priority.

The owner approved a small effort-only comparison after two scans of one photo
returned different species. Test whether Sol-medium is a useful Pro candidate
while retaining Sol-low for Free. Preserve the activated
`openai_identify_vision_confidence_v1` instructions and schema, high image
detail, inline moderation, 8,192 output-token limit, 90-second deadline, and one
generation per scheduled attempt. Only `reasoning.effort` differs.

## Completed pilot

The private `openai_photo_reasoning_report_v1` contains twelve immutable claims,
twelve results and twelve submitted reviews, with no operational failures,
retries or outstanding cost reservations. Conservative accounted cost was
$0.468209501 against the $10 cap. This is not an invoice amount.

| Measurement                                             |  Sol-low | Sol-medium |
| ------------------------------------------------------- | -------: | ---------: |
| Completed calls                                         |        6 |          6 |
| Accepted canonical matches on the three reference cases |      1/3 |        2/3 |
| Demonstrated wrong identifications on reference cases   |        1 |          1 |
| Unmapped named answers on reference cases               |        1 |          0 |
| Mean provider time                                      |  6.805 s |   11.092 s |
| Median provider time                                    |  6.491 s |   11.202 s |
| Mean conservative accounted cost                        | $0.03611 |   $0.04192 |

Medium took about 4.29 seconds longer per call on average (63%) and cost about
16% more under the same conservative pricing rules. These are observations from
six calls per setting, with three repeats of one image; they are not independent
production samples or end-to-end app timings.

All scheduled outcomes are retained below. Names that fail the frozen taxonomy
mapping remain unverified; a familiar common name does not earn correctness
credit or establish a canonical rank.

| Call | Case               | Effort | Raw score | Outcome                                              |
| ---: | ------------------ | ------ | --------: | ---------------------------------------------------- |
|    1 | Supplied photo     | Low    |      0.82 | Unmapped name A; no reference correctness score      |
|    2 | Supplied photo     | Medium |      0.81 | Unmapped name A; no reference correctness score      |
|    3 | Supplied photo     | Medium |      0.87 | Unmapped name A; no reference correctness score      |
|    4 | Supplied photo     | Low    |      0.87 | Unmapped name A; no reference correctness score      |
|    5 | Supplied photo     | Low    |      0.78 | Unmapped name A; no reference correctness score      |
|    6 | Supplied photo     | Medium |      0.82 | Mapped Golden Pothos; no reference correctness score |
|    7 | Purple Dead-nettle | Medium |      0.94 | Accepted species match                               |
|    8 | Purple Dead-nettle | Low    |      0.89 | Accepted species match                               |
|    9 | Queen butterfly    | Low    |      0.97 | Wrong species: Monarch                               |
|   10 | Queen butterfly    | Medium |      0.96 | Wrong species: Monarch                               |
|   11 | Shaggy Mane        | Medium |      0.97 | Accepted species match                               |
|   12 | Shaggy Mane        | Low    |      0.95 | Unmapped scientific name; no correctness credit      |

Name A has normalized name hash
`7e7078ae475a79804a3c1f5f2c0188963ddc814c4170351f5ff169409506f4a0`. Low repeated
it three times; medium returned it twice and a different, mapped answer once.
Thus medium did not resolve the supplied-photo inconsistency. This does not
establish which answer is correct. The reference-case difference is a
scientific-name mapping improvement on the mushroom, not evidence that medium
corrected an additional demonstrated biological error.

Assistant review found specific decision reasons in all twelve explanations.
Both butterfly explanations failed grounding and uncertainty review: they used
vein prominence to discount the reviewed Queen reference, while limiting their
uncertainty discussion to sex rather than the species distinction. The other ten
explanations passed decision-reason and uncertainty review, but full grounding
remained not assessable. The supplied photo lacks independent species reference
support, and the plant/mushroom explanations included alternative-taxon
comparisons beyond the frozen fact cards. No fully grounded explanation pass is
claimed. These assistant ratings are not independent human validation.

Decision: retain Sol-low and close this pilot without promotion or additional
calls. Medium showed one naming benefit, but the reference error remained,
repeatability did not improve, explanation grounding was limited, and average
provider time increased. Keep 0.95/0.60 and `openai_unqualified_v1`; this pilot
does not qualify badges, individual percentages or automatic verification. A
future naming-validation or lookalike-discrimination change is separate work.

Evidence identifiers:

- Manifest: `427c953d3108d85882a8d7ffebd7ee44e06b5f53f3a5e163d268fb216f4d8cf5`.
- Source graph:
  `6e33cbbc24fef70290a0650adb533ee017ec7bbda7cd1e5837f39df3aa37cc2d`.
- Completed report file:
  `2bcf93d582fa761ca49ddfa455b859e677aa81962b1d6b0ca10ca7c04fb9166a`.
- Completion recorded at `2026-10-01T04:19:21Z`.

Tooling validation passed before collection: 2,234 Edge tests, the complete
Supabase tooling suite, five focused runner tests, five synthetic launcher
scenarios, four adapter/parity tests, all 103 isolated function graphs and
entrypoint checks, formatting and lint. This evaluation introduced no iOS or
database schema change and did not deploy a backend.

## Fixed comparison

- Twelve calls maximum: three independent low/medium pairs on the supplied
  hanging-plant photo, then one pair on each of three existing reference cases
  (Purple Dead-nettle, Queen butterfly, and Shaggy Mane). Alternate which effort
  runs first. These repetitions are predeclared experimental assignments, not
  retries of failed calls or duplicate calls on customers' scans.
- The supplied photo is a repeatability case without independently established
  species ground truth. Agreement or higher confidence does not establish
  correctness. Keep it outside reference-accuracy denominators.
- Reuse reviewed development cases `c0024`, `c0037`, and `c0116`, their exact
  media, supported references, diagnostic evidence and frozen taxonomy. The
  previous confidence study and its held-out set remain untouched. The reference
  review is automated and source-grounded, not independent human validation.
- No description, species suggestion, reference fact, filename, or source label
  enters a provider request. Both efforts receive identical prepared pixels and
  context. The supplied photo is oriented, stripped of metadata and resized to a
  1,024-pixel long edge; existing references retain their prepared pixels. This
  tests provider behavior, not identical phone-upload bytes or end-to-end mobile
  latency.
- Freeze the protocol, case/reference facts, taxonomy, pricing, source graph,
  request and settings hashes before paid execution. Only the new report
  `openai_photo_reasoning_report_v1` describes this pilot.

## Accounting and review

The cumulative cap is $10. Reserve the full reviewed context/output ceiling
before each dispatch, including reasoning tokens and a 10% regional premium.
Using the reviewed maximum rates, the reservation is $5.910168 per sequential
call. It is an upper bound, not forecast spend. Reconcile complete usage before
releasing unused reservation and admitting the next call. All input is priced at
the highest reviewed rate; no assumed cache discount is used. Report these
amounts as conservative accounted costs rather than invoices.

Immutable, fsynced claims and an exclusive run lock prevent duplicate calls.
Before live dispatch, a sibling authorization receipt binds this approval to the
original packet directory and frozen manifest. The approved plan also fixes the
original directory's digest, so copying it under another parent fails
preparation. Failed or interrupted calls consume a slot. Missing or
contradictory usage, unexpected model/tier, provider failure, or an unavailable
explanation review stops the run. Resume retains completed and uncertain claims;
it never replaces cases, repeats requests, changes either cap, or rewrites
frozen inputs.

The existing Naturebook key is entered once through a hidden local Terminal
prompt and kept only in process memory. The assistant reviews explanations in
the existing one-use loopback view. Only enum ratings, canonical identity/rank,
scores, timings, numeric usage/accounting and hashes enter reports. Provider
prose, reasoning traces, raw response bodies and credentials are not retained.
Reference facts remain separate from provider input. For repeatability only, a
normalized scientific-name hash records whether unmapped named answers agree. It
never assigns a taxonomic rank or correctness credit.

## Decision and follow-up

Report all twelve outcomes, within-photo agreement, supported reference matches,
unmapped answers, explanation grounding/uncertainty, latency and conservative
cost per effort. Higher scores alone are not evidence of improvement. A missing
or ambiguous taxonomy mapping stays unresolved; no inferred rank or model
adjudication fills the gap. The small selected mixture supports a beta decision,
not a population accuracy, calibration or marketing speed claim.

Recommend medium for further Pro integration only when its observed benefit
justifies the measured latency/cost and it introduces no material reference or
explanation regression. A tie or inconclusive result retains Sol-low. Do not
expand this pilot automatically. Keep Strong/Possible at 0.95/0.60 and
`openai_unqualified_v1`.

A selected medium production profile still needs its own immutable provenance,
server-admitted tier assignment, and compatible iOS reader. Current readers
recognize the released low-effort tuples; changing the effort in production
without that integration could produce “Needs review.” Production activation is
a separate explicit operation. This pilot does not require an iOS archive.

See the
[tooling procedure](../../services/supabase/scripts/identification_evaluation/README.md#sol-reasoning-pilot)
and the
[original Free/Pro plan](identification-openai-free-pro-models-2026-09-28.md).
