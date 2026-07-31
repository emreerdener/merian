# Public Web Share Pages

Naturebook's public web surface lives in `apps/web/`. It is a Next.js + Mantine
app for public, shareable Explore posts and Species Dictionary references on
`naturebook.earth`.

The shipped share routes are:

```text
https://naturebook.earth/explore/post/{postId}
https://naturebook.earth/species/{speciesId}/{slug}
```

These are the long-term share targets for Explore posts and dictionary species.
They render useful pages for recipients without the app, provide Open Graph
metadata for Messages/social previews, and act as Universal Links that open the
matching native detail when Naturebook is installed.

The permanent public-name and stable-identifier rules live in
[`08-public-brand-compatibility.md`](../system-architecture/08-public-brand-compatibility.md).
Use
[`15-naturebook-rebrand-rollout.md`](../development-guides/15-naturebook-rebrand-rollout.md)
for DNS, Vercel, AASA, mail, App Store, rollout, and rollback operations.

## Product Contract

- Canonical domain: `naturebook.earth`.
- Redirect aliases: `naturebook.app`, both Naturebook `www` hosts, and the
  legacy `merian.earth` hosts. Redirects preserve the path and query.
- App location: `apps/web/`.
- Frameworks: Next.js App Router, React, Mantine, and Supabase JS.
- Share routes: `/explore/post/[postId]` and `/species/[speciesId]/[slug]`, with
  `/species/[speciesId]` retained as a permanent compatibility redirect.
- Policy/support routes: `/privacy`, `/privacy-choices`, `/terms`,
  `/guidelines`, `/support`, and `/legal`.
- Native fallback buttons: `naturebook://explore/post/{postId}` and
  `naturebook://species/{speciesId}` via each page's "Open in Naturebook"
  action.
- Web page audience: anonymous recipients of shared Explore posts or species
  references.
- Metadata audience: iMessage, social crawlers, link unfurlers, and search
  previews.

The public web page is not the full Explore product yet. It is a rich read-only
detail surface for one post, with enough context to understand what was shared
and a clean path back into the app. Anonymous web visitors can view the post,
but engagement counts are not rendered and they cannot like, comment, reply,
follow, or edit on the web surface. A centered support-email report action sits
below the Taxonomy card and contains the immutable post id; this is not an
authenticated in-product report write.

## Data Flow

1. The iOS app shares `https://naturebook.earth/explore/post/{postId}` in the
   message text.
2. Next.js server-rendering handles `/explore/post/[postId]`.
3. `apps/web/lib/explore.ts` imports `server-only` and creates the validated
   server client through `apps/web/lib/supabaseAdmin.ts`. The credential never
   crosses into a client component or rendered response.
4. The page calls the dedicated `get_public_web_explore_post_page` RPC with:

   ```ts
   {
     p_target_post_id: postId
   }
   ```

   PostgreSQL fixes the underlying viewer to `NULL`; no request or environment
   value can impersonate another user. The routine is revoked from
   `PUBLIC`/`anon`/`authenticated` and calls `internal.require_service_role()`.
5. That one statement returns `post_payload` plus independently
   canonical-gated `detail_payload`, hydrating public field notes, hashtags,
   references, overview, conservation status, taxonomy labels, and alternate
   names without a check-then-fetch race.
6. The server maps those payloads into the `ExplorePost` page model. The card
   includes the canonical ordered `media_items` snapshot; the hero image
   remains the static poster and metadata fallback.
   Engagement counts are always zero and viewer/ownership flags are always false
   on this anonymous surface.
7. `explorePosterUrl(...)` prefers the canonical visual hero and otherwise uses
   the first persisted standalone-audio spectrogram thumbnail.
8. `generateMetadata(...)` emits canonical, Open Graph, and Twitter metadata
   using the post title and resolved poster.
9. The page renders the public post with default Mantine components and props,
   without route-specific CSS classes or custom page chrome.

Visual media on the detail route is rendered in canonical `order_index` order.
Confirmed-missing items are absent from that ordered snapshot. If every primary
item is confirmed missing, canonical visibility excludes the post. The atomic
page RPC and direct detail RPC both return no row, so the permalink and its
social metadata resolve to the same non-indexable not-found response as other
hidden posts.
The retained post becomes visible at the same URL after verified repair; the web
app never reconstructs it from direct table reads or substitutes species
reference artwork for missing observation evidence.

The active video slide autoplays muted and inline with native browser controls;
it loops continuously while selected, and leaving the slide pauses and rewinds
it. Autoplay failure leaves the poster and controls available for user-initiated
playback. Species reference images follow the post-owned visual media, except
for human, `Felis catus`, and `Canis lupus familiaris` identifications, where
third-party references are suppressed and only post-owned media remains. Wild
felids and canids retain their reference galleries. The public Explore grid
remains poster-only so browsing it does not fetch or autoplay video. The detail
carousel uses one responsive square frame for post-owned images, videos, audio
spectrograms, posters, and eligible species reference images.

The detail data projection excludes the backing scan's
`scans.image_storage_urls` from its ordered reference-image compatibility field
before the web page maps carousel slides. The exclusion is exact to the current
scan: another scan's Naturebook reference and Wikipedia/GBIF images retain their
existing order. If every reference is excluded, the page renders only the
post-owned media and does not reserve a reference slide or indicator. The RPC
shape is unchanged, so this protection applies to web independently of the iOS
client rollout.

If the RPC returns no visible row—including when a post is unshared,
administratively hidden, media-quarantined, tombstoned, blocked, or otherwise
privacy-filtered—the route returns a not-found page and marks metadata as
non-indexable. The route must not render stale content or metadata from a prior
request. Approved audio-only posts are public and indexable: WAV posts render
the persisted spectrogram in the audio-focused post header, Open Graph metadata,
and Twitter metadata, while the public home grid uses the species reference
thumbnail. Mixed posts retain their visual social preview and render approved
audio in the same canonical square media carousel. Audio slides fill the frame
with their persisted spectrogram and anchor native playback controls over a
bottom gradient. Legacy non-WAV posts or failed poster generation retain the
speaker fallback and normal playback. Audio uses `preload="metadata"` and never
autoplays.

## Species Dictionary Pages

`/species/[speciesId]/[slug]` validates the dictionary UUID and invokes the
existing public `species-dictionary` Edge Function server-side with
`species_id`. It does not query broad Supabase tables or reconstruct the
response with service-role reads. The slug is derived from the common name,
falling back to the scientific name and then `species`; it is lowercase ASCII,
bounded to 80 characters, and never used for lookup. UUID-only requests and
requests with a stale or incorrect slug permanently redirect to the current
canonical URL only after a successful UUID lookup. This adds no database
migration or Edge response-contract change. Successful pages revalidate every
five minutes.

The page maps only the versioned public payload: canonical and alternate names,
content quality, conservation and hazard status, overview/source link, habitat,
taxonomy, and similar-species names/links. It intentionally excludes local
observations, authenticated Community sightings, user media, locations, field
notes, comments, and scan-specific data.

Before any reference image enters HTML or metadata, `apps/web/lib/species.ts`
runs `publicWebReferenceImageAttributionIssues(...)` from the shared public
species projection. Images missing either license or attribution are omitted.
Similar species remain textual because their current payload does not carry
equivalent rights fields for thumbnails.

Invalid UUIDs and Edge `404` responses become non-indexable application 404s.
Configuration, network, malformed-payload, and other transient upstream errors
remain server errors instead of being cached as missing content. Successful
metadata includes canonical, Open Graph, and Twitter fields and uses only an
attribution-approved image.

## Environment Variables

Required server-side values:

- `SUPABASE_URL`
- `SUPABASE_SERVER_API_KEY` — preferred current `sb_secret_...` key. A
  platform-managed `SUPABASE_SECRET_KEYS` dictionary is also supported when
  present.
- `SUPABASE_SERVICE_ROLE_KEY` — legacy service-role JWT migration fallback only;
  it is not required when a current key source is configured.
- `WAITLIST_IP_HASH_SECRET` — dedicated high-entropy server secret used only to
  derive daily rotating waitlist IP HMACs.
- `WAITLIST_TRUSTED_IP_HEADER` — `x-vercel-forwarded-for` for the production
  Vercel deployment.
- `TURNSTILE_SECRET_KEY`
- `TURNSTILE_ALLOWED_HOSTNAMES` — exact comma-separated hosts; production is
  `naturebook.earth`.

Optional public values:

- `NEXT_PUBLIC_SITE_URL` — canonical site URL. Production should be
  `https://naturebook.earth`.
- `NEXT_PUBLIC_APP_STORE_URL` — optional App Store CTA target.
- `NEXT_PUBLIC_SUPPORT_EMAIL` — public support contact shown on legal/support
  pages.
- `NEXT_PUBLIC_POSTHOG_API_KEY` — optional public ingestion key for privacy-safe
  audio playback telemetry.
- `NEXT_PUBLIC_TURNSTILE_SITE_KEY` — operationally required while the homepage
  waitlist form is enabled; it is public by design and must match the server
  secret's widget.

Optional fallback values:

- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`

No privileged Supabase key may be prefixed with `NEXT_PUBLIC_`, rendered into
HTML, committed to the repo, or used from client components. It is acceptable
only inside server-rendered route code or server-only helpers. The server
resolver accepts current `sb_secret_...` values or legacy HS256 `service_role`
JWTs and rejects publishable, anon/user, or malformed configuration.

This allowlist is intentionally unrelated to the GitHub deployment secret set.
Do not add `SUPABASE_ACCESS_TOKEN`, `SUPABASE_DB_URL`, `SUPABASE_DB_PASSWORD`,
any `REVENUECAT_*` server secret, or `DWCA_PSEUDONYM_HMAC_KEY_V1` to Vercel.
GitHub Actions consumes the deployment credentials and synchronizes the
provider/export credentials to Supabase Edge. `SUPABASE_URL` here means the
HTTPS project API endpoint, not the direct PostgreSQL `SUPABASE_DB_URL`. See the
canonical
[deployment environment ownership matrix](../development-guides/05-keychain-and-secrets.md#deployment-environment-ownership).

### Public Waitlist Boundary

The homepage waitlist is the only public write path in this web surface.
`POST /api/waitlist` streams at most 4 KiB of uncompressed JSON, accepts only a
canonical bounded email plus one Turnstile token, and returns a server-generated
request ID. A trusted proxy address becomes a purpose-separated, daily-rotating
HMAC; raw addresses and CAPTCHA tokens are never stored or logged. The
service-only pre-challenge RPC limits Siteverify traffic to 20 attempts per
IP/10 minutes and 100/day before the route verifies the Turnstile action,
hostname, remote IP, and bounded provider response.

The route cannot write `beta_waitlist_signups` directly. It calls the
service-only `submit_beta_waitlist_signup` RPC, which combines uniqueness with
tighter verified per-IP and global growth limits in one transaction. Duplicate
addresses return the same success message so the API is not an email-membership
oracle. The public privacy policy discloses the waitlist email, bounded browser
metadata, daily rotating network HMAC, and Cloudflare Turnstile processing; keep
that disclosure aligned with any future provider or retention change.

## Privacy Contract

The web page may render only data already intended for the public Explore
projection:

- public post id
- public hero image URL
- ordered public media items, including standalone-audio URL and persisted
  spectrogram `thumbnail_url`
- public species common/scientific name
- privacy-filtered location label
- coarse public telemetry such as time of day, month, weather condition, and
  temperature
- public author display name/avatar, plus canonical username handle only if the
  public projection supplies it
- public like/comment counts, retained in the projection for compatibility but
  intentionally not rendered on the public detail page
- public field notes already copied onto the Explore post
- normalized public hashtags
- public reference images, species overview, conservation status, taxonomy
  labels, and alternate names from the Explore detail projection

The web page must not render:

- exact coordinates
- raw GPS/elevation telemetry
- private field notes
- auth identifiers beyond the public author projection
- scan owner email or private profile fields
- private scan IDs in copy or metadata
- moderation-only state
- service-role credentials or Supabase tokens

The server may use its service-role credential only to invoke the dedicated
public-web boundary. The card routine is the current source of canonical
visibility. The detail routine must not be called directly until it owns that
same gate. Server code must not bypass `moderated_at IS NULL`, publication, or
media-health rules or reconstruct a hidden post from direct table reads. Restore
makes a post eligible for public projection again; resolving or dismissing a
review case by itself does not.

Public audio playback emits privacy-safe PostHog events for start, completion,
and failure when `NEXT_PUBLIC_POSTHOG_API_KEY` is configured. These events carry
only the public web surface name; they never include media URLs, transcripts,
filenames, post/species identity, or location. The PostHog project key is a
public ingestion key and must not be confused with a server-side secret.

Public post details offer an opt-in per-post **Boost audio** control. On first
use, the browser switches that player to the allowlisted same-origin audio
stream and applies a local fixed gain, 35 Hz high-pass filter, and peak limiter.
The control transitions through **Boosting audio…** to **Boosted audio** and is
reversible without replacing, uploading, or mutating the canonical recording.
The preference is stored only in that browser and post; preparation failure
keeps original playback available.

`/api/explore/audio` is a bounded media proxy used only for boost processing. It
accepts HTTPS WAV URLs on the exact `media.merian.app` host under
`public_uploads/`, forwards range requests, rejects oversized full responses,
and never accepts arbitrary upstream hosts or private/staging object paths.

The web app never downloads the recording to calculate FFT data in a visitor's
browser. Spectrogram PNGs are generated once at the approved publication seam,
stored beside the durable WAV under `public_uploads/{tier}/{userId}/`, and
referenced through the public post projection. This avoids R2 CORS dependence,
repeated audio downloads, and per-viewer DSP. Missing thumbnails are a
presentation fallback only and must not affect moderation or playback.

The web page must trust the public post projection as-is. Post-level
`location_sharing` controls whether `public_location_label` is present; the web
route must not query scan GPS, scan `semantic_location`, or scan geoprivacy to
reconstruct location. If Explore geoprivacy changes, the RPC/view contract must
be updated before the web UI consumes the new fields.

The detail projection independently requires an otherwise canonical visible
card. Within that visible set, it does not hide a post only because
`location_sharing = 'private'`; that setting suppresses public location display,
not public species-detail content.

`get_public_web_explore_post_page(...)` returns card and independently gated
detail in the same statement. Production promotion remains held for exact-SHA
fresh-catalog, complete CI, production smoke, and hosted-load evidence in the
[release assurance record](../backend-and-data/14-dwca-and-public-web-release-hold-2026-07-27.md).

## Sharing Strategy

For the best long-term user experience, iOS share payloads should use the HTTPS
URL as the durable identifier:

```text
https://naturebook.earth/explore/post/{postId}
https://naturebook.earth/species/{speciesId}/{slug}
```

The web page can include an "Open in Naturebook" button using:

```text
naturebook://explore/post/{postId}
naturebook://species/{speciesId}
```

Custom schemes are useful as an explicit button target, but they should not be
the primary shared link. They do not unfurl well, they fail for recipients
without the app, and they cannot serve public web previews.

## Theme Preference Bridge

Naturebook-owned web links opened by the signed-in iOS user may append a theme
query parameter so the web surface follows the app's theme preference:

```text
?theme=light
?theme=dark
?theme=system
```

`apps/web/lib/theme-preference.ts` maps `system` to Mantine's `auto` scheme,
while `apps/web/components/ThemePreferenceBridge.tsx` syncs the value into
Mantine storage. `apps/web/app/layout.tsx` also runs a small pre-hydration
script before `ColorSchemeScript` so the initial paint uses the requested color
scheme.

Do not append this parameter to public Explore share payloads. Recipient-facing
links should stay neutral and render with the recipient browser's stored or
system preference.

## Universal Links Configuration

Universal Links are configured for `naturebook.earth`, allowing shared Explore
posts and species pages to open in the native iOS app when installed and fall
back to their public web pages for everyone else.

### Implementation Details

1. **Associated Domains Entitlement**: The iOS app is configured with the
   Associated Domains capability:
   ```text
   applinks:naturebook.earth
   ```
   This is declared in the target entitlements
   (`apps/ios/Merian/Configuration/Merian.entitlements`) and defined within the
   XcodeGen spec `project.yml`.

2. **Apple App Site Association (AASA)**: The Next.js application hosts the AASA
   file dynamically via a route handler. It is served with the required
   `application/json` content-type header at:
   ```text
   https://naturebook.earth/.well-known/apple-app-site-association
   https://naturebook.earth/apple-app-site-association
   ```
   Both locations are routed using Next.js config rewrites mapping directly to
   the route handler. The same two paths are served directly on `merian.earth`
   so old app builds retain Universal Link compatibility; those requests must
   never redirect.

3. **Active Path Mapping**: The AASA details route Explore and species path
   patterns directly to the app:
   - App ID: `TA8S64ST9W.app.merian.Merian`
   - Paths: `["/explore/post/*", "/species/*"]`

4. **Deep Linking Route Handler**: Incoming `NSUserActivityTypeBrowsingWeb` web
   links route through the same typed native router as custom-scheme links.
   Species routes carry only the validated canonical UUID, ignore the optional
   descriptive slug, select Explore's Identify tab and Index mode, and push
   `SpeciesDictionaryRoute(entryPoint: .deepLink)`. The parser accepts both
   Naturebook and legacy Merian hosts/schemes and ignores unrelated policy
   routes.

The app emits `naturebook://` and `https://naturebook.earth` links. It continues
to accept `merian://` and `https://merian.earth` indefinitely for older shared
payloads, widgets, app versions, and push actions.

Rollout note: publishing `/species/*` in AASA can cause an older installed build
to claim a species HTTPS link even though that build does not understand the
species route. This risk is accepted for the initial rollout. Keep the web page
deployed before sharing is enabled in the current iOS build, and verify the
installed current build during release QA.

## Local Development

```bash
cd apps/web
cp .env.example .env.local
npm ci
npm run dev
```

Useful checks:

```bash
npm run typecheck
npm test
npm run build
npm run audit:dependencies
```

Local waitlist submissions need a Turnstile test widget and matching test
secret. Never put a production Turnstile secret or privileged Supabase server
key in a `NEXT_PUBLIC_` variable. An absent or inconsistent CAPTCHA, hostname,
proxy-header, HMAC, or service-role configuration fails closed with `503`; it
never falls back to a direct table upsert.

The web package pins the reviewed Next.js version exactly. `proxy.ts` creates a
fresh nonce and applies the same nonce-based CSP to the request and response;
`layout.tsx` binds the color-scheme bootstrap script to that nonce. The policy
uses `'strict-dynamic'` and intentionally makes pages dynamic. Production also
sets HSTS, while all environments set explicit referrer, framing, MIME,
permissions, and cross-origin headers. Do not add `'unsafe-inline'` to
`script-src` or move service-role access out of the `server-only` admin module.

The root web manifest temporarily overrides Next.js's nested PostCSS and Sharp
edges to reviewed patched releases. `lib/dependencySecurity.test.ts` verifies
all locked copies and the workflow gate; the registry-backed CI audit then
blocks newly disclosed high or critical dependency findings. Remove an override
only after a stable reviewed Next.js release declares an equal or newer
dependency and all four web checks pass.

## Vercel Deployment

The Vercel project for `naturebook.earth` must be configured as a monorepo app
with:

- Root Directory: `apps/web`
- Framework Preset: Next.js
- Build Command: `npm run build`
- Install Command: `npm ci`
- Production domains: `naturebook.earth`, `www.naturebook.earth`,
  `naturebook.app`, `www.naturebook.app`, `merian.earth`, and `www.merian.earth`

A Vercel platform response body of:

```text
404: NOT_FOUND
Code: NOT_FOUND
```

is not the app-level Explore not-found state. The app-level 404 renders
`apps/web/app/not-found.tsx` with Naturebook styling. The plain Vercel response
indicates the domain is not attached to a valid production deployment or the
project is building the wrong directory.

### Species deployment verification

After deployment, choose a real canonical dictionary UUID with complete public
content and verify:

1. `https://naturebook.earth/species/{speciesId}/{slug}` returns the Naturebook
   page, canonical metadata points to the same UUID-plus-current-slug URL, and
   Open Graph/Twitter images are present only when the rendered image shows
   license and attribution.
2. Every linked similar species with a UUID opens its own textual
   `/species/{speciesId}/{slug}` route; no lookalike thumbnail is rendered.
3. UUID-only and stale-slug Naturebook requests return a permanent redirect to
   the current readable canonical URL. The equivalent `merian.earth` URL first
   preserves the complete UUID-plus-slug path in its 308 to `naturebook.earth`;
   both AASA paths on `merian.earth` still return 200 directly.
4. An invalid UUID and a missing UUID resolve to the styled, non-indexable app
   404. A forced transient Edge failure produces a server error, never a cached
   not-found page.
5. With the current app installed, canonical, UUID-only, and stale-slug HTTPS
   links open Explore, select Index/Dictionary, and push the matching species
   page by UUID. Without the app, or when opened explicitly in a browser, the
   canonical URL remains on the web fallback and compatibility forms redirect
   there. The page's **Open in Naturebook** action targets
   `naturebook://species/{speciesId}`.
6. All four associated-domain AASA responses return the exact path list
   `["/explore/post/*", "/species/*"]` for `TA8S64ST9W.app.merian.Merian`.

## Public Policy Pages

The public web app includes App Store-ready policy/support routes:

- `https://naturebook.earth/privacy`
- `https://naturebook.earth/privacy-choices`
- `https://naturebook.earth/terms`
- `https://naturebook.earth/guidelines`
- `https://naturebook.earth/support`
- `https://naturebook.earth/legal`

`/community-guidelines` redirects to `/guidelines`, and `/data-deletion`
redirects to `/privacy-choices`. Keep the iOS Settings community links pointed
at the `naturebook.earth` versions of these URLs. In-app Settings links may
include the `theme` query parameter; public share URLs should not.

## Maintenance Notes

- Keep `apps/web/.env.example`, `apps/web/README.md`, root `README.md`, and this
  doc aligned when adding public web routes or env variables.
- Keep Open Graph metadata server-rendered. Messages and social crawlers need
  HTML metadata before client-side hydration.
- Treat `apps/web/lib/explore.ts` as a public projection mapper, not a place to
  expose raw database rows.
- Keep direct detail independently canonical and page rendering on the atomic
  card-plus-detail RPC; never regress to a sequential check-then-fetch flow.
- Treat `apps/web/lib/species.ts` as a strict mapper for the versioned public
  Edge payload. Keep UUID validation, attribution filtering, 404 mapping, and
  transient failure behavior covered together.
- Keep `apps/web/lib/exploreMedia.ts` pure and covered by Node tests so visual
  heroes remain canonical for visual posts, audio grids prefer species reference
  thumbnails, and detail/social surfaces retain spectrogram posters.
- Keep `/api/explore/audio` exact-host and public-WAV-path only. Any expansion
  of its upstream allowlist requires a security review and matching proxy tests.
- Prefer adding dedicated Supabase RPCs/views for web surfaces instead of
  querying broad private tables.
- Use `NEXT_PUBLIC_SITE_URL=https://naturebook.earth` in production so canonical
  and Open Graph URLs point at the real domain.
- If an Explore post is unshared, blocked, removed, or privacy-filtered out for
  the public viewer, the route should resolve to not found rather than showing
  stale metadata.
