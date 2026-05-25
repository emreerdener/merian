# Merian Web

Next.js + Mantine web surface for public Merian pages.

The first route is the public Explore share page:

```text
/explore/post/[postId]
```

It fetches the public Explore projection from Supabase on the server and emits
Open Graph metadata so Messages/social shares can render a clean preview.

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

Required server-side variables:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`

Optional public variables:

- `NEXT_PUBLIC_SITE_URL`
- `NEXT_PUBLIC_APP_STORE_URL`
- `NEXT_PUBLIC_SUPPORT_EMAIL`

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
- `/explore/post/[postId]` — public Explore share page.
- `/apple-app-site-association` and `/.well-known/apple-app-site-association` — served Apple App Site Association file for iOS deep linking capabilities.
- `/privacy` — App Store privacy policy URL.
- `/privacy-choices` — optional App Store privacy choices URL and data deletion help.
- `/terms` — Terms of Service.
- `/guidelines` — Community Guidelines. `/community-guidelines` redirects here.
- `/support` — support/contact page.
- `/legal` — hub linking the legal and support pages.
- `/data-deletion` — redirects to `/privacy-choices`.

## Privacy Notes

The public page should consume only the privacy-safe Explore projection returned
by `get_explore_post`: public image, species labels, public author identity,
counts, shared timestamp, and privacy-filtered location/telemetry. Do not expose
exact coordinates, private field notes, raw scan telemetry, auth data, or server
credentials.

See `../../docs/features-and-hardware/17-public-web-share-pages.md` for the full
contract and Universal Links roadmap.
