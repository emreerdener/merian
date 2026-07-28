# Naturebook Terms: Counsel and Release Review

Status: internal working memo  
Draft reviewed against repository behavior: July 28, 2026  
Public draft: [`apps/web/app/terms/page.tsx`](../../apps/web/app/terms/page.tsx)

This memo is not legal advice. It records product facts, drafting decisions, unresolved
business choices, and implementation gaps for qualified counsel and the release team.
The public Terms should not be treated as launch-ready until the release blockers below
are resolved.

## Drafting Position

The Terms use three distinct permissions:

1. **Operational license for private and public user content.** Naturebook may process
   content only as reasonably needed to provide, secure, troubleshoot, and support the
   Service and the user's selected features.
2. **Public Contribution license.** Media deliberately published to Explore may appear
   on public surfaces and may be selected as species reference imagery while it remains
   shared and eligible. The draft does not turn every private scan into public reference
   media and does not grant Naturebook a standalone stock-media resale right.
3. **Scientific Data license.** Reduced, non-identifying scientific facts may be
   aggregated, shared, published, licensed, or sold, and Naturebook may retain the
   revenue without paying contributors. This license can survive account deletion only
   for data that is lawfully non-personal or otherwise lawfully retained.

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

### P0 — Implement Affirmative Terms and AI Acceptance

Current onboarding has only welcome, camera, location, and ready steps:

- [`OnboardingView.swift`](../../apps/ios/Merian/Features/Onboarding/Shell/Views/OnboardingView.swift)
- [`OnboardingStep.swift`](../../apps/ios/Merian/Features/Onboarding/Steps/Models/OnboardingStep.swift)

No versioned Terms acceptance or specific Google Gemini permission was found. A linked
Terms page or "use means consent" browsewrap is not enough for App Review's current
third-party-AI rule. The desired single-flow approach is viable only if it is an
affirmative clickwrap that conspicuously states, before the first transmission:

- which information may be sent, including media, descriptions, exact location, and
  environmental/capture context;
- that the recipient is Google Gemini;
- why it is sent;
- that AI processing is necessary for core identification; and
- what Decline does.

Use one clear **Accept Terms and Continue with AI** action and a real Decline path. The
AI disclosure can be part of the Terms acceptance screen; it should not be buried only
inside the full Terms. Persist at least the user/account identifier, Terms version, AI
disclosure version, timestamp, app version, and acceptance action. Obtain renewed
acceptance for material changes. Add screenshots and an explanation to App Review notes.

### P0 — Stop Analytics Before Permission and Add Withdrawal

[`PostHogManager.swift`](../../apps/ios/Merian/Core/Analytics/PostHogManager.swift)
configures PostHog lifecycle events with a US host and disables screen replay, automatic
screen views, element interactions, surveys, and swizzling. However,
[`SupabaseManager.swift`](../../apps/ios/Merian/Core/Network/SupabaseManager.swift)
configures PostHog during singleton initialization, before onboarding or any choice.
The SDK later receives the Supabase UUID. No `optOut`/`optIn` integration or analytics
preference was found.

Before release:

- do not initialize or emit non-essential analytics before a valid choice or other
  counsel-approved lawful basis;
- add an easily accessible in-app withdrawal/objection control that actually calls the
  SDK opt-out behavior and persists the choice;
- ensure withdrawal prevents lifecycle and custom events and resets or disassociates
  identity where appropriate;
- decide whether analytics consent is bundled into the main acceptance or presented as
  an optional choice, with jurisdiction-specific counsel review;
- confirm that no PostHog feature can be remotely enabled beyond the disclosed boundary;
  and
- update the Privacy Policy and App Store privacy answers to match captured event
  properties and hosting region.

The public draft does not make non-essential analytics irrevocable or a condition of the
core app. A contract cannot remove statutory consent, objection, or withdrawal rights.

### P0 — Resolve the Under-18 Provider Conflict

The current app uses the Gemini Developer API. Google's Gemini API Additional Terms
effective March 23, 2026 say API clients may not be directed to or likely accessed by
people under 18. The current Privacy Policy says only that Naturebook is not directed to
children under 13, and no complete minor gate was found.

The draft therefore uses an interim **18+** rule. Before release, product and counsel
must either:

- enforce an 18+ declaration/gate and align the Privacy Policy, age rating, marketing,
  distribution, and community safety process; or
- move to a provider/product agreement that permits the intended younger audience and
  redesign consent and precise-location handling accordingly.

### P0 — Make Account Deletion Truly Match "De-identified"

The current account-erasure routine is
[`20260725052337_enforce_account_storage_erasure.sql`](../../services/supabase/migrations/20260725052337_enforce_account_storage_erasure.sql).
It makes scans ownerless and clears media URLs/manifests, exact-coordinate columns,
elevation, semantic location, locale/time zone, observation context, custom tags, and
free-form intervention notes. It deletes the user profile and uses a verified object
store eraser.

The routine uses a removal list rather than a positive retention allowlist. It does not
visibly clear every field that could remain personal or user-authored, including:

- `gps_lat_public` and `gps_long_public`, which may be precise for an open observation;
- `user_identification_override`;
- review/confirmation fields and timestamps that may increase re-identification risk;
  and
- future scan columns added after the erasure routine.

Before describing retained rows as de-identified:

- define and enforce a positive allowlist of scientific fields permitted in a tombstone;
- clear or coarsen every location copy so an "open" public coordinate cannot preserve
  the exact coordinate after account deletion;
- remove all user-authored free text;
- assess whether time plus location plus species is still personal information;
- add a migration-contract test that fails whenever a new scan column lacks an explicit
  retain/delete decision; and
- document recipient restrictions against re-identification.

Apple says account deletion is expected to remove shared UGC, including photos, videos,
text posts, and reviews. Current code also removes scan media and account-linked Explore
content. The public draft therefore retains only a reduced scientific record—not the
deleted user's public photos. Keeping public media permanently after account deletion
would require a different product decision, a lawful irrevocable-media license analysis,
new UX, and specific App Review review; it should not be achieved merely by changing
the Terms.

### P0 — Correct the Account-Deletion UI

[`DeleteAccountSheet.swift`](../../apps/ios/Merian/Features/Profile/Settings/Views/DeleteAccountSheet.swift)
currently says all uploaded scans and cloud backups will "perish." That is misleading if
reduced scientific records remain. It also does not warn an annual subscriber that Apple
billing continues until separately canceled.

Before release, the confirmation should clearly distinguish:

- deletion of profile, attribution, community content, private notes, exact location,
  and all scan media;
- retention and permitted use of a reduced ownerless scientific record;
- local deletion versus accepted server-side deletion work and expected completion
  timing; and
- the need to cancel an Apple auto-renewing subscription separately, with a direct
  subscription-management action.

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

The current Privacy Policy and Privacy Choices page do not yet provide a complete match
for this Terms draft. Before the Terms become effective, update them to cover:

- the main identification payload sent to Google Gemini, not only Explore audio
  classification;
- the exact production Gemini data-treatment configuration;
- PostHog event categories, identifier linkage, host region, consent or lawful basis,
  and a working withdrawal method;
- public-photo selection as species reference imagery;
- free and paid sharing/licensing of de-identified Scientific Data;
- the exact account-tombstone retention allowlist;
- retention periods and deletion completion timing;
- the 18+ eligibility rule; and
- applicable privacy rights, appeals, and regional contact/representative details.

Both pages currently describe Darwin Core Archive export as available. The authoritative
launch gate currently disables that feature. Remove or qualify those statements until
the release gate is deliberately enabled.

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
  even when the business intends the data to be de-identified;
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
| Seven-day non-renewing pass, annual auto-renewing plan, and trials | 8 |
| Operational content license and contributor warranties | 9 |
| Explore is public UGC and eligible photos can become reference imagery | 10 |
| De-identified Scientific Data can be shared or licensed free or for money | 11 |
| Exact/private location, public projections, embedded photo metadata | 12 |
| Likes, comments, replies, follows, reports, blocks, and moderation | 13 |
| Fair-use, scraping, security, model-training, clinical-use restrictions | 3 and 14 |
| Supabase, Cloudflare, Google, RevenueCat, PostHog, Resend, GBIF, Wikipedia | 15 |
| Durable biological media, 30-day non-biological purge, temporary storage | 16 |
| Individual scan deletion and content-free anti-resurrection UUID fence | 16 |
| Account deletion removes media and attribution but can retain reduced facts | 16 |
| AI/data loss disclaimers, liability cap, indemnity, termination | 18–22 |
| Apple's minimum custom-EULA concepts | 23 |

## Deliberately Not Promised

The draft does not promise:

- accurate or successful identification;
- medically, legally, or regulatorily safe output;
- truly unbounded Pro usage;
- that every queued or offline item will upload;
- permanent storage or backup;
- Darwin Core Archive export at launch;
- complete end-to-end Apple Watch functionality;
- permanent public use of a photo after unsharing or account deletion;
- payment or royalties to contributors;
- that anonymized data is outside every privacy law in every context; or
- that future Terms changes alone can authorize a materially different data purpose.

## Final Review Evidence

Before approval, provide counsel with:

- the final in-app acceptance screen and Decline behavior;
- the final Terms, Privacy Policy, Privacy Choices, Community Guidelines, and account
  deletion copy;
- App Store subscription product metadata and every paywall variant;
- final App Store privacy labels and age-rating answers;
- a data-flow diagram and current scan/tombstone field allowlist;
- Google and PostHog contracts, DPAs, regions, and subprocessor lists;
- representative PostHog event payloads;
- public/reference-photo promotion and removal tests;
- account and individual-scan deletion test evidence, including object storage;
- moderation policy and operating procedures; and
- all third-party ecological-data and media licenses used in commercial outputs.
