# Naturebook AI Provider Flexibility — PRD

Document ID: NB-PRD-IDENTIFICATION-001\
Version: 0.3\
Date: 2 September 2026\
Status: Active infrastructure plan; Gemini remains the only enabled provider\
Suggested owners: Backend and Product, with iOS contract review\
Companion: [Provider Flexibility SRD](../rfcs/identification-foundation-srd.md)

## 1. Goal and benefit

Prepare the identification backend so we can add or change AI providers later.
**Keep Gemini for every identification request now.** Preserve the existing
Gemini model choices, prompts, media preparation, confidence behavior, and
subscription rules. Supporting species-content generation also stays on Gemini.

This phase creates a common provider interface, explicit task configuration, and
the tests and measurements needed to make a later change manageable. Its benefit
is reducing the amount of identification code that a future provider change must
touch. It does not promise better accuracy, lower cost, or faster answers by
itself.

OpenAI is an example of a provider we might add later, not an implementation,
evaluation, or rollout commitment in this phase. No alternate-provider SDK,
credentials, paid requests, or live shadow calls are needed to complete it.

## 2. Scope and actual identification inputs

The active scope includes the primary identification endpoint, its supported
compatibility endpoints, and supporting species overviews, lookalikes, and group
tags. This includes `enrich-scan` and related background content-refresh
workers. Shared helpers must preserve their other callers.

| Input or task                                   | What the model receives                                                                                                                          | Provider in this phase |
| ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------- |
| Still-photo identification                      | One or more prepared images, with optional text context.                                                                                         | Gemini                 |
| Description-only identification                 | Text, without fabricated visual evidence.                                                                                                        | Gemini                 |
| Identification from a five-second video capture | Normally five sampled image snapshots, about one per second, with their clip/frame order. The raw video is not sent to the identification model. | Gemini                 |
| Audio identification                            | Prepared audio and applicable context.                                                                                                           | Gemini                 |
| Images or sampled frames with audio             | The images and separately prepared audio together, with their existing relationships.                                                            | Gemini                 |
| Species overviews, lookalikes, and group tags   | Existing task-specific content inputs.                                                                                                           | Gemini                 |

A video capture is an **ordered set of image snapshots for visual inference**.
The saved playback video and the inputs sent to the model are separate. The
current pipeline can also extract companion audio; when that audio is included,
it remains part of the observation. This plan preserves that behavior.

A future provider handling snapshots alone needs qualified multi-image support,
not native video-file input. If the observation includes audio, it also needs to
handle that complete combination. Clip origin remains useful context and
provenance; it must not automatically force a native-video capability
requirement.

Each observation keeps **one primary identification call**, including its
explanation and required observed details. Five snapshots do not mean five
separate identifications. Existing separately admitted enrichment and moderation
operations retain their own lifecycle.

Field/Insight, Explore, and Dictionary chat migrations, replacement of
public-audio moderation, family plans, BioCLIP, model training, automatic
provider failover, model cascades, and changes to video sampling are outside
this phase.

## 3. Build now and defer until a provider change

| Build now                                                                             | Do when we decide to add another provider                                                        |
| ------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| Common task/input/output interfaces with a Gemini adapter.                            | Implement and configure the selected provider's adapter.                                         |
| Server task bindings that all resolve to the existing approved Gemini models.         | Extend authoritative admission for exact qualified models and supported inputs.                  |
| Preserve current Gemini consent and result interpretation behind explicit boundaries. | Complete the new processor's onboarding, permission, and confidence/consumer compatibility work. |
| Record route/model/usage facts through the existing execution and accounting paths.   | Add any provider-specific usage units, prices, retention, and transport handling.                |
| Prove Gemini parity and use a deterministic test adapter to exercise the interface.   | Compare a real candidate against Gemini on eligible, independently verified examples.            |

The test adapter is confined to tests and cannot be selected in production. It
proves that callers use the interface; it does not qualify a real provider or
prove identification quality.

The default implementation preserves existing public API payloads, iOS models,
confidence labels, and consent screens. Necessary internal metadata additions
must remain scoped; a future provider migration is not a prerequisite for this
infrastructure work.

## 4. Product requirements

| ID        | Requirement for the current phase                                                                                                                                             |
| --------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| PRD-PF-01 | Put scoped identification and content tasks behind common interfaces and explicit server bindings; every enabled binding remains Gemini.                                      |
| PRD-PF-02 | Preserve actual accepted evidence, complete results, uncertainty, safety, and durable saved observations. Video capture uses sampled images and any included companion audio. |
| PRD-PF-03 | Inventory endpoint, helper, enrichment, and background content-refresh dispatches; replace hidden Gemini construction in scoped callers with explicit task execution.         |
| PRD-PF-04 | Keep database-authorized Gemini models, entitlement, and budget limits authoritative. Reject unknown providers and unsupported inputs before dispatch.                        |
| PRD-PF-05 | Preserve current account/processor permission and revocation checks, including queued work; do not add or infer permission for another recipient.                             |
| PRD-PF-06 | Keep Gemini confidence thresholds, candidate behavior, current client payloads, and historical interpretation unchanged. Document what a later model change must revisit.     |
| PRD-PF-07 | Preserve one observation allowance lifecycle, one primary call, deadlines, and retry/replay behavior.                                                                         |
| PRD-PF-08 | Expose task, admitted model, route version, timing, errors, and normalized usage through bounded internal execution/accounting interfaces. Preserve explicit coverage gaps.   |
| PRD-PF-09 | Verify current behavior and interface substitution with Gemini fixtures and a test-only adapter; do not require another live provider to complete the milestone.              |
| PRD-PF-10 | Deliver a controlled infrastructure release and a concrete future-provider onboarding, qualification, switching, and return procedure.                                        |

## 5. Delivery plan

| Phase                          | Deliverable                                                                                                                                                    | Completion condition                                                                                                                                    |
| ------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| P0. Map the current flow       | Caller/task inventory including enrichment and content-refresh workers; actual inference-input map; current Gemini request/settings and measurement baseline.  | Capture, provider, admission, result, and accounting boundaries are identified, including sampled frames and optional companion audio.                  |
| P1. Isolate Gemini             | Shared task contracts and a Gemini adapter; scoped callers use the common interface.                                                                           | Requests, prompts, media, output handling, primary-call count, and dependent operations retain current behavior.                                        |
| P2. Make bindings explicit     | A Gemini-only registry tied to current server admission; distinct model, media, permission, and confidence references; normalized internal execution metadata. | Every enabled task resolves to the same admitted Gemini model as before. Unknown providers and capability mismatches fail before disclosure.            |
| P3. Prove the foundation       | Parity, routing, media, permission, quota, result, recovery, and test-adapter coverage; a documented later-provider procedure.                                 | The current Gemini flow passes and a test-only substitution exercises the common interface without changing caller logic or allowing production access. |
| P4. Release the infrastructure | Controlled rollout of the Gemini-backed implementation under existing release procedures.                                                                      | Gemini continues to serve all scoped requests, operating limits hold, and the approved return to the prior Gemini-backed implementation is verified.    |

Backend owns the implementation and measurement. Product reviews the preserved
experience and future change procedure. iOS and other consumer owners review
compatibility where an affected boundary requires it. No new provider rollout or
consent-screen migration is part of P0–P4.

## 6. How we would change providers later

When there is a concrete reason to change a task's provider:

1. **Choose the task and candidate.** Specify the actual inputs: text, images,
   ordered video snapshots, audio, or their combination. Pin the exact model/API
   variant and implement its adapter.
2. **Make it eligible.** Extend server admission and accounting; complete the
   actual processor's contractual/data-handling onboarding, user permission,
   media transport, and confidence/old-client compatibility work.
3. **Qualify it.** Compare complete results, confidence, safety, latency, and
   cost against Gemini using eligible independent examples and predeclared
   acceptance limits.
4. **Change selected bindings gradually.** Route a small eligible cohort to the
   qualified provider, monitor it, and retain an eligible Gemini return path.
   Keep in-flight work and saved results tied to their recorded interpretation.

Other task bindings can stay on Gemini. Once adapters, permissions, admission,
and result contracts support both choices, subsequent compatible switches can be
reviewed server configuration changes. Installing an adapter alone cannot make a
new provider ready for live traffic.

These are future change requirements, not remaining work for the current
infrastructure milestone. The
[SRD](../rfcs/identification-foundation-srd.md#7-verification-and-future-qualification)
separates current verification from future provider qualification.

## 7. Completion and authority

This phase is complete when the shared infrastructure is verified with Gemini,
the production registry remains Gemini-only, current identification behavior is
preserved, and the later change procedure identifies the work still needed for a
real second provider. Do not describe test-only substitution as a completed
multi-provider integration.

The repository's [AI contracts](../system-architecture/04-ai-engineering.md),
[consent readiness requirements](../legal/production-consent-readiness-2026-08-03.md),
and release procedures remain authoritative. This is a planning document; it
changes no implementation or deployed configuration. The
[earlier combined PRD](./02-family-plans-and-ai-platform-prd.md) remains
deferred background.
