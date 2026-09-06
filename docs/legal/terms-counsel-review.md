# Naturebook Terms: Counsel and Release Review

Status: internal working memo

Product retention decision recorded: July 31, 2026

Draft and release controls reviewed against repository behavior: August 5, 2026

Public draft: [`apps/web/app/terms/page.tsx`](../../apps/web/app/terms/page.tsx)

This memo is not legal advice. It records product facts, drafting decisions,
unresolved business choices, and implementation gaps for qualified counsel and
the release team. The public Terms should not be treated as launch-ready until
the release blockers below are resolved.

The operator's documented product requirements and implemented Service behavior
are the source of truth. Earlier Terms and policy drafts do not define or
constrain product requirements. The mandatory product decision is: every
submitted scan contributes a scientific observation; exact coordinates and the
other scientific facts remain after account deletion; this retention has no
separate opt-in or opt-out; and no additional retention table is introduced.
Public documents must accurately disclose that behavior without purporting to
remove statutory rights that cannot be waived by contract.

## Drafting Position

The Terms use three distinct permissions:

1. **Operational license for private and public user content.** Naturebook may
   process content only as reasonably needed to provide, secure, troubleshoot,
   and support the Service and the user's selected features.
2. **Public Contribution license.** Media deliberately published to Explore may
   appear on public surfaces and may be selected as species reference imagery
   while it remains shared and eligible. The draft does not turn every private
   scan into public reference media and does not grant Naturebook a standalone
   stock-media resale right.
3. **Mandatory Scientific Data contribution and license.** Every submitted scan
   creates a scientific observation containing exact coordinates when present,
   elevation, time, taxonomy, identification, environmental, quality, and
   provenance facts. The ownerless scientific record survives account deletion
   as a required condition of the Service. Scientific Data may be aggregated,
   shared, published, licensed, or sold under the Terms' privacy, geoprivacy,
   sensitive-species, access, and legal restrictions, and Naturebook may retain
   resulting revenue without paying contributors.

The draft intentionally does **not** grant Google or another third party
permission to train a general-purpose AI model on user submissions. A materially
different future AI use or provider should receive a new disclosure and
permission where required.

## Release Blockers

### P0 — Identify the Contracting Party

The repository contains the Naturebook brand and `support@naturebook.earth`, but
no operator legal name, physical address, or telephone number. Counsel must add:

- full legal entity or individual operator name;
- registered or business address;
- complaint and claims telephone number;
- any required trader, company-registration, tax, or representative details; and
- the correct copyright owner and App Store seller/developer identity.

Apple's minimum custom-EULA terms require the developer's name, address,
telephone number, and email address. Until those facts exist, do not submit this
draft as a custom EULA in App Store Connect.

### Implemented UI and Evidence Design — Release-Blocked

Current onboarding has welcome, camera, location, and ready steps:

- [`OnboardingView.swift`](../../apps/ios/Merian/Features/Onboarding/Shell/Views/OnboardingView.swift)
- [`OnboardingStep.swift`](../../apps/ios/Merian/Features/Onboarding/Steps/Models/OnboardingStep.swift)
- [`ReadyStepView.swift`](../../apps/ios/Merian/Features/Onboarding/Steps/Ready/ReadyStepView.swift)

The product-owner-approved internal-testing disclosure is: “Naturebook sends
observation data to Google Gemini for AI-powered identification.” The **One last
step** screen presents three initially-off switches in one continuous stack
without section titles or a divider. The switch-and-label rows share a common
leading edge, and the three labels omit terminal periods. The 18+
self-attestation and agreement to the inline-linked Terms plus permission for
that data sharing are required; usage and diagnostics is optional and changeable
in Settings. Only the required pair enables **Start scanning**, and
accessibility hints retain the required/optional distinction. The
punctuation-only label revision does not increment the substantive policy
versions; new immutable evidence stores the displayed no-period copy while prior
current-version evidence remains valid. The UI does not name PostHog; PostHog
remains the documented analytics provider in the Terms and Privacy Policy. There
is no separate Decline action because the app has no non-AI operating mode;
withholding required permission keeps scanning unavailable and prevents
submission. The onboarding disclosure and linked legal documents collectively
state, before a new user can submit a scan:

- which information may be sent, including media, descriptions, location, and
  environmental/capture context;
- that the recipient is Google Gemini;
- why it is sent;
- that AI processing is necessary for core identification; and
- what withholding permission does.

Migrations `20260804020351_record_legal_consent_receipts.sql` and
`20260804033307_add_adult_and_analytics_consent.sql`, plus forward migration
`20260806024844_enforce_causal_consent_streams.sql`, forward migration
`20260806144105_authorize_consent_from_provider_stream_heads.sql`, and
`Core/Security/Consent/Models/ConsentPolicy.swift`,
`Core/Security/Consent/Policies/ConsentAuthorityPolicy.swift`,
`Core/Security/Consent/Policies/ConsentSynchronizationMergePolicy.swift`,
`Core/Security/Consent/Coordinators/ConsentRealtimeCoordinator.swift`,
`Core/Security/Consent/Coordinators/ConsentSynchronizationCoordinator.swift`,
`Core/Security/Consent/Coordinators/RequiredConsentRestorationCoordinator.swift`,
`Core/Security/Consent/Repositories/ConsentLedgerRepository.swift`,
`Core/Security/Consent/Services/{ConsentRemoteModels,ConsentRemoteService,ConsentRemoteService+Live,ConsentRealtimeCoordinator+Live}.swift`,
and `Core/Security/ConsentManager.swift` establish the intended evidence
boundary. Before the workspace opens, the app appends local adult-confirmation,
Terms, and Gemini actions with separate policy versions, exact displayed copy,
client UUID, device action time, platform, app version, and build. The focused
remote service maps and synchronizes those records to immutable, owner-only
Supabase tables with server-controlled timestamps and no client update/delete
path; the synchronization coordinator retains the account, SDK-session,
generation, and cancellation fences, the restoration coordinator owns the
bounded restoration retry state plus UUID-keyed cancellation drain and rejects
canceled retry callers after manual attempt-number reuse, and the manager
retains account authority and transition timing. The repository owns verified
ledger/journal persistence, recovery, and rebinding. Existing installs with the
old onboarding flag but no current local evidence remain on a neutral
restoration surface until the initial session establishes no active account or
an identity-fenced authoritative merge persists. An authenticated account enters
this disclosure only when that successful merge establishes absence. A cached
session with an expired access token remains a known account during refresh and
cannot temporarily mount the disclosure. Fetch, decoding, pending consent
upload, and verified-ledger-write failures retain the neutral surface with
bounded automatic and explicit retry; they do not ask the user to consent again
or constitute evidence that consent is absent.

Gemini and optional PostHog actions also carry the provider event observed when
the action was created. Direct client inserts are forbidden. The authenticated
database RPC accepts a grant only if its parent remains current, but always
accepts a revocation and rebases it to the locked current head. The returned
server revision—not device time or upload receipt time—orders permission. A
delayed offline grant therefore cannot supersede another device's withdrawal,
and a delayed withdrawal cannot leave a newer grant enabled. Authorization first
resolves the greatest provider revision across every disclosure version. Any
head revocation denies before rollout compatibility is consulted; only a head
grant may enter the current or temporarily allowlisted disclosure checks.

Every iOS inference entry point verifies that the current rows reached the
active account before constructing its provider request. Both service-only
`reserve_ai_quota` overloads repeat the check before provider admission, so a
modified or stale client fails closed. Settings intentionally provides no Gemini
processing opt-out because the app has no non-AI identification mode.
Withholding permission keeps the scanner unavailable, while historical or remote
revocation events still return the app to the disclosure gate.

All tracked client findings are closed in source. The implementation now rebinds
the complete local ghost ledger before verified handoff removal,
generation-fences stale session work, activates and flushes a restored account
before refetch, uses `ConsentRealtimeCoordinator` to independently own and
repair the account-scoped Realtime subscription through an isolated live
adapter, coalesces explicit/listener/deinitialization channel teardown while
initiating deinitialization cleanup independently of listener cancellation,
suppresses analytics before OAuth session replacement, and enters an explicit
remote-authority wait state before cached analytics consent can reach PostHog.
Only a successfully persisted, identity-fenced current-account grant enables
analytics; remote absence, revocation, fetch failure, or write failure remains
off. Local compiled/runtime evidence is recorded, but the exact candidate SHA
still needs the hosted unit, UI-smoke, Release-archive, and disposable-database
gates in the
[production consent readiness record](./production-consent-readiness-2026-08-03.md).

Required-consent root routing is stricter than the analytics-only gate above.
Remote absence may present the Ready consent screen only after a successful
durable merge; synchronization failure remains unresolved on the neutral
restoration surface. The surface offers immediate retry, performs bounded 5-,
10-, and 20-second attempts, and rejects stale retry work after an account or
synchronization generation changes.

Internal test builds may continue without the deferred operator approvals.
Public release still requires the additive migration, exact-SHA replacement
TestFlight build, old-build expiration, owner-only strict cutover, deployed
contract verification, renewed acceptance whenever a required material policy
version changes, and final screenshots and an explanation in App Review notes.
Qualified counsel must approve the final combined acceptance and disclosure
copy; this engineering record is not a legal conclusion that bundled Terms and
provider permission is valid in every release region.

### Implemented Analytics Design — Release-Blocked

The implemented design configures PostHog lifecycle events with a US host only
after a separate optional grant. The user-facing switch says “Share usage and
diagnostics to help improve Naturebook”; it does not name PostHog or display an
“Optional” suffix. Replay, automatic screen views, element interactions,
surveys, swizzling, and push capture are explicitly disabled. `ConsentManager`
stores immutable account-wide grants and revocations; absence means off.
Settings exposes **Analytics & diagnostics** without changing core
functionality. Edge telemetry checks the same latest account event before every
PostHog request and does not send auth email or name.

The withdrawal and account-lifecycle findings are closed in source.
[`PostHogManager.swift`](../../apps/ios/Merian/Core/Analytics/PostHogManager.swift)
installs a closed-by-default, host-scoped transport gate and closes it before
preserving `reset → optOut → close`, so PostHog 3.69.0's feature-flag reload is
cancelled locally. Durable ghost handoffs suppress analytics through rebind,
synchronization, authoritative refetch, and verified queue removal. Account
restoration, Realtime retry/repair, and OAuth replacement also fail closed.
Restored sessions cannot reuse a cached local grant while the account-wide state
is unresolved; only the verified final merge may reopen capture. Production
still requires exact-candidate evidence of no PostHog setup, identification,
capture, or network activity before grant and after withdrawal or account
change.

Before release, counsel must still review the displayed choice and updated
Privacy Policy. The signed archive's Xcode aggregate privacy report and App
Store privacy answers must match the actual event properties, identifier
linkage, US host, app manifest, and bundled SDK manifests. See the
[iOS App Privacy Manifest Contract](../development-guides/16-ios-privacy-manifest.md).

The public draft does not make non-essential analytics irrevocable or a
condition of the core app. A contract cannot remove statutory consent,
objection, or withdrawal rights.

### P0 — Resolve the Under-18 Provider Conflict

The current app uses the Gemini Developer API. Google's Gemini API Additional
Terms effective March 23, 2026 say API clients may not be directed to or likely
accessed by people under 18. The Terms and Privacy Policy use an **18+** rule.
The replacement iOS build now requires an initially-off self-attestation switch
on the final disclosure screen and stores exact, versioned evidence locally and
account-wide. It does not collect a birth date or exact age. The strict server
cutover requires current adult, Terms, and Gemini evidence before every provider
reservation.

The tracked implementation findings are closed in source and local compiled
tests pass. The replacement build is not eligible for public release until the
clean hosted exact-SHA gate passes; internal testing may continue under the
readiness record.

Public production remains blocked until App Store Connect carries the reviewed
18+ rating override and marketing/distribution are confirmed not directed toward
minors. Product and counsel must archive that evidence with the release record.

### P0 — Counsel Review of Mandatory Scientific Retention

The fixed product and engineering boundary is canonical in
[`17-scientific-observation-retention.md`](../backend-and-data/17-scientific-observation-retention.md).
Migration
[`20260731154139_retain_scientific_coordinates_after_account_deletion.sql`](../../services/supabase/migrations/20260731154139_retain_scientific_coordinates_after_account_deletion.sql)
implements the product decision without a new table. It makes scans ownerless
and clears media URLs/manifests, semantic and public location labels, device
locale/time-zone context, observation context, custom tags, and free-form
intervention notes. It retains exact and projected coordinates, elevation,
observation time, taxonomy, identification, review, environmental, quality, and
provenance fields. The privileged routine deletes the public profile and the
durable workflow verifies object-store erasure before deleting Auth. Tombstones
remain excluded from personal and broad anonymous scan access.

The scan-generation trigger compares complete `OLD` and `NEW` rows after
subtracting only the account fields that deletion is allowed to change. This
fails closed for every current or future scientific field when account deletion
collides with an individual scan-deletion fence. The account routine
deliberately uses a clearing list because every other scan field is retained
Scientific Data; new columns still require an explicit privacy and retention
review.

The retained observation must not be described as necessarily anonymous or
de-identified. Exact location plus time and species may remain personal
information. Before release, qualified counsel should review the applicable
legal bases, notice at collection, purpose and retention disclosures, regional
deletion exceptions and other non-waivable rights, sensitive-location
safeguards, recipient restrictions, and App Review explanation. This is a
legal-compliance review of a fixed product requirement, not a consent, opt-in,
or opt-out product decision.

The product still deletes account-linked Explore content and all submitted
photos, videos, and audio. Permanent retention of public media is not part of
this decision.

### P0 — Correct the Account-Deletion UI

[`DeleteAccountSheet.swift`](../../apps/ios/Merian/Features/Profile/Settings/Views/DeleteAccountSheet.swift)
now distinguishes deletion of the profile, attribution, community content, scan
media, private notes, life list, and collections from mandatory retention of
exact coordinates, time, taxonomy, and the other ownerless scientific facts. It
also warns that account deletion does not cancel Apple billing. Keep this
language synchronized with the Terms, Privacy Policy, and backend migration
contract. A direct subscription-management action would further improve the flow
but is not implemented in this patch.

Sign in with Apple revocation is now implemented in source. The current iOS
callback requires Apple's authorization code, an authenticated Edge route
exchanges it and stores the refresh token in Vault, and the durable deletion
worker requires Apple's successful revocation plus token destruction before
Supabase Auth removal. Supporting iOS binaries persist Apple's manual-removal
instructions for accounts that predate token capture. Older binaries ignore the
new response field, and this repository currently has neither an enforced
minimum-build gate nor an independent server-delivered fallback. Public launch
therefore remains blocked until one of those controls is implemented and
verified; distributing the new build is not sufficient evidence. The app also
revalidates Apple's credential-revoked notification against the same active
provider subject before clearing the local session. Counsel and launch review
should verify the final customer wording, the treatment of the manual
acknowledgement and update path, and retained exact-SHA deployment/staging
evidence against
[Apple TN3194](https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple).
The engineering and rollout evidence contract is
[`20-sign-in-with-apple-account-deletion.md`](../backend-and-data/20-sign-in-with-apple-account-deletion.md).

### P0 — Use Gemini's Paid Production Terms and DPA

Google's current Gemini Developer API terms distinguish unpaid and paid
Services. Unpaid-Service submissions and outputs may be used to improve Google
products and may be reviewed by humans. Paid-Service prompts and responses are
not used by Google to improve its products, though limited logging may occur for
abuse prevention and legal requirements. EEA, Switzerland, and UK API clients
may use only Paid Services.

Before release:

- confirm every production key belongs to a Cloud project with active billing;
- accept and archive the applicable Data Processing Addendum;
- verify regions, subprocessors, retention, transfer terms, and abuse-logging
  behavior;
- prevent fallback to an unpaid project or key;
- ensure test and staging data contain no real user personal information if
  unpaid;
- align the in-app disclosure and Privacy Policy with the actual configuration;
  and
- review whether Google Grounding, caching, files, tuning, or another feature
  changes retention or user-facing attribution obligations.

### P0 — Update the Privacy Documents at the Same Time

The Privacy Policy and Privacy Choices page now disclose the mandatory ownerless
scientific record, exact-coordinate retention, absence of a separate retention
choice, and launch-disabled DwC-A export. Before the Terms become effective,
counsel must still review the complete privacy package for:

- the main identification payload sent to Google Gemini, not only Explore audio
  classification;
- the exact production Gemini data-treatment configuration;
- PostHog event categories, identifier linkage, host region, consent or lawful
  basis, and a working withdrawal method;
- the app-owned privacy manifest, every bundled SDK manifest, the signed
  archive's aggregate Xcode privacy report, and matching App Store privacy and
  ATT answers;
- the public no-cross-company-tracking and no-targeted-advertising statement
  against every production SDK, endpoint, and data-sharing arrangement;
- public-photo selection as species reference imagery;
- automatic profile-visible Backyard Safari enrollment, immediate author-profile
  discoverability at zero progress, and the adequacy of Stop/Reset as the only
  unfinished-status controls;
- free and paid sharing/licensing of Scientific Data that may remain personal;
- the exact account-tombstone retention and clearing boundary;
- retention periods and deletion completion timing;
- the 18+ eligibility rule; and
- applicable privacy rights, appeals, and regional contact/representative
  details.

Both pages now qualify Darwin Core Archive export as launch-disabled. Keep that
language until the authoritative release gate is deliberately enabled.

## Counsel and Business Decisions

Counsel and the operator should decide and document:

- governing law, venue, and whether to use arbitration or a class-action waiver;
- release countries and region-specific consumer, privacy, and UGC obligations;
- whether the app uses Apple's Standard EULA plus separate Service Terms or
  submits these Terms as a custom EULA;
- whether the US $100 / prior-12-month-fees liability cap is suitable and
  enforceable;
- indemnity scope for consumers;
- formal copyright/DMCA process and agent registration, if applicable;
- a repeat-infringer policy;
- moderation staffing, escalation, appeals, evidence retention, and regulator
  response;
- dangerous-organism, sensitive-species, trespass, and field-safety warnings;
- insurance appropriate to AI identification, UGC, privacy, and outdoor-use
  risks;
- research ethics and recipient terms for Scientific Data;
- whether any commercial data arrangement is a "sale" or "sharing" under a
  privacy law, particularly when retained Scientific Data includes exact
  location and time;
- tax, attribution, database-right, and third-party-license constraints for
  commercial datasets;
- rules for government, law-enforcement, and emergency requests;
- accessibility, localization, and electronic-notice requirements; and
- a retention schedule for moderation evidence, fraud prevention, support,
  analytics, subscription records, backups, and legal holds.

## Product Facts Covered by the Draft

| Product fact                                                                                                                              | Terms section |
| ----------------------------------------------------------------------------------------------------------------------------------------- | ------------- |
| Anonymous accounts may be created automatically and later linked                                                                          | 4             |
| Gemini is central to identification and receives multimodal and context inputs                                                            | 5             |
| AI results are probabilistic and not safety or professional advice                                                                        | 6             |
| PostHog product analytics and currently disabled capture modes                                                                            | 7             |
| Three included Pro scans with no calendar expiry, a separate daily Flash scan, seven-day non-renewing pass, and annual auto-renewing plan | 8             |
| Operational content license and contributor warranties                                                                                    | 9             |
| Explore is public UGC and eligible photos can become reference imagery                                                                    | 10            |
| Every submitted scan contributes mandatory Scientific Data that can be used or licensed                                                   | 11            |
| Exact/private location, public projections, embedded photo metadata                                                                       | 12            |
| Likes, comments, replies, follows, reports, blocks, and moderation                                                                        | 13            |
| Fair-use, scraping, security, model-training, clinical-use restrictions                                                                   | 3 and 14      |
| Supabase, Cloudflare, Google, RevenueCat, PostHog, Resend, GBIF, Wikipedia                                                                | 15            |
| Durable biological media, 30-day non-biological purge, temporary storage                                                                  | 16            |
| Individual scan deletion and content-free anti-resurrection UUID fence                                                                    | 16            |
| Account deletion removes account content but retains ownerless exact scientific facts                                                     | 16            |
| AI/data loss disclaimers, liability cap, indemnity, termination                                                                           | 18–22         |
| Apple's minimum custom-EULA concepts                                                                                                      | 23            |

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
- that future Terms changes alone can authorize a materially different data
  purpose.

## Final Review Evidence

Before approval, provide counsel with:

- the closed
  [production consent readiness record](./production-consent-readiness-2026-08-03.md),
  including clean compiled iOS and deployed enforcement evidence;
- the final in-app acceptance screen and withholding/withdrawal behavior;
- the final Terms, Privacy Policy, Privacy Choices, Community Guidelines, and
  account deletion copy;
- App Store subscription product metadata and every paywall variant;
- final App Store privacy labels and age-rating answers;
- the signed Organizer archive's aggregate Xcode privacy report and the
  app-level manifest validation evidence for the same source SHA;
- a data-flow diagram and current scan/tombstone retention and clearing
  boundary;
- Google and PostHog contracts, DPAs, regions, and subprocessor lists;
- representative PostHog event payloads;
- public/reference-photo promotion and removal tests;
- account and individual-scan deletion test evidence, including object storage;
- moderation policy and operating procedures; and
- all third-party ecological-data and media licenses used in commercial outputs.
