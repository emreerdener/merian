# Naturebook Rebrand Rollout Runbook

This runbook completes the public rename from Merian to Naturebook without
changing the app's technical identity. The permanent decision and allowed
compatibility boundaries are defined in
`docs/system-architecture/08-public-brand-compatibility.md`.

The release must not proceed until domains, AASA, email, backend, and App Store
metadata are ready. These systems are ordered deliberately so a renamed binary
never generates links or support addresses that are not operational.

## Release Message

Use this exact nonblocking message in the in-app changelog and App Store release
notes:

> Merian is now Naturebook. The name is new; your scans, account, subscriptions, and Explore content stay exactly where they are.

Do not show a forced rename modal.

## Repository Artifacts

- Public brand contract:
  `apps/ios/Shared/Branding/PublicBrand.swift`
- Xcode source of truth: `project.yml`
- Main plist and associated domains:
  `apps/ios/Merian/Configuration/Info.plist` and
  `apps/ios/Merian/Configuration/Merian.entitlements`
- Deep-link compatibility:
  `apps/ios/messages/ScanSharing/Shared/MessageScanShareCache.swift`
- Web host routing: `apps/web/proxy.ts` and
  `apps/web/lib/canonicalHost.ts`
- Web environment template: `apps/web/.env.example`
- Forward migration:
  `services/supabase/migrations/20260716012046_rebrand_public_surfaces_to_naturebook.sql`
- App Store notes: `apps/ios/AppStore/ReleaseNotes/1.0.3.md`
- In-app notes: `apps/ios/Merian/Resources/Changelog/changelog.json`

## Current Rollout Status

Live checks on 2026-07-15 found these launch blockers:

- `naturebook.earth` redirected to `www.naturebook.earth` instead of remaining
  the canonical origin.
- Naturebook and Merian AASA endpoints redirected instead of returning HTTP 200.
- `naturebook.app` was still served by GoDaddy and did not redirect to the
  canonical origin.
- This workspace had no Vercel CLI or linked Vercel project, so deployment and
  domain reassignment were not performed here.

Replace this section with a dated completion record when the external rollout
is finished.

## Phase 1: Domain and Web Prerequisites

### Vercel project

1. Deploy `apps/web` to the production Vercel project.
2. Set the project root directory to `apps/web`.
3. Configure:

   ```text
   NEXT_PUBLIC_SITE_URL=https://naturebook.earth
   NEXT_PUBLIC_SUPPORT_EMAIL=support@naturebook.earth
   ```

4. Assign `naturebook.earth` as the canonical production domain.
5. Assign every alias to this same project. Do not configure an upstream domain
   redirect that bypasses the application:

   ```text
   naturebook.app
   www.naturebook.app
   www.naturebook.earth
   merian.earth
   www.merian.earth
   ```

6. Confirm TLS is valid for every host.

The application issues the path- and query-preserving 308 responses. If Vercel
redirects `naturebook.earth` to `www` before the application, make the apex the
project's primary domain and remove that platform redirect. If `merian.earth`
redirects before the application, its AASA exception cannot work.

### DNS and registrar

Point both Naturebook domains at the Vercel project using the DNS records Vercel
provides. Remove the GoDaddy parked site and forwarding configuration from
`naturebook.app`. DNS may remain at the registrar; only web serving/forwarding
must move to the deployed application.

### Web verification

Run from a network outside the local development machine:

```bash
curl -sS -I 'https://naturebook.earth/explore/post/example?ref=qa'
curl -sS -I 'https://www.naturebook.earth/explore/post/example?ref=qa'
curl -sS -I 'https://naturebook.app/explore/post/example?ref=qa'
curl -sS -I 'https://www.naturebook.app/explore/post/example?ref=qa'
curl -sS -I 'https://merian.earth/explore/post/example?ref=qa'
curl -sS -I 'https://www.merian.earth/explore/post/example?ref=qa'
curl -sS -I 'https://naturebook.earth/species/00000000-0000-0000-0000-000000000000?ref=qa'
curl -sS -I 'https://merian.earth/species/00000000-0000-0000-0000-000000000000?ref=qa'
curl -sS -I 'https://merian.earth/species/{real-species-uuid}/{current-slug}?ref=qa'
```

Expected results:

- The canonical Naturebook URL does not redirect because of its host.
- Each alias returns 308 with the exact path and query on
  `https://naturebook.earth`.
- No alias redirects to a `www` canonical URL.
- A real UUID-only or stale-slug request on the canonical host returns a
  permanent redirect to its current UUID-plus-slug species path.

## Phase 2: AASA and Universal Links

Both endpoints must be served directly on both associated domains:

```bash
for host in naturebook.earth merian.earth; do
  curl -sS -D - "https://${host}/apple-app-site-association"
  curl -sS -D - "https://${host}/.well-known/apple-app-site-association"
done
```

For all four responses verify:

- Status is HTTP 200, not 301, 302, 307, or 308.
- `Content-Type` is JSON-compatible.
- The payload contains `TA8S64ST9W.app.merian.Merian`.
- The path contract is exactly `["/explore/post/*", "/species/*"]`.

Do not add `applinks:naturebook.app`. It is redirect-only.

`/species/*` is intentionally enabled immediately. Older installed builds may
claim that Universal Link without a native species router; the rollout accepts
this compatibility window. Deploy the browser fallback first and verify the
current signed app before enabling user-facing species sharing.

After Xcode creates the production archive, verify the associated-domain
entitlement in the archived app rather than relying only on the source plist.
In Organizer, reveal the selected archive in Finder and inspect its app:

```bash
RELEASE_ARCHIVE=/path/to/Naturebook.xcarchive
codesign -d --entitlements - \
  "$RELEASE_ARCHIVE/Products/Applications/Merian.app"
```

Record only the reviewed entitlement values in release evidence. Do not
publish the provisioning profile or unrelated signed metadata.

## Phase 3: Mail and Support

1. Provision `support@naturebook.earth` and verify inbound delivery.
2. Provision or authorize `exports@naturebook.earth` in Resend.
3. Publish the SPF, DKIM, and DMARC records required by the mail provider.
4. Set the Supabase Edge secret, preserving the display name as part of the
   quoted value:

   ```bash
   supabase --workdir services secrets set \
     'RESEND_FROM_EMAIL=Naturebook Data Exports <exports@naturebook.earth>'
   ```

5. Send a real export to a non-team mailbox and verify sender name, subject,
   download link, reply behavior, and spam placement.
6. Verify support mail links on `/support`, `/privacy`, `/terms`, and public
   Explore reporting flows.

Do not release while production export email still falls back to
`onboarding@resend.dev`.

## Phase 4: Database and Edge Functions

The rebrand migration is forward-only. Do not edit historical migrations.

1. Review the local/remote migration list and ordering.
2. Run repository migration validation:

   ```bash
   make validate-supabase-migrations
   ```

3. Apply
   `20260716012046_rebrand_public_surfaces_to_naturebook.sql` through the normal
   GitHub Actions deployment path.
4. Deploy affected functions through the dependency-aware planner. Shared
   prompt or moderation changes may select additional dependents; do not guess
   a smaller manual set.
5. Verify:

   ```sql
   SELECT source, license, attribution
   FROM public.species_reference_images
   WHERE source = 'merian'
   ORDER BY updated_at DESC
   LIMIT 20;

   SELECT public.is_reserved_public_username('merian'),
          public.is_reserved_public_username('naturebook'),
          public.is_reserved_public_username('naturebookearth');
   ```

6. Run the reference-image refresh as a dry run through its existing technical
   function/worker name. New generated attribution must say Naturebook.
7. Request a Darwin Core export and inspect `recordedBy`, email branding, and
   pseudonymous identifiers.

Never roll back the migration by restoring old public labels. If a production
problem appears, ship a new forward migration or function fix.

## Phase 5: Apple Developer, App Store Connect, and RevenueCat

Update the existing listing; do not create a new app.

### Apple Developer identifier

In Certificates, Identifiers & Profiles, ensure there is exactly one explicit
App ID for `app.merian.Merian` with description
`Naturebook iOS (Merian)`. If it does not exist, register it with those values;
if it already exists, edit only its description. Do not register a separate
Naturebook bundle identifier. This description is an Apple Developer identifier
field, not App Store Connect metadata.

### App Store Connect app information

| Field | Required value |
| --- | --- |
| Public name | Naturebook |
| Bundle ID | `app.merian.Merian` unchanged |
| Primary category | Reference |
| Secondary category | Education |
| Marketing URL | `https://naturebook.earth` |
| Support URL | `https://naturebook.earth/support` |
| Privacy URL | `https://naturebook.earth/privacy` |

Update descriptions, keywords, promotional text, screenshots, captions, and
review notes wherever the old product name appears. Preserve the legal seller
name when App Store Connect requires the account's legal identity.

### Subscriptions and IAP

- Rename customer-facing localizations to Naturebook Pro.
- Do not change RevenueCat entitlement IDs, offering IDs, package mapping, or
  App Store product IDs.
- Confirm existing subscribers remain entitled in an update build.

### Release notes

Use `apps/ios/AppStore/ReleaseNotes/1.0.3.md` as the reviewed source. Confirm
the exact transition sentence appears and does not imply a data migration or
new account.

## Phase 6: iOS Release Preparation

1. Regenerate and validate the project:

   ```bash
   make xcodegen
   make validate-ios-project
   make validate-ios-versioning
   ```

2. Wait for **iOS Build and Test** to pass on the exact intended SHA. Confirm
   both conditional macOS jobs ran; a scope-only success is not release
   evidence.
3. In Xcode use **Product → Archive**, then Organizer **Distribute App →
   TestFlight & App Store → Upload** as described in the
   [operator runbook](./14-ios-release-versioning.md). Keep automatic signing
   and **Manage version and build number** enabled.
4. Record the Organizer archive date, source SHA/fingerprint, and the final
   version/build reported by App Store Connect.
5. Inspect the compiled plists in the Organizer archive:

   - iOS display name: Naturebook
   - Watch display name: Naturebook
   - Messages display name: Naturebook
   - Widget display name: Explore
   - Main category: `public.app-category.reference`
   - URL schemes: `naturebook` and `merian`
   - Main bundle ID: `app.merian.Merian`

6. After upload, confirm App Store Connect shows the Organizer-managed
   version/build. Retain the Xcode distribution log with the release record;
   never record signing credentials or provisioning profiles.
7. Complete physical-device update-continuity, purchase/restore, push, link,
   and scan-flow QA on that build. Promote the same processed binary through
   internal TestFlight, external TestFlight, and App Review; never rebuild for
   a stage change.

## Phase 7: Upgrade and Link QA

Test an actual update, not only a clean install.

### Update continuity

Install the last Merian build, create representative state, then update to the
Naturebook build. Verify:

- The app updates in place rather than installing beside the old app.
- The signed-in or Ghost account remains the same.
- Local and synced scans remain available.
- SwiftData migrations and startup recovery remain healthy.
- Keychain state, preferences, themes, notification choices, and quota state
  remain intact.
- RevenueCat entitlement and active subscription remain intact.
- Widget and Messages App Group content remain available.
- Existing Explore posts, comments, follows, and notifications remain attached
  to the same account.

### Link matrix

On a physical device and a simulator, test:

```text
https://naturebook.earth/explore/post/{real-public-id}
https://merian.earth/explore/post/{real-public-id}
naturebook://explore/post/{real-public-id}
merian://explore/post/{real-public-id}
https://naturebook.earth/species/{real-species-uuid}
https://naturebook.earth/species/{real-species-uuid}/{current-slug}
https://naturebook.earth/species/{real-species-uuid}/{stale-slug}
https://merian.earth/species/{real-species-uuid}
https://merian.earth/species/{real-species-uuid}/{current-slug}
naturebook://species/{real-species-uuid}
merian://species/{real-species-uuid}
```

Also test canonical `naturebook://scan/{id}` and `naturebook://scans`, plus their
legacy `merian://` equivalents where applicable.

For species links, verify the UUID-only and stale-slug browser forms permanently
redirect to `/species/{real-species-uuid}/{current-slug}`. With the current app
installed, all accepted HTTPS forms must route directly by UUID without relying
on the slug. The legacy host must preserve both UUID and slug while redirecting
to `naturebook.earth`.

### Generation audit

Create new content through every outward path and verify it emits Naturebook
only:

- Explore sharing
- Species Dictionary sharing
- Messages extension cards
- Referrals
- Support and public reporting email
- Darwin Core export mail
- Web canonical and Open Graph metadata
- App Intents and Siri results
- Widget links
- Notifications

## Phase 8: Verification Commands

Repository checks:

```bash
make xcodegen
xcodebuild -scheme Merian -project Merian.xcodeproj \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

cd apps/web
npm test
npm run typecheck
npm run build

cd ../..
make validate-supabase-migrations
git diff --check
```

Run the focused iOS brand, deep-link, sharing, changelog, import, and extension
tests on an available simulator. Run the changed Edge Function checks and tests
under `services/supabase/functions/deno.json`.

## Repository Branding Audit

Search public-risk patterns:

```bash
rg -n 'Merian Pro|Merian AI|Explore Merian|Open in Merian|WHY MERIAN|New to Merian' \
  apps services README.md CHANGELOG.md

rg -n 'https://merian\.earth|support@merian\.earth|exports@merian\.earth' \
  apps services README.md CHANGELOG.md

rg -n 'Merian needs|Merian uses|Merian couldn.t' apps/ios apps/watch
```

Every hit must be classified against the allowed list in the public brand
contract. Legacy URL tests and immutable historical migrations are expected.
Visible copy, generated links, current metadata, current attribution, and
current email are not.

## Rollback and Incident Rules

- Do not change the bundle ID or create a second listing as a rollback.
- Do not remove `merian.earth`, `merian://`, the old associated domain, or old
  reserved username.
- Do not rename persistence, RevenueCat, analytics, backend, or App Group
  identifiers during an incident.
- Do not reverse an applied migration. Fix forward.
- If the new domain fails after release, repair routing/AASA immediately while
  retaining both link families. Do not make new shares emit the legacy domain.
- If public copy is wrong, update the affected surface and release notes; do not
  widen the technical rename scope.

## Completion Record

The release owner should record:

- Production web deployment URL and commit
- DNS/TLS verification time
- Four AASA response checks
- Mailbox and Resend verification time
- Supabase migration/deployment run
- App Store metadata reviewer
- TestFlight upgrade device/build pair
- Four-form link matrix result
- Final repository branding audit result

The rebrand is complete only when all external blockers are cleared and a real
Merian-to-Naturebook update passes continuity testing.
