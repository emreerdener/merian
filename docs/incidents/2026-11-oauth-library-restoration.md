# Incident: Library restoration skipped after an already-linked OAuth session

- **Date detected:** 2026-11-12
- **Status:** Native corrections validated and installed in the simulator;
  library and saved-photo navigation verified; fresh live OAuth replay unrun
- **Affected environment:** Primary-app 1.1.0 simulator, normal OAuth
- **Current contract:**
  [Library transitions](../backend-and-data/21-guest-library-transitions.md)

## Symptom and bounds

The user reached Scans after normal OAuth but saw an empty library alongside a
published-media-unavailable count. Those are independent projections: the count
comes from Explore incidents and does not establish private scan loss. Both the
biological grid and non-biological collection appeared empty. No data deletion
or account replacement was performed during this investigation.

## Reproduction and cause

The actual `AuthSessionLifecycleCoordinator`, compiled with its existing
synthetic harness, skipped historical synchronization when the purchase identity
was already linked; a newly linked identity scheduled it. OAuth can link that
identity inside its transition before the deferred Auth listener runs.
`PurchaseIdentitySessionCoordinator.ensureIdentity` correctly returns false for
an already-ready identity. Using that return value to decide whether to restore
the library violated the independent restoration contract.

The source reproduction establishes a defect, not yet the sole cause of the
reported simulator symptom. Retained simulator diagnostics did not provide a
restoration error. The existing restoration-status UI and the corrected runtime
remain the next discriminators. Exact deployed backend source review found no
ordinary scan-select/grant/owner-detail contract incompatibility.

## Correction and verification

Stable authenticated publication now schedules restoration without requiring a
new purchase link. Test execution and pending purchase handoffs remain excluded.
Current session/generation, transition and native-media renewal checks remain
before scheduling; historical hydration retains its own library-owner lease.

The host before/after reproduction passes. Independent read-only review accepts
the correction. Native tests include already-linked OAuth, pending handoff,
stale-session/transition and media-renewal rejection, plus existing historical
coalescing and purchase-identity checks. Native results and simulator validation
are pending; scoped static preflight and strict lint pass.

## Deployment, runtime and data recovery

Backend deployment: **Not performed; no backend change in this correction.**
Corrected simulator installation/runtime verification: **Pending.** Data
recovery: **Not performed.** No records were deleted, reset or repaired. No
credentials, account identifiers, raw responses, scan content or session state
are included in this record.

## Exit criteria and retained evidence

Confirm native regression results, update the existing simulator while
preserving its data, and verify that historical records restore. If it remains
empty, continue diagnosis rather than claiming recovery. Full History activation
and all-media acceptance remain separately open. The local Completion401 packet
retains source hashes, before/after reproduction, review, build results and the
unobserved deletion-tombstone/read race for later affected acceptance review.

## November 12 runtime recovery update

The supplied restoration-status screenshot showed the unmatched/not-recorded
account fallback. One existing Retry synchronization action progressed through
Restoring library to Library restoration completed. Scan tiles then populated,
with the generic empty-library message gone. The separate five published-media
incidents remained. This establishes that cloud records existed and ordinary
hydration succeeded; it is not media repair or verification of the corrected
candidate, which has not yet been installed. No reset, uninstall or sign-out was
used.

## Candidate validation update

Sixty-one distinct native checks now have passing results across the retained
runs. The initial architecture failure was two extra comment lines against the
unchanged Auth budget; removing only those comments restored7,887 lines. The
first historical-sync selector named the file rather than its class; the second
run executed all five actual historical scheduler checks and the source-reading
architecture suite. No skipped test is counted as passing. The release-optimized
simulator build is still pending; the automatic sign-in path is proven by
synthetic regression, not a new live OAuth exchange.

## November 12 saved-scan crash follow-up

The optimized restoration build succeeded but was not installed. A subsequent
user crash report contains a SwiftUICore required-environment assertion. The
exact gesture is uncertain. Read-only tracing found that LocalScanInsightLoader
requires AppDIContainer but the shared injection modifier supplied only its
managers. The modifier now supplies the owning container too, with an
independently reviewed rendered-child identity regression. This changes no
persistence, session, OAuth or backend behavior. Native regression execution and
saved-scan runtime verification remain pending storage availability; the
unchanged 25 GiB pre-build floor is enforced. The local Completion402 record
retains the evidence and resume steps. Existing library data remains preserved.

## November 12 corrected simulator verification

After the user freed storage, all 10 dependency-injection/Core architecture
tests passed (zero failures/skips), followed by the optimized build. The
data-preserving 1.1.0 (275) simulator update succeeded with unchanged directory
identities and verified executable/signature. Scans populated without a sign-in
prompt or restoration spinner. An existing saved photo displayed its image and
saved identification; returning, closing/reopening Scans and reopening that
photo also succeeded. The reported navigation crash is mitigated and verified in
this simulator. The fresh live OAuth scheduling path remains covered by
synthetic regression, not a repeated live sign-in; full History activation and
all-media acceptance remain open. No reset, sign-out, media repair or backend
deployment occurred. Completion402 retains the exact artifact and sanitized
runtime receipts.
