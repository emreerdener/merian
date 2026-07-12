# Merian Web

Next.js + Mantine web surface for public Merian pages.

The first route is the public Explore share page:

```text
/explore/post/[postId]
```

It fetches the public Explore post and detail projections from Supabase on the
server, renders a rich read-only post page with default Mantine components, and
emits Open Graph metadata so Messages/social shares can render a clean preview.
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
https://merian.earth
```

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

Optional public variables:

- `NEXT_PUBLIC_SITE_URL`
- `NEXT_PUBLIC_APP_STORE_URL`
- `NEXT_PUBLIC_SUPPORT_EMAIL`
- `NEXT_PUBLIC_POSTHOG_API_KEY` — optional public ingestion key for privacy-safe web playback events

Optional server/public fallback variables:

- `SUPABASE_PUBLIC_VIEWER_ID`
- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`

The service role key must stay server-side only. Do not prefix it with
`NEXT_PUBLIC_`.

## Vercel Deployment

Configure the Vercel project as a monorepo app:

- **Root Directory**: `apps/web`
- **Framework Preset**: Next.js
- **Build Command**: `npm run build`
- **Install Command**: `npm install`
- **Production domains**: `merian.earth` and `www.merian.earth`

Both `merian.earth` aliases must point at the same Vercel project that builds
from `apps/web`. A plain Vercel response like:

```text
404: NOT_FOUND
Code: NOT_FOUND
```

means the request is not reaching this Next.js app. Check the Vercel project
Root Directory, production deployment status, and domain assignment before
debugging app routes.

## Scripts

```bash
npm run dev
npm run typecheck
npm run build
npm audit --audit-level=moderate
```

## Share URL Shape

Use this public URL in iOS share payloads:

```text
https://merian.earth/explore/post/{postId}
```

Universal Links are active, meaning the HTTPS URL opens the native iOS app when installed, and gracefully falls back to the public web preview otherwise.

The web page includes a native-app CTA using:

```text
merian://explore/post/{postId}
```

Keep the HTTPS URL as the primary shared link so recipients without the app still get a real page and a rich Open Graph preview.

## Theme Preference Bridge

Merian-owned links opened from the iOS app may append:

```text
?theme=light
?theme=dark
?theme=system
```

The web app maps `system` to Mantine's `auto` color scheme and stores the value
in Mantine's color scheme storage key before hydration. Public share links should
omit this parameter so recipients see their own browser/system preference.

## Public Routes

- `/` — lightweight Merian public home.
- `/explore/post/[postId]` — public Explore share page. The MVP is read-only:
  anonymous visitors can view post context and send a support-email report, but
  cannot like, comment, reply, follow, or edit from the web page. Engagement
  counts are intentionally omitted from the public detail presentation.
  Ordered image, video, and audio media appear in the detail carousel. Its
  active video autoplays muted and inline on a continuous loop with native
  controls, while inactive videos pause and rewind. The homepage Explore grid
  remains poster-only and uses species reference images for audio posts. Audio
  detail slides retain their spectrogram, bottom-anchored controls, and optional
  browser-local Boost Audio toggle.
- `/api/explore/audio?url={canonicalWavUrl}` — range-capable same-origin stream
  used only by Boost Audio. It accepts canonical public Merian WAV URLs, is not
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

The Explore share page intentionally uses default Mantine components and
component props instead of route-specific CSS classes or custom page chrome.

See `../../docs/features-and-hardware/17-public-web-share-pages.md` for the full
contract and Universal Links roadmap.
