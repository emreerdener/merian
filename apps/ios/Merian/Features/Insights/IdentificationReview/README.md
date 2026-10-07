# Insight Identification Review

`IdentificationReview` owns the candidate-confirmation and confidence UX for a
completed biological Insight. The canonical product behavior remains
[Insight Sheet](../../../../../../docs/features-and-hardware/05-insight-sheet.md#identification-candidates).

## Ownership

- `Candidates/Models` owns candidate visibility, swipe-session transitions, and
  typed candidate presentation or dismissal values.
- `Candidates/Services` is the only candidate owner allowed to resolve live
  entitlements, image dependencies, or `InferenceEngine` review mutations.
- `Candidates/ViewModels` owns scan-and-generation-fenced modal presentation,
  pending dismissal requests, local card dismissal, and mutation orchestration.
- `Candidates/Views` contains full-screen destinations and the swipe-modal
  composition root. Drag offsets, grid selection, animation completion, paywall
  visibility, and the 1.5-second success delay remain view-owned.
- `Candidates/Components/{Card,Review,Swipe}` contains rendering grouped by the
  interaction it supports. Candidate artwork uses the injected Species Reference
  image dependency rather than resolving its live loader locally.
- `Confidence/Models` owns badge labels, confidence-band presentation, copy
  fallbacks, and typed outer-sheet actions.
- `Confidence/Services` owns refinement-snapshot loading, Settings opening, and
  refinement route requests. `Shared/Services` owns the narrow SwiftData actor
  and haptic adapter used across both areas.
- `Confidence/ViewModels` owns explanation-sheet identity, nested candidate
  action staging, route resumption, and generation-fenced refinement loading.
- `Confidence/Views` composes the badge and explanation sheet. Detents, shimmer,
  icon rotation, paywall visibility, and actual SwiftUI dismissal stay in the
  views; `Confidence/Components/{Guidance,ReviewState,Scale}` renders the
  subordinate sections.

Platform-neutral Models import no SwiftUI, UIKit, or SwiftData. Views and
Components perform no networking, persistence fetches, singleton lookup, or
direct review mutations. Dependency value initializers are inert for tests and
previews; existing public feature-view initializers explicitly default to
`.live`, preserving production call sites and signatures without making an
otherwise plain dependency value resolve global services.

## Confidence display boundary

`InferenceConfidencePolicy.displayBands` supplies the existing Strong / Possible
/ Weak labels. Recognized Gemini profiles keep their tier-specific thresholds.
The exact shipped OpenAI photo profile uses Strong at `0.95`, Possible at
`0.60`, and Weak below `0.60`, regardless of plan tier. Its explanation
identifies the score as a model estimate, without a Flash/Pro accuracy or
upgrade claim. Unknown or damaged present provenance retains Needs review;
confirmed decisions still take precedence.

These are display thresholds only. Candidate visibility, review collections,
sharing recommendations, score-based promotions and rewards continue to use
`bands` / `SpeciesData.identificationConfidenceBands`, which do not qualify
OpenAI scores. See the
[threshold decision](../../../../../../docs/rfcs/identification-openai-confidence-display-2026-09-28.md)
for the evidence, scope and calibration limits.

## Modal action lifecycle

`CandidateSwipeModal` records a typed `CandidateSwipeDismissalRequest`
containing the action, scan ID, and engine presentation generation, then closes
through its explicit binding. The owning `CandidatesCard`, `InsightContentView`,
or `ConfidenceExplanationSheet` resumes that request only from the candidate
sheet's real `onDismiss`. `CandidateReviewViewModel` rejects a request or
binding update that belongs to an older modal subject, and the owner revalidates
the captured scan and generation before invoking the injected mutation. A
pending request cannot be taken while the modal still reports itself presented,
is consumed at most once after dismissal, and is cleared if the current scan
disappears instead of being retained for a later subject.

The Insight content host wraps that request in
`InsightCandidateSwipeDismissalRequest` and serializes it through
`InsightContentPresentation`; both value types live in `Shell/Models`, while the
candidate feature retains its review policy and UI. This boundary prevents the
Shell from absorbing candidate-domain behavior merely because it owns the modal.

Confidence explanation follows the same rule for community and refinement
handoffs. Nested candidate actions resolve first; actions leaving the
explanation are staged as `ConfidenceExplanationDismissalAction` and consumed by
`ConfidencePresentationViewModel` only after the outer sheet dismisses. Never
mutate the engine, request a sibling route, or sleep for an assumed dismissal
animation inside a presented review surface. The confidence owner likewise
refuses pre-dismissal consumption and clears pending state when its current scan
is no longer available. A stale nested-candidate request is consumed and
discarded before the explanation checks whether its captured subject remains
current, so it cannot survive for a later callback.

Each `SwipeableCandidateCard` owns one typed `CandidateCardPresentation` slot
for the original capture, reference-image gallery, and distinguishing feature.
Those lightweight destinations share one `.sheet(item:)`; do not add independent
Boolean sheet presenters to the card.

## Media decoding boundary

`CandidateSwipeLiveThumbnail` and `OriginalCapturePiPView` retain only local
decode presentation state. Their detached downsampling work must check task
cancellation before publishing; the original-capture picture-in-picture task is
also keyed to and revalidates the engine presentation generation. Candidate
reference-image discovery and loading remain owned by the injected Species
Reference image dependency rather than these views.

## Refinement and entitlement boundaries

`ConfidenceExplanationViewModel` loads only an immutable
`IdentificationReviewRefinementSnapshot` through
`IdentificationReviewDatabaseActor`. A load generation prevents an older scan
from replacing a newer explanation's refinement description. The explanation
continues to observe the environment-provided `RevenueCatManager` for reactive
plan presentation; action-time entitlement checks in the candidate modal use the
injected service closure. Complimentary Results copy and Pro admission remain
governed by
[Three Complimentary Pro Scans](../../../../../../docs/backend-and-data/18-complimentary-pro-scans.md).

## Verification

Mirrored tests under
`MerianTests/Features/Insights/IdentificationReview/{Candidates,Confidence}`
cover swipe-session and visibility policy, stale modal ownership, one-time
dismissal-action consumption, rejection of pre-dismissal consumption, confidence
copy and bands, inert test dependencies, route injection, and overlapping
refinement loads. `IdentificationReviewArchitectureTests` enforces the folder
owners, Services-only live effects, platform-neutral Models, retired legacy
locations, absence of unchecked sendability, and the 600-line production-file
ceiling.

## Identification rejection menu action

**Mark as incorrect** is the last action in the scan menu’s Identification
section and appears below Ask the community in the confidence sheet’s button
stack. Both actions are red and show a confirmation alert with a destructive
Mark as incorrect action and Cancel before saving. Confirmation calls the
retained `InferenceEngine.markIdentificationIncorrect` workflow for the captured
scan. Already rejected, pending, and ineligible identifications do not offer the
action. The original identification names, reasoning, and reference content
remain visible. The confidence badge turns red and reads **Incorrect**, and the
confidence sheet heading reflects that state. A red **Marked as incorrect** card
above the candidates mirrors the Match confirmed layout, with an inline **Undo**
action.

Saved review decisions and queued operations remain intact. A presentation-only
copy restores the original AI result and confidence without restoring species
authority, statistics, or Field Trip credit. Background review sync continues.

When an identification is marked incorrect, candidate cards and the end of the
candidate swipe deck hide the green original-identification confirmation slider.
Alternative candidate selection remains available.

After a rejection is saved locally, a brief **Marked as incorrect** toast offers
**Undo**. The menu offers **Undo incorrect** while the original rejection
remains reversible. The confidence sheet offers **Undo** in the incorrect-state
card; the completed candidate-review screen retains its neutral gray Undo
button. The menu shows **Incorrect mark undone** after Undo is saved locally.
Undo needs no confirmation, restores the confidence presentation and candidate
confirmation controls, and does not confirm the species. It uses the durable
review queue, including when the rejection has not yet synced. Reanalysis
proposals awaiting acceptance and conflicts do not offer rejection Undo.

After Undo, **Mark as incorrect** is available immediately, including while Undo
is waiting to sync. Repeated rejection and Undo operations remain ordered in the
durable queue.

The exhausted candidate-review screen offers **Mark as incorrect** last in its
action stack as a red slide-to-confirm control. Completing the slide saves the
mark directly, without an additional dialog, and shows the immediate Undo toast.
A reversible rejection replaces that action with **Undo incorrect**. The
completion screen scrolls when its content exceeds the available height.

**Review alternatives** remains in the scan menu after all candidates have been
reviewed. It reopens the stored candidate list without clearing saved completion
state or resurfacing the inline candidate card.

In the confidence sheet, the incorrect-state card replaces the standalone gray
Undo button. Menu and completed candidate-review Undo actions remain available.

Confirmation sliders await their action, show progress while it runs, and reset
when the action returns instead of permanently displaying a success checkmark.
The candidate owner reports success only when the same scan is confirmed and no
AI-review intent remains pending. Failed confirmation can be retried; an already
queued confirmation explains that it is waiting to sync without enqueueing a
duplicate. Explicit-primary confirmation awaits the existing serialized review
operation before evaluating the result.

## Incorrect-identification next steps

The main biological Insight shows a white, shadowed **Find a better match** card
above the candidates when the local review state is `aiRejected`, including a
pending rejection. It uses the surrounding candidate-card dark-mode styling and
stacks existing **Reanalyze species** and **Ask the community** actions. Actions
follow the host's eligibility and scan/generation guards; the card is hidden if
neither action is available. It is independent of candidate availability,
dismissal, or exhaustion and disappears after Undo or accepted identification.
The confidence sheet and its Undo card are unchanged.

## Prepared protected reanalysis handoff

When the host supplies `SavedReanalysisPreparation`, candidate and confidence
reanalysis prepare a ticket at the user's tap before child dismissal. Cards
inside the confidence explanation forward the same ticket through both modal
layers; they do not prepare again when either layer closes. The parent Insight
owns request resolution, current-owner/source validation and cancellation. A
child's stale or abandoned pending action cancels only its ticket. Protected
failures never call legacy refinement, and their lock display is independent of
legacy Pro admission. With no capability, existing entitlement and route
behavior remains unchanged. Review actions retain their existing separate owner.

Each child-local ticket owner cancels and clears its pending handle on
disappearance, including removal before a nested dismissal callback. Forwarding
clears local state first, so disappearance cannot cancel a request already
passed onward. Parent cancellation also clears its pending chat ticket.

## Protected identification history

Candidate and Confidence review controls consult the fresh enrollment guard.
Staged or acknowledged history, missing records and failed lookups deny legacy
confirmation, rejection, Undo, alternative override and reset. Already-open
sheets and delayed dismissal callbacks recheck the guard before mutation.
Protected review belongs to the retained selected-result Shell host or
historical preview; nil protected access never restores legacy permission.
Confidence's protected reanalysis handoff remains independent. Ordinary
unenrolled scans retain their existing controls. This wiring is prepared behind
disabled gates; see the canonical Insight contract for activation and remaining
qualification.

## Integrated review: proposal and rejection are distinct

Only an explicit `aiRejected` state displays **Incorrect**. The legacy
replacement flow preserves its existing carry contract: a new proposal is
`awaitingAcceptance`, displays **Review new result**, and needs explicit
acceptance. It has not been rejected by the user. A settled species-level
proposal offers **Accept this identification** even without alternative
candidates. Pending sync, damaged review and ineligible acceptance explain why
further actions are unavailable. Broader identifications can use community help.

Prepared history reanalysis instead appends a separate unreviewed result and
preserves the selected result and its authority. It does not invoke legacy
carry. Viewing a completed result and using it remain separate actions.

The confidence card receives the same retained, receipt-bound protected Undo
control as the main menu. Both Shell and engine presentation scopes are checked
at invocation. Unavailable reversal is explained; no Undo confirms a species or
reverses another result's rejection. Delayed rejection, confirmation, Undo and
candidate-override callbacks cannot act on a later displayed subject or review.
Each legacy action captures the exact review shown with the action: the UI and
coordinator recheck it, and the existing write transaction compares it with
fresh durable authority before creating an intent. Candidate controls and
delayed child-dismissal handoffs retain that same review. Both authority-free
persistence paths compare it before saving; a denied legacy save stops remote
synchronization rather than treating a no-op as success. Alternatives never make
an obsolete proposal callback eligible after rejection. Rollout gates remain
disabled.
