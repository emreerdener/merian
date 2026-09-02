# Naturebook Family Plans and AI Platform Evolution — PRD

Document ID: NB-PRD-FAMILY-AI-001\
Version: 0.2\
Date: 2 September 2026\
Status: Deferred combined draft; identification requirements superseded\
Suggested owners: Product, Engineering, and ML\
Companion:
[System Requirements Document](../rfcs/family-plans-and-ai-platform-srd.md)

The active scope is now the
[Provider Flexibility PRD](./03-identification-foundation-prd.md) and its
[SRD](../rfcs/identification-foundation-srd.md). Family plans are deferred by
the user's direction; BioCLIP and model training are also outside the active
provider-flexibility plan. The combined content below preserves prior planning
for reference; its AI requirements, delivery sequence, and family milestones are
not the active implementation scope.

## 1. Purpose and evidence

Define three connected workstreams:

1. Family plans that let eligible people share subscription value while keeping
   their accounts and observations independent.
2. A backend AI boundary that can support providers other than Gemini.
3. Measured improvements to identification quality, latency, and cost, with a
   staged path toward models Naturebook operates and adapts itself.

This revision reconciles the initiating request with the conversation excerpt
supplied on 2 September 2026, identified below as **S1**. The excerpt begins
with a correction about confidence-based routing, then discusses specialist
biodiversity models and their economics. It contains recommendations and worked
examples, not an explicit decision log. It does not specify a family plan,
price, membership mechanism, child-account policy, or approved deployment.

Repository evidence was reviewed at `3c6bbfa67741`, and external claims were
checked against official sources on 2 September 2026. Existing concurrent iOS
inference work is outside this proposal. No transcript copy, production data,
model weights, or benchmark results are added by this documentation change.

**Confirmed intent** means one of the three workstreams above. **Current** means
supported by repository evidence, not verified production deployment.
**Proposed** means a recommendation requiring a product decision. Numeric goals
below are proposed acceptance targets, not measured results or forecasts.

### 1.1 Conversation reconciliation

| S1 topic                                                                                           | Treatment in this PRD/SRD                                                                                                          |
| -------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| Confidence exists only after the model that produces it runs.                                      | Separate pre-dispatch routing from a metered, durable escalation stage.                                                            |
| A biodiversity specialist generates candidates; an LLM explains or adjudicates.                    | Make this the proposed target architecture, with an explicit authority boundary.                                                   |
| Begin with BioCLIP 2, geography/season priors, and the existing LLM.                               | Add an early offline proof of concept, without waiting for a trained proprietary model or a production provider cutover.           |
| Retrieval, hierarchical taxonomy, and multiple photos strengthen the evidence.                     | Add runtime evidence/fusion requirements and test calibration; do not assume independent signals or guaranteed improvement.        |
| Audio needs a specialist; video supplies selected frames and possibly audio.                       | Qualify each modality and preserve the current multimodal fallback and public-audio safety controls.                               |
| Improve from a frozen encoder to a small head, partial fine-tuning, and eventually an owned model. | Use successive evidence and investment gates; confirmed observations enter datasets only after rights and label review.            |
| 200K users, 4M monthly observations, 5–15K initial taxa, GPU budgets, and escalation percentages.  | Keep as planning scenarios. They are not observed scale, approved scope, or demonstrated economics.                                |
| Family plans and an explanation for a child.                                                       | Family plans remain part of the initiating request. The excerpt does not settle family requirements or authorize access by minors. |

These documents add a proposal. They do not replace the
[master product document](./01-master-product-document.md), current consent and
retention contracts, or release runbooks.

## 2. Product direction

The recommended starting point is an adult family subscription using Apple
Family Sharing, subject to an identity and receipt compatibility spike. Keep
usage accounting and personal records per account. Build an in-app household
roster only if invitations, cross-platform membership, or pooled allowances are
essential product requirements. S1 does not resolve this choice.

For AI, retain the existing identification orchestrator and extract explicit
provider adapters. Prove the boundary first with Gemini, then qualify a second
provider for a defined set of operations and modalities. A provider is eligible
only when its quality, consent, data handling, safety, and operating costs meet
the same product requirements.

In parallel, run an offline **BioCLIP 2 proof of concept** using authorized
images and a bounded taxon set. Compare visual candidates with and without soft
geography/season priors, retrieval, and multi-photo fusion. Start with a frozen
encoder; evaluate a small classifier head and partial fine-tuning only after the
baseline identifies a useful gap. The target is a Naturebook-owned candidate and
confidence layer, with a separately replaceable LLM for grounded explanation and
approved difficult-case adjudication.

BioCLIP 2 remains the S1 baseline. The current publisher also provides BioCLIP
2.5 Huge, so include it as a separately pinned challenger, alongside a DINOv2
baseline when resources permit. A newer or larger checkpoint is not
automatically the production choice.
[BioCLIP 2 model card](https://huggingface.co/imageomics/bioclip-2),
[BioCLIP 2.5 model card](https://huggingface.co/imageomics/bioclip-2.5-vith14),
[DINOv2 reference implementation](https://github.com/facebookresearch/dinov2).

Training a broad multimodal foundation model from scratch remains a later
investment decision. Operating and adapting licensed weights is an earlier,
distinct form of ownership.

## 3. Current position

| Current evidence                                                                                                                           | Consequence for this proposal                                                                                           |
| ------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------- |
| Naturebook is iPhone-first, with private observations, Explore, and multiple capture modalities.                                           | Family access must preserve each person's existing record ownership and capture experience.                             |
| The product requires self-attested 18+ eligibility; there is no complete guardian or child-account system.                                 | Family pricing does not authorize child accounts. Adult sharing and child access are separate scope decisions.          |
| RevenueCat, server entitlements, promotional grants, and per-user AI quotas already exist.                                                 | Extend these boundaries; do not implement a second billing or credit system.                                            |
| Stable purchase principals are implemented additively, with checked-in rollout defaults still using the legacy mode.                       | Compatibility must be proved for the supported identity modes; an accepted RFC is not evidence of a production cutover. |
| Gemini client construction is shared, but requests, model selection, consent, safety handling, and usage parsing remain provider-specific. | Changing an API key or SDK is insufficient for a provider switch.                                                       |
| Durable scan ingestion, canonical response validation, species caches, and an AI usage ledger already exist.                               | Preserve them and add the missing provider and evaluation boundaries.                                                   |
| No dedicated identification benchmark, training corpus, or embedding pipeline was found.                                                   | Quality and savings claims need a baseline before model selection or training investment.                               |

Sources: [product definition](./01-master-product-document.md),
[revenue and identity](../features-and-hardware/02-revenue-and-identity.md),
[purchase-principal design](../rfcs/purchase-principal-auth-separation.md), and
[AI engineering](../system-architecture/04-ai-engineering.md). The SRD provides
the implementation evidence map.

## 4. Options evaluated

### 4.1 Family access

| Option                                                             | Product benefit                                                                                 | Constraint                                                                                                        | Proposed disposition                       |
| ------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- | ------------------------------------------ |
| A. A distinct subscription product supporting Apple Family Sharing | Fits the current iPhone product and delegates group management to Apple.                        | Limited household visibility; receipt, restore, and identity behavior need verification.                          | First option to validate.                  |
| B. Naturebook-managed households with invitations and seats        | Supports an explicit roster, roles, and potentially cross-platform access or shared allowances. | Adds membership authorization, invitation abuse controls, concurrent seat allocation, and billing reconciliation. | Select if those capabilities are required. |
| C. A shared login or shared observation account                    | Appears simple to explain.                                                                      | Conflicts with account ownership, consent, deletion, and private location boundaries.                             | Excluded.                                  |

Apple supports eligible subscriptions shared with up to five additional family
members. Enabling sharing for a product cannot be undone in App Store Connect;
the proposed separate product avoids changing existing individual products by
default.
[Apple Family Sharing configuration](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/turn-on-family-sharing-for-in-app-purchases).

RevenueCat exposes shared ownership information but does not provide a reliable
household linkage. It also documents an initial sharing delay of up to one hour.
Therefore Option A must not promise an in-app roster, immediate activation, or
exact household cost attribution.
[RevenueCat Family Sharing](https://www.revenuecat.com/docs/platform-resources/apple-platform-resources/apple-family-sharing).

The existing adult eligibility rule is a material dependency. Gemini's current
terms restrict API clients directed toward or likely to be accessed by people
under 18. Family positioning, including any proposed supervised-child use,
requires review against that restriction; a parent's subscription or consent
does not resolve it. [Gemini API terms](https://ai.google.dev/gemini-api/terms).

### 4.2 AI independence

| Option                                                    | Assessment                                                                                                                  | Proposed disposition                                        |
| --------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------- |
| Replace Gemini calls individually                         | Leaves inconsistent contracts, consent checks, retries, and cost reporting.                                                 | Excluded as the long-term design.                           |
| Internal adapters behind existing operation orchestration | Preserves current business logic and allows provider-specific capabilities and normalization.                               | Recommended.                                                |
| Add an external AI gateway                                | May assist transport or operations, but does not establish Naturebook's entitlement, data permission, or quality contracts. | Evaluate later if it solves a measured operating need.      |
| Immediately self-host all inference                       | Adds serving and model-quality responsibilities before a validated alternative exists.                                      | Defer until a specific workload passes the ownership gates. |

S1 makes OpenAI a candidate for routine explanation and difficult-case
adjudication; GPT-5.6 Luna and Terra are proposed comparison candidates, with
Gemini as the existing baseline. The excerpt also names DeepSeek as a possible
future comparison, without an exact model or capability contract. None is an
approved production selection. Use a matrix covering images, descriptions,
audio, video, mixed evidence, structured results, chat, and moderation.
Qualifying one cell does not qualify the entire provider.

### 4.3 Optimization and model ownership

| Investment                                                     | Expected value to test                                                                  | Required evidence                                                                       |
| -------------------------------------------------------------- | --------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| Complete usage accounting and a frozen benchmark               | Makes later quality and cost decisions credible.                                        | Coverage and label-quality audit.                                                       |
| Prompt/schema tuning, safe caching, and media preparation      | May reduce work per request without changing the product promise.                       | Controlled quality, cost, and latency measurements.                                     |
| Specialized retrieval/classification with selective escalation | May serve common cases efficiently while retaining a stronger path for uncertain cases. | Calibrated coverage, open-set behavior, and end-to-end economics including escalations. |
| Fine-tuning a licensed pretrained model                        | May improve domain performance and give Naturebook control over adapted weights.        | Eligible data, license review, held-out gains, and serving cost.                        |
| Training a foundation model from scratch                       | Offers broader control at substantially greater scope.                                  | A separate business case showing that narrower approaches cannot meet the need.         |

No option is credited with savings or accuracy gains before measurement.

### 4.4 Assessment of the technical claims in S1

BioCLIP 2's published model card supports its role as a biological image encoder
for zero-shot and few-shot classification, lists an MIT license, and reports
training on nearly 214M images spanning 952K taxa. These facts justify testing
it; they do not establish Naturebook accuracy, latency, training-data rights, or
cost. Its listed class imbalance also matters for rare-species evaluation.
[BioCLIP 2 model card](https://huggingface.co/imageomics/bioclip-2).

| Claim or suggestion                                               | Required correction or qualification                                                                                                                                                  |
| ----------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Specialist scores are “real probabilities.”                       | Similarity, logits, and softmax scores are different quantities. Treat them as scores until calibrated on representative held-out data with unknown taxa and changing candidate sets. |
| Classifier and nearest-neighbor evidence are independent.         | They can share an encoder, images, and biases. Validate their joint benefit; do not multiply scores as independent probabilities.                                                     |
| Restrict the candidate list using location and season.            | Use a soft prior with a global/out-of-range path. Absence from an occurrence dataset is not proof of absence; locality may be missing, stale, or imprecise.                           |
| Multiple images automatically produce higher certainty.           | Evaluate correlated/duplicate views, different subjects, missing views, and conflicts. Fusion must not automatically inflate confidence.                                              |
| A high escalation rate means direct premium inference is cheaper. | Compute the actual break-even point. In the 1-unit routine/10-unit premium example, 60% escalation costs 7 units, not 10; latency or quality may still favor a direct route.          |
| Open weights make inference nearly free.                          | The model license does not remove hosting, idle capacity, preprocessing, retrieval, explanation, safety, maintenance, or data-rights costs.                                           |
| Every confirmation becomes a training example.                    | Confirmation is a review signal. Admission requires valid rights, provenance, independent label-quality controls, and deletion/withdrawal handling.                                   |

The iNaturalist 2021 benchmark contains about 2.7M training images across 10,000
species, but availability is not a blanket license for Naturebook training. GBIF
explicitly distinguishes media licenses from occurrence licenses. Source and
media permissions must be evaluated separately.
[iNaturalist 2021 benchmark](https://github.com/visipedia/inat_comp/tree/master/2021),
[GBIF multimedia guidance](https://techdocs.gbif.org/en/data-publishing/multimedia-publishing).

## 5. Users and scope

Primary users are an adult subscriber paying for shared access, another eligible
adult using that access, and an observer expecting dependable identification.
Engineering and ML need to compare providers and operate approved models.
Product and Finance need reliable usage and contribution-margin evidence.

The proposed first release includes adult subscription sharing, private
per-account records, entitlement lifecycle handling, provider abstraction,
baseline evaluation, an offline specialist proof of concept, and a limited
second-provider pilot. A child experience, shared albums, family location
tracking, household chat, pooled scan credits, classroom administration, and a
foundation-model training program each require their own scope decision. An
offline proof of concept is not a dependency for the adult family pilot or
permission to change identification authority.

Changing an AI provider must not silently change the meaning of Naturebook Pro,
remove a capture modality, or turn probabilistic identification into a safety
guarantee.

## 6. Product requirements

### 6.1 Family plans

| ID         | Requirement                                                                                                                                               | Acceptance evidence                                                                                                                                                                 |
| ---------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| PRD-FAM-01 | Each member uses an independently authenticated eligible account. AI processing requires that account’s applicable age, Terms, and processor permissions. | One person's purchase, consent, or account switch cannot grant another person's data access or processing permission. Verified paid access remains separate from AI permission.     |
| PRD-FAM-02 | Offer a clearly described family product with price, billing period, eligibility, sharing method, and included capabilities.                              | Product identifiers and prices come from the configured store offering; existing individual subscribers have an explicit upgrade and restore path.                                  |
| PRD-FAM-03 | Distinguish purchased access, shared access, pending verification, billing grace when verified, expiration, and revocation.                               | Subscriber and recipient journeys cover activation, cancellation, refund, sharing removal, and delayed provider events. Cancellation alone does not prematurely end valid access.   |
| PRD-FAM-04 | Keep observations, media, exact locations, messages, consent, and deletion controls private to their current owners.                                      | Cross-account access tests pass, including two members with the same paid benefit. Paying for access confers no content permission.                                                 |
| PRD-FAM-05 | Keep allowances and abuse controls per user in Option A. Paid shared access must not copy promotional grants or lifetime complimentary balances.          | Purchase restoration, account merge, sign-out, and concurrent scans cannot duplicate or transfer account grants. A family pool is absent unless separately selected.                |
| PRD-FAM-06 | Preserve records and explain the next action when shared access ends or cannot be verified.                                                               | Existing records remain available under the ordinary product rules; capture can follow the existing offline queue flow, while new paid processing requires authoritative admission. |
| PRD-FAM-07 | Measure family-plan economics without double-counting recipient access as subscription revenue.                                                           | Finance receives family-product revenue and recipient usage cohorts, an attribution-coverage note, and stress cases for maximum participation and heavy use.                        |

### 6.2 Provider flexibility

| ID        | Requirement                                                                                                                             | Acceptance evidence                                                                                                                                                                                                      |
| --------- | --------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| PRD-AI-01 | Every AI operation routes through a common backend contract, with provider details contained in adapters.                               | The SRD inventory is complete, Gemini passes adapter parity checks, and a second real provider passes its declared operation/modality contract. A mock alone does not establish portability.                             |
| PRD-AI-02 | Model choice is controlled by approved server policy, based on capability, entitlement, permissions, quality, availability, and budget. | A client cannot request an unapproved model, paid access, region, or provider by altering its payload.                                                                                                                   |
| PRD-AI-03 | Use only processors and purposes covered by the active user's valid permission.                                                         | Existing Gemini permission never silently authorizes another recipient; queued work and any shadow evaluation recheck eligibility before disclosure.                                                                     |
| PRD-AI-04 | Preserve identification meaning, uncertainty, taxonomy, safety outcomes, and durable success behavior across providers.                 | Validated responses remain compatible with supported clients; unsupported modalities and unsafe or incomplete output cannot masquerade as a successful identification.                                                   |
| PRD-AI-05 | Bound provider work and preserve quota/idempotency behavior.                                                                            | Ambiguous timeouts, client retries, and database failures do not trigger an adapter-level second provider call or duplicate user charges. Existing explicit recovery remains governed by its current contract.           |
| PRD-AI-06 | Make provider, model, policy version, failures, latency, and cost coverage observable without storing user content in telemetry.        | Usage distinguishes unknown from zero, includes failed/unknown attempts where measurable, and supports controlled cohort rollout and reversion.                                                                          |
| PRD-AI-07 | Distinguish routing on existing facts from escalation after a valid first-stage result.                                                 | A documented cascade meters every stage, rechecks processor permission, preserves one logical scan and user allowance settlement, and never treats a safety refusal or ambiguous timeout as a low-confidence escalation. |

### 6.3 Identification optimization and owned models

| ID         | Requirement                                                                                                                                   | Acceptance evidence                                                                                                                                                                                                                               |
| ---------- | --------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| PRD-OPT-01 | Establish representative, independently labeled identification evaluations before changing model authority.                                   | Versioned dataset, label provenance, frozen test split, taxonomy version, slice coverage, and reproducible baseline report exist.                                                                                                                 |
| PRD-OPT-02 | Optimize complete cost and latency while preserving useful quality and supported modalities.                                                  | Candidate-versus-baseline reports include failed attempts, retries, moderation, enrichment, escalation, media processing, and serving overhead.                                                                                                   |
| PRD-OPT-03 | Prefer lower-risk measured improvements before a new training program.                                                                        | Experiments cover existing cache reuse, prompt/output size, bounded media preparation, and model selection; each change has a quality guardrail.                                                                                                  |
| PRD-OPT-04 | Treat uncertain, unfamiliar, dangerous, and non-biological inputs explicitly.                                                                 | The system can abstain or use an approved escalation path; performance is reported by confidence coverage and error type, not just average accuracy.                                                                                              |
| PRD-OPT-05 | Build a candidate-evidence layer that supports calibrated taxonomic ranks, soft geographic/seasonal priors, retrieval, and multi-view fusion. | Visual-only and fused ablations, unknown/out-of-range cases, conflict handling, and an explanation-only LLM boundary are verified; raw similarities are not presented as probabilities.                                                           |
| PRD-OWN-01 | Admit data to evaluation or training only for an approved purpose with documented rights and retention.                                       | Every admitted asset has traceable source, permission or license basis, label provenance, and deletion/withdrawal handling. Public visibility alone is insufficient.                                                                              |
| PRD-OWN-02 | Introduce Naturebook-operated models in bounded tasks before expanding authority.                                                             | A retrieval model, classifier, or adapted model passes the same task-specific benchmark and operational gates as a hosted provider.                                                                                                               |
| PRD-OWN-03 | Make each ownership investment conditional on a documented economic and operating case.                                                       | The proposal specifies data availability, training/labeling cost, serving cost, maintenance, licenses, staffing, and the advantage over approved alternatives.                                                                                    |
| PRD-OWN-04 | Evaluate an early BioCLIP 2 proof of concept and report whether specialist inference is justified now or after launch.                        | Compare pinned checkpoints and eligible LLM baselines on representative observations; deliver accuracy/calibration, T4/L4/A10/A100-class throughput where available, capacity, full-cost sensitivity, and a staged implementation recommendation. |

## 7. Core journeys

**Subscriber and recipient:** An eligible adult chooses the family product,
completes the store purchase, and follows the sharing instructions. Another
eligible adult opens Naturebook with their own account and restores or refreshes
access. Pending activation is explained; verified shared access is recorded
independently of that person's AI permission. The existing age, Terms, and
onboarding gates still apply. Within those gates, declining or revoking a new
processor's permission preserves paid access and already available non-AI Pro
features. AI work uses an eligible consented route or presents the applicable
permission/unavailability state. Neither library is merged, and removal from
sharing changes access rather than ownership of existing records.

**A scan during a provider outage:** The observer captures normally. The backend
uses an approved route that supports the submitted evidence and the user's
permissions. If no eligible route is available, the ordinary recoverable failure
and queue experience applies. A timeout after dispatch is treated as uncertain
execution; it is not an invitation to submit the same content to another vendor.

**A candidate owned model:** The team registers a candidate and evaluates it
offline on authorized held-out data. A passing candidate can enter an approved
shadow or limited serving cohort. Its outputs cannot change user results,
taxonomy, or billing during shadow evaluation. Wider use follows measured
quality, cost, and operational evidence.

## 8. Success measures

Thresholds are proposals to ratify after the baseline is available. A confidence
interval too wide to support a quality decision means more evidence is needed.

Before qualification testing, decision D4 must bind each operation/modality to
its primary endpoint, label/rank policy, acceptance coverage, minimum critical
slice sample sizes, and explicit slice thresholds. The identification margin
below compares the same pre-registered endpoint on paired observations. Chat,
summaries, suggestions, and moderation require their own task-specific quality
and safety thresholds; they cannot qualify through a species-accuracy result.

| Measure                                     | Proposed target or decision rule                                                                                                                                                                                                                |
| ------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Account isolation and entitlement integrity | Zero cross-account disclosures or duplicated account grants in the required negative and concurrency tests.                                                                                                                                     |
| Family access convergence                   | Online refresh reflects an authoritative entitlement update within 60 seconds at p95, measured after the update is received by Naturebook. Store propagation delay is measured separately; repair follows the existing reconciliation controls. |
| Family adoption and retention               | Establish eligible-paywall conversion, recipient activation, and payer retention baselines in the pilot; Product sets targets before expansion. Do not invent household-level metrics when linkage is unavailable.                              |
| Family contribution margin                  | Positive at the approved heavy-use scenario and acceptable at the chosen support/usage percentile; price and margin floor remain undecided.                                                                                                     |
| Identification quality                      | On the frozen paired benchmark, the one-sided 95% lower confidence bound for candidate minus baseline primary accuracy is at least −1 percentage point, with separate critical-slice requirements.                                              |
| Safety and uncertainty                      | No new confirmed release-blocking safety regression; report open-set errors and accuracy at matched acceptance coverage so increased abstention cannot conceal a decline.                                                                       |
| Complete serving cost                       | Initial optimization goal: at least 20% lower cost per successful eligible identification, including unsuccessful attempts and related processing. This is a target to test, not a forecast.                                                    |
| Latency                                     | Preserve documented non-provider p95 ≤1 second and response-to-first-render p95 ≤300 ms. Compare end-to-end p50/p95 against the same modality, network, and device cohorts.                                                                     |
| Data eligibility                            | Every benchmark/training asset has approved provenance; every promoted model has a dataset version, license record, evaluation report, and serving owner.                                                                                       |

The latency boundaries come from the current
[AI engineering contract](../system-architecture/04-ai-engineering.md#benchmark-timing).
They are documented gates, not newly measured production results.

For the economic analysis, use net subscription receipts and measured variable
costs. Include all participating users' inference, media, and support costs in a
family scenario. For Option A, use cohort accounting and modeled household
scenarios where purchaser-to-recipient attribution is unavailable.

### 8.1 Economics: verified rates and illustrative scenarios

The standard text-token rates quoted in S1 match the official model pages
checked on 2 September 2026:

| Candidate     | Input / 1M tokens | Cached input / 1M tokens | Output / 1M tokens |
| ------------- | ----------------- | ------------------------ | ------------------ |
| GPT-5.6 Luna  | $0.20             | $0.02                    | $1.20              |
| GPT-5.6 Terra | $2.00             | $0.20                    | $12.00             |

These are list rates, not a price per identification. The pages also describe
long-context and cache-write pricing conditions. The excerpt does not include
the earlier per-request token/image assumptions needed to establish its
$0.001/$0.01 identification examples.
[GPT-5.6 Luna](https://developers.openai.com/api/docs/models/gpt-5.6-luna),
[GPT-5.6 Terra](https://developers.openai.com/api/docs/models/gpt-5.6-terra).

For a routine-first cascade, let `c` be the first call's mean cost, `s` the
additional stronger call's mean cost, and `r` the escalation fraction. Before
other costs, mean spend is `c + r × s`; it beats a comparable strong-only cost
`b` only when `r < (b - c) / s`. With S1's 1/10-unit example and `b = s = 10`,
the cost-only break-even is 90%. This threshold changes with longer escalation
prompts, extra explanations, quality requirements, and latency constraints.

The following reconstructs S1's **hypothetical** 4M observations/month scenario
using its flat $0.001 routine call, $0.01 strong call, and $1,000 specialist
hosting assumptions. None is a measured Naturebook workload or hosting quote.

| Scenario                                | Specialist + strong identification spend | If every observation also gets a separate $0.001 explanation |
| --------------------------------------- | ---------------------------------------- | ------------------------------------------------------------ |
| Specialist first, 15% strong escalation | $7,000/month                             | $11,000/month                                                |
| Specialist first, 5% strong escalation  | $3,000/month                             | $7,000/month                                                 |

Under the same flat-call assumptions, routine-only is $4,000/month and
strong-only is $40,000/month. The $7,000 routing subtotal is 82.5% below the
strong-only example, but it is not total product cost and is already above the
routine-only example. Compare complete routes that meet the same quality and
output requirements. If a strong response already supplies the final
explanation, do not charge for an unnecessary second explanation in the model.

The decision model must vary explanation frequency, escalation by modality,
images/frames per observation, utilization, idle/warm capacity, indexing,
preprocessing, retries, moderation, enrichment, transfer, and operations. Fixed
hosting costs can be amortized only while capacity and latency targets hold;
scaling does not preserve a $300 or $1,000 bill indefinitely. S1's volume bands
are hypotheses, not a launch rule. The SRD defines the throughput and break-even
report required to decide **implement now versus after launch**.

## 9. Delivery sequence

| Stage                                             | Deliverable                                                                                                                                                                              | Exit condition                                                                                                                                        |
| ------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| 0. Resolve product choices and establish evidence | Record S1 decisions still needed; validate family receipt/identity behavior; inventory AI calls, data rights, costs, and benchmark gaps.                                                 | Decisions D1–D7 below have owners; the first release scope and baseline plan are agreed.                                                              |
| 1F. Family pilot                                  | Approved adult sharing mechanism, store-product preparation, entitlement integration, lifecycle UI, and tests.                                                                           | Privacy, restore, billing, account-switch, and economics checks pass. This can proceed alongside the AI work.                                         |
| 1A. Provider foundation                           | Gemini adapter, canonical contracts, capability registry, permission mapping, and attempt accounting.                                                                                    | Gemini-only behavior passes the existing system gates and the benchmark baseline.                                                                     |
| 1B. Specialist proof of concept                   | Offline BioCLIP 2 candidates, soft priors, retrieval/fusion ablations, and comparisons with the existing LLM and selected challengers.                                                   | Report quality, calibrated coverage, throughput, complete cost, and implement-now versus after-launch recommendation; no production authority change. |
| 2. Alternative provider and optimization pilot    | One qualified alternative route plus controlled prompt/cache/media experiments; an explicitly funded routine-first cascade only if its quality and economics pass.                       | Quality, safety, latency, cost, and data-processing requirements pass for each enabled workload.                                                      |
| 3. Specialized model ownership                    | An eligible confirmed-observation pipeline after launch, a calibrated classifier/retrieval system, then a small head or partial fine-tuning and an operated serving path when justified. | Measured advantage justifies training and operating responsibilities.                                                                                 |
| 4. Broader model investment                       | Expanded modalities or foundation-model proposal, if justified.                                                                                                                          | A separate investment case beats the narrower alternatives on the agreed product need.                                                                |

Child access, if required, adds an explicit dependency on a suitable provider
agreement, age/guardian design, privacy rules, and child-appropriate safety and
community behavior. It must not be folded into the adult pilot as a billing
flag.

Any public family pilot also depends on the existing
[consent production-readiness hold](../legal/production-consent-readiness-2026-08-03.md).
Its candidate-specific iOS/backend evidence, App Store 18+ and marketing review,
paid Gemini billing/DPA evidence, and counsel/privacy controls must be satisfied
through that canonical process. Apple sharing is not recipient-age evidence. A
new provider or live shadow cohort additionally requires its processor,
disclosure, purpose, contract, and region evidence before receiving user data.
The stages above do not clear those dependencies.

## 10. Decisions and material risks

| Decision                                     | Proposed starting point                                                                                                               | Evidence or owner needed                                                                                                                                                                    |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| D0. Source reconciliation                    | Completed for supplied excerpt S1; product choices remain proposed.                                                                   | The excerpt is summarized and factual/cost claims are assessed; it does not record binding family, pricing, provider, data, or rollout decisions.                                           |
| D1. What does “family” mean?                 | Apple Family Sharing for eligible adults; private accounts.                                                                           | Product confirms Apple group sharing versus an app-managed household, invitations, children, or classroom use.                                                                              |
| D2. What is sold?                            | A separate family product with per-user usage controls.                                                                               | Product/Finance define billing periods, prices, eligible products, upgrade behavior, geography, and any explicit usage allowance.                                                           |
| D3. Which identity mode supports the pilot?  | Preserve the current compatibility contract.                                                                                          | Engineering proves receipt ownership, family recipient restore, transfer behavior, and supported legacy/stable modes.                                                                       |
| D4. What is the second-provider workload?    | Evaluate OpenAI Luna/Terra for eligible workloads and BioCLIP 2 specialist candidates against Gemini; production choice remains open. | Engineering/ML document capabilities, retention, region, terms, cost, and a workload-specific qualification record with primary endpoint, rank policy, sample sizes, and safety thresholds. |
| D5. Which data can support owned models?     | Use only separately verified eligible material; do not presume all historical scans qualify.                                          | Product and the appropriate legal/data owners approve each purpose, source, license, and retention rule.                                                                                    |
| D6. What scale and investment are justified? | Baseline-first targets and staged ownership.                                                                                          | Product/Finance/ML approve traffic assumptions, margin floor, experiment spend, staffing, and promotion thresholds.                                                                         |
| D7. Initial specialist coverage              | Explore the S1 North American/common-taxa starting point; 5–15K taxa is a sizing hypothesis.                                          | Product/ML select the actual taxa, geography, modalities, unknown-case policy, and sufficient rights-cleared labels before setting coverage claims.                                         |

The largest risks are identity transfer accidentally treating family recipients
as one account, increased AI cost per paid subscription, unsupported child use,
provider-specific behavior hidden behind a generic interface, and biased or
unlicensed training data. The SRD translates these into concrete isolation,
admission, evaluation, and lifecycle requirements.

Gemini's current terms restrict using the service to develop competing models.
Do not assume its responses may be used as a teacher dataset for a replacement;
that route needs a separately verified contractual basis.
[Gemini API terms](https://ai.google.dev/gemini-api/terms).

The existing scientific-retention contract is also distinct from a
model-training permission: account deletion removes stored media while retaining
restricted, ownerless scientific facts. Those facts are not necessarily
anonymous, and they do not constitute an available paired media corpus.
[Scientific observation retention](../backend-and-data/17-scientific-observation-retention.md),
[Terms review](../legal/terms-counsel-review.md#drafting-position).
