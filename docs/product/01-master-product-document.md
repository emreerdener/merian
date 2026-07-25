# Naturebook Master Product Document

Repository-aligned edition - 22 July 2026

> Turn everyday curiosity into field science.

Document owner: Product and Engineering  
Review basis: Merian monorepo as inspected on 22 July 2026
Public product name: Naturebook  
Engineering identity: Merian  
Document status: Replacement for the stale master product document

# Document control

## Purpose

This document is the current product reference for Naturebook. It replaces claims in the prior Merian master product document that no longer match the repository. It describes what exists in the reviewed codebase, what is gated or incomplete, and which ideas remain strategic rather than implemented.

The repository is the authority for implementation status. Product strategy, market hypotheses, financial forecasts, legal conclusions, and store declarations require their own owners and evidence. They are included here only when they affect product direction, and are clearly labeled.

## Status vocabulary

| Status | Meaning |
|---|---|
| Implemented | A production code path or product surface exists in the reviewed repository. Deployment and store availability may still vary by environment. |
| Release-gated | Implemented behind tester, preview, subscription, or environment access. It is not a general-availability promise. |
| Partial | Meaningful code exists, but an end-to-end path, integration, or operational dependency is incomplete. |
| Planned | Product intent only. No complete supporting implementation was found. |
| Retired | A former design or policy that is no longer the current product behavior. |
| Requires review | Cannot be established from code alone and needs product, legal, finance, security, or operations review. |

## Snapshot and precedence

- This edition reflects the visible monorepo on 22 July 2026.
- Current source code, schemas, migrations, configuration, tests, and release guardrails take precedence over older prose documents.
- Where the repository contains conflicting prose, executable behavior and the newest explicit compatibility contract take precedence.
- Public-facing copy must use Naturebook. Merian remains the stable internal and technical identity where renaming would break compatibility.
- This is a product specification, not a claim that every implemented capability has been deployed to every environment or approved for every store listing.

## Current release identifiers

| Item | Current value |
|---|---|
| Public product | Naturebook |
| Subscription | Naturebook Pro |
| iOS marketing version | 1.0.2 |
| iOS build | 235 |
| Minimum iOS deployment | iOS 17.2 |
| Device family | iPhone |
| SwiftData schema | MerianSchemaV50 |
| Local Supabase Postgres | 17 |
| Website | https://naturebook.earth |
| Support | support@naturebook.earth |
| Preferred deep-link scheme | naturebook |

# Executive summary

Naturebook is an iPhone-first field identification and observation product. It lets a person capture a still image, short video, audio clip, or written description; receive an AI-assisted identification; preserve the observation in a personal library; and, when desired, share it with a nature community. Its differentiation is not simply an identification answer. The product combines multimodal capture, structured natural-history context, privacy-aware geospatial records, offline durability, and low-friction participation in field science.

The current product is materially broader than the stale document in several areas. Explore is implemented as a full social discovery system rather than a future or reaction-only concept. Field trips are available as a standard organizing feature. The capture workspace supports mixed media, short Pro video, descriptions, and audio. Offline submission is durable. Public web observation pages, an Explore widget, App Intents, an iMessage extension, and an Apple Watch target exist.

At the same time, the current implementation is narrower than the stale document in other areas. The Apple Watch capture path does not have a complete iPhone receiver. Full UI localization, minor-specific compliance controls, targeted observation bounties, and several older growth concepts are not present as end-to-end features. The former Rive experience, TelemetryDeck stack, two-call identification design, free-media expiration policy, and old subscription price points must not be represented as current.

The product should be managed around four truths:

1. Capture must remain fast, calm, and durable even when the network is unreliable.
2. Identification is probabilistic guidance, not an authority for consumption, handling, medical, or safety decisions.
3. Location and community features must reveal only the precision appropriate to the observer's privacy setting and ecological sensitivity.
4. Public promises must distinguish shipped behavior from gated, partial, planned, and externally reviewed work.

# 1. Product identity and positioning

## 1.1 Name and compatibility contract

The public product is Naturebook. User-facing copy, app display names, marketing pages, support references, web URLs, and preferred deep links should use the Naturebook identity.

Merian is the permanent engineering identity. The Xcode project and scheme, targets, bundle identifiers, app group, SwiftData schema names, backend resource names, RevenueCat identifiers, and existing media host remain Merian where compatibility depends on them. The main application bundle identifier is `app.merian.Merian`, the shared app group is `group.app.merian.shared`, and the current schema is `MerianSchemaV50`.

Legacy `merian.earth` links and the `merian://` scheme remain accepted compatibility inputs. New links should use `naturebook.earth` and `naturebook://`.

## 1.2 Product promise

Naturebook turns a moment of curiosity into a durable, contextual observation. The core promise is:

- Capture what you encounter with the medium that best fits the moment.
- Receive a useful identification with uncertainty, evidence, lookalikes, and safety context.
- Keep the observation in a personal, searchable field record.
- Share selectively, with privacy-aware location handling.
- Continue working through weak connectivity and synchronize later.

## 1.3 Strategic position

Naturebook sits between a fast identification utility, a personal natural-history notebook, and a community observation network. The intended advantage is the continuity between those modes: a scan becomes a structured record; a record can become a field-trip entry; and a chosen record can become a public post or export.

Market size, competitor conversion, acquisition cost, retention, and lifetime-value assumptions are strategic hypotheses. They are not implementation facts and must be maintained in a separate, dated business model.

# 2. Audiences and jobs to be done

## 2.1 Primary audiences

- Curious observers who want a quick, understandable answer about a plant, animal, fungus, or other natural subject.
- Hobby naturalists who want a private, structured history of encounters.
- Families and educators who use walks and outings as prompts for learning.
- Field participants who need reliable capture despite limited connectivity.
- Community contributors who want to publish observations, discuss identifications, and follow other observers.

## 2.2 Core jobs

- "Help me understand what I am seeing without making me configure a scientific workflow."
- "Save enough context that I can find and understand this encounter later."
- "Let me capture now even if the network is poor."
- "Let me choose how much location detail other people can see."
- "Help me organize a walk or outing as a coherent set of observations."
- "Let me ask follow-up questions while preserving the distinction between AI guidance and verified fact."

## 2.3 Product principles

- Curiosity first. The first useful action is capture, not account setup or form completion.
- Evidence over false certainty. Confidence, alternatives, lookalikes, and hazards matter.
- Durable by default. An accepted submission must not disappear because the app backgrounds or connectivity changes.
- Privacy by projection. Public views derive from owner-controlled records and reveal only approved precision.
- Calm field ergonomics. Capture controls, haptics, audio feedback, thermal behavior, and offline messaging should reduce cognitive load.
- Honest scope. Preview and partial features are labeled as such in product copy and planning.

# 3. Product surfaces

## 3.1 iPhone application - Implemented

The primary product is an iPhone application with capture, Insight, personal records, Explore, Field trips, profile, subscription, identity, privacy, settings, export, and deletion flows. The deployment target is iOS 17.2 and the current target family is iPhone only.

## 3.2 Public web - Implemented, read-only

The public Next.js application serves rich observation pages at `naturebook.earth`. Pages can display imagery, video, audio, species context, and universal-link handoff into the app. Policy routes are also present. The public web experience is a viewing and acquisition surface; social engagement actions remain in the native app.

## 3.3 Administration - Implemented, private

The private admin application runs separately from the public site. It uses Google OAuth, time-based one-time password step-up to AAL2, and role-scoped operations for Analyst, Moderator, and Owner responsibilities. The client and admin browser bundles do not contain the Supabase service-role credential. Privileged work is exposed through narrow server-side functions and RPCs.

## 3.4 Extensions and companion surfaces

- Explore widget - Implemented. WidgetKit surfaces Explore snapshots rather than a "Species of the Day" product.
- App Intents - Implemented. Identify and Recall intents provide system entry points using Naturebook wording.
- Messages extension - Implemented target. Supports sharing into iMessage within its current target scope.
- Apple Watch - Partial. Watch capture code records audio and context and transfers a payload, but the iPhone receiver required for a complete user journey was not found.

# 4. Capture workspace

## 4.1 Capture modes - Implemented

The capture workspace presents three user-orderable pages:

1. Scan - camera-based still and short-video capture.
2. Record - field audio capture.
3. Describe - text-first identification.

The first configured page initializes without unnecessarily starting hardware for a different mode. Reordering is a user preference and should be preserved.

## 4.2 Mixed-media submission model - Implemented

A submission can contain up to two user-created timeline items across supported media. The shared cap applies to still photographs, eligible Pro video, audio clips, and descriptions. The interface should communicate the remaining capacity consistently across all modes.

Mixed-media submissions route through the active multimodal identification function. Older single-purpose functions remain compatibility paths and should not be treated as the primary architecture.

## 4.3 Camera behavior - Implemented

Naturebook selects camera hardware in priority order based on device capability: virtual triple camera, LiDAR-backed configuration, dual camera, then wide camera. The workspace supports tap focus and exposure, pinch and swipe zoom, direct zoom controls, and approximately 0.5x to 15x zoom where hardware permits. Hardware shutter events use native capture interaction.

Viewfinder guidance uses bounded CPU luminance analysis at approximately three frames per second. A legacy/live inference preference can reduce default live inference on newer hardware. Product copy must not imply continuous high-cost analysis when this preference is disabled.

## 4.4 Still-image preparation - Implemented

Identification images are bounded before inference: approximately 768 pixels for the Flash path and 1,024 pixels for the Pro path. Display media is prepared up to approximately 2,048 pixels. The media preparation actor prefers WebP and falls back to JPEG with controlled quality. The user interface should use the prepared representations rather than decoding unbounded originals on the main thread.

## 4.5 Photo import - Implemented

The app accepts one image through the `public.image` document association and normal import path. Included EXIF date and location can be preserved. Imported content then follows the same crop, queue, privacy, quota, and identification rules as camera content.

This is not a general Share Extension. Product and support copy should describe it as an image import or "Open in Naturebook" flow.

## 4.6 Pro video capture - Implemented, Pro-gated

Pro users can submit a video of up to five seconds. Identification uses five ordered sampled frames and, when present, accompanying audio. The saved playback clip targets 720p or a 1,280-pixel long edge, approximately 3 MB, with a 12 MB hard cap.

Video is a short observation aid, not a general video publishing tool. Capture affordances must show the limit before recording.

## 4.7 Audio capture - Implemented on iPhone

The iPhone Listen flow records up to 15 seconds of audio as PCM Int16 WAV, presents waveform or spectrogram feedback, calculates signal-to-noise information, and preprocesses inference input to mono 16 kHz audio. Audio consumes one item in the shared two-item submission cap.

The legacy `/audio-spec` route exists for compatibility; new mixed-media work should use `/identify-multimodal`.

## 4.8 Apple Watch recording - Partial

The Watch target records up to 15 seconds in AAC/M4A and attaches available GPS and weather context. It attempts immediate `WCSession` messaging and can fall back to `transferUserInfo`.

The reviewed iOS code does not contain the corresponding receiver that completes ingestion into the main capture and identification pipeline. Until that receiver, reconciliation, user feedback, and tests exist, Watch logging must be labeled partial and should not be sold as a reliable end-to-end Pro capability.

# 5. Submission, identification, and Insight

## 5.1 Durable acceptance - Implemented

Every scan is inserted into the local durable queue at submission time before asynchronous network work begins. The product can therefore acknowledge capture without depending on a successful immediate request. When offline, Naturebook skips live inference, informs the user that the observation is queued, and retries through the background pipeline.

Quota is evaluated when the observation is accepted into the queue. A technical failure can refund usage. A completed non-biological result still represents a processed request and counts as usage.

## 5.2 Primary AI path - Implemented

The current primary server route is `/identify-multimodal`. The free path uses Gemini 2.5 Flash and the Pro path uses Gemini 2.5 Pro. Current generation settings are conservative and deterministic-oriented: temperature 0.1, seed 42, up to 8,192 output tokens, and a Pro thinking budget of 5,000.

The older document's mandatory two-call architecture is retired. The active design uses one primary identification call per scan, followed by optional asynchronous dictionary enrichment and result hydration. Compatibility routes such as `/identify` and `/identify-describe` remain for existing clients or fallback behavior.

## 5.3 Context timing - Implemented

For live camera submissions, identification receives a short context grace window of approximately 150 milliseconds. Context that arrives later can be patched through `/update-scan-context` without repeating the biological identification request. This keeps the capture response fast while preserving weather or place data that becomes available shortly afterward.

## 5.4 Expected result shape

An identification may include:

- Common and scientific names.
- Taxonomic and dictionary-backed context.
- Confidence and candidate alternatives.
- Lookalikes and differentiating features.
- Habitat, seasonality, range, behavior, or natural-history notes when supported.
- Hazard, handling, toxicity, or caution information when relevant.
- A non-biological classification when the content is not a supported natural subject.

The interface must present uncertainty as useful information. It must not convert model output into guarantees.

## 5.5 Insight and follow-up

The Insight experience is the structured reading surface for an observation. It can combine the primary result with asynchronously hydrated species data, candidates, dictionary material, and follow-up AI chat for eligible users.

Idle camera throttling hooks exist in `CameraManager`, including a one-frame-per-second idle state and restoration behavior. No shipped sheet-lifecycle call site was found. The product document therefore does not claim that opening Insight automatically switches the camera to 1 FPS. Wiring and verification are required before making that promise.

## 5.6 AI safety boundary

Naturebook is educational. It is not a substitute for an expert, field guide, poison control, veterinary advice, medical advice, or local regulations. The product must never recommend eating, handling, treating, or approaching an organism solely on model output. Hazard messaging should be prominent when confidence is low or consequences are high.

# 6. Personal records, search, and organization

## 6.1 Observation library - Implemented

Accepted scans become durable local records and synchronize with the backend when possible. The personal library supports recall and organization of observations, including media, identification results, time, place context, privacy, and field-trip membership.

Search and filtering should prioritize the mental model of "what I saw, where, and when" rather than expose backend taxonomy mechanics.

## 6.2 Field trips - Implemented

Field trips, also described in parts of the codebase as outings, group observations into a coherent activity. They are a standard product feature rather than a Pro-only expedition. Standard outings must be explicitly started; matching scans do not auto-start them. The capture workspace can show progress against an active outing's goal, and a saved biological Insight persistently lists every outing or joined Event credited by that scan.

A scan can advance several deliberately active experiences, but it receives at
most one goal credit per standard outing and one per joined Event. A visibly
selected eligible camera goal wins inside its own outing; deterministic
specificity and checklist ranking handles all other cases. Identification
corrections may move or remove credit while an experience is unfinished.
Completed experiences remain immutable.

Seasonal Challenges and Events are separate concepts. Their current access is preview-gated for designated testers and simulator conditions, and that gate is not a server authorization boundary. Product marketing must not represent preview access as general availability or use the client gate as a security control.

## 6.3 Expedition Mode - Implemented, Pro-gated

Expedition Mode is a performance and field-resilience profile, not another name for a Field trip. It targets reduced camera load, disables glass effects, and pauses ordinary queue synchronization while active. It is intended for extended field use where battery and thermal stability matter.

## 6.4 Achievements and persona - Implemented

The app contains 16 achievement types covering first actions, category depth, environments, conditions, and observation quality. Current categories include first scan, first Field trip, Naturalist, Botanist, Zoologist, Mycologist, Urban, Cat, Dog, Frost, Alpine, Nocturnal, Guardian, Conservationist, Toxicologist, and Perfect Lens.

Persona progression uses five thresholds: Observer at 0, Casual Explorer at 10, Dedicated Naturalist at 50, Verified Scholar at 250, and Apex Observer at 1,000. The experience is asset-based SwiftUI. The former Rive-driven interactive sphere concept is not the current implementation.

Achievements are primarily computed from local projections. First Field trip uses server-authoritative state. The system is personal progression, not a competitive ranking product.

# 7. Explore and community

## 7.1 Explore status - Implemented

Explore is an active product surface, not a future roadmap item. It supports public, following, trending, nearby, and map discovery. Rich posts can include imagery, short video, and audio. Canonical public links use `naturebook.earth`.

## 7.2 Social graph and engagement - Implemented

The current community model includes:

- Likes.
- Comments, replies, and comment reactions.
- Following.
- Hashtags and discovery views.
- Notifications.
- Public usernames, display names, avatars, and author profiles.
- Community identification participation.

The stale "react-only" description is retired. Conversation and relationship features are part of the current codebase.

## 7.3 Reporting and blocking - Implemented

Users can report posts, comments, and other users, and can block users. Moderator workflows are supported through the private admin surface. Community safety must be treated as an operational system requiring staffing, review standards, appeals, and response targets in addition to code.

## 7.4 Public location projection

Community and web surfaces must render projected public location, never assume the owner's exact coordinate is public. The projection depends on the observation privacy mode and can be further obscured for sensitive species.

## 7.5 Audio sharing safety - Implemented, fail-closed

Explore audio sharing uses a content-addressed attestation flow. The backend generates a spectrogram and uses a Gemini Flash speech/non-speech classifier. Publication is fail-closed when safe classification cannot be established. This reduces the risk of publishing human speech accidentally captured during a nature recording.

# 8. Monetization and entitlements

## 8.1 Free usage

The database policy grants one free primary scan per UTC day. The iOS local
meter previews that limit but is not authoritative. Unlimited local-meter
bypasses are DEBUG-only; Release and TestFlight still reach the server quota.

## 8.2 Naturebook Pro products

| Product | Type | Current display price |
|---|---|---|
| `pro_week` | Non-renewing 7-day pass | $3.99 |
| `pro_annual` | Auto-renewing annual subscription | $24.99 |

New eligible users can receive a dynamic seven-day Pro trial. Storefront pricing and eligibility ultimately come from the store and RevenueCat; fixed display strings must be audited before release in every region.

## 8.3 Pro capability set

The current entitlement model removes the ordinary one-scan product cap for
Pro and includes the Gemini Pro path, short video scans, follow-up AI chat,
mixed multi-capture, Expedition Mode, offline queue benefits, group-event
hosting, and Apple Watch logging. High database fair-use and rate ceilings bound
automation and provider cost, so product copy must not promise technically
unbounded model traffic.

This list must be read with implementation status. Events are preview-gated. Apple Watch logging is partial because the phone receiver is incomplete. Paywall copy must not promise an end-to-end capability that the released client cannot fulfill.

## 8.4 Entitlement synchronization

RevenueCat webhooks synchronize tier and timed-pass expiry into backend state
only after raw-body HMAC verification and an authoritative subscriber lookup.
Unique event IDs plus a per-user event-time watermark prevent duplicate or
delayed deliveries from rolling access backward, and accepted tier/expiry
changes atomically advance `users.entitlement_version`. A RevenueCat transfer
fetches authoritative source and destination state and commits both projections
under one event transaction. Paid-model authorization uses the database quota
reservation, not client display state or Edge-isolate memory; lookup errors fail
closed.

Biological media stays in the storage prefix selected when it was uploaded. There is no free-to-Pro or Pro-to-free object migration. Storage policy must not be documented as if a subscription change relocates existing media.

## 8.5 Unit economics

The repository contains token ledgers and SQL-based cost reporting. Current analytic constants reflect Gemini Flash at approximately $0.30 per million input tokens, $0.03 per million cached input tokens, and $2.50 per million output tokens; Gemini Pro is modeled at approximately $1.25 per million input tokens and $10 per million output tokens.

These constants are operational inputs, not a financial forecast. The former fixed CPS, MRR, CAC, LTV, and margin claims are retired from the product specification. Finance should maintain a dated model using actual request mix, media costs, refunds, store fees, taxes, retention, and current vendor pricing.

# 9. Onboarding, permissions, and account identity

## 9.1 Onboarding - Implemented

Current onboarding contains four steps:

1. Welcome.
2. Camera.
3. Location.
4. Ready.

Photo-library and notification permissions are requested progressively at the point of need. Hardware initialization and ordinary synchronization are gated until onboarding is complete. The older six-step flow is retired.

## 9.2 Permission philosophy

- Explain the immediate benefit before requesting a system permission.
- Do not request photo access solely because capture exists; request it when the user imports.
- Do not request notifications until a notification benefit is understandable.
- Location remains optional for identification, though it improves context and record quality.
- A denied permission must degrade to a usable alternative rather than a dead end.

## 9.3 Anonymous-first identity - Implemented

Naturebook starts with an anonymous Supabase user and a device-derived local identity protected through Keychain-based storage. A person can later link or merge with Apple or Google authentication. RevenueCat and PostHog identities transition to the authenticated Supabase UUID when appropriate.

Sign-out clears the local user scope without redefining backend retention or deletion policy. Account deletion is a separate, explicit operation.

# 10. Privacy, location, and data rights

## 10.1 Location modes - Implemented

Each observation can use one of three location-sharing modes:

- Open - public views may use the recorded coordinate subject to ecological safety rules.
- Obscured - public views use an offset location at roughly 10 km precision.
- Private - public views do not expose the observation location.

The owner record and public projection are separate. Exact owner coordinates may synchronize to the backend for owner functionality; they are not necessarily "device only." Public clients must consume the privacy-projected representation.

For endangered or sensitive species, an additional safety offset can extend to approximately 50 km. Ecological sensitivity can therefore override a user's broader public setting.

## 10.2 Exports - Implemented

Darwin Core Archive export uses an asynchronous request-and-worker flow. The
database atomically leases canonical jobs, the worker keyset-pages records into
a streaming multipart archive, and Resend receives a job-idempotent delivery
request for a time-limited link. Successful/non-terminal requests are
rate-limited to approximately one per 24 hours; failed jobs remain retryable.

Personal exports can include the owner's exact location where allowed.
Global/public exports include only open public records and apply privacy rules.
Global attribution uses a versioned, dedicated HMAC-SHA256 key rather than a
plain hash, JWT secret, or fallback salt. Export policy should be tested against
current schema and ecology rules rather than relying on older blanket claims
about domesticated observations.

## 10.3 Deletion - Implemented

Account deletion uses `/safe-delete` to revoke authentication, tombstone scan ownership to a zero UUID where retention integrity requires it, anonymize cost and linkage records, and queue object-store deletion. After backend success, the client removes the local store.

Deleting an individual scan uses an owner-bound `/delete-scan` path that removes owned media and then the database record. Deletion user experience should clearly separate local removal, server completion, and any legally required residual anonymized records.

## 10.4 Analytics privacy boundary

Product analytics is consolidated under PostHog. "Zero PII" should be interpreted as a telemetry collection boundary, not a claim that Naturebook processes no user data. The product necessarily processes observations, media, account identifiers, and optional location to provide its service.

The repository does not establish final App Store privacy nutrition labels, ATT conclusions, COPPA compliance, or jurisdiction-specific minor consent. Those are Requires review. No complete minor-specific precise-location gate, App Attest, or DeviceCheck enforcement was found in the reviewed paths.

## 10.5 Localization status - Partial

The identification pipeline can pass device locale as contextual input and common-name handling is primarily English-oriented. A full localized UI resource system was not found. Naturebook should not claim comprehensive internationalization until product copy, pluralization, accessibility strings, taxonomy naming, and support content are localized and tested.

# 11. Safety and moderation

## 11.1 Identification safety - Implemented foundation

Result models support hazard and warning content. The product should surface toxicity, handling concerns, aggressive behavior, protected status, and uncertainty without sensationalizing them. Safety language must emphasize observation and expert confirmation.

## 11.2 Model moderation - Implemented

The identification backend treats Gemini safety finish reasons and medium or high safety ratings as moderation signals. Staged uploads are promoted into public storage only after safe processing. Strike handling escalates from deletion and warning for early strikes to shadowban behavior at three or more strikes.

Automated moderation is one layer. False positives, appeals, abuse patterns, and urgent safety cases require documented human operations.

## 11.3 Community safety - Implemented foundation

Post, comment, and user reporting plus blocking provide the product foundation. Before broad community growth, operations must define response ownership, evidence retention, enforcement levels, appeal handling, and child-safety escalation.

## 11.4 Legal and store claims - Requires review

The codebase can show available controls; it cannot approve privacy policy language, health and safety representations, App Store declarations, subscription terms, age ratings, or regional compliance. Those claims require dated legal and operational sign-off.

# 12. Offline, synchronization, and resilience

## 12.1 Offline-first queue - Implemented

An observation is durably represented before upload or inference. Offline work is modeled as persistent job records with explicit state. Background URL sessions support transfer continuation when the app is not foregrounded.

The queue uses a network path monitor with approximately three seconds of debounce. It avoids ordinary transfer work on constrained paths and follows expensive-network policy. Synchronization retries should remain idempotent and observable.

## 12.2 User-visible phases

The product models distinct synchronization phases rather than a single spinner. Interfaces should translate these into clear language such as queued, preparing, uploading, identifying, enriching, completed, or needs attention. A retry should not create a duplicate observation or double-charge quota.

## 12.3 Failure semantics

- Offline is a normal state, not an exceptional alert loop.
- Accepted work remains visible locally.
- A local technical failure may refund the advisory iOS meter. Server quota
  refunds only a proven pre-provider no-op; provider failures remain charged
  and may retry as a newly metered attempt.
- User deletion cancels or reconciles pending work.
- Background retries must use bounded backoff and preserve enough diagnostics for support.
- Low-data and constrained-network choices are respected.

# 13. Performance, thermal behavior, and field ergonomics

## 13.1 Hardware orchestration - Implemented

The hardware orchestrator adapts the capture experience to system pressure:

| Condition | Target behavior |
| Nominal | Up to 60 FPS where appropriate. |
| Fair | Approximately 45 FPS. |
| Serious | Approximately 30 FPS and glass effects disabled. |
| Critical | Approximately 15 FPS with a visible warning. |
| Expedition Mode | Approximately 24 FPS, glass effects disabled, ordinary queue sync paused. |

Thermal degradation should preserve capture correctness before visual richness. A reduced frame rate is preferable to a crash, camera interruption, or lost observation.

## 13.2 Media limits

Current backend and client guardrails include approximately 5 MB per staged image, 2.7 MB per audio object, and 12 MB per video object. A signing request accepts up to six files, including at most two audio files and one video file. Queue processing uses bounded batches rather than unbounded parallel upload.

## 13.3 Accessibility and haptics

Accessibility is a release requirement across capture, result reading, Explore, paywall, and privacy flows. Controls need meaningful labels, scalable text, non-color status cues, reduced-motion behavior, sufficient contrast, and clear focus order. Haptics should confirm state changes and capture completion without becoming the only feedback channel.

Repository presence alone is not proof of complete WCAG or VoiceOver conformance. Accessibility must remain part of manual and automated release testing.

# 14. Media and storage lifecycle

## 14.1 Durable biological media - Implemented

Biological observation media is durable for both free and Pro users unless the user deletes it, moderation removes it, or an operator performs an authorized action. The former 90-day expiration for free biological media is retired.

Biological objects remain in their original free or Pro prefix. Subscription changes do not migrate them.

## 14.2 Temporary and non-biological media

Object-store lifecycle rules abort incomplete multipart uploads after seven days. Staging, quarantine, and generated export areas expire after approximately one day. Avatars and biological scan media are durable. Non-biological scans and their media are purged after 30 days, with server and local cleanup paths.

The former "Archive Safety Protocol" and domesticated-media purge description are retired. The current Archive Manager downloads generated archive ZIPs; it is not the owner of an expiring-media rescue workflow.

## 14.3 Storage safety

- Upload authorization is owner-bound and size-bound.
- Public promotion follows moderation and processing.
- Deletion paths reconcile database and object-store state.
- Staging and quarantine remain short lived.
- Client UI must not invent retention promises from bucket prefixes.

# 15. Backend and data architecture

## 15.1 Core stack

Naturebook uses SwiftUI and SwiftData on iOS, Supabase for database, authentication, Realtime, storage coordination, and Edge Functions, Cloudflare R2 for media, Gemini for multimodal inference, RevenueCat for entitlements, PostHog for analytics, and Resend for transactional export delivery.

The reviewed local Supabase configuration targets Postgres 17, caps ordinary API result sets at 1,000 rows, and contains a large migration history plus dozens of Edge Function directories. Schema changes must be migration-driven and tested against Row Level Security.

## 15.2 Data access boundaries

- Mobile and web clients use user-scoped Supabase access.
- Row Level Security and owner checks are the primary database boundary.
- Service credentials remain server-side.
- Admin operations use narrow RPCs or functions plus role and assurance checks.
- Public web pages receive only publishable projections.
- Exact owner context is not selected merely because a public post exists.

## 15.3 Current Supabase posture

New tables and Data API objects should use explicit grants and RLS rather than assume broad defaults. GraphQL exposure is opt-in rather than an assumed universal interface. Anonymous-key access, generated OpenAPI behavior, and nested Edge Function calls must be reviewed against current platform restrictions when backend dependencies are upgraded.

## 15.4 Direct and pinned dependencies

The iOS project directly depends on RevenueCat, PostHog, Supabase Swift, and Google Sign-In. The reviewed lockfile includes PostHog 3.48.2, RevenueCat 5.66.0, Supabase Swift 2.43.0, and Google Sign-In 9.1.0, plus transitive packages.

Key Edge Function dependencies include Supabase JS 2.110.6, JOSE 5.9.6,
aws4fetch 1.0.20, Google Gen AI 1.0.0, and Deno standard library 0.224 imports.
DwC-A production delivery uses the local streaming ZIP implementation and
Resend's HTTP API; JSZip remains only an independent ZIP-reader test dependency.
Versions are a snapshot, not a promise; upgrades require tests and security
review.

Rive and TelemetryDeck are not direct dependencies in the current implementation.

# 16. Telemetry, quality, and operations

## 16.1 Analytics - Implemented

PostHog is the consolidated application analytics provider. App initialization does not depend on a fixed startup sleep. Events should be minimal, purpose-bound, and reviewed for accidental observation, location, or account leakage.

Cost and usage truth lives in backend ledgers and SQL reporting rather than a client analytics event alone.

## 16.2 Quality gates - Implemented foundation

The repository contains CI workflows for Supabase formatting, linting, type checking, tests, migration and function deployment; iOS project guardrails; startup-safety builds; scan-media health checks; and community taxonomy import.

The old document's fixed coverage percentages are not verified by the repository and are retired as current claims. Teams may set coverage goals, but release confidence must be based on critical-path tests, migration safety, media-path checks, privacy projection tests, and device validation - not one aggregate percentage.

## 16.3 Release-critical journeys

Each release should exercise at minimum:

1. New install through the four-step onboarding flow.
2. Anonymous still scan, queued acceptance, identification, and Insight.
3. Offline submission, relaunch, and later synchronization.
4. Pro entitlement activation and restoration.
5. Short video and audio limits.
6. Image import with and without EXIF context.
7. Open, obscured, and private public projections.
8. Explore post, report, block, and moderator handling.
9. Field-trip assignment and goal progress.
10. Individual scan deletion and account deletion.
11. Personal and public export generation.
12. Thermal, background, constrained-network, and low-storage behavior.

Apple Watch capture should not enter the release-critical "complete" set until the phone receiver and end-to-end tests exist.

# 17. Roadmap and release posture

## 17.1 General availability foundation

The release foundation consists of iPhone capture, multimodal identification, Insight, the personal record, privacy modes, offline durability, Field trips, Explore, public observation pages, identity, monetization, deletion, and export.

Exact availability still depends on deployment, store configuration, backend migrations, vendor credentials, and release flags.

## 17.2 Release-gated or partial work

| Area | Current status | Exit condition |
|---|---|---|
| Events and Seasonal Challenges | Release-gated preview | Server-authorized rollout, product rules, operations, and full tests. |
| Apple Watch logging | Partial | Implement phone receiver, reconciliation UI, failure handling, and end-to-end tests. |
| Full localization | Partial | Localized resource architecture, content coverage, taxonomy rules, and QA. |
| Minor-specific controls | Planned / Requires review | Age policy, consent design, location restrictions, legal review, and enforcement. |
| App Attest / DeviceCheck enforcement | Planned | Threat model, server verification, failure policy, and rollout. |
| Targeted observation bounties | Planned | Product model, abuse controls, incentives, backend, and UX. |
| Insight-triggered 1 FPS camera idle | Partial hook only | Wire lifecycle calls and validate restoration across navigation and interruptions. |

## 17.3 Retired concepts

- Merian as the public-facing brand.
- A six-step onboarding flow.
- A mandatory two-model-call identification pipeline.
- Gemini output limited to 1,000 tokens.
- Two free scans per day as the public policy.
- $2.99 weekly and $19.99 annual Pro pricing.
- Ninety-day free biological-media expiration.
- Subscription-driven media-prefix migration.
- Archive Manager as an expiring-media rescue system.
- Rive as a core persona or terrarium runtime.
- TelemetryDeck as an analytics provider.
- Explore as future, TikTok-only, or reaction-only.
- A "Species of the Day" widget as the implemented widget product.
- Apple Watch capture as a complete end-to-end feature.

# 18. Growth and product learning

## 18.1 Current growth loops

Implemented surfaces that can support organic discovery include public observation URLs, rich previewable media, universal links, profile and follow graphs, hashtags, comments, shareable records, the Messages extension, widgets, and App Intents.

Growth work must preserve private-by-choice observation behavior. A private record is not a failed social conversion.

## 18.2 Learning priorities

Product analytics should answer a small number of durable questions:

- Do new users complete a first useful identification?
- Does durable offline acceptance reduce abandonment?
- Which media types improve successful identification without raising failure or cost disproportionately?
- Do users return to records, Field trips, or Explore after the first scan?
- Which uncertainty and safety treatments improve trust and responsible behavior?
- Which Pro benefits drive sustained value rather than one-time trial activity?
- How often do location privacy controls change sharing decisions?

Metrics should be defined with event contracts, denominators, exclusions, and privacy review. The master product document should not embed undated target numbers.

# 19. Product and engineering directives

## 19.1 Naming

- Use Naturebook in all new user-facing strings and URLs.
- Preserve Merian technical identifiers unless a separately planned migration proves safe.
- Accept legacy domain and scheme inputs indefinitely under the compatibility contract.

## 19.2 Status honesty

- Never market a client-only preview gate as backend authorization.
- Never describe the Apple Watch path as complete before the iPhone receiver ships.
- Separate implementation status from deployment status.
- Treat market and financial assertions as dated analyses, not source-code facts.

## 19.3 Data and privacy

- Use projected location for public and community surfaces.
- Keep exact owner data out of public queries and telemetry.
- Make open, obscured, and private choices understandable before posting.
- Preserve user deletion intent across queued, database, and object-store states.
- Test RLS and grants for every new table, view, function, and storage path.

## 19.4 Capture and offline

- Insert durable local work before asynchronous upload or inference.
- Maintain idempotency across retry, relaunch, duplicate callback, and entitlement refresh.
- Keep media size, duration, item-count, and signing limits aligned across UI, client validation, and server validation.
- Degrade visual effects and frame rate before capture correctness.

## 19.5 AI and safety

- Keep one primary inference request as the default architecture; enrichment may be asynchronous.
- Display uncertainty and candidates where useful.
- Do not turn biological identification into consumption or handling advice.
- Record model, token, cost, moderation, and failure metadata server-side with access controls.
- Review vendor models, limits, and pricing before changing published cost or capability claims.

## 19.6 Community

- Ship reporting and blocking with every new social interaction surface.
- Keep moderation promotion fail-closed for public media.
- Treat community operations, appeals, and safety response as product dependencies.
- Avoid engagement mechanics that incentivize unsafe wildlife interaction or precise disclosure of sensitive species.

# Appendix A. High-impact correction register

| Stale claim | Repository-aligned correction |
|---|---|
| Product is publicly named Merian. | Public product is Naturebook; Merian remains the stable engineering identity. |
| Current schema is V45. | Current SwiftData alias is `MerianSchemaV50`. |
| Two free scans are allowed per day. | Public policy is one per day; Release and TestFlight use it, while unlimited local-meter overrides are DEBUG-only. |
| Pro costs $2.99 weekly and $19.99 annually. | Current fixed display values are $3.99 for a seven-day non-renewing pass and $24.99 annually. |
| Onboarding is six steps and requests all permissions. | Current onboarding is Welcome, Camera, Location, Ready; photos and notifications are progressive. |
| Identification always uses two model calls. | One primary Gemini call is followed by optional asynchronous enrichment. |
| AI output is capped at 1,000 tokens. | Current configuration allows up to 8,192 output tokens, with a Pro thinking budget. |
| Explore is future, video-feed-first, and reaction-only. | Explore already includes multiple feeds, map/nearby, rich media, likes, comments, replies, follows, profiles, reports, and blocking. |
| Field trips are the same as Expedition Mode. | Field trips organize observations; Expedition Mode is a separate Pro performance profile. |
| Watch capture is shipped end to end. | Watch recording and transfer exist, but the iPhone receiving path is incomplete. |
| Free biological media expires after 90 days. | Biological media is durable for free and Pro users unless deleted or moderated. |
| Upgrading moves media from free to Pro storage. | Existing objects remain in their original storage prefix. |
| Archive Manager rescues expiring media. | Archive Manager downloads generated export ZIPs; the former rescue protocol is retired. |
| GPS remains only on the device. | Exact owner location can synchronize; public views consume privacy-projected location. |
| The product has complete localization. | Locale informs identification, but a complete localized UI resource system was not found. |
| PostHog plus TelemetryDeck provide analytics. | Analytics is consolidated under PostHog; TelemetryDeck is not a current direct dependency. |
| Rive powers the core persona experience. | Current persona and achievement visuals are asset-based SwiftUI; Rive is not a current direct dependency. |
| The widget is Species of the Day. | The implemented WidgetKit surface shows Explore snapshots. |
| Opening Insight automatically idles the camera at 1 FPS. | Idle hooks exist, but no current sheet-lifecycle wiring was found. |
| Fixed coverage percentages prove release readiness. | Current CI has meaningful guardrails, but the old percentage claims are not repository-backed. |
| Historical CAC, LTV, MRR, and margin figures are current. | Financial forecasts require a separate dated model based on actual usage and current vendor costs. |

# Appendix B. Repository source map

The following files and areas were used as implementation authority. Paths are repository-relative.

## Product identity and release

- `docs/system-architecture/08-public-brand-compatibility.md`
- `project.yml`
- `README.md`
- `apps/ios/Merian/Models/Aliases.swift`
- `apps/ios/Merian/Config/MerianConfig.swift`

## iOS application and capture

- `apps/ios/Merian/App/`
- `apps/ios/Merian/Features/Capture/`
- `apps/ios/Merian/Features/Audio/`
- `apps/ios/Merian/Features/Describe/`
- `apps/ios/Merian/Services/CameraManager.swift`
- `apps/ios/Merian/Services/HardwareOrchestrator.swift`
- `apps/ios/Merian/Services/MediaPreparationActor.swift`
- `apps/ios/Merian/Services/UsageManager.swift`
- `apps/ios/Merian/Services/Sync/`

## Product surfaces

- `apps/ios/Merian/Features/Explore/`
- `apps/ios/Merian/Features/FieldTrips/`
- `apps/ios/Merian/Features/Profile/`
- `apps/ios/Merian/Features/Onboarding/`
- `apps/ios/MerianWatch/`
- `apps/ios/MerianExploreWidget/`
- `apps/ios/MerianMessages/`
- `apps/web/`
- `apps/admin/`

## Backend, privacy, and operations

- `services/supabase/config.toml`
- `services/supabase/migrations/`
- `services/supabase/functions/identify-multimodal/`
- `services/supabase/functions/update-scan-context/`
- `services/supabase/functions/safe-delete/`
- `services/supabase/functions/delete-scan/`
- `services/supabase/functions/`
- `.github/workflows/`

## Authority note

The source map is intentionally representative rather than exhaustive. A future change to any behavior in this document should update its implementation, tests, user-facing copy, and this product reference in the same change set when practical.
