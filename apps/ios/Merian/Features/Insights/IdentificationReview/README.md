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
