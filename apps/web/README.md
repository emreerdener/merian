# Naturebook Web

Next.js + Mantine web surface for public Naturebook pages. The package and
repository continue to use Merian as their stable engineering identity.

The public share routes are:

```text
/explore/post/[postId]
/species/[speciesId]/[slug]
```

`/species/[speciesId]` remains a UUID-only compatibility route and permanently
redirects to the current readable canonical path after resolving the species.

The Explore route fetches the public post and detail projections from Supabase
on the server, renders a rich read-only post page with default Mantine
components, and emits Open Graph metadata so Messages/social shares can render
a clean preview.
Unshared, administratively hidden, tombstoned, blocked, and otherwise
privacy-filtered posts resolve to the application not-found page with
non-indexable metadata; server code must not reconstruct them from direct table
reads.
Standalone-audio post details and social previews consume the persisted
`media_items.thumbnail_url` spectrogram. The home grid uses the public species
reference thumbnail instead, with the spectrogram as a legacy fallback. The
public web app never downloads recordings to calculate FFT data in a visitor's
browser; blank or unsupported legacy thumbnails retain the volume-icon fallback
and normal `<audio>` playback.

Post-detail audio slides include an optional browser-local **Boost audio** mode.
Only boost requests use the allowlisted `/api/explore/audio` WAV stream; Web
Audio applies conservative gain, rumble filtering, and peak limiting without
uploading or changing the canonical recording.

The production domain is:

```text
https://naturebook.earth
```

Species pages are server-rendered from the existing privacy-safe
`species-dictionary` Edge Function. They publish only licensed reference
imagery with complete attribution and intentionally omit observations,
Community sightings, user media, locations, and scan-specific data.

## Setup

```bash
cd apps/web
cp .env.example .env.local
npm install
npm run dev
```

If `npm run dev` reports `next: command not found`, install dependencies from
inside `apps/web` first:

```bash
cd apps/web
npm install
```

Required server-side variables:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `WAITLIST_IP_HASH_SECRET` — at least 32 random characters. Generate a
  dedicated value; do not reuse a Supabase, Turnstile, or application secret.
- `TURNSTILE_SECRET_KEY` — server-side secret for the production Cloudflare
  Turnstile widget.
- `TURNSTILE_ALLOWED_HOSTNAMES` — comma-separated exact widget hostnames.
  Production is `naturebook.earth`.

Required public variables:

- `NEXT_PUBLIC_TURNSTILE_SITE_KEY` — public site key for the same Turnstile
  widget.

Ingress configuration:

- `WAITLIST_TRUSTED_IP_HEADER` — use `x-vercel-forwarded-for` on Vercel. The
  application accepts only a small header allowlist and uses only the first
  syntactically valid address. A non-Vercel proxy must overwrite its configured
  header at the trusted ingress; never trust a client-appended forwarding
  chain.

Optional public variables:

- `NEXT_PUBLIC_SITE_URL` — set to `https://naturebook.earth` in production.
- `NEXT_PUBLIC_APP_STORE_URL`
- `NEXT_PUBLIC_SUPPORT_EMAIL` — set to `support@naturebook.earth` in
  production.
- `NEXT_PUBLIC_POSTHOG_API_KEY` — optional public ingestion key for privacy-safe web playback events

Optional server/public fallback variables:

- `SUPABASE_PUBLIC_VIEWER_ID`
- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`

The service role key must stay server-side only. Do not prefix it with
`NEXT_PUBLIC_`.

### Waitlist Security Boundary

`POST /api/waitlist` accepts one uncompressed JSON object no larger than 4 KiB:

```json
{
  "email": "person@example.com",
  "turnstile_token": "single-use-widget-token"
}
```

The route requires a JSON media type, enforces declared and streamed lengths,
and coalesces tiny chunks into a bounded buffer so allocation remains
proportional to accepted bytes. It canonicalizes a conservatively shaped email,
derives a purpose-separated daily HMAC of the trusted proxy address, discards
the raw address, and uses the explicit service-role client to claim a
distributed pre-challenge budget. PostgreSQL allows at most 20 Turnstile checks
per IP/10 minutes and 100/day, so invalid-token floods cannot invoke Siteverify
without bound.

All trusted-IP, IP-HMAC, hostname, and Turnstile-secret configuration is
validated before that claim. An incomplete production configuration returns a
stable `503` without consuming a database counter or contacting Cloudflare.

After that claim, the route verifies Turnstile with action `waitlist`, exact
hostname allowlisting, the trusted remote IP, a five-second deadline, a 32 KiB
streamed response ceiling, and the request UUID as the Siteverify idempotency
key. A successful challenge permits the separate
`submit_beta_waitlist_signup` call. Direct table access is revoked. PostgreSQL
atomically enforces tighter verified limits of 5 attempts per IP/10 minutes, 20
per IP/day, and 2,000 new unique addresses globally/day. Duplicate addresses
receive the same success copy and consume only the verified IP budget,
preventing address enumeration and unbounded table growth. Turnstile tokens,
raw IP addresses, and emails must not appear in logs.

Errors use stable `code` and server-generated `request_id` fields, plus the same
ID in `X-Request-ID`. A `429` includes `Retry-After: 600`; internal database or
provider details are logged privately and never returned.

## Vercel Deployment

Configure the Vercel project as a monorepo app:

- **Root Directory**: `apps/web`
- **Framework Preset**: Next.js
- **Build Command**: `npm run build`
- **Install Command**: `npm install`
- **Canonical production domain**: `naturebook.earth`
- **Redirect aliases**: `naturebook.app`, `www.naturebook.app`,
  `www.naturebook.earth`, `merian.earth`, and `www.merian.earth`

All aliases must be assigned to the same Vercel project that builds from
`apps/web`; do not configure provider-level redirects in front of the app.
`naturebook.earth` must be the project's primary production domain. `proxy.ts`
issues permanent path- and query-preserving redirects to `naturebook.earth`.
The two Apple App Site Association paths on the exact `naturebook.earth` and
`merian.earth` hosts are served directly with HTTP 200. They must never pass
through a host redirect. A plain
Vercel response like:

```text
404: NOT_FOUND
Code: NOT_FOUND
```

means the request is not reaching this Next.js app. Check the Vercel project
Root Directory, production deployment status, and domain assignment before
debugging app routes.

### Production Verification

Run these checks after every domain or redirect change:

```bash
curl -I 'https://naturebook.earth/explore/post/example?source=docs'
curl -I 'https://www.naturebook.earth/explore/post/example?source=docs'
curl -I 'https://naturebook.app/explore/post/example?source=docs'
curl -I 'https://www.naturebook.app/explore/post/example?source=docs'
curl -I 'https://merian.earth/explore/post/example?source=docs'
curl -I 'https://www.merian.earth/explore/post/example?source=docs'
curl -I 'https://naturebook.earth/species/00000000-0000-0000-0000-000000000000'
curl -I 'https://merian.earth/species/00000000-0000-0000-0000-000000000000'
curl -I 'https://merian.earth/species/{real-species-uuid}/{current-slug}?source=docs'
curl -I 'https://naturebook.earth/apple-app-site-association'
curl -I 'https://naturebook.earth/.well-known/apple-app-site-association'
curl -I 'https://merian.earth/apple-app-site-association'
curl -I 'https://merian.earth/.well-known/apple-app-site-association'
```

The canonical host may return the route's normal status. Every alias must
permanently redirect to the matching path and query on `naturebook.earth`.
All four AASA checks must return HTTP 200 directly with JSON content and no redirect.
The AASA payload must continue to use `TA8S64ST9W.app.merian.Merian` with the
exact path list `["/explore/post/*", "/species/*"]`.

For a real species UUID, also verify the UUID-only and stale-slug Naturebook
paths return a permanent redirect to the current UUID-plus-slug canonical path.

## Scripts

```bash
npm run dev
npm test
npm run typecheck
npm run build
npm audit --audit-level=moderate
```

`.github/workflows/web-quality.yml` runs install, unit tests, TypeScript, and a
production build when the web route, its security helpers, the waitlist
migration, or the workflow changes.

## Share URL Shape

Use this public URL in iOS share payloads:

```text
https://naturebook.earth/explore/post/{postId}
https://naturebook.earth/species/{speciesId}/{slug}
```

Universal Links are active, meaning the HTTPS URL opens the native iOS app when installed, and gracefully falls back to the public web preview otherwise.

The web page includes a native-app CTA using:

```text
naturebook://explore/post/{postId}
naturebook://species/{speciesId}
```

Keep the HTTPS URL as the primary shared link so recipients without the app still get a real page and a rich Open Graph preview.

## Theme Preference Bridge

Naturebook-owned links opened from the iOS app may append:

```text
?theme=light
?theme=dark
?theme=system
```

The web app maps `system` to Mantine's `auto` color scheme and stores the value
in Mantine's color scheme storage key before hydration. Public share links should
omit this parameter so recipients see their own browser/system preference.

## Public Routes

- `/` — lightweight Naturebook public home.
- `/explore/post/[postId]` — public Explore share page. The MVP is read-only:
  anonymous visitors can view post context and send a support-email report from
  the centered action below the Taxonomy card, but
  cannot like, comment, reply, follow, or edit from the web page. Engagement
  counts are intentionally omitted from the public detail presentation.
  Ordered image, video, and audio media appear in the detail carousel. Its
  active video autoplays muted and inline on a continuous loop with native
  controls, while inactive videos pause and rewind. The homepage Explore grid
  remains poster-only and uses species reference images for audio posts. Audio
  detail slides retain their spectrogram, bottom-anchored controls, and optional
  browser-local Boost Audio toggle.
- `/species/[speciesId]/[slug]` — public Species Dictionary reference page. The
  lowercase ASCII slug is derived from the common name, with the scientific
  name and then `species` as fallbacks; it is descriptive only and never used
  for lookup. UUID-only and stale-slug requests permanently redirect to the
  current canonical path. Successful pages revalidate every five minutes, emit
  canonical/Open Graph/Twitter metadata, link similar species textually, and
  filter every rendered or metadata image through the shared attribution audit.
  Invalid IDs and missing species are non-indexable 404s; transient Edge
  failures remain server errors.
- `/api/explore/audio?url={canonicalWavUrl}` — range-capable same-origin stream
  used only by Boost Audio. It accepts canonical public Naturebook WAV URLs on
  the stable `media.merian.app` infrastructure host, is not
  a general media proxy, and stores no derived audio.
- `/apple-app-site-association` and `/.well-known/apple-app-site-association` — served Apple App Site Association file for iOS deep linking capabilities.
- `/privacy` — App Store privacy policy URL.
- `/privacy-choices` — optional App Store privacy choices URL and data deletion help.
- `/terms` — Terms of Service.
- `/guidelines` — Community Guidelines. `/community-guidelines` redirects here.
- `/support` — support/contact page.
- `/legal` — hub linking the legal and support pages.
- `/data-deletion` — redirects to `/privacy-choices`.

## Privacy Notes

The public page should consume only the privacy-safe Explore projections
returned by `get_explore_post` and `get_explore_post_detail`: public image,
species labels, public author identity, engagement counts (not rendered on the
detail page), shared timestamp,
privacy-filtered location/telemetry, public field notes, normalized hashtags,
reference images, overview text, conservation status, taxonomy labels, and
alternate names. If the public projection supplies `author_username`, render it
only as a public handle. Do not expose exact coordinates, private field notes,
raw scan telemetry, auth data, private email, or server credentials.

Species pages consume only the versioned public payload returned by the
`species-dictionary` Edge Function with `species_id`. Server code must not query
broad species, scan, profile, or Explore tables to reconstruct that payload.
Similar-species thumbnails are intentionally omitted because the current
lookalike payload does not carry the required license and attribution fields.

The Explore share page intentionally uses default Mantine components and
component props instead of route-specific CSS classes or custom page chrome.
Post visibility comes exclusively from the public projection contract. In
particular, do not bypass its `moderated_at IS NULL` rule with service-role table
queries or cached page data.

See
`../../docs/system-architecture/08-public-brand-compatibility.md` for the
permanent brand and compatibility contract,
`../../docs/development-guides/15-naturebook-rebrand-rollout.md` for production
rollout and rollback steps, and
`../../docs/features-and-hardware/17-public-web-share-pages.md` for the full web
and Universal Link implementation contract.
