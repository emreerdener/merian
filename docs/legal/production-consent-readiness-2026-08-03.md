# Production Consent Readiness — 2026-08-03

## Status

**Blocked.** The repository contains the intended final onboarding surface,
versioned consent evidence, server-side Gemini admission guard, optional
analytics control, and legal copy. The reviewed consent-lifecycle defects,
including durable local-write and withdrawal recovery, the adjacent
stale-sync/unit-fixture defects, and the account-restoration lifecycle findings
are complete in source. AI and analytics streams now also reject delayed
offline grants whose causal parent is no longer authoritative and rebase
revocations onto the locked current head. Every permission consumer now resolves
that all-version head before evaluating a grant's disclosure bundle, so a
withdrawal under an older disclosure cannot be hidden by a current-version
grant. Hosted exact-SHA execution and the
external operator controls below must still close before this candidate is
nominated for production.

For internal test builds, the App Store, billing/DPA, and counsel approvals are
explicitly deferred. That deferral permits continued engineering and internal
beta validation; it does not authorize production submission or public release.

The shorter disclosure, analytics label, and Analytics → Age → Terms ordering
currently in the app are an explicit product-owner choice. They now carry fresh
Gemini and analytics disclosure versions so immutable receipts do not mix
different text under one version. Counsel approval of that retained copy remains
an external production requirement.

This record is the canonical status source for the adult, Terms, Google Gemini,
and PostHog consent release. Architecture documents describe the required end
state; they do not override the release hold recorded here.

## Adjacent iOS Privacy Manifest Status

The missing main-application `PrivacyInfo.xcprivacy` finding is closed in
source. The app-owned manifest declares no tracking, conservatively declares
the reviewed linked data categories, and records `C617.1`, `E174.1`, and
`CA92.1` for the current file-timestamp, disk-space, and app-only user-defaults
uses. Source, project, archive, and exported-IPA validators are implemented.

This is adjacent to, not a replacement for, the consent gate. A manifest
describes potential collection and required-reason API use; it does not grant
PostHog or Gemini permission, prove consent ordering, establish an ATT
conclusion, or approve App Store privacy answers. Production evidence still
requires the exact-SHA archive to report `privacy_manifest_valid: true`, then a
reviewed Xcode aggregate privacy report from the signed archive and matching
owner/counsel-approved App Store answers. See the
[iOS App Privacy Manifest Contract](../development-guides/16-ios-privacy-manifest.md).

## Adjacent iOS Transport Security Status

The global `NSAllowsArbitraryLoads` exception is removed in source. The app now
requires credential-free HTTPS for configured origins and backend-supplied
remote media, while ATS remains the independent operating-system backstop.
Source, archive, and exported-IPA validators reject broad, media, web-content,
local-network, and domain-scoped exceptions.

Production evidence still requires the exact-SHA archive to report
`transport_security: "ats-default"`, and the signed Organizer archive must
pass the same final-bundle check. See the
[iOS App Transport Security Contract](../development-guides/17-ios-transport-security.md).

## Required Product Contract

The onboarding order remains Welcome → Camera → Location → Powered by AI. The
final screen must show this disclosure before its controls:

> Naturebook sends observation data to Google Gemini for AI-powered
> identification.

It presents three initially-off, left-aligned switches:

1. **Optional:** “Share usage and diagnostics to help improve Naturebook.”
2. **Required:** “I confirm I am 18 or older.”
3. **Required:** “I accept the terms and allow this data sharing.” The word
   “terms” links to the full Terms of Service.

Only the two required switches gate **Start scanning**. Withholding or withdrawing
analytics permission must never block core functionality. Existing beta users
stay on a launch-matched neutral surface while the initial session and
authoritative consent evidence are reconciled. If the resolved account still
lacks current required evidence, they return directly to Powered by AI without
repeating Camera or Location; restored evidence opens the workspace without
presenting approval controls. A network, decoding, pending-row push, or
ledger-persistence failure is not evidence of absence: the neutral surface
remains the active root, offers an immediate retry, and performs three bounded
account-fenced retries before requiring an explicit retry. Duplicate
same-account auth notifications do not consume the budget. Account or
synchronization-generation invalidation cancels stale retry work and returns
the same unresolved account to reconciliation; it never leaves a waiting state
after its timer is gone.

## Evidence and Enforcement Contract

- Adult eligibility uses self-attestation on every supported iOS version. Do
  not collect a birth date or exact age.
- Current adult policy and Terms versions are `2026-08-03`; the current Google
  Gemini disclosure version is `2026-08-04.1`, and the current analytics
  disclosure version is `2026-08-04`.
- Adult, Terms, Gemini, and PostHog actions use immutable, versioned evidence
  containing the exact displayed text, device action time, platform, app
  version/build, and a server-controlled timestamp.
- Absence of a current PostHog grant means analytics is off.
- The local ledger is installed in memory only after a throwing, verified atomic
  file replacement. Analytics withdrawal closes capture first and records its
  exact event in an independent Keychain journal before the main ledger write;
  pending journal entries remain fail-closed and replayable across restart.
- Local required evidence closes the UI gate, but Gemini remains unauthorized
  until current adult, Terms, and Gemini evidence exists on the active Supabase
  account and the service-only quota boundary accepts it.
- Public consent tables require explicit privileges and owner-only RLS. This is
  deliberate rather than relying on changing Data API defaults; see the
  [Supabase Data API exposure change](https://supabase.com/changelog/45329-breaking-change-tables-not-exposed-to-data-and-graphql-api-automatically).
- Reauthentication, account change, withdrawal, offline retry, and
  ghost-to-existing-account merging must preserve the latest user action and
  must never infer or fabricate consent.
- Gemini and PostHog mutations name the account/provider event observed when
  the action was created. An authenticated `SECURITY DEFINER` causal
  compare-and-append
  RPC locks the account against ghost merge and then serializes that stream. It
  accepts a grant only from the current causal parent; a revocation is accepted
  and rebased to the locked current head so withdrawal wins either race order.
  The response returns the accepted parent and immutable server revision used
  for authorization. Direct client inserts are forbidden. A rejected stale
  grant remains local superseded evidence and cannot become authoritative
  merely because it reconnects later. Gemini, Edge PostHog, and iOS all resolve
  the all-version greatest revision first. Any head revocation denies; only that
  exact head, when granted, may proceed to current or allowlisted disclosure
  checks.

## Primary Policy Basis

Checked against the official sources on August 3, 2026:

- [Apple App Review Guideline 5.1.2(i)](https://developer.apple.com/app-store/review/guidelines/)
  requires clear disclosure of where personal data is shared with third
  parties—including third-party AI—and explicit permission before sharing.
- The [Gemini API Additional Terms](https://ai.google.dev/gemini-api/terms)
  require API users to be 18+ and prohibit API clients directed toward or
  likely accessed by people under 18.
- The same [Gemini paid-services terms](https://ai.google.dev/gemini-api/terms)
  classify Gemini API use as paid only through a Cloud project with active
  billing and state that paid prompts/responses are processed under Google's
  Data Processing Addendum rather than used to improve Google products.

This repository record translates those platform/provider requirements into
engineering release controls; it is not a legal opinion.

## Source Status

`CONSENT-001` through `CONSENT-011` are closed in source. “Closed in source” is
not exact-SHA runtime evidence and is not a production approval.

| ID | Implemented control | Remaining evidence |
| --- | --- | --- |
| `CONSENT-001` | PostHog uses a closed-by-default, host-scoped transport gate. Withdrawal closes transport before preserving `reset → optOut → close`, and permission generations reject stale setup work. | Exact-SHA hosted regression execution. |
| `CONSENT-002` | Ghost handoff durably rebinds all four immutable ledgers, synchronizes/refetches the permanent account, and only then removes the retry proof. Analytics remains suppressed until completion. | Exact-SHA hosted handoff execution. |
| `CONSENT-004` | Synchronization generation-fences every awaited operation. The final merge independently rechecks cancellation, observed account, synchronous Supabase SDK session, and generation before any ledger mutation, persistence, or analytics change. | Exact-SHA account-switch regression execution. |
| `CONSENT-005` | Restoring or changing an account enters an explicit remote-authority wait state before cached consent is refreshed or applied. Analytics stays closed while every target-owned pending adult, Terms, Gemini, and analytics row is pushed and authoritative state is refetched. Only a verified, identity-fenced ledger write may resolve account restoration. Authoritative absence or revocation may route to Powered by AI; fetch, decoding, pending-row push, and persistence failures remain on the neutral restoration surface with bounded automatic and explicit retry. Duplicate auth cannot consume the budget, and account/generation invalidation cannot leave a canceled timer represented as pending. | Exact-SHA cached grant, remote absence/revocation, offline revoke → switch away → return, synchronization-failure retry, persistence failure, duplicate-auth, and invalidated-retry execution. |
| `CONSENT-006` | Analytics-consent Realtime independently owns channel and subscribed-user identity, generation-fences stale listeners, and gives failed subscriptions an account-owned bounded retry. | Exact-SHA reconnect and cross-device execution. |
| `CONSENT-007` | OAuth replacement suppresses analytics and closes consent Realtime before session installation; success and failure reconcile the SDK's actual session under a transition generation. | Exact-SHA account-replacement execution. |
| `CONSENT-009` | The retained internal copy has distinct Gemini and analytics disclosure versions, and forward-only server compatibility preserves immutable historical receipts. | Exact-SHA migration/client contracts and replacement-build validation. |
| `CONSENT-010` | Consent mutations use a throwing, fault-injectable storage boundary and transactional candidate ledger. Onboarding completes only after a verified atomic file write. Analytics withdrawal closes capture first, journals exact revocation events independently in Keychain, remains off across failed writes/restart, preserves multiple accounts, and clears the journal only after ledger durability. | Exact-SHA fault-injection, restart-replay, onboarding, account-switch, full-unit, and Release archive execution. |
| `CONSENT-011` | AI and analytics writes lock the account row against ghost merge, then use account/provider causal RPCs under transaction-scoped advisory locks. The database atomically rejects stale grants, rebases revocations to the current head, issues the only authoritative monotonic `consent_revision`, and denies authenticated direct inserts and sequence access. iOS retains rejected grants as superseded evidence, persists the server-returned accepted parent, fetches the all-version stream head, and orders accepted events by revision. Gemini authorization, Edge analytics, and iOS permission first evaluate that provider-wide head: every head revocation denies regardless of disclosure version and before rollout configuration is read, while only the exact head grant may enter current or legacy bundle checks. Database, Edge, and iOS fixtures include a prior-disclosure revocation uploaded after a current-version grant; the database fixture submits the old observed causal parent and verifies that the RPC rebases both providers onto the newer grant before authorization denies. The disposable-database `legalConsentConcurrencyDb.test.ts` fixture also releases overlapping grant/revocation callers and requires a revoked final head for both providers. | Exact-SHA inverse-order and cross-disclosure iOS execution plus pinned-CLI fresh-catalog replay of both cross-device directions, the overlapping concurrency fixture, revocation retry idempotency, and RPC ACL/locking contracts. |

### Superseded Fixed Test Defects

- `CONSENT-003` was the missing `throws` declaration in the inline Terms-link
  test. It is fixed and is no longer an active blocker.
- `CONSENT-008` was a foreground-replay fixture that did not inject isolated
  granted consent. It is fixed, retains its closed-gate negative case, and is no
  longer an active blocker.

Older hosted and local runs remain useful diagnostic history, but their test
totals and outcomes are not current-candidate evidence. In particular, the
earlier hosted iOS run whose queued-audio smoke failed and the earlier Supabase
run whose database concurrency fixture failed are superseded. The subsequent
source fixes must be proven together on one new, unchanged candidate SHA.

## Current Exact-SHA Evidence

No green hosted evidence for the post-fence candidate is recorded yet. Do not
copy counts from older or local runs into this table; populate it only from the
two workflow summaries for the same immutable candidate SHA.

| Gate | Required result | Current result |
| --- | --- | --- |
| **iOS Build and Test** | Complete unit target, queued-audio UI smoke, and validation Release archive all green on one clean SHA; archive evidence must include `privacy_manifest_valid: true` and `transport_security: "ats-default"`. | Pending a new hosted run. |
| **Supabase Candidate Validation** | Fail-closed PR scope and stable Candidate readiness check, clean-SHA check, pinned tools, formatting/lint, migration replay, every discovered pgTAP catalog, complete Edge/database-concurrency suite, database lint, and advisors all green. | Pending a new hosted validation-only run. |
| Production Supabase deployment | Separate operator action after release authorization; it must require the reusable candidate gate first. | Not part of candidate validation and not authorized by a validation-only run. |

The candidate workflow has no Production environment, production secrets,
migration push, Function deployment, or production smoke. Its disposable
database is release evidence without production mutation. The workflow-reported
SHA, run URL, test totals, iOS archive fingerprint/version/build, and database
result become canonical only after both hosted gates pass on the same SHA.

## Required Remediation and Rollout Order

1. Run the complete hosted **iOS Build and Test** workflow on the exact candidate
   SHA. Require a compiled and executed complete `merianTests` target, the
   focused UI smoke, and the unsigned Release validation archive.
2. Run **Supabase Candidate Validation** on that unchanged SHA. Require its
   validation-only disposable replay, all pgTAP fixtures, complete Edge and
   database-concurrency suite, strict lint, and advisors to pass without a
   Production environment or production secrets.
3. Upload the corrected replacement binary and let App Store Connect finish
   processing it, but do not distribute it while the causal RPC or provider-head
   authorization migration is absent.
4. After separate production authorization, open the consent maintenance
   window. Suspend consent-changing app access and expire every older
   TestFlight build that writes Gemini or analytics events directly.
5. Use **Deploy Merian to Supabase**. Its production job must first require the
   reusable candidate gate, then apply the causal consent and provider-head
   authorization migrations and deploy consent-gated Edge code. Verify
   authenticated callers cannot insert directly,
   both compare-and-append RPCs return a monotonic revision and accepted parent,
   stale grants are rejected, stale revocations are rebased, and the inverse
   AI/analytics fixtures pass, including prior-disclosure revocations after
   current-version grants. Keep
   `internal.ai_consent_rollout_config.enforcement_mode` at
   `legacy_compatible`.
6. Distribute the processed replacement TestFlight build. Verify all switch
   combinations, inline Terms navigation, VoiceOver, Dynamic Type, smallest
   supported screens, offline withdrawal, account switching, foreground
   reconciliation, Realtime propagation, ghost-profile merging, and cold launch
   with completed onboarding after clearing only the local consent ledger. The
   latter must stay on the launch-matched restoration surface and open the
   workspace without a Powered by AI frame when the account restores current
   evidence; a genuinely absent account must proceed to Powered by AI only after
   reconciliation resolves. Interrupt connectivity on TestFlight and verify the
   same surface exposes retry without mounting Powered by AI. Require the
   unchanged candidate's hosted synchronization- and ledger-write-failure
   fixtures to prove decoding, pending-row push, and persistence errors have the
   same outcome; only a later successful authoritative merge may choose the
   workspace or Powered by AI. Verify duplicate auth does not advance the
   attempt and an account/generation transition cancels the old timer, rejects
   its stale wake, and starts the replacement reconciliation with a fresh
   budget. Also verify both inverse sequences for each
   provider: another device revokes before a delayed offline grant reconnects,
   and another device grants before a delayed offline revocation reconnects. The
   grant must be rejected in the first sequence; the revocation must be accepted
   and rebased in the second, and every consumer must deny when that revocation
   carries a prior disclosure version.
7. Only then run the owner-only forward strict-cutover script and verify legacy,
   partial, revoked, and current-complete accounts against the deployed server.

Never backfill age, Terms, Gemini, or analytics evidence. Never relax the
provider guard to recover availability.

This maintenance cutover is valid only while the affected cohort can be
stopped and every direct-writing build can be expired. If any consent-capable
public App Store cohort cannot be forced off before the ACL/RPC migration, the
one-step sequence is unsafe: prepare a separately reviewed two-phase protocol
and forced-update boundary instead of deploying this migration unchanged.

## External Production Blockers

Repository correctness does not close these operator-owned requirements:

- Configure and archive the reviewed 18+ App Store Connect age-rating override;
  verify product pages, campaigns, and distribution are not directed toward
  minors.
- A Google Cloud owner must confirm active paid billing for the project behind
  `GEMINI_PAID_API_KEY`, confirm the applicable DPA is in force, archive dated
  evidence in the restricted release record, rotate the key after confirmation,
  synchronize the new secret, smoke-test it, and revoke the superseded key.
- Counsel must approve the final Terms, Privacy Policy, consent presentation,
  Xcode aggregate privacy report, App Store privacy and ATT answers, operator
  identity, and regional release scope.

Production remains blocked until hosted exact-SHA validation and every external
production control are closed with exact-version, exact-build evidence. Those
operator controls remain deferred for internal-only test builds.
