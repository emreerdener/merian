# Naturebook Terms: Counsel and Release Review

Status: internal working memo

Product retention decision recorded: July 31, 2026

Draft and release controls reviewed against repository behavior: August 3, 2026

Public draft: [`apps/web/app/terms/page.tsx`](../../apps/web/app/terms/page.tsx)

This memo is not legal advice. It records product facts, drafting decisions, unresolved
business choices, and implementation gaps for qualified counsel and the release team.
The public Terms should not be treated as launch-ready until the release blockers below
are resolved.

The operator's documented product requirements and implemented Service behavior are the
source of truth. Earlier Terms and policy drafts do not define or constrain product
requirements. The mandatory product decision is: every submitted scan contributes a
scientific observation; exact coordinates and the other scientific facts remain after
account deletion; this retention has no separate opt-in or opt-out; and no additional
retention table is introduced. Public documents must accurately disclose that behavior
without purporting to remove statutory rights that cannot be waived by contract.

## Drafting Position

The Terms use three distinct permissions:

1. **Operational license for private and public user content.** Naturebook may process
   content only as reasonably needed to provide, secure, troubleshoot, and support the
   Service and the user's selected features.
2. **Public Contribution license.** Media deliberately published to Explore may appear
   on public surfaces and may be selected as species reference imagery while it remains
   shared and eligible. The draft does not turn every private scan into public reference
   media and does not grant Naturebook a standalone stock-media resale right.
3. **Mandatory Scientific Data contribution and license.** Every submitted scan creates
   a scientific observation containing exact coordinates when present, elevation, time,
   taxonomy, identification, environmental, quality, and provenance facts. The ownerless
   scientific record survives account deletion as a required condition of the Service.
   Scientific Data may be aggregated, shared, published, licensed, or sold under the
   Terms' privacy, geoprivacy, sensitive-species, access, and legal restrictions, and
   Naturebook may retain resulting revenue without paying contributors.

The draft intentionally does **not** grant Google or another third party permission to
train a general-purpose AI model on user submissions. A materially different future AI
use or provider should receive a new disclosure and permission where required.

## Release Blockers

### P0 — Identify the Contracting Party

The repository contains the Naturebook brand and `support@naturebook.earth`, but no
operator legal name, physical address, or telephone number. Counsel must add:

- full legal entity or individual operator name;
- registered or business address;
- complaint and claims telephone number;
- any required trader, company-registration, tax, or representative details; and
- the correct copyright owner and App Store seller/developer identity.

Apple's minimum custom-EULA terms require the developer's name, address, telephone
number, and email address. Until those facts exist, do not submit this draft as a custom
EULA in App Store Connect.

### Implemented UI and Evidence Design — Release-Blocked

Current onboarding has welcome, camera, location, and ready steps:

- [`OnboardingView.swift`](../../apps/ios/Merian/Features/Onboarding/Shell/Views/OnboardingView.swift)
- [`OnboardingStep.swift`](../../apps/ios/Merian/Features/Onboarding/Steps/Models/OnboardingStep.swift)
- [`ReadyStepView.swift`](../../apps/ios/Merian/Features/Onboarding/Steps/Ready/ReadyStepView.swift)

The ready step now states that Naturebook sends scan data to Google Gemini, a third-party
AI service, for identification. It presents three initially-off switches: required 18+
self-attestation, required agreement to the inline-linked Terms plus permission for that
data sharing, and separate optional PostHog analytics. Only the first two enable **Start
scanning**. There is no separate Decline action because the app has no non-AI operating
mode; withholding permission keeps scanning unavailable and prevents submission. The
disclosure and linked legal copy state, before a new user can submit a scan:

- which information may be sent, including media, descriptions, location, and
  environmental/capture context;
- that the recipient is Google Gemini;
- why it is sent;
- that AI processing is necessary for core identification; and
- what withholding permission does.

Migrations `20260804020351_record_legal_consent_receipts.sql` and
`20260804033307_add_adult_and_analytics_consent.sql`, together with
`ConsentManager.swift`, establish the intended evidence boundary. Before the
workspace opens, the app appends local adult-confirmation, Terms, and Gemini actions with
separate policy versions, exact displayed copy, client UUID, device action time, platform,
app version, and build. It synchronizes those records to immutable, owner-only Supabase
tables with a server-controlled recorded time and no client update/delete path. Existing
installs with the old onboarding flag but no current evidence enter directly at this
disclosure.

Every iOS inference entry point verifies that the current rows reached the active account
before constructing its provider request. Both service-only `reserve_ai_quota` overloads
repeat the check before provider admission, so a modified or stale client fails closed.
Settings provides a confirmed Gemini withdrawal action that appends a revocation event and
immediately returns the app to the disclosure gate.

That design is not yet a verified production control. The second-pass review found that
unsynchronized ghost-owned actions can be orphaned during account merge, stale/cancelled
session fetches lack a post-await identity guard, target-owned pending actions may wait for
a later sync, Realtime startup/retry is not guaranteed, and the consent unit-test target
does not currently compile. These defects and the exact exit evidence are canonical in
the
[production consent readiness record](./production-consent-readiness-2026-08-03.md).

Release still requires the additive migration, replacement TestFlight build, old-build
expiration, closure of every internal consent-readiness finding, owner-only strict cutover,
deployed contract verification, renewed acceptance
whenever a required material policy version changes, and final screenshots and an
explanation in App Review notes. Qualified counsel must
approve the final combined acceptance and disclosure copy; this engineering record is not
a legal conclusion that bundled Terms and provider permission is valid in every release
region.

### Implemented Analytics Design — Release-Blocked

The intended design configures PostHog lifecycle events with a US host only after a
separate optional grant. Replay, automatic screen views, element interactions, surveys,
swizzling, and push capture are explicitly disabled. `ConsentManager` stores immutable
account-wide grants and revocations; absence means off. Settings exposes **Analytics &
diagnostics** without changing core functionality. Edge telemetry checks the same latest
account event before every PostHog request and no longer sends auth email or name.

The iOS lifecycle is not release-ready. [`PostHogManager.swift`](../../apps/ios/Merian/Core/Analytics/PostHogManager.swift)
currently invokes PostHog 3.69.0 `reset()` before opt-out and close; that SDK call may
reload feature flags and therefore can start a network request during withdrawal. Offline
ghost-account revocations, account replacement, and Realtime startup/retry also have open
findings. Production requires evidence of no PostHog setup, identification, capture, or
network activity before grant and after withdrawal or account change.

Before release, counsel must still review the displayed choice and updated Privacy Policy,
and the App Store privacy answers must match the actual event properties and US host.

The public draft does not make non-essential analytics irrevocable or a condition of the
core app. A contract cannot remove statutory consent, objection, or withdrawal rights.

### P0 — Resolve the Under-18 Provider Conflict

The current app uses the Gemini Developer API. Google's Gemini API Additional Terms
effective March 23, 2026 say API clients may not be directed to or likely accessed by
people under 18. The Terms and Privacy Policy use an **18+** rule. The replacement iOS
build now requires an initially-off self-attestation switch on the final disclosure screen
and stores exact, versioned evidence locally and account-wide. It does not collect a birth
date or exact age. The strict server cutover requires current adult, Terms, and Gemini
evidence before every provider reservation.

The replacement build is not eligible for release until the internal readiness findings
are closed and a clean compiled consent test run passes.

Public production remains blocked until App Store Connect carries the reviewed 18+ rating
override and marketing/distribution are confirmed not directed toward minors. Product and
counsel must archive that evidence with the release record.

### P0 — Counsel Review of Mandatory Scientific Retention

The fixed product and engineering boundary is canonical in
[`17-scientific-observation-retention.md`](../backend-and-data/17-scientific-observation-retention.md).
Migration
[`20260731154139_retain_scientific_coordinates_after_account_deletion.sql`](../../services/supabase/migrations/20260731154139_retain_scientific_coordinates_after_account_deletion.sql)
implements the product decision without a new table. It makes scans ownerless and clears
media URLs/manifests, semantic and public location labels, device locale/time-zone
context, observation context, custom tags, and free-form intervention notes. It retains
exact and projected coordinates, elevation, observation time, taxonomy, identification,
review, environmental, quality, and provenance fields. The privileged routine deletes
the public profile and the durable workflow verifies object-store erasure before deleting
Auth. Tombstones remain excluded from personal and broad anonymous scan access.

The scan-generation trigger compares complete `OLD` and `NEW` rows after subtracting
only the account fields that deletion is allowed to change. This fails closed for every
current or future scientific field when account deletion collides with an individual
scan-deletion fence. The account routine deliberately uses a clearing list because every
other scan field is retained Scientific Data; new columns still require an explicit
privacy and retention review.

The retained observation must not be described as necessarily anonymous or
de-identified. Exact location plus time and species may remain personal information.
Before release, qualified counsel should review the applicable legal bases, notice at
collection, purpose and retention disclosures, regional deletion exceptions and other
non-waivable rights, sensitive-location safeguards, recipient restrictions, and App
Review explanation. This is a legal-compliance review of a fixed product requirement,
not a consent, opt-in, or opt-out product decision.

The product still deletes account-linked Explore content and all submitted photos,
videos, and audio. Permanent retention of public media is not part of this decision.

### P0 — Correct the Account-Deletion UI

[`DeleteAccountSheet.swift`](../../apps/ios/Merian/Features/Profile/Settings/Views/DeleteAccountSheet.swift)
now distinguishes deletion of the profile, attribution, community content, scan media,
private notes, life list, and collections from mandatory retention of exact coordinates,
time, taxonomy, and the other ownerless scientific facts. It also warns that account
deletion does not cancel Apple billing. Keep this language synchronized with the Terms,
Privacy Policy, and backend migration contract. A direct subscription-management action
would further improve the flow but is not implemented in this patch.

Verify that Sign in with Apple tokens are revoked as part of account deletion. No token
revocation implementation was found in the reviewed deletion paths.

### P0 — Use Gemini's Paid Production Terms and DPA

Google's current Gemini Developer API terms distinguish unpaid and paid Services.
Unpaid-Service submissions and outputs may be used to improve Google products and may
be reviewed by humans. Paid-Service prompts and responses are not used by Google to
improve its products, though limited logging may occur for abuse prevention and legal
requirements. EEA, Switzerland, and UK API clients may use only Paid Services.

Before release:

- confirm every production key belongs to a Cloud project with active billing;
- accept and archive the applicable Data Processing Addendum;
- verify regions, subprocessors, retention, transfer terms, and abuse-logging behavior;
- prevent fallback to an unpaid project or key;
- ensure test and staging data contain no real user personal information if unpaid;
- align the in-app disclosure and Privacy Policy with the actual configuration; and
- review whether Google Grounding, caching, files, tuning, or another feature changes
  retention or user-facing attribution obligations.

### P0 — Update the Privacy Documents at the Same Time

The Privacy Policy and Privacy Choices page now disclose the mandatory ownerless
scientific record, exact-coordinate retention, absence of a separate retention choice,
and launch-disabled DwC-A export. Before the Terms become effective, counsel must still
review the complete privacy package for:

- the main identification payload sent to Google Gemini, not only Explore audio
  classification;
- the exact production Gemini data-treatment configuration;
- PostHog event categories, identifier linkage, host region, consent or lawful basis,
  and a working withdrawal method;
- public-photo selection as species reference imagery;
- automatic profile-visible Backyard Safari enrollment, immediate author-profile
  discoverability at zero progress, and the adequacy of Stop/Reset as the only
  unfinished-status controls;
- free and paid sharing/licensing of Scientific Data that may remain personal;
- the exact account-tombstone retention and clearing boundary;
- retention periods and deletion completion timing;
- the 18+ eligibility rule; and
- applicable privacy rights, appeals, and regional contact/representative details.

Both pages now qualify Darwin Core Archive export as launch-disabled. Keep that language
until the authoritative release gate is deliberately enabled.

## Counsel and Business Decisions

Counsel and the operator should decide and document:

- governing law, venue, and whether to use arbitration or a class-action waiver;
- release countries and region-specific consumer, privacy, and UGC obligations;
- whether the app uses Apple's Standard EULA plus separate Service Terms or submits
  these Terms as a custom EULA;
- whether the US $100 / prior-12-month-fees liability cap is suitable and enforceable;
- indemnity scope for consumers;
- formal copyright/DMCA process and agent registration, if applicable;
- a repeat-infringer policy;
- moderation staffing, escalation, appeals, evidence retention, and regulator response;
- dangerous-organism, sensitive-species, trespass, and field-safety warnings;
- insurance appropriate to AI identification, UGC, privacy, and outdoor-use risks;
- research ethics and recipient terms for Scientific Data;
- whether any commercial data arrangement is a "sale" or "sharing" under a privacy law,
  particularly when retained Scientific Data includes exact location and time;
- tax, attribution, database-right, and third-party-license constraints for commercial
  datasets;
- rules for government, law-enforcement, and emergency requests;
- accessibility, localization, and electronic-notice requirements; and
- a retention schedule for moderation evidence, fraud prevention, support, analytics,
  subscription records, backups, and legal holds.

## Product Facts Covered by the Draft

| Product fact | Terms section |
| --- | --- |
| Anonymous accounts may be created automatically and later linked | 4 |
| Gemini is central to identification and receives multimodal and context inputs | 5 |
| AI results are probabilistic and not safety or professional advice | 6 |
| PostHog product analytics and currently disabled capture modes | 7 |
| Three included Pro scans with no calendar expiry, a separate daily Flash scan, seven-day non-renewing pass, and annual auto-renewing plan | 8 |
| Operational content license and contributor warranties | 9 |
| Explore is public UGC and eligible photos can become reference imagery | 10 |
| Every submitted scan contributes mandatory Scientific Data that can be used or licensed | 11 |
| Exact/private location, public projections, embedded photo metadata | 12 |
| Likes, comments, replies, follows, reports, blocks, and moderation | 13 |
| Fair-use, scraping, security, model-training, clinical-use restrictions | 3 and 14 |
| Supabase, Cloudflare, Google, RevenueCat, PostHog, Resend, GBIF, Wikipedia | 15 |
| Durable biological media, 30-day non-biological purge, temporary storage | 16 |
| Individual scan deletion and content-free anti-resurrection UUID fence | 16 |
| Account deletion removes account content but retains ownerless exact scientific facts | 16 |
| AI/data loss disclaimers, liability cap, indemnity, termination | 18–22 |
| Apple's minimum custom-EULA concepts | 23 |

## Deliberately Not Promised

The draft does not promise:

- accurate or successful identification;
- medically, legally, or regulatorily safe output;
- truly unbounded Pro usage;
- that every queued or offline item will upload;
- permanent storage or backup of account-owned content or media;
- Darwin Core Archive export at launch;
- complete end-to-end Apple Watch functionality;
- permanent public use of a photo after unsharing or account deletion;
- payment or royalties to contributors;
- that ownerless Scientific Data is anonymous or outside privacy law; or
- that future Terms changes alone can authorize a materially different data purpose.

## Final Review Evidence

Before approval, provide counsel with:

- the closed
  [production consent readiness record](./production-consent-readiness-2026-08-03.md),
  including clean compiled iOS and deployed enforcement evidence;
- the final in-app acceptance screen and withholding/withdrawal behavior;
- the final Terms, Privacy Policy, Privacy Choices, Community Guidelines, and account
  deletion copy;
- App Store subscription product metadata and every paywall variant;
- final App Store privacy labels and age-rating answers;
- a data-flow diagram and current scan/tombstone retention and clearing boundary;
- Google and PostHog contracts, DPAs, regions, and subprocessor lists;
- representative PostHog event payloads;
- public/reference-photo promotion and removal tests;
- account and individual-scan deletion test evidence, including object storage;
- moderation policy and operating procedures; and
- all third-party ecological-data and media licenses used in commercial outputs.
