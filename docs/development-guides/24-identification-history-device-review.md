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
exact explicitly approved project/host and test-account/data scope, isolated
bundle/app-group/keychain/disk/auth namespaces, and fail-closed validation
before constructing live clients or installing the composition. Ordinary
Debug/Release must exclude that branch and retain the hard-false
`PreparedHistoryReanalysisComposition.isAppInstallationQualified` path. Remote
flags, preferences, warning suppression and simply relaxing a production-denial
check are not qualification mechanisms. Validate wrong/missing target, missing
marker, ordinary builds and out-of-scope account/data refusal alongside the
positive authorized configuration. These checks are **planned**, not claimed as
implemented by this document.

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
