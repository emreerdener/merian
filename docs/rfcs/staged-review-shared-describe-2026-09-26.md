# Staged review, shared Describe, and accessible settings

This is the dated implementation and validation record. As of 27 September 2026,
the
[staged-review feature contract](../features-and-hardware/29-staged-capture-review.md)
owns current UX and lifecycle behavior;
[the testing matrix](../development-guides/08-testing-strategy.md#staged-review-and-shared-describe-validation)
owns executable selectors. Initial validation limitations below are historical;
the follow-up section records their later resolution and remaining release
gates.

## Integration checkpoint

Implementation is based on reviewed commit
`ba97f7eba479f3b7357ebb3b0b1153a0f96a82b9`, including native recipient preflight
`5877cc7e97121fea6f0072239e9806711d2f52af`. Later branch changes and uncommitted
work are excluded. See the
[native recipient contract](./identification-native-recipient-preflight-2026-09-26.md)
and
[result provenance contract](./identification-client-result-provenance-2026-09-26.md).

Outstanding dependency evidence: full native suite was not repeated after
test-only corrections; six database-dependent provenance tests were skipped; iOS
17.2 runtime was unavailable; a genuine released-V51 install-over and second
launch remains required for distribution. Combined capture validation is tracked
below. This feature adds no schema migration or capture-specific wire field. It
preserves the integrated provider/provenance schema, routing, and immutable
results.

Prepare server eligibility changes before distributing the client. Deployment,
TestFlight, and App Store publication remain separate authorized operations with
the existing exact-SHA release gates. Unrelated optimization and benchmarks are
not prerequisites.

## Settings and capacity

- Staged review is the default for existing and new users. The new
  `autoSubmitScans` preference defaults to false, independently of old
  confirmation and multi-capture keys. Subsequent explicit choices persist.
- Auto-submit copy: “Submit each capture immediately, skipping review and the
  chance to add a note or another media item.” There is no multi-capture toggle.
- Free: one photo or standalone audio item plus one optional note. Pro: two
  media items plus one optional note. Video remains Pro-only. Historical
  evidence and the reanalysis supplement retain their existing semantics.
- Expedition is a normal Workspace toggle for everyone, using its existing key,
  saved value, and default-off behavior. Persist before hardware reconciliation.
  Copy: “Conserves battery by lowering camera frame rates, reducing visual
  effects, suppressing haptics, and pausing background uploads.” No entitlement
  dependency applies to hardware, haptics, or ordinary background-upload gating.
- Remove Expedition from Pro summaries, carousel, and its attributed
  testimonial; mark Included for both tiers in the comparison. Preserve prices,
  purchase flows, provider claims, and other paid benefits. Multi-capture
  explains two media items plus an optional note.

## Shared text and tray

Root Describe is the single ordinary editor. Typing saves draft text without
revealing the tray or submitting. Before staging, its nonempty action is plus
(Add description to scan) for review, or arrow (Identify) for auto-submit. Once
the tray exists, omit the central Describe action; keep prompts and dictation.
Keyboard Done dismisses the keyboard to reveal the tray. Identify uses the
latest text. Switching modes and keyboard dismissal preserve it; clearing it
removes the note. Removing the last media preserves remaining text. Empty drafts
return to initial capture.

The note node opens and focuses root Describe even at physical capacity. Empty
uses a message-plus, populated uses a filled message bubble; labels are Add/Edit
note. Show “Add a note about what you noticed” once per install. Free tray is
media / note / Identify; Pro is media / add-media-or-media / note / Identify.
Represent text once, including text-only scans. Placeholders never enter
payloads. Allow horizontal media overflow while keeping Discard and Identify
visible.

Ordinary editing and the current reanalysis supplement do not use
`StagedDescriptionSheet`. Retain it for historical descriptions only: Done
commits, swipe-dismiss discards pending changes, Remove commits removal.
Stop/fence current dictation before opening it.

Use native Liquid Glass on iOS 26+ for the tray and circular discard control,
adaptive appearance, older-iOS material, and opaque reduced-effect fallbacks for
accessibility, Expedition, and thermal constraints. Identify alone becomes
text-only system blue and retains its capsule and 48-point height. Analyze keeps
its icon/color.

## Destructive actions and ownership

Trash is red on neutral glass. Confirm with “Discard this scan?”, “Your staged
media and description will be removed,” and Keep editing / Discard scan.
Reanalysis uses “Discard reanalysis?” and restores the original insight after
confirmation. Opening/dismissing the confirmation does not erase anything and
blocks new composition/submission. Confirmation is bound to a draft generation.
Confirmed discard clears media, shared text, editor/refinement state, stops
recording/dictation, invalidates pending callbacks, and deletes only draft-owned
files. Historical media is never owned by that discard. Individual removal keeps
its existing behavior.

Before durable acceptance, retain draft and sources; lock enqueue against edits,
discard, and duplicate submission. Queue preparation copies sources to unique
queue-owned files. Failed save cleans only those copies and releases the draft
for manual retry. After acceptance, live inference receives the exact accepted
queue-owned timeline, and staging references/source files can be cleared.
Recovery uses the existing scan ID and durable owner. No accepted scan is
restored as a newly submittable draft. Ambiguous acceptance must be resolved
before another enqueue or deletion.

## Readiness and automatic attempts

Snapshot eligibility at photo/audio/video/import entry, before asynchronous
work: auto-submit enabled, all composition including pending text empty, no
reanalysis. Carry that eligibility through preparation and the initial required
crop. Completion consumes eligibility; it cannot create it. Turning the setting
off revokes it, including an off/on cycle. Turning it on, recropping, removing
media, and adding context cannot arm an existing attempt. Video may submit after
preparation. Fresh auto-submit gallery selection is limited to one item.

Register draft work before asynchronous execution. UI and direct submission use
one readiness policy, checked again after admission and before enqueue.
Recording, capture, import, preparation, and required crop block
Identify/Analyze. Commit prepared media and resolve the owning operation
together. Failure/cancellation resolves work, revokes auto-submit, and retains
existing content for manual review. Completions from a discarded generation
cannot affect its successor.

## Eligibility and provider invariants

One nonvideo photo/audio plus at most one nonempty note, or one description
alone, qualifies for the existing Free allowance. Additional media, video, or
multiple descriptions do not. Apply parity at photo/audio/gallery entry,
submission, enqueue, replay, recipient preflight, and server admission. Preserve
Pro-first funding precedence and exhausted-Pro/remaining-Free fallback.
Expedition never changes funding or quotas.

Preflight remains derived from final serialized evidence. Video frames and
companion audio retain video-derived classification, routing, and all evidence.
Manual, automatic, and replay paths retain dispatch-time account, permission,
version, and attempt checks. Consent denial/withdrawal, recipient changes, and
client-version rejection preserve the same observation through pause/recovery.
Re-preflight reassignment without silent provider switching or a new scan.
Preserve denial-only expectations, recovery-only responses, fail-closed
behavior, chronological evidence, historical descriptions, supplements, and
provenance. Reanalysis retains historical descriptions alongside the existing
primary-media selection, preserving their original order. Historical text and
the single current supplement do not consume the physical-media budget.

## Validation and handoff

Required coverage includes both media/note input orders across entry, enqueue,
preflight, and replay; exhausted Pro with Free remaining; video classification;
provider/consent/version failures and same-scan recovery; a second item in
progress; attempt-bound auto-submit through every preparation/crop; root
Describe focus and text-only flows; historical isolation; discard generations;
failed acceptance; and source/copy ownership. Verify Expedition for Free, Pro,
expired, unverified, and offline users, preserving preferences and restoring
normal constraints when disabled. Verify paywall carousel after slide removal.
Exercise VoiceOver, larger text, overflow, glass, and reduced-effect fallbacks
on devices/simulators.

Implementation branch: `codex/capture-staged-review`. Implementation commit:
`5c0f6b71a16a59b70789a085785b49c76849d09e`. The app and test targets build on
Xcode 27 / iOS 27. Successful UI evidence covers shared Describe
staging/editing, confirmed discard, note focus at physical capacity, keyboard
Done, and accessibility XXXL tray overflow with both fixed actions visible. The
two existing Describe focus/first-launch tests also passed.

Backend validation: 2,109 Deno tests and 265 steps passed; six
database-dependent tests were ignored. Recursive frozen function type checks,
Deno lint, Supabase tooling, captured-media and generated Edge DTO contract
checks, and the exact recursive candidate formatter gate passed. iOS project
membership, event routing, privacy, transport, and migration source guards
passed. SwiftLint passed with existing warnings; Markdown formatting and
whitespace checks passed.

Local synthetic screenshots and logs are retained under
`.artifacts/capture-staged-review/`, outside the disposable build cache. These
are development checks, not release or live-provider evidence. Distribution
still requires the released-V51 install-over/second-launch evidence, unavailable
iOS 17.2 coverage, database-dependent checks, and physical-device VoiceOver,
older-iOS/reduced-effect visual review. Server eligibility must be released
through the existing exact-SHA gates before client distribution; no deployment
or publication is included in this change.

### Initial native validation status at handoff

At the initial handoff, the full native gate was **not green**. The initial
complete run executed 1,366 XCTest tests and 3,006 Swift Testing tests. It
reported an authentication facade failure, an architecture line-budget
violation, and two obsolete replay file-ownership assertions. The latter three
assertions were corrected and their focused suites passed. The authentication
facade passed unchanged on a fresh simulator; it failed on the earlier simulator
with accumulated durable fixture state.

The latest focused run passed all 118 Swift Testing tests in 11 suites and 91 of
92 XCTest tests, including the new historical-note ordering and full-media
supplement cases. Its remaining failure was an old refinement fixture that
counted historical text against physical capacity. That fixture now stages two
physical items. A final regression was also added for individually removing the
last media item: subsequent Describe typing must remain unstaged. These last
fixture/reset changes require the final build and native rerun.

The two new UI flows passed on iOS 27 before those last fixture/reset changes:
shared Describe editing plus confirmed discard, and note access at capacity with
accessibility XXXL text. The keyboard test exposed and verified a real fix: a
dedicated keyboard-toolbar Done action dismisses the multiline editor.
Successful screenshots were visually inspected. These checks do not substitute
for physical-device VoiceOver or older-OS material/thermal-effect review.

The final complete native rerun was attempted twice but refused by
`scripts/local-ios-build.py` because another task's main-checkout `xcodebuild`
was active. At handoff it was collecting `simctl diagnose` output; it was not
interrupted. Re-run through `make ios-local-build` on a fresh simulator once
that process releases the shared guard, using
`test -only-testing:merianTests
-parallel-testing-enabled NO -collect-test-diagnostics never`,
then rerun the two new UI selectors after any further UI changes. Use the
wrapper's normal checkout-local cache; do not bypass its concurrency guard. This
native gate is required before merge/distribution, in addition to the dependency
release evidence listed above.

### Follow-up review (2026-09-27)

The follow-up review corrected three gallery/admission cases. Picker entry now
admits the minimum one-photo addition, preserving exhausted-Pro/remaining-Free
access to one photo with an optional note. After selection, admission checks the
actual count before loading files. The one-photo automatic picker limit applies
only to an empty composition, including pending Describe text. A discarded
draft's late admission response is ignored before it can present a paywall or
error on the next draft. Regression tests cover both note input orders, actual
selection counts, pending text, and discard during admission.

An independent read-only review found no further admission or durable-ownership
defect. Current feature documentation was reconciled with the single shared
Describe editor and separate physical/text budgets; historical validation
records remain intact.

Production review fixes are committed in
`f643bdd8460ecaf1ce267e87757395a5eb52f18e`, following the original
implementation `5c0f6b71a16a59b70789a085785b49c76849d09e` and initial evidence
record `d125a6b8a4f0d3cd8fbeeb45ec868110f809cb38`.

The first complete review run passed 1,370 XCTest cases and 3,008 Swift Testing
cases in 465 suites. The final complete run, including both later guards, passed
**1,372 XCTest cases and 3,008 Swift Testing cases** on a fresh iOS 27
simulator. Its result bundle is
`.artifacts/local-ios/e5f6727393f14734913687d39381906c.xcresult`. This closes
the initial native gate failure described above. No production code changed
after that successful run.

The first four-case UI run passed three cases and failed the existing lower-area
focus test. Its recording confirmed that the lower-area tap focused the editor
and opened the keyboard; the test had injected typing without waiting for
keyboard readiness. The test now explicitly waits for the keyboard and verifies
the entered value with a bounded expectation. That test-only change is committed
in `aea6a8f5f58770f447b948026403efa47136ea49`. All four selectors then passed
three consecutive iterations: **12 executions, zero failures**. The successful
repeat result bundle is
`.artifacts/local-ios/a18d4ce058114be0952b4e69365466b6.xcresult`. Shared-note
and accessibility XXXL screenshots were visually inspected. The initial failure
and successful repeat logs are retained alongside the final native log under
`.artifacts/capture-staged-review/`.

SwiftLint passed with existing warnings. Project membership, event routing,
privacy, transport-security, migration source guards, Markdown formatting, and
whitespace checks passed. The prior backend results remain applicable because
this follow-up changed no backend or wire contract. The six database-dependent
checks, iOS 17.2 coverage, actual released-V51 install-over/second-launch
evidence, and physical-device VoiceOver/material/thermal checks remain open. No
deployment or distribution was performed; server-before-client and
infrastructure release gates remain in force.
