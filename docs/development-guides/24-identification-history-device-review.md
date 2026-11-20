## November 13 — enabled Release candidate preparation

The main-app `Release` configuration now compiles and bundles the normal-OAuth
History capability, reusing the same primary identities and exact-host checks as
HistoryTesting. Debug remains inactive. Test/qualification configurations still
refuse archive/distribution. Local static stage diagnostics compile only under
`MERIAN_HISTORY_LOCAL_DIAGNOSTICS` in HistoryTesting and are forbidden in the
Release binary. The archive/IPA metadata validators require enabled History,
qualification off and unchanged primary namespaces; CI also checks the Release
binary for absence of the local diagnostic category.

This source preparation does not establish a clean candidate, complete Release
compilation, signed archive, phone upgrade, TestFlight or all-media acceptance.
Use the
[release checklist](../release-evidence/identification-history-release-checklist-2026-11-13.md)
for exact evidence and outstanding approvals. The installed417 simulator and its
preserved data remain unchanged by this preparation.

## November 12 — beta History activation and simulator recovery

Under the user's explicit beta-wide release/testing authorization, deployed
backend `c435ea80f5bace1d28b6fc383f290c264c73d3d9` on `qlarqavoqhkuwzmevrmf` now
has the34 current-scope History switches enabled. Completion408 committed and
independently read back the inventory, preserving all other18 switches and
non-gate fields. Photo/audio/video reanalysis, selection, review/Undo and
recovery are enabled for compatible clients. The existing scheduled cleanup
worker remains active. Completion409 verified a 68-byte synthetic private object
through upload, separate reader access, normal scheduled erasure and a permanent
empty marker; existing scans/media were untouched. The earlier407 query error
stopped before any write and remains recorded.

The current simulator is HistoryTesting1.1.0(275), artifact
`ed98804e978b733853c3d87a0a0d8f6917e7cef4f518559e2c8622a3cbffe2c0`.
Completion411 verified the preserved submission completed with two History
versions;413 verified selection/Undo and automatic incorrect-review/Undo list
refresh, preserving all six data identities. Original remains Current and both
versions are Not confirmed. No duplicate analysis is needed. The deterministic
refresh defect is fixed; the earlier intermittent selection-Undo freeze still
has no established cause and remains open.

Automatic prompts remain **PAUSED**. This is a local simulator artifact, not a
TestFlight or matching physical-phone build. The later Release preparation above
supersedes the former disabled Release configuration; Debug and local-only
archive restrictions remain unchanged. Use the
[single current release checklist](../release-evidence/identification-history-release-checklist-2026-11-13.md)
for all-media, accessibility, resource, cumulative-review and distribution gaps.
Later deletion/export/redesign and private-library migration remain separate.
Exact scoped results, failures and preservation evidence are in
[Completion413](../../.artifacts/native-app-capture-handoff-20261020/completion413-history-refresh.md);
activation/storage evidence remains Completion408/409. No fresh hosted readback
is implied by this November13 documentation reconciliation.

## November 12 — History with normal OAuth

`HistoryTesting` is a release-optimized local build of the primary app, using
`Config.xcconfig`, the existing Google registration and primary Keychain
session. It enables the complete prepared History composition without the
separate `HistoryQualification` Auth journal or timed identity-evidence window.
Release now uses this capability as described above; Debug remains disabled and
the existing qualification mode is unchanged.

`HistoryNormalOAuthConfiguration` requires both the compiled and bundled marker,
the primary app/group/Keychain identity, no alternate Auth namespace and the
exact existing beta host. Debug fixtures and qualification Auth cannot be
combined with this mode. The ordinary OAuth coordinator, account/library
ownership checks, current JWT, generation and container fences remain
authoritative. Signing in with another account does not relabel or release an
existing library.

The named `preservesExistingLibrary` policy stops destructive store recovery in
both testing configurations and enabled Release; a failed open preserves the
original store and reports `existing_store_preserved`. The primary session is
used directly, never copied into a parallel Auth client. Archive/distribution
remains blocked for `HistoryTesting`. This is a build configuration, not a
separate app, registration or hosted environment.

Select the **HistoryTesting** scheme in Xcode for this local mode. For managed
simulator compilation, use the wrapper-owned Merian scheme with an explicit
configuration (do not add another `-scheme` argument):

```bash
make ios-local-build ARGS='simulator -- build -configuration HistoryTesting -destination "generic/platform=iOS Simulator"'
```

Backend rollout gates remain independent. Installing this build does not
activate History, enroll existing scans or authorize provider execution.
Full-flow testing requires the existing beta activation and actual-byte cleanup
prerequisite; user sign-in and a selected existing scan provide the remaining
account/observation binding. Automatic prompts remain paused.

For the first live saved-photo enrollment, reaching the reanalysis composer
requires the enrollment path to read the exact selected state and acknowledge it
under the existing account/container fences. Dismiss without submitting and
verify the saved photo/current identification remain unchanged. Enrollment
persists after dismissal. The ordinary History menu appears only when two
results exist; do not claim History-list coverage from a single baseline or
submit an extra analysis merely to expose that menu.

# Identification history: guided device review

Use these Xcode launch profiles to review the prepared interface on an iPhone.
They reuse the existing Debug fixtures, with synthetic responses and an
in-memory library. The live history installation gate stays false. No backend
configuration, provider calls, deployment or distribution is part of this setup.

## Start

1. Open `merian.xcodeproj` in Xcode. If the profiles are missing, run
   `make xcodegen` from the repository root and reopen the project.
2. Select **Merian Device - History** and your connected iPhone as the run
   destination. Use the existing development-signing setup, then choose **Run**.
3. Open **Scans** and the **Map Meadowlark** fixture. Open its three-dot menu.
4. Work through the scenarios below. Stop the app in Xcode before switching
   profiles; each Run starts with fresh fixture state.

These profiles use the existing Merian app target and bundle identifier. A
signed Xcode installation can replace an installed copy of the app: use your
chosen test device and preserve any installation needed for the separate
install-over test. The fixture's in-memory library does not exercise the normal
stored library. Always launch through the selected Xcode profile so its test
arguments and environment are present; launching from the Home Screen does not
supply them. Use Run for this checklist, not Archive or a release workflow.
Profile also stays Debug to contain the inherited fixture arguments; these
profiles are not a release-performance qualification setup.

## Scenarios

| Xcode profile                        | Steps                                                                                                                                                                                                                                 | Expected result                                                                                                                                                                |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Merian Device - History**          | Open Map Meadowlark → menu → Identification history. Preview the second identification, then choose **Use this identification**. Tap **Undo**.                                                                                        | Preview alone does not select. Both entries remain. Current moves to the second identification after the explicit action, then back after Undo.                                |
| **Merian Device - Reanalysis Guard** | Open Map Meadowlark → menu → Reanalyze species. Repeat from its Strong match explanation.                                                                                                                                             | The intentional unavailable response says the identification is unchanged. The saved result remains open; no paywall or legacy replacement starts.                             |
| **Merian Device - Community Photos** | Open Consent Butterfly → menu → Ask the community → Choose photos. Confirm is initially disabled. Select the **second photo, then the first**. Preview a photo and share the two selected photos. Close and reopen Ask the community. | Selection order is retained. Status becomes **Waiting to send**. Reopening shows the existing request, without a second chooser. The current identification stays selected.    |
| **Merian Device - Species Name**     | Open Consent Butterfly → menu → Confirm species name. Close the empty form and reopen it. Enter **Danaus plexippus**, then confirm.                                                                                                   | Empty confirmation is disabled. The exact saved review shows **Review pending**. Reopening does not create a replacement request.                                              |
| **Merian Device - Chat Pending**     | Open Consent Butterfly → Field chat. Send **What does this identification mean?** Close and reopen chat; use the saved-question action.                                                                                               | The original question remains pending with one saved identity. The fixture intentionally leaves delivery pending; it does not produce an AI answer.                            |
| **Merian Device - Chat Refresh**     | Send the same exact question in Consent Butterfly's Field chat. Close and reopen. Choose **Refresh identification**, then open chat again.                                                                                            | **Question not sent** survives closing. Explicit refresh closes stale chat. Reopening offers an empty composer, keeps the historical receipt, and sends nothing automatically. |

Follow the specified photo order, species name and question text: these fixtures
assert those exact production persistence handoffs. Different input is outside
the guided fixture and can trigger a Debug assertion. **Waiting to send** and
**Review pending** are intentional endpoints for these scenarios.

For each scenario also check large text, VoiceOver labels, light/dark
appearance, keyboard dismissal, scrolling and repeated open/close behavior.
Record clipped controls, unreachable actions, surprising dismissals, freezes or
crashes. Keep account changes and real captures for the separately configured
end-to-end pass.

## Confirmation Undo: additional scenario still required

The existing **History** profile exercises selection Undo. **Species Name**
saves a confirmation but intentionally stops at **Review pending**. Neither
profile supplies an applied confirmation receipt and eligibility lookup, so
neither demonstrates **Undo confirmation**. Do not treat the table above as
coverage of that new action or enable live gates to make it appear.

A separate prepared fixture now exists. Launch with
`-seedPublicationConsentChooser -seedConfirmationUndo`; also add
`-seedSelectedNameConfirmation` for the named-correction case. The six
`PublicationConsentUITests` primary/name scenarios exercise History, the
selected menu and Confidence using real native admission, delivery and paired
reconciliation with synthetic network boundaries. They passed in the dated
[capability follow-up](../rfcs/identification-history-integrated-review-results-2026-10-07.md#capability-follow-up-direct-undo-coverage).
The original launch profiles above still do not exercise this action.

Physical-device acceptance remains required. Record these outcomes:

- From History, the selected-result menu and Confidence card, primary Undo
  directly saves the exact reversal. Named Undo first explains that the original
  AI identification returns; Cancel creates no operation and final confirmation
  saves exactly one operation.
- The result becomes unreviewed while selection, original evidence and
  confidence remain unchanged. Returning to another history result uses that
  result's own review; an older rejection is not restored.
- Pending, conflicted, community-controlled and receipt-unavailable imported
  results show the appropriate explanation. Dismissal, revision or account
  changes invalidate retained actions instead of targeting a newer result.
- Reopening after an uncertain save observes the same operation. Actual process
  restart and second-device receipt recovery still require the separate durable
  store and explicitly authorized named-target acceptance pass; an in-memory
  fixture cannot prove them.

The
[verification matrix](08-testing-strategy.md#durable-confirmation-undo-verification)
records the lower-level coverage, six direct UI paths and passing joined-waiter
cancellation regression. Direct stale/imported UI cases and physical-device
results remain separate; simulator success is not device, restart or hosted
qualification. This checklist does not authorize deployment or activation.

## What this establishes

This pass checks the actual interface, touch behavior and selected native
persistence owners on device using synthetic boundaries. Selection in the simple
History profile uses its existing presentation fixture; the publication/review/
chat profiles exercise their production local admission owners in the test
container. Fixture seeding is compiled only in Debug and additionally requires
`UITesting=true`. Each scheme has a distinct synthetic keychain namespace. The
normal Merian scheme, live composition gate, database rollout gates, signing
configuration and bundle identifier remain unchanged.

Relaunch resets this test library. It cannot establish crash/restart durability,
account switching, live provider reanalysis, private storage, cross-device
reconciliation or a V57-to-V58 migration. Those checks require the named beta
backend/device plan below and a separately authorized build/install path.
Existing migration tests and simulator measurements do not replace a real
install-over test or sustained-memory trace. See the
[history verification contract](08-testing-strategy.md#observation-analysis-history-preparation)
and [runtime qualification guide](18-ios-runtime-quality-and-benchmarking.md).

## Planned real-app qualification environment

### November 10 CST — signed primary 1.1.0 preparation

Completion324 supersedes the unsigned Completion299 preparation for the retained
primary **1.1.0 (local275)** phone artifact. The signed Build-only succeeded;
all four app/watch/widget/Messages signatures, expected identities, development
profiles for the intended phone, privacy manifest and transport checks passed.
Completion332 confirms all 114 preserved artifact files still match. Approval
inputs remain empty: this artifact is inactive, uninstalled and unlaunched.
Installed-app signing continuity and actual data-preserving install-over remain
unverified. Xcode continues to own future TestFlight numbering.

Use `completion332-coordinated-readiness.md` in the native-app handoff artifacts
for the current candidate and coordinated operation boundaries. Exact backend
`b6bd9fed8adbf87030be22f8dce4fee05eaa8966` passed CI528; Completion333
independently reconciles all 22 handoff suites and records verified prospective
corrections separately from historical unknown causes and the narrow observed
transfer margin. Those residual release decisions remain explicit. The
user-installed private-scans settings passed bounded metadata verification; the
finite hosted fixture storage test passed independent review. Neither proves
production-key or full-app behavior. Final live build binding, beta
deployment/activation, attended existing-account sign-in and phone
install/launch still require their concrete operation authorization. Physical
all-media, upgrade/resource/accessibility and cumulative acceptance remain open.
Automatic prompts remain **PAUSED**.

### November 10 CST — matching video-fix phone candidate

Completion299 supersedes completion298 for the prepared unsigned, inactive
primary **1.1.0 (local275)** phone artifact. The managed device build passed in
703.0seconds with4,268 unchanged inputs; Engine verified all106 preserved files,
four unsigned product identities, existing Google callbacks and empty approval
fields. It includes the bounded video-decoder executor/post-read cancellation
fix. Scoped producer, recovery/History/Undo UI, architecture and tooling results
are retained; the final callback tests compile without Swift warnings. These
results do not establish physical-device or cumulative functional acceptance.

The device result has zero errors and ten missing-PCM warnings specifically in
watch dSYM generation, plus two separate AppIntents notices. Engine accepted
this explicit watch-symbol limitation for phone preparation; do not describe the
whole build as warning-free or watch debugging as qualified. Any later watch
symbol acceptance requires narrow regeneration and matching UUID verification.
The prior artifact and original diagnostics remain preserved.

Use `completion299-phone-build-handoff.md` for exact artifact hashes, source
fingerprint and remaining release/install prerequisites. This is still an
unsigned, uninstalled product with inactive live qualification. Organizer
manages the future TestFlight number. The phone's installed version/signing
continuity, exact backend deployment authorization, live compatibility,
integrated/resource acceptance and whole-candidate review remain open. No
external action is authorized by the local overnight continuation.

### November 10 CST — storage recovered; focused large-text recovery verified

Manual local continuation passed the storage floor and completion308 build. The
three reanalysis success methods passed on the same308 products at the largest
simulator text size, with exact source/product pins and setting restoration. The
two initial-photo passes from306 are retained only by explicit source
applicability. This is not one same-binary five-method run. Original
failures300–307 remain in the local evidence; see
`completion308-reconciled01.json` in the native-app handoff artifacts.

The test-only corrections keep production timers and account/version/revision
defenses intact. Exact-row positioning and preview transition precede mutations;
real selection Undo occurs before slow row traversal. Current acceptance focuses
on functional reachability, saved-version correctness, nonmutating preview,
exact selection/review/Undo and persistence/recovery. Essential large-text and
assistive-technology usability remains required; cosmetic polish of the planned
replacement UI is deferred. Scoped simulator passes do not establish general
accessibility, live execution or physical upgrade/resource acceptance.

The preserved299 unsigned inactive primary1.1.0/local275 phone artifact remains
uninstalled. See the
[finite release checklist](../rfcs/identification-history-alpha-readiness-2026-10-11.md#november-10--finite-consolidation-release-and-explicit-pause)
for remaining integration, dependency, usability, upgrade/resource and
cumulative requirements. Automatic prompts remain **PAUSED by the user**.
Storage recovery never resumes them; external action boundaries are unchanged.

### November 9 CST — version 1.1.0 preparation after warning cleanup

Completion298 preserves the unsigned primary app/watch/widget/Messages **1.1.0
(local275)** candidate after both warning-cleanup handbacks. Its managed build
passed with 4,268 unchanged inputs and zero log/XCResult warnings or errors. All
four bundle identities and existing Google registration/callbacks match;
qualification approvals remain empty, so live testing is inactive. The
incremental build reuses the exact warning-cleanup device04 executable with
verified qualification compile-flag provenance. No signing, installation,
launch, store access or upload is claimed. Xcode Organizer manages the future
TestFlight number.

Prior populated V54-to-V69 migration/reopen evidence remains applicable after
independent review: 153 identical source pins and four semantically unchanged
warning edits; MigrationPlanTests is unchanged. This does not establish the
phone's installed build, signing continuity or actual install-over preservation.
The local archive/upload348 reference and old-client restrictions below remain
applicable within their stated scope. Existing Field Chat admission activation
in the deployment workflow is distinct from protected History routing; neither
live state is inferred from source defaults.

The user resumed local-only automatic continuation overnight; external
publication, merge, deployment, beta changes, uploads and phone installation
remain excluded. CI524 passed, while the exact final release SHA still needs its
own gate and explicit target/operation approval. Preserve unresolved acceptance
and use completion298-phone-build-handoff.md for exact artifact fingerprints,
remaining prerequisites and the all-media walkthrough. No new hosted environment
or Google registration is required.

### Earlier November 9 CST — uploaded-app compatibility and pre-cleanup build

Completion296 found a signed local primary-app archive with clean source
`dbb1b8f3b7e17f6c63dcdecd3e2235e1c88aee2b`, version 1.0.3/local build275 and an
Apple upload receipt for build348. Signature and source fingerprint were
independently verified. Its V54 source is covered by the unchanged populated
V54-to-V69 migration/cold-reopen evidence in native269. This establishes
uploaded lineage, not current TestFlight availability, the phone's installed
build or signed install-over. Never confuse the local archive/build number with
Apple's uploaded number.

The refreshed primary HistoryQualification app/watch/widget/Messages compilation
passed with 4,271 unchanged input hashes and independently verified products.
The unsigned app retains existing Google registration/callbacks and empty
approval inputs; it cannot yet perform the live walkthrough. Warnings remain
under separately authorized cleanup. Preserve the exact pre-cleanup product and
rebuild after relevant source fixes before installation. No signed installation,
user-store read, sign-in, hosted activation or deployment occurred.

The archived client's ordinary unenrolled scan contracts are retained within the
reviewed source boundary. Enrolled deletion, review, community authority and
legacy sharing require the new protocols. Protected Field Chat and pending
library transfers can also reject old-client operations. The workflow's existing
Field Chat admission cutover does not enable the separate protected-History
routing flag; verify live rollout state rather than assuming its source default.
Old-client request retries must not be described as successful cloud deletion or
completed transfer. The candidate-specific compatibility matrix, preservation
limits and exact product evidence are in completion296's local handoff records.
Actual mixed-client beta/phone qualification remains required.

### November 8 CST — primary-app qualification revision

The user explicitly selected the primary beta app experience, existing bundle ID
and existing Google registration. Completion269 adapts the qualification
configuration to those identities; the earlier separate-registration proposal is
withdrawn. No new Google client or hosted audience change is needed. This
supersedes the earlier separate bundle/App Group/keychain-access-group plan;
historical build receipts below retain their original scope and do not qualify
the revised configuration.

The revised inactive unsigned app/watch/widget/Messages build passed in 702.490
seconds with all 4,165 input hashes unchanged (version 1.0.3, build 275). Built
bundle identifiers and the existing Google client/callback match the primary
configuration; private approval fields remain empty. Native269's store,
sign-out, namespace and migration checks passed; its initial aggregate-size
failure was corrected without raising the limit. All 19 Auth recovery checks
passed, including primary-state preservation through cancelled cleanup. The
subsequent test-inventory assertion correction passed its exact 1/1 selector
with zero skips. Engine independently verified the preservation fix, and the
complete iOS tooling gate passed. The original failed runs remain retained; this
is unsigned local evidence, not installed qualification.

Populated synthetic V57-to-V69 migration, preserved history/queued work and cold
reopen passed in native269. The populated V58-to-V69 disk-store test passed in
native230; its migration, model, factory and test inputs are unchanged. This
bounded reuse does not reuse native230's overall failed run as a pass or qualify
the subsequently changed bootstrap. Both tests ran on iOS Simulator 26.5.
`completion269-primary-store-evidence01.json` records applicability. The
outgoing installed app's version/source/schema and signed upgrade continuity
remain unknown; no personal store was read.

The app, watch, widget and Messages targets retain their ordinary identifiers,
App Group, keychain access group, deep links and entitlements. This selects the
existing library and media locations. The compiled qualification marker and
exact target/account approval checks remain mandatory. The internal
qualification Auth transaction journal stays in its dedicated service/key:
ordinary raw SDK session bytes and legacy keys are neither rewritten nor copied
into another refreshing client. Using the same Google account may require a
separately authorized sign-in; existing app registration is not exchange
authorization.

Qualification refuses sign-out/guest transitions and inherited sign-out-journal
execution before any session clearing or library purge. Both Auth-failure
cleanup entry points reject before transition acquisition, SDK sign-out, primary
recovery Keychain cleanup or purchase sign-out, including the cancelled
mutated-OAuth policy. A failed persistent store open enters safe mode without
quarantine, rescue or empty persistent-store replacement. Normal schema
migration remains possible on a successful open; prove supported populated-store
upgrades before any authorized install-over. Do not claim an older binary can
read a migrated store without matching rollback compatibility evidence. Preserve
deletion barriers, journals, ownership and media. Never uninstall/reinstall,
reset the store or clear Keychain to simulate an update. Signed
team/application-identifier/access-group continuity and actual install-over
remain unverified until the exact device operation is approved and run. Local
source changes and unsigned products do not establish preservation on the user's
device.

The October 29 decision selects the existing **beta production backend for
planning** eventual real-app qualification. No additional hosted database is
required. Use local disposable databases for destructive migration, injected
fault and contention testing; never direct those tests at existing beta data.
This replaces earlier separate hosted nonproduction database planning for the
real-app journey only, while preserving historical evidence and every current
executable guard. It is not an installed, validated or enabled configuration.
The deployment runbook
[history activation hold](../backend-and-data/06-supabase-deployment-runbook.md#observation-analysis-history-activation-hold)
still requires its separate nonproduction edge/R2 security evidence. Those
requirements neither imply another hosted database nor permit destructive or
contention testing on beta data; retain them as distinct pending authorization
and qualification obligations.

Before use, implement and review the dedicated `HistoryQualification` design and
its executable safety checks together. Require a compiled qualification marker,
exact explicitly approved project/host and test-account/data scope, primary-app
bundle/App Group/keychain-access-group/disk identities, a separate internal Auth
transaction journal, and fail-closed validation before constructing live clients
or installing the composition. Ordinary Debug/Release must exclude that branch
and retain the hard-false
`PreparedHistoryReanalysisComposition.isAppInstallationQualified` path. Remote
flags, preferences, warning suppression and simply relaxing a production-denial
check are not qualification mechanisms. Validate wrong/missing target, missing
marker, ordinary builds and out-of-scope account/data refusal alongside the
positive authorized configuration. Native250 implements the inactive
configuration and local guards; native component checks, independent review and
unsigned qualification compilation passed (native250). Native251 connects the
existing composition only in the compiled qualification configuration with a
validated bundled scope. Its 41 methods / 61 expanded cases and independent
source review passed. The combined native253 unsigned compile also passed for
all four products with 4,163 matching pins. Native254 refreshed the compile
after a closure-argument warning correction: 524.523s, 4,163 matching pins,
expected unsigned products and empty activation inputs. It retains 383 unique
warning headers, including five unchanged predecessor diagnostics in touched
files. Compilation remains distinct from activation and installed qualification.
Ordinary Debug/Release remain hard-false. The public empty packet remains
inactive. The generated `HistoryQualification` scheme has no synthetic launch
arguments. Its public xcconfig contains empty approval/target/account inputs and
cannot launch live clients without a complete private approved packet.
`MerianEnvironment` validates that packet before AppDI/client creation. The
separate SDK Auth storage refuses out-of-scope or anonymous sessions before
restoration/refresh and preserves refused stored data. Provider login, identity
linking, callback installation and anonymous signup remain unavailable pending a
reviewed way to establish the approved existing-account mapping before any
hosted exchange. A post-exchange account check is insufficient. Before enabling
provider exchange, verify exact-target server refusal of new-user creation and
trusted existing provider/account mapping. The existing OAuth workflow records
SDK mutation before adoption. Native260 corrects failed-replacement
reconciliation to preserve only the exact unexpired source and checks the
callback target policy before publication. Its final 30 callback/architecture
methods pass; 35 unchanged provider/workflow methods retain earlier passes.
Original inventory and aggregate-budget failures remain retained, with both
corrected without raising limits. These synthetic checks do not verify the
provider/account mapping or server refusal prerequisites; provider exchange
remains closed. Deletion intake, commit, recovery, acknowledgement and local
recovery resolution are refused; existing pending barriers and proofs remain
retained. Qualification closes RevenueCat identity linking/configuration and
PostHog setup regardless of inherited or overridden keys. Build scripts suppress
environment dumps. The existing release preflight explicitly refuses
qualification archive/distribution even with a private packet; ordinary builds
retain their existing controls and integrations.

Completion265 locally implements the dormant Google presentation/install
consumer. The private evidence must bind exactly one account to the validated
scope. Presentation checks current evidence; completion checks the exact parsed
Google subject after source-session verification; the service repeats that check
before `signInWithIdToken`. Replacement rechecks cancellation and operation
ownership, then validates the exact non-anonymous returned account and current
evidence before unpublished adoption and atomic storage acceptance. A durable
pending envelope blocks SDK persistence while retaining the prior approved
session. Exact-attempt accepted receipts resolve lost write acknowledgements;
unreadable settlement remains fenced from generic cleanup, including on
cancellation. Confirmed acceptance alone records mutation. This preserves
listener fencing and source-only failed reconciliation. Ordinary sign-in retains
its existing subject handling. Linking, Apple, callback exchange and anonymous
creation stay closed in qualification builds. Public packet fields remain empty.
Qualification also refuses anonymous bootstrap at coordinator entry, before
starting a transition or draining account work. Capture prewarming must not hide
recovery controls behind work that can never create an allowed session. The
independent SDK listener remains responsible for initial signed-out state and
restoration of an already accepted session. Never force a generation or clear
stored state to dismiss a startup spinner. Digest-shaped metadata alone is not
trusted mapping or server-refusal proof: separately reviewed private evidence,
the actual exchange-path refusal verification and explicit
operation/build/install/login authorization still control activation. Local
synthetic checks and independent source review do not authorize those
operations. Engine accepted the settlement correction. Native05 passed 106 tests
with zero failures/skips and 4,165 unchanged inputs; the final focused native06
run passed after lint-only corrections. The required tooling, compiled
configuration checks and strict touched-source lint passed. No qualification
build has been installed or used for sign-in.

Run `python3 -B scripts/test-ios-device-review-schemes.py --swift-qualification`
for generated namespace checks and actual host-Swift ordinary/qualification
branches using synthetic configuration. This does not execute the iOS app or
contact providers. Native250's first run passed 118/119 methods; its sole
failure was the Auth aggregate size budget. The shared-check correction
preserved every limit; native02 passed all 94 methods / 104 cases. Independent
review closed HQ255/HQ256. The four-target unsigned build passed with 4,163
matching pins; 425 unique warning headers remain retained, none in changed Swift
sources. Compilation does not qualify real startup, Auth setup or installed
journeys.

`project.yml` references separate checked-in main-app entitlement plist inputs
for ordinary and qualification configurations; XcodeGen's single generated
entitlement path would otherwise override the configuration-specific setting.
Widget/Messages entitlements remain generated from the manifest. Completion269
uses the ordinary main entitlement input and inherits primary App Group,
keychain-access-group, Documents/defaults, URL schemes and companion identities.
Only the internal qualification Auth journal retains a separate service/key. The
earlier dedicated entitlement file is historical and unused by the revised
manifest. These are implementation/preparation claims, not installed or
qualified live behavior. See the current evidence status in the
[scan-to-history guide](25-scan-to-history.md).

The authorized November 8 read-only beta inspection completed Auth-settings and
function-version reads at 15:00 UTC: signup was enabled and required History
function slugs were absent. Anonymous sign-in remains unverified. After the
local link repair, the user chose the separate
[manual read-only Actions inspector](../backend-and-data/06-supabase-deployment-runbook.md#manual-read-only-migration-inspection)
using existing Production secrets. Authorized PR145/146/147 publication retained
the active backend hold. The original generic failure and subsequent certificate
failure remain recorded. PR147's public-CA fix merged as `24094e3`; read-only
run42525137324 succeeded at 21:25:46 UTC, recording 372 migration versions.
Inspector main has 36 unapplied versions; the shared History inventory has 141,
including the eight existing digest-pinned recovery migrations. The offline
planner confirms the reviewed recovery path. This version snapshot does not
prove deployed SQL contents or function compatibility, and the shared dirty
inventory is not a release candidate. No local password, temporary role,
credential change or backend deployment was needed. Certificate and hostname
checks remain enabled. Provider exchange stays closed pending the existing
reviewed prerequisites and explicit operation authorization.

Under separate explicit authorization, the selected existing Google account's
mapping was verified read-only at 22:30:24 UTC on November 8. Account/subject
fingerprints and provenance remain in a private local file outside the
repository; no raw identity or credential belongs in qualification artifacts.
The original generic local failure and subsequent Keychain timeout remain
retained. Extending the local prompt wait allowed the authorized read to
complete; no credential or backend configuration changed. Source review and ten
synthetic helper tests cover the bounded inspection, not live sign-in. This
observation does not prove mapping freshness at exchange time or server refusal
of new-user creation. Those prerequisites, provider exchange and installation
remain gated.

The separately authorized November 8 CST registration inspection found only the
ordinary application's iOS client in the Google project that owns its configured
public client ID. No client for the separate qualification bundle was listed in
that project. After the user completed dashboard sign-in, the approved public
metadata read confirmed that Supabase accepts the existing web and ordinary iOS
client IDs. This is not evidence about other Google projects or a live token
exchange. No registration or provider setting changed. The subsequent
primary-app revision above reuses the inspected ordinary registration and
accepted audience, so the separate-registration proposal is withdrawn. Public
approval inputs remain empty.

At completion262, the local identity-evidence validator expressed the reviewed
packet binding without a consuming exchange path. It checks approval, host,
Google provider and approved account against the existing qualification scope;
requires subject and evidence digests plus separate mapping/server-refusal
observation and expiry windows; and refuses malformed, mismatched,
future-observed or expired metadata. Public inputs remain empty. Parsing is
optional for existing composition/stored-session checks and does not verify
referenced evidence, refresh mapping, attest server settings, or authorize any
operation. At that checkpoint exchange was unconditionally refused.
Completion265 added the inactive pre-exchange consumer described above. Its
public empty packet still refuses presentation and exchange; operator-reviewed
mapping and server-refusal evidence plus explicit operation authorization remain
required. A synthetically valid local record is not live readiness. Host-Swift
ordinary/qualification checks pass all eight methods, including LF/CRLF digest
rejection. Independent review withdrew that suspected defect after verifying the
unchanged-source regression. The complete iOS tooling gate also passes. Neither
result is an iOS product build or live provider test.

Completion263 added the local Google-subject comparison using the mapping
inspector's exact domain-separated UTF-8 SHA-256 contract. Synthetic host-Swift
checks cover matching and mismatching subjects, wrong digest domain, invalid
subjects and expired evidence. Completion265 consumes this matcher at the
guarded Google presentation/completion/service boundaries described above. The
matcher does not authenticate a JWT; the current public artifact remains
inactive.

Prepare a reviewable operation packet before requesting external authorization:
exact source/build artifact and backend revisions; named target; each proposed
operation, test accounts and data scope; provider/cost bounds; preservation,
cleanup and rollback plan. Obtain explicit operation-and-target authorization
before hosted mutation, migration, deployment, credentials, provider
experiments, device installation or activation. Cleanup against the hosted
target also needs that explicit scope. No actual target identifier, credential
or personal data belongs in these public instructions. Existing beta selection
is planning consent, not blanket operational approval. PR116 and deployment
holds remain; ordinary production activation stays disabled.

Use real navigation, AppDI owners and disk-backed storage for the separately
authorized run. Record exact artifact/backend identity and sanitized outcomes
for all three media types, populated-store upgrades, offline/relaunch, lost
responses, account/deletion fences and resource measurements. Dedicated test
accounts do not make a shared production backend disposable. Apply the
[cumulative functional audit](../rfcs/identification-history-alpha-readiness-2026-10-11.md#october-29--cumulative-functional-qualification-agreement)
and A1–A21 matrix; fixture results above retain their narrower scope. Continue
independent authorized local work while this external packet is pending.

## Report a result

For each profile record **Pass**, **Fail**, or **Blocked**, plus:

- Candidate commit, device model, iOS version and Xcode version.
- Profile name, exact steps, expected behavior and actual behavior.
- Whether it repeats after a fresh Run; relevant synthetic screenshots or a
  short screen recording.
- For a crash, a sanitized Xcode crash report. Exclude credentials, session
  values, personal photos and location data.

A compact report such as “History / iPhone / iOS version / Fail: Undo closes the
sheet; repeats after a fresh Run” is enough to start an investigation.
