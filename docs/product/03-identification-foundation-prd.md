# Naturebook AI Provider Flexibility — PRD

Document ID: NB-PRD-IDENTIFICATION-001\
Version: 0.2\
Date: 2 September 2026\
Status: Active planning draft; provider flexibility only\
Suggested owners: Product, Backend, and iOS\
Companion: [Provider Flexibility SRD](../rfcs/identification-foundation-srd.md)

## 1. Goal and benefit

Let Naturebook choose an AI provider for each identification task without
rewriting the identification flow whenever that choice changes. Start by placing
the existing Gemini integration behind a common interface, then add OpenAI as
the second provider.

The practical benefits are:

- **Choice:** compare providers and select the one that meets our quality,
  speed, and cost needs for each task.
- **Less dependence on one supplier:** move future requests to another qualified
  provider when service, availability, or commercial terms change.
- **Smaller future changes:** adding or changing a model is concentrated in its
  adapter, configuration, and qualification work.

Provider flexibility does not itself improve identification accuracy or reduce
cost. Those benefits must be measured. Switching between already supported,
qualified routes should be a reviewed server configuration change; a new
processor, input capability, or result contract can still require backend and
app changes.

This revision narrows the earlier identification-foundation plan. BioCLIP,
specialist pipelines, model training, and family plans are deferred. The
[prior combined PRD](./02-family-plans-and-ai-platform-prd.md) retains that
background; none of those projects is a prerequisite for this work.

## 2. Scope and example configuration

The active scope covers identification and the content generation that supports
its results: descriptions, species overviews, lookalikes, and group tags. The
current primary endpoint and supported compatibility endpoints are included.

The first configuration to qualify is:

| Task or submitted evidence                           | Proposed provider                            |
| ---------------------------------------------------- | -------------------------------------------- |
| One or more still photos, with optional text context | OpenAI                                       |
| Description-only identification                      | OpenAI                                       |
| Species overviews, lookalikes, and group tags        | OpenAI                                       |
| Audio identification                                 | Gemini                                       |
| Video identification, including associated audio     | Gemini                                       |
| Combined photo/audio/video observation               | Gemini, using the complete accepted evidence |

The existing all-Gemini configuration remains the initial default and an
eligible return path. Exact OpenAI models are selected through evaluation.
Images, descriptions, and enrichment have separate settings; they do not have to
move providers together.

Each observation still uses **one primary identification call**. Its explanation
and required observed details remain part of that response. Existing separately
admitted enrichment and moderation work keeps its own lifecycle. Multiple photos
are assessed as one observation rather than becoming one identification per
photo.

Field/Insight, Explore, and Dictionary chat are outside this migration.
Replacing public-audio moderation is also deferred. Therefore, “Gemini for
audio/video” describes the proposed identification configuration, not every AI
call in the backend. Shared helpers must preserve these other callers.

Automatic cross-provider retries, confidence-based model escalation, running two
providers on every live scan, and splitting one mixed-media observation between
providers are outside the first release.

## 3. Intended experience

**Taking a photo:** the app sends its usual observation. The server chooses the
configured eligible provider, validates the answer, and returns the familiar
identification result. Users do not have to choose a model.

**Recording audio or video:** the server uses the qualified Gemini route. A
video's frames still count as video evidence for routing; associated audio and
media order must not disappear during conversion.

**Changing providers:** an operator changes an approved task binding for future
requests. Saved observations retain their original confidence interpretation;
in-flight work and retries follow their recorded route and existing recovery
rules.

**Using an older app or declining a new processor:** the account uses an
eligible Gemini route or the existing consent/unavailability experience. Adding
an OpenAI adapter cannot turn a Gemini-only permission into permission for
OpenAI.

## 4. Product requirements

| ID        | Requirement                                                                                                                                                         |
| --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| PRD-PF-01 | Configure providers independently for still-photo identification, description-only identification, enrichment tasks, audio, video, and mixed observations.          |
| PRD-PF-02 | Preserve supported evidence, result completeness, uncertainty, safety, and durable saved observations across providers.                                             |
| PRD-PF-03 | Include identification-dependent generation and background callers in the routing inventory; prevent hidden provider defaults in shared helpers.                    |
| PRD-PF-04 | Select only approved models that support the task and complete evidence, within server-authorized entitlement and spending limits.                                  |
| PRD-PF-05 | Check permission for every actual processor and purpose before sending data, including queued work and evaluations.                                                 |
| PRD-PF-06 | Keep confidence labels meaningful across providers and historical results. A new model's score cannot inherit Gemini thresholds automatically.                      |
| PRD-PF-07 | Preserve one observation allowance lifecycle, bounded execution, and existing retry/replay behavior; a lost response must not silently trigger another vendor call. |
| PRD-PF-08 | Measure provider, task, quality, latency, errors, and complete cost with appropriate data access boundaries and explicit gaps in usage coverage.                    |
| PRD-PF-09 | Qualify each new route against a representative, independently verified baseline before enabling it for users.                                                      |
| PRD-PF-10 | Support gradual activation and a tested return to an eligible qualified route, without requiring an app release for each compatible configuration change.           |

Product tier remains separate from provider choice. The server retains the
existing subscription and allowance rules; changing suppliers cannot silently
change a user's entitlement or make the same uncertainty appear more certain.

## 5. Delivery plan

| Phase                              | Deliverable                                                                                                                                        | Completion condition                                                                                                                             |
| ---------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| P0. Establish the baseline         | Inventory all scoped calls; prepare an eligible identification comparison set; record current Gemini behavior, quality, timing, and cost coverage. | Task owners, acceptance thresholds, critical cases, and comparison method are recorded.                                                          |
| P1. Isolate Gemini                 | Introduce the common adapter interface and move scoped Gemini transport behind it.                                                                 | Existing prompts, media preparation, primary-call count, quota, confidence, output, and recovery pass parity checks. Gemini remains the default. |
| P2. Make routing and clients ready | Add versioned task bindings, authoritative admission, processor permissions, provider usage records, and compatible confidence interpretation.     | Unsupported or unauthorized routes cannot dispatch; old and new consumers can safely read supported results.                                     |
| P3. Add and qualify OpenAI         | Implement photo/description and enrichment adapters; compare complete results against Gemini.                                                      | Each enabled task meets its quality, confidence, safety, latency, and cost criteria. Failed tasks stay on Gemini.                                |
| P4. Enable selected routes         | Activate qualified bindings for a small eligible cohort, then expand while checking results and rehearsing rollback.                               | Route changes work independently, operating limits hold, and returning future traffic to an eligible baseline is verified.                       |

Before any live traffic, the new provider also needs approved processing terms,
verified data-handling and production-account settings, and the applicable user
permission. P2/P3 must produce this onboarding record; an adapter and a consent
screen alone do not satisfy it.

P1 is independently useful even if OpenAI is not selected for live traffic. P2
and P3 may be developed alongside each other after the interface is stable, but
both must be complete before a new provider handles live observations.

Backend owns adapters, routing, admission, and measurement. Backend and iOS own
permission and result compatibility. Product and the identification-quality
owner set the comparison criteria; the appropriate privacy owner resolves
processor eligibility. These are proposed responsibilities, not staffing
commitments.

## 6. What counts as success

The first success is demonstrated interchangeability: Gemini and OpenAI
implement the same scoped task contracts, and an approved task can change
providers without rewriting the caller or changing unrelated task bindings.

Before live activation, require:

- Complete, valid results and preserved subject/safety behavior.
- Identification quality and confidence reliability within predeclared limits,
  measured at comparable rates of accepted and unresolved identifications.
- Full user-visible latency and cost within agreed budgets, including failures
  and dependent generation.
- Passing provider-onboarding, permission, compatibility, quota, recovery, and
  rollback checks.

P0 must freeze numeric quality margins, minimum coverage for important cases,
latency limits, and a cost ceiling before confirmatory comparison. Unset
criteria or an undersized evaluation cannot count as a pass. The
[SRD](../rfcs/identification-foundation-srd.md#7-qualification-and-measurement)
defines the measurements and existing timing constraints.

No percentage savings, accuracy improvement, or delivery date is promised by
this draft. A cheaper provider may be selected only after meeting the required
quality and operating limits.

## 7. Decisions to close during implementation planning

| Decision                                    | Proposed approach                                                                                               | Owner                                    |
| ------------------------------------------- | --------------------------------------------------------------------------------------------------------------- | ---------------------------------------- |
| First OpenAI model for each task            | Start with a small candidate set; select and pin exact API/model variants using the comparison results.         | Backend and identification-quality owner |
| Quality, latency, and spend thresholds      | Measure the Gemini baseline, then freeze task-specific limits before evaluating challengers.                    | Product and Backend                      |
| Confidence and older-client compatibility   | Preserve Gemini semantics in P1; agree the canonical interpretation and all read paths before admitting OpenAI. | Backend and iOS                          |
| New processor permission and initial cohort | Use actual processor/purpose permissions and begin with supported clients and eligible data.                    | Product, iOS, and privacy owner          |

The repository's [AI contracts](../system-architecture/04-ai-engineering.md),
[consent readiness requirements](../legal/production-consent-readiness-2026-08-03.md),
and release procedures remain authoritative. This document is a plan; it does
not change an implementation or activate a provider.
