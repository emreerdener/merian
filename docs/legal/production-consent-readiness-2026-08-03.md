# Production Consent Readiness — 2026-08-03

## Status

**Blocked.** The repository contains the intended final onboarding surface,
versioned consent evidence, server-side Gemini admission guard, optional
analytics control, and legal copy. The two P1 consent-lifecycle defects from the
second-pass review, the adjacent stale-sync/unit-fixture defects, and the three
account-restoration lifecycle findings are complete in source. Hosted exact-SHA
execution and the external operator controls below must still close before this
candidate is nominated for production.

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
without current required evidence return directly to Powered by AI without
repeating Camera or Location.

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
- Local required evidence closes the UI gate, but Gemini remains unauthorized
  until current adult, Terms, and Gemini evidence exists on the active Supabase
  account and the service-only quota boundary accepts it.
- Public consent tables require explicit privileges and owner-only RLS. This is
  deliberate rather than relying on changing Data API defaults; see the
  [Supabase Data API exposure change](https://supabase.com/changelog/45329-breaking-change-tables-not-exposed-to-data-and-graphql-api-automatically).
- Reauthentication, account change, withdrawal, offline retry, and
  ghost-to-existing-account merging must preserve the latest user action and
  must never infer or fabricate consent.

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

`CONSENT-001` through `CONSENT-009` are closed in source. “Closed in source” is
not exact-SHA runtime evidence and is not a production approval.

| ID | Implemented control | Remaining evidence |
| --- | --- | --- |
| `CONSENT-001` | PostHog uses a closed-by-default, host-scoped transport gate. Withdrawal closes transport before preserving `reset → optOut → close`, and permission generations reject stale setup work. | Exact-SHA hosted regression execution. |
| `CONSENT-002` | Ghost handoff durably rebinds all four immutable ledgers, synchronizes/refetches the permanent account, and only then removes the retry proof. Analytics remains suppressed until completion. | Exact-SHA hosted handoff execution. |
| `CONSENT-004` | Synchronization generation-fences every awaited operation. The final merge independently rechecks cancellation, observed account, synchronous Supabase SDK session, and generation before any ledger mutation, persistence, or analytics change. | Exact-SHA account-switch regression execution. |
| `CONSENT-005` | Restoring an account activates its ledger with analytics closed, pushes every target-owned pending adult, Terms, Gemini, and analytics row, then refetches and merges authoritative state. | Exact-SHA offline revoke → switch away → return execution. |
| `CONSENT-006` | Analytics-consent Realtime independently owns channel and subscribed-user identity, generation-fences stale listeners, and gives failed subscriptions an account-owned bounded retry. | Exact-SHA reconnect and cross-device execution. |
| `CONSENT-007` | OAuth replacement suppresses analytics and closes consent Realtime before session installation; success and failure reconcile the SDK's actual session under a transition generation. | Exact-SHA account-replacement execution. |
| `CONSENT-009` | The retained internal copy has distinct Gemini and analytics disclosure versions, and forward-only server compatibility preserves immutable historical receipts. | Exact-SHA migration/client contracts and replacement-build validation. |

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
| **iOS Build and Test** | Complete unit target, queued-audio UI smoke, and validation Release archive all green on one clean SHA. | Pending a new hosted run. |
| **Supabase Candidate Validation** | Clean-SHA check, pinned tools, formatting/lint, migration replay, every discovered pgTAP catalog, complete Edge/database-concurrency suite, database lint, and advisors all green. | Pending a new hosted validation-only run. |
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
3. After separate production authorization, use **Deploy Merian to Supabase**.
   Its production job must first require the reusable candidate gate, then
   apply only the additive consent schema and deploy consent-gated Edge code.
   Keep `internal.ai_consent_rollout_config.enforcement_mode` at
   `legacy_compatible`.
4. Distribute the corrected replacement TestFlight build. Verify all switch
   combinations, inline Terms navigation, VoiceOver, Dynamic Type, smallest
   supported screens, offline withdrawal, account switching, foreground
   reconciliation, Realtime propagation, and ghost-profile merging.
5. Expire every older TestFlight build that cannot produce the current consent
   bundle.
6. Only then run the owner-only forward strict-cutover script and verify legacy,
   partial, revoked, and current-complete accounts against the deployed server.

Never backfill age, Terms, Gemini, or analytics evidence. Never relax the
provider guard to recover availability.

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
  App Store privacy answers, operator identity, and regional release scope.

Production remains blocked until hosted exact-SHA validation and every external
production control are closed with exact-version, exact-build evidence. Those
operator controls remain deferred for internal-only test builds.
