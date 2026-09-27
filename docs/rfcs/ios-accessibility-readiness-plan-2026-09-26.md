# iOS accessibility readiness plan

Status: Proposed. Created: 2026-09-26. Applies to: Naturebook on iPhone.

This plan defines the work and evidence needed to make the app's common tasks
accessible and accurately declare App Store accessibility support. It does not
assert that the current build meets these criteria. Implementation, device
testing, and publication are separate steps; this proposal authorizes none of
the release operations described in the release runbooks.

## Target and scope

Use Apple's Accessibility Nutrition Label evaluation criteria for each claimed
feature, alongside applicable WCAG 2.2 Level A and AA criteria interpreted for
native software through WCAG2ICT. WCAG2ICT is informative guidance, not an
independent certification or a legal compliance determination.

Prioritize VoiceOver, Larger Text, Voice Control, Sufficient Contrast,
Differentiate Without Color Alone, Reduced Motion, and Dark Interface. Evaluate
Captions and Audio Descriptions against the media actually present in the app;
do not claim either merely because the app records sound or generates species
descriptions. Evaluate iPad and watchOS separately if support is later declared
for those platforms.

Success means a person can independently complete the app's fundamental and
primary tasks with the relevant accessibility feature enabled. A screen passing
an automated audit is supporting evidence, not proof of this outcome.

## Current evidence and limits

- Source inspection found existing accessibility labels and announcements,
  motion-reduction handling in shared loading effects and Insights, and dark
  appearance handling. These are foundations to test, not verified feature-wide
  support.
- Fixed-size text in onboarding, settings, paywall, and capture views needs
  rendered Dynamic Type review. Fixed font sizes alone do not establish a
  defect; decorative icon sizing must be distinguished from readable text.
- The initial search found no use of `performAccessibilityAudit()` in the iOS
  sources or runtime tooling. Verify existing coverage before adding tests.
- The
  [private scan map contract](../features-and-hardware/28-private-scan-map.md)
  records a missing candidate-level manual accessibility matrix.
- No device accessibility audit or assistive-technology task test was performed
  as part of preparing this plan.

## Work packages

### 1. Establish the baseline and task inventory

- [ ] Select a candidate commit and record its app version, build, Xcode
      version, device, and OS. Reconcile existing work before making overlapping
      edits.
- [ ] Inventory every shipping screen, custom control, sheet, alert, permission
      transition, embedded web surface, and media player used by common tasks.
- [ ] Map each task below to its views and existing Debug fixtures. Confirm
      which features actually ship in the candidate; mark absent functionality
      out of scope with a reason.
- [ ] Run an initial Accessibility Inspector pass and a manual VoiceOver pass.
      Record reproducible failures, affected tasks, and severity.
- [ ] Create a feature-by-task evidence matrix. Use `Pass`, `Fail`,
      `Not tested`, or `Not applicable`, with a reason required for the last
      status.

Deliverable: a candidate-specific baseline with prioritized defects and explicit
coverage gaps. Do not change App Store declarations from source inspection
alone.

### 2. Fix shared controls and establish automated coverage

- [ ] Audit shared components under `apps/ios/Merian/Core/UI`: accessible names,
      roles, values, selection/disabled state, grouping, and reading order.
- [ ] Give icon-only actions meaningful names. Hide decorative elements and
      avoid duplicate announcements when a card already exposes combined
      content.
- [ ] Make text styles scale, and make layouts wrap or reflow at accessibility
      sizes. Avoid solving clipped content by shrinking essential text.
- [ ] Measure text and essential control contrast in supported appearances.
      Correct shared colors first, then inspect local overrides and image
      backgrounds. Pair color with text, shape, or symbols for meaningful
      states.
- [ ] Respect Reduce Motion in shared transitions and repeating effects. Keep
      progress and state changes understandable when animation is removed.
- [ ] Prefer touch targets of at least 44 by 44 points and provide simple
      actions for functionality otherwise dependent on dragging or complex
      gestures.
- [ ] Add focused XCTest accessibility audits for deterministic representative
      screens. Use `XCUIApplication.performAccessibilityAudit()` where supported
      by the pinned toolchain, after the screen reaches a stable state.
- [ ] Fix findings or document narrowly scoped, reviewed exceptions with an
      equivalent manual check. Do not suppress entire audit categories to make
      tests pass.

Implementation owners: shared UI components, the existing Debug seed
coordinator, and `apps/ios/MerianUITests`. Extend the existing runtime audit
selector manifest at `scripts/config/ios-runtime-audit.json` when tests join
that lane. Do not create a competing runner or a second selector registry.

### 3. Make the core journeys independently usable

| Journey                | Required task checks                                                                                                                                                         |
| ---------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Onboarding and sign-in | Read consent, choose options, complete authentication, recover from validation errors, and continue after permission denial.                                                 |
| Capture and import     | Choose an available input method, operate capture controls, select media, answer description prompts, and submit or cancel. Test camera/audio hardware on a physical device. |
| Processing and results | Understand progress, offline queueing, failures, retry, identification results, uncertainty, and lookalikes without depending on color or animation.                         |
| Personal library       | Find and open observations, search, edit, share, and delete; preserve focus through navigation and confirmation dialogs.                                                     |
| Settings and account   | Change preferences, find help and privacy information, sign out, and complete account deletion without inaccessible confirmations.                                           |
| Purchases              | Understand plan, price, and terms; buy, restore, cancel, and recover from errors in a sandbox flow.                                                                          |

Initial source review targets include `OnboardingStepWrapper.swift`,
`ReadyStepView.swift`, `SettingsRows.swift`, `PaywallView.swift`,
`DescribeQuestionNavigationView.swift`, and
`CaptureStagingToolbarMediaRow.swift`. Treat these as starting points, not the
complete scope of the audit.

For each task, cover meaningful success, loading, empty, error, offline, and
permission-denied states. Verify announcements on asynchronous completion and
errors without repeatedly interrupting the user. Restore focus to a sensible
control when a sheet, alert, or detail view closes.

### 4. Address maps, community, and media

- [ ] Audit private and Explore maps. Provide a discoverable accessible list or
      equivalent controls for the observations and actions needed to complete
      common tasks. A user must not need to visually locate or pan to a pin.
- [ ] Verify filters, selection changes, and transitions between map, list, and
      detail preserve understandable state and focus.
- [ ] Test Explore feeds, following, comments, reporting, and blocking wherever
      present. Make action menus, counts, selected states, and errors
      accessible.
- [ ] Cover field trips and the species dictionary where included in the
      shipping build, including search, lists, details, and navigation.
- [ ] Inventory app-provided audio/video and user-generated media separately.
      Assess captions, transcripts, playback controls, and audio descriptions
      against the relevant criteria and content exceptions.
- [ ] Give meaningful nontext content useful accessible descriptions. Validate
      generated or species-based descriptions for usefulness; do not imply that
      they describe visual details they cannot establish.

### 5. Validate the candidate and decide individual labels

- [ ] Repeat automated audits and manual task tests on the final candidate after
      remediation. Evidence from an earlier build needs impact review and
      retesting for affected journeys.
- [ ] Include people who regularly use assistive technologies in task-based
      evaluation, with particular attention to capture, results, and maps.
- [ ] Review every proposed App Store label against Apple's current criteria and
      the complete common-task matrix. An untested task is not a pass.
- [ ] Record which labels are supported, which are unsupported, and which remain
      unverified. Keep the decision and known limitations with the candidate
      evidence.
- [ ] Publish declarations only through a separately authorized App Store
      action.

## Acceptance checks

| Feature                           | Pass criteria for common tasks                                                                                                                                                                                             |
| --------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| VoiceOver                         | Every necessary action and meaningful result is reachable, named, and understandable. Reading order, values, state changes, modal focus, and focus restoration support task completion without traps.                      |
| Voice Control                     | Necessary actions can be identified and activated using Voice Control, with useful control names and no gesture-only dead ends.                                                                                            |
| Larger Text                       | Meet Apple's text enlargement criteria, including at least 200% enlargement for the applicable text. Test accessibility text sizes for clipping, overlap, lost controls, and blocked scrolling.                            |
| Sufficient Contrast               | Measure applicable normal text at 4.5:1, large text at 3:1, and essential nontext UI at 3:1, applying the relevant criteria and exceptions. Check supported light/dark appearances and relevant increased-contrast states. |
| Differentiate Without Color Alone | Selection, errors, identification confidence, status, and meaningful map distinctions remain understandable without color perception.                                                                                      |
| Reduced Motion                    | Respect the system setting across common tasks; remove or replace problematic motion while preserving meaning and progress feedback. Evaluate autoplay and pause controls where applicable.                                |
| Dark Interface                    | All common tasks, including sheets, alerts, paywall, and app-controlled help surfaces, satisfy Apple's dark-interface criteria without disruptive bright transitions.                                                      |
| Captions and Audio Descriptions   | Assess actual media against Apple's separate criteria. Do not infer support from the absence of media or from unrelated recording and identification features.                                                             |

Also test Switch Control and hardware-keyboard operation for actionable
controls, focus visibility, and navigation. These improve usability even where
they do not correspond to a label in the current App Store form.

## Test and evidence strategy

Use a small supported iPhone layout and a larger layout, the minimum supported
OS where available, and the current supported OS. Record unavailable runtimes as
coverage gaps. Include a physical iPhone for VoiceOver, Voice Control, camera,
microphone, and gesture evaluation. Simulator audits supplement this work.

Test default text plus accessibility sizes, light/dark appearance, Reduce
Motion, Increase Contrast, and Reduce Transparency. Combine settings where they
can interact, such as the largest text size with VoiceOver and a small screen;
avoid claiming coverage from isolated settings alone.

Use the existing local build and audit workflow in the
[testing strategy](../development-guides/08-testing-strategy.md) and
[runtime quality guide](../development-guides/18-ios-runtime-quality-and-benchmarking.md):

- Run builds and tests through `make ios-local-build`; reuse its checkout-local
  caches and storage controls.
- Extend production-shaped Debug fixtures without adding release-visible test
  paths or dependencies on production accounts, providers, or network services.
- Keep the narrow accessibility checks useful during iteration, then run the
  complete affected iOS gate before implementation handoff. Run
  `make test-ios-ci-tooling` if the audit tooling or manifest changes.
- Regenerate project membership through `project.yml` and `make xcodegen` when
  required; do not edit the generated project manually.
- Store retained reports and XCResults outside `.build`, following the canonical
  storage procedure. Use synthetic, non-sensitive fixtures; never retain
  personal data, credentials, session state, or raw coordinates in evidence.

Each evidence row must record candidate SHA/build, device/OS, accessibility
setting, journey and state, expected result, observed result, status, evidence
reference, and any linked defect or reviewed exception. Automated reports must
state their screen coverage and cannot stand in for manual journey results.

## Priority and completion rules

1. Fix blockers to consent, authentication, primary capture/results, payment,
   recovery, and account deletion first.
2. Fix shared-component failures next to improve all affected journeys, followed
   by feature-specific navigation, maps, community, and media failures.
3. Finish candidate-level verification and evidence review before selecting
   supported labels. A remaining failure that violates a feature's common-task
   criteria blocks that label, even when most screens pass.

Update the nearest feature READMEs and canonical testing/runtime documentation
when implementation changes behavior or test ownership. This proposal alone does
not change the repository's required gates. The implementation is complete when
the scoped journeys meet their criteria, required gates pass, and any remaining
limitations are explicit in the candidate review.

## References

Criteria reviewed for this proposal on 2026-09-26; recheck at candidate
sign-off.

- [Apple: Accessibility Nutrition Labels overview](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels)
- [Apple: Larger Text evaluation criteria](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/larger-text-evaluation-criteria)
- [Apple: Sufficient Contrast evaluation criteria](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/sufficient-contrast-evaluation-criteria)
- [Apple: Dark Interface evaluation criteria](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/dark-interface-evaluation-criteria)
- [Apple: Performing accessibility audits for your app](https://developer.apple.com/documentation/accessibility/performing-accessibility-audits-for-your-app)
- [W3C: Applying WCAG to non-web information and communications technologies](https://www.w3.org/TR/wcag2ict/)
