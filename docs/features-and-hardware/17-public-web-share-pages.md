# Public Web Share Pages

Merian's public web surface lives in `apps/web/`. It is a Next.js + Mantine app for public, shareable Merian pages, starting with Explore post links on `merian.earth`.

The first shipped route is:

```text
https://merian.earth/explore/post/{postId}
```

This URL is the long-term share target for Explore posts. It should render a useful web page for recipients without the app, provide Open Graph metadata for Messages/social previews, and eventually become the Universal Link that opens the native iOS detail page when Merian is installed.

## Product Contract

- Primary domain: `merian.earth`.
- App location: `apps/web/`.
- Frameworks: Next.js App Router, React, Mantine, and Supabase JS.
- Initial route: `/explore/post/[postId]`.
- Policy/support routes: `/privacy`, `/privacy-choices`, `/terms`, `/guidelines`,
  `/support`, and `/legal`.
- Native fallback button: `merian://explore/post/{postId}` via the page's "Open in Merian" action.
- Web page audience: anonymous recipients of shared Explore posts.
- Metadata audience: iMessage, social crawlers, link unfurlers, and search previews.

The public web page is not the full Explore product yet. It is a public detail surface for one post, with enough context to understand what was shared and a clean path back into the app.

## Data Flow

1. The iOS app shares `https://merian.earth/explore/post/{postId}` in the message text.
2. Next.js server-rendering handles `/explore/post/[postId]`.
3. `apps/web/lib/explore.ts` creates a server Supabase client through `apps/web/lib/supabase.ts`.
4. The page calls the `get_explore_post` RPC with:

   ```ts
   {
     self_id: process.env.SUPABASE_PUBLIC_VIEWER_ID ?? null,
     target_post_id: postId
   }
   ```

5. The server maps the RPC row into the `ExplorePost` page model.
6. `generateMetadata(...)` emits canonical, Open Graph, and Twitter metadata using the post title and hero image.
7. The page renders the public post with Mantine components.

If the RPC returns no visible row, the route returns a not-found page and marks metadata as non-indexable.

## Environment Variables

Required server-side values:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`

Optional public values:

- `NEXT_PUBLIC_SITE_URL` — canonical site URL. Production should be `https://merian.earth`.
- `NEXT_PUBLIC_APP_STORE_URL` — optional App Store CTA target.
- `NEXT_PUBLIC_SUPPORT_EMAIL` — public support contact shown on legal/support pages.

Optional fallback values:

- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`
- `SUPABASE_PUBLIC_VIEWER_ID`

`SUPABASE_SERVICE_ROLE_KEY` must never be prefixed with `NEXT_PUBLIC_`, rendered into HTML, committed to the repo, or used from client components. It is only acceptable inside server-rendered route code or server-only helpers.

## Privacy Contract

The web page may render only data already intended for the public Explore projection:

- public post id
- public hero image URL
- public species common/scientific name
- privacy-filtered location label
- coarse public telemetry such as time of day, month, weather condition, and temperature
- public author display name/avatar
- public like/comment counts

The web page must not render:

- exact coordinates
- raw GPS/elevation telemetry
- private field notes
- auth identifiers beyond the public author projection
- scan owner email or private profile fields
- private scan IDs in copy or metadata
- moderation-only state
- service-role credentials or Supabase tokens

If Explore geoprivacy changes, the RPC/view contract must be updated before the web UI consumes the new fields.

## Sharing Strategy

For the best long-term user experience, iOS share payloads should use the HTTPS URL as the durable identifier:

```text
https://merian.earth/explore/post/{postId}
```

The web page can include an "Open in Merian" button using:

```text
merian://explore/post/{postId}
```

Custom schemes are useful as an explicit button target, but they should not be the primary shared link. They do not unfurl well, they fail for recipients without the app, and they cannot serve public web previews.

## Theme Preference Bridge

Merian-owned web links opened by the signed-in iOS user may append a theme query
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

## Universal Links Roadmap

When the public site is deployed and the Apple association file is ready, promote the same HTTPS route into a Universal Link:

1. Add the Associated Domains entitlement to the app:

   ```text
   applinks:merian.earth
   ```

2. Serve the Apple App Site Association file at:

   ```text
   https://merian.earth/.well-known/apple-app-site-association
   ```

3. Include the `/explore/post/*` path in the AASA details.
4. Route incoming `NSUserActivityTypeBrowsingWeb` links through the same native Explore post router that currently handles `merian://explore/post/{postId}`.
5. Keep the web page as the fallback for users without Merian installed.

After Universal Links are live, the app should still tolerate the custom scheme because widgets, push actions, or older shared links may continue to use it.

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
npm run build
npm audit --audit-level=moderate
```

## Public Policy Pages

The public web app includes App Store-ready policy/support routes:

- `https://merian.earth/privacy`
- `https://merian.earth/privacy-choices`
- `https://merian.earth/terms`
- `https://merian.earth/guidelines`
- `https://merian.earth/support`
- `https://merian.earth/legal`

`/community-guidelines` redirects to `/guidelines`, and `/data-deletion`
redirects to `/privacy-choices`. Keep the iOS Settings community links pointed
at the `merian.earth` versions of these URLs. In-app Settings links may include
the `theme` query parameter; public share URLs should not.

## Maintenance Notes

- Keep `apps/web/.env.example`, `apps/web/README.md`, root `README.md`, and this doc aligned when adding public web routes or env variables.
- Keep Open Graph metadata server-rendered. Messages and social crawlers need HTML metadata before client-side hydration.
- Treat `apps/web/lib/explore.ts` as a public projection mapper, not a place to expose raw database rows.
- Prefer adding dedicated Supabase RPCs/views for web surfaces instead of querying broad private tables.
- Use `NEXT_PUBLIC_SITE_URL=https://merian.earth` in production so canonical and Open Graph URLs point at the real domain.
- If an Explore post is unshared, blocked, removed, or privacy-filtered out for the public viewer, the route should resolve to not found rather than showing stale metadata.
