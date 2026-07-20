# Public Web Share Pages

Naturebook's public web surface lives in `apps/web/`. It is a Next.js + Mantine app for public, shareable Naturebook pages, starting with Explore post links on `naturebook.earth`.

The first shipped route is:

```text
https://naturebook.earth/explore/post/{postId}
```

This URL is the long-term share target for Explore posts. It renders a useful
web page for recipients without the app, provides Open Graph metadata for
Messages/social previews, and is the Universal Link that opens the native iOS
detail page when Naturebook is installed.

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
- Initial route: `/explore/post/[postId]`.
- Policy/support routes: `/privacy`, `/privacy-choices`, `/terms`, `/guidelines`,
  `/support`, and `/legal`.
- Native fallback button: `naturebook://explore/post/{postId}` via the page's "Open in Naturebook" action.
- Web page audience: anonymous recipients of shared Explore posts.
- Metadata audience: iMessage, social crawlers, link unfurlers, and search previews.

The public web page is not the full Explore product yet. It is a rich read-only
detail surface for one post, with enough context to understand what was shared
and a clean path back into the app. Anonymous web visitors can view the post,
but engagement counts are not rendered and they cannot like, comment, reply,
follow, or edit on the web surface. A centered support-email report action sits
below the Taxonomy card and contains the immutable post id; this is not an
authenticated in-product report write.

## Data Flow

1. The iOS app shares `https://naturebook.earth/explore/post/{postId}` in the message text.
2. Next.js server-rendering handles `/explore/post/[postId]`.
3. `apps/web/lib/explore.ts` creates a server Supabase client through `apps/web/lib/supabase.ts`.
4. The page calls the `get_explore_post` RPC with:

   ```ts
   {
     self_id: process.env.SUPABASE_PUBLIC_VIEWER_ID ?? null,
     target_post_id: postId
   }
   ```

5. The page calls `get_explore_post_detail` with the same viewer id and post id
   to hydrate public field notes, hashtags, reference images, overview,
   conservation status, taxonomy labels, and alternate names.
6. The server maps those RPC rows into the `ExplorePost` page model.
   `get_explore_post` includes the canonical ordered `media_items` snapshot;
   the hero image remains the static poster and metadata fallback.
7. `explorePosterUrl(...)` prefers the canonical visual hero and otherwise uses
   the first persisted standalone-audio spectrogram thumbnail.
8. `generateMetadata(...)` emits canonical, Open Graph, and Twitter metadata
   using the post title and resolved poster.
9. The page renders the public post with default Mantine components and props,
   without route-specific CSS classes or custom page chrome.

Visual media on the detail route is rendered in canonical `order_index` order.
The active video slide autoplays muted and inline with native browser controls;
it loops continuously while selected, and leaving the slide pauses and rewinds
it. Autoplay failure leaves the poster and controls available for user-initiated playback.
Species reference images follow the post-owned visual media, except for human,
`Felis catus`, and `Canis lupus familiaris` identifications, where third-party
references are suppressed and only post-owned media remains. Wild felids and
canids retain their reference galleries. The public Explore grid remains
poster-only so browsing it does not fetch or autoplay video. The detail carousel
uses one responsive square frame for post-owned images, videos, audio spectrograms,
posters, and eligible species reference images.

If the RPC returns no visible row—including when a post is unshared,
administratively hidden, tombstoned, blocked, or otherwise privacy-filtered—the
route returns a not-found page and marks metadata as non-indexable. The route
must not render stale content or metadata from a prior request. Approved
audio-only posts are public and indexable:
WAV posts render the persisted spectrogram in the audio-focused post header,
Open Graph metadata, and Twitter metadata, while the public home grid uses the
species reference thumbnail. Mixed posts retain their visual social preview
and render approved audio in the same canonical square media carousel. Audio
slides fill the frame with their persisted spectrogram and anchor native
playback controls over a bottom gradient. Legacy non-WAV posts or failed poster
generation retain the speaker fallback and normal playback. Audio uses
`preload="metadata"` and never autoplays.

## Environment Variables

Required server-side values:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`

Optional public values:

- `NEXT_PUBLIC_SITE_URL` — canonical site URL. Production should be `https://naturebook.earth`.
- `NEXT_PUBLIC_APP_STORE_URL` — optional App Store CTA target.
- `NEXT_PUBLIC_SUPPORT_EMAIL` — public support contact shown on legal/support pages.
- `NEXT_PUBLIC_POSTHOG_API_KEY` — optional public ingestion key for privacy-safe
  audio playback telemetry.

Optional fallback values:

- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`
- `SUPABASE_PUBLIC_VIEWER_ID`

`SUPABASE_SERVICE_ROLE_KEY` must never be prefixed with `NEXT_PUBLIC_`, rendered into HTML, committed to the repo, or used from client components. It is only acceptable inside server-rendered route code or server-only helpers.

## Privacy Contract

The web page may render only data already intended for the public Explore projection:

- public post id
- public hero image URL
- ordered public media items, including standalone-audio URL and persisted
  spectrogram `thumbnail_url`
- public species common/scientific name
- privacy-filtered location label
- coarse public telemetry such as time of day, month, weather condition, and temperature
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

The server may use its service-role credential only to invoke the existing
privacy-safe public projections. It must not bypass `moderated_at IS NULL` or
reconstruct a hidden post from direct table reads. Restore makes a post eligible
for public projection again; resolving or dismissing a review case by itself
does not.

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

`/api/explore/audio` is a bounded media proxy used only for boost processing.
It accepts HTTPS WAV URLs on the exact `media.merian.app` host under
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

`get_explore_post_detail` should not hide an otherwise visible post only because
`location_sharing = 'private'`; that setting suppresses public location display,
not the public species-detail content.

## Sharing Strategy

For the best long-term user experience, iOS share payloads should use the HTTPS URL as the durable identifier:

```text
https://naturebook.earth/explore/post/{postId}
```

The web page can include an "Open in Naturebook" button using:

```text
naturebook://explore/post/{postId}
```

Custom schemes are useful as an explicit button target, but they should not be the primary shared link. They do not unfurl well, they fail for recipients without the app, and they cannot serve public web previews.

## Theme Preference Bridge

Naturebook-owned web links opened by the signed-in iOS user may append a theme query
parameter so the web surface follows the app's theme preference:

```text
?theme=light
?theme=dark
?theme=system
```

`apps/web/lib/theme-preference.ts` maps `system` to Mantine's `auto` scheme, while
`apps/web/components/ThemePreferenceBridge.tsx` syncs the value into Mantine storage.
`apps/web/app/layout.tsx` also runs a small pre-hydration script before
`ColorSchemeScript` so the initial paint uses the requested color scheme.

Do not append this parameter to public Explore share payloads. Recipient-facing
links should stay neutral and render with the recipient browser's stored or
system preference.

## Universal Links Configuration

Universal Links are fully configured for `naturebook.earth`, allowing shared explore posts to open seamlessly in the native iOS app when installed, and falling back to the web preview for everyone else.

### Implementation Details

1. **Associated Domains Entitlement**:
   The iOS app is configured with the Associated Domains capability:
   ```text
   applinks:naturebook.earth
   ```
   This is declared in the target entitlements (`apps/ios/Merian/Configuration/Merian.entitlements`) and defined within the XcodeGen spec `project.yml`.

2. **Apple App Site Association (AASA)**:
   The Next.js application hosts the AASA file dynamically via a route handler. It is served with the required `application/json` content-type header at:
   ```text
   https://naturebook.earth/.well-known/apple-app-site-association
   https://naturebook.earth/apple-app-site-association
   ```
   Both locations are routed using Next.js config rewrites mapping directly to the route handler.
   The same two paths are served directly on `merian.earth` so old app builds
   retain Universal Link compatibility; those requests must never redirect.

3. **Active Path Mapping**:
   The AASA details are configured to route `/explore/post/*` path patterns directly to the app:
   - App ID: `TA8S64ST9W.app.merian.Merian`
   - Paths: `["/explore/post/*"]`

4. **Deep Linking Route Handler**:
   Incoming `NSUserActivityTypeBrowsingWeb` web links route through the same native Explore post router that handles `naturebook://explore/post/{postId}`. The native deep-link parser accepts both Naturebook and legacy Merian hosts/schemes and ignores unrelated policy routes.

The app emits `naturebook://` and `https://naturebook.earth` links. It continues
to accept `merian://` and `https://merian.earth` indefinitely for older shared
payloads, widgets, app versions, and push actions.

## Local Development

```bash
cd apps/web
cp .env.example .env.local
npm install
npm run dev
```

Useful checks:

```bash
npm run typecheck
npm test
npm run build
npm audit --audit-level=moderate
```

## Vercel Deployment

The Vercel project for `naturebook.earth` must be configured as a monorepo app with:

- Root Directory: `apps/web`
- Framework Preset: Next.js
- Build Command: `npm run build`
- Install Command: `npm install`
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
at the `naturebook.earth` versions of these URLs. In-app Settings links may include
the `theme` query parameter; public share URLs should not.

## Maintenance Notes

- Keep `apps/web/.env.example`, `apps/web/README.md`, root `README.md`, and this doc aligned when adding public web routes or env variables.
- Keep Open Graph metadata server-rendered. Messages and social crawlers need HTML metadata before client-side hydration.
- Treat `apps/web/lib/explore.ts` as a public projection mapper, not a place to expose raw database rows.
- Keep `apps/web/lib/exploreMedia.ts` pure and covered by Node tests so visual
  heroes remain canonical for visual posts, audio grids prefer species reference
  thumbnails, and detail/social surfaces retain spectrogram posters.
- Keep `/api/explore/audio` exact-host and public-WAV-path only. Any expansion of
  its upstream allowlist requires a security review and matching proxy tests.
- Prefer adding dedicated Supabase RPCs/views for web surfaces instead of querying broad private tables.
- Use `NEXT_PUBLIC_SITE_URL=https://naturebook.earth` in production so canonical and Open Graph URLs point at the real domain.
- If an Explore post is unshared, blocked, removed, or privacy-filtered out for the public viewer, the route should resolve to not found rather than showing stale metadata.
