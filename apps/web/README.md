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

Generic **Share Naturebook** actions are not referral links. Before the App
Store listing is live, iOS shares the served `https://naturebook.earth`
homepage. `lib/appShareContract.test.ts` locks that fallback across the Swift
source, canonical web origin, root page, and web-quality workflow. Once the
listing is publicly reachable, replace the explicit iOS TODO with the reviewed
App Store Connect campaign link; do not invent an `/invite` route unless a real
referral product is designed and deployed.

The Explore route fetches the public post and detail projections from Supabase
on the server, renders a rich read-only post page with Mantine components and
responsive observation styling, and emits Open Graph metadata so Messages/social
shares can render a clean preview. Unshared, administratively hidden,
tombstoned, blocked, and otherwise privacy-filtered posts resolve to the
application not-found page with non-indexable metadata; server code must not
reconstruct them from direct table reads. Standalone-audio post details and
social previews consume the persisted `media_items.thumbnail_url` spectrogram.
The Explore grid uses the public species reference thumbnail instead, with the
spectrogram as a legacy fallback. The public web app never downloads recordings
to calculate FFT data in a visitor's browser; blank or unsupported legacy
thumbnails retain the volume-icon fallback and normal `<audio>` playback.

Post-detail audio slides include an optional browser-local **Boost audio** mode.
Only boost requests use the allowlisted `/api/explore/audio` WAV stream; Web
Audio applies conservative gain, rumble filtering, and peak limiting without
uploading or changing the canonical recording.

The production domain is:

```text
https://naturebook.earth
```

Species pages are server-rendered from the existing privacy-safe
`species-dictionary` Edge Function. They publish only licensed reference imagery
with complete attribution and intentionally omit observations, Community
sightings, user media, locations, and scan-specific data.

Image captions link recognized Creative Commons terms and, for Wikimedia Commons
images, the exact source file page; GBIF credits link the supplied original
image. Missing rights are filled by the backend's durable species refresh, not
by browser or page-rendering fetches; see
`services/supabase/functions/refresh-species-content/README.md` for
existing-data refresh requirements. Uncredited images remain excluded from media
and metadata.

Embedded URLs in photographer credits render as labeled website or Creative
Commons license links, preserving names and destinations. Social-image captions
use the same readable labels; attribution never displays naked URLs.

## Public design direction

The homepage `/` is a full-screen public Explore canvas. Drag, touch pan,
trackpad scrolling and keyboard arrows move a stable square lattice of unique
public posts. A shared WebGL lens bends cards and gutters together; dragging
zooms the scene out by 6%, then settles with restrained momentum. Cards are
photo-only, open their existing detail route on activation, and have no hover
animation. Reduced motion and unavailable WebGL automatically use an ordinary
linked HTML grid; there is no Canvas/Grid/Refresh/Help toolbar. Rendering sleeps
when stationary or hidden, with four active image slots (at most eight requests
while fallbacks overlap), a 96-tile GPU cache, 512px textures and a 1.5
device-pixel-ratio ceiling.

`/explore` permanently redirects to `/`. `/about` owns the previous homepage:
decorative hero, feature previews, app details, beta invitation and full footer.
The butterfly wordmark remains centered at the top at every screen size. A
shared bottom-centered navigation pill contains Explore, About, Support and Join
beta (or the configured app-store action). Explore opens beta signup in the
existing modal; About retains its signup anchor. Other pages reserve bottom
space so the navigation does not obscure their footer. QR preview appears only
in the footer, never on the canvas. Legacy root `#about`, `#features` and
`#waitlist` anchors redirect to About. The following hero/motion descriptions
apply to **About**, including its `?hero=mesh` comparison.

Explore initially requests 48 posts through the additive service-only
`get_public_web_explore_posts_page` RPC. `GET /api/explore?cursor=…` returns
`{items: [{id, label, poster}], nextCursor, hasMore}`. Its versioned opaque
cursor preserves the exact database timestamp and UUID. Pages append in stable
expanding rings with ID deduplication; new publications appear on refresh.
Loading, failure, empty and end states are distinct. The homepage shell renders
immediately with curved neutral skeletons and requests the feed in the browser.
The initial SVG skeleton projects rounded squares through the same inverse lens
geometry used by WebGL; the renderer continues that geometry while photos load.
After a 1.2-second grace period, an unavailable, slow, or empty feed uses a
decorative nature preview from the 12 bundled About photographs. These preset
images are explicitly labeled as a preview and never open post links or enter
the public API response. A late successful feed replaces the preview. Reloading
starts a new feed session. The accessible grid retains its load-more and retry
controls for additional pages.

The canvas covers the full viewport behind the logo and navigation. Its visible
cell bounds include lens distortion and the 6% drag zoom-out. Cells beyond the
loaded feed are filled with decorative presets, never duplicated observations.
Photos use a 25% larger composition scale (starting at 300px on desktop and
188px on phones), retaining the 12px/8px gutters so fewer photos fill the view.
The preset-only canvas pans continuously; a real feed retains its loaded-region
pan limit with decorative coverage beyond that boundary. Very large viewports
increase card size enough to retain complete coverage within the 96-tile GPU
budget. Appending real posts replaces their corresponding decorative cells.

Each photo starts with a plain neutral-gray skeleton tile, with no center dot or
icon. Pending tiles pulse gently over two seconds in both WebGL and HTML; loaded
photos and failed placeholders remain still. Missing, failed or slow community
posters use a bundled preset after the same grace period; a later successful
community image replaces it. A card only opens its post once its actual image
has loaded, so decorative substitutes are never attributed to an observation.
Image failures retain a neutral tile if even the bundled preset is unavailable.
Reduced motion disables skeleton pulsing and image crossfades. WebGL failure
uses the same real/preset selection in the standard HTML grid.

WebGL posters use `/api/explore/poster/[postId]`: the server rechecks canonical
public visibility, permits only raster public-upload URLs on `media.merian.app`
or Wikimedia Commons, rejects redirects, limits fetching to 8 seconds/8 MiB, and
limits decoding to 16 megapixels. Sharp emits a maximum 512px WebP with a
3-second processing timeout. Unsupported sources use neutral placeholders. Both
API routes are `no-store`, accept no arbitrary media URL, and never expose
server credentials. No hosted CORS changes are required. The additive migration
must be applied through the authorized backend release before releasing this
frontend for full pagination. During that transition, only a first-page
`PGRST202` (missing pagination RPC signature) retries through the existing
`get_public_web_explore_posts` public projection, capped at 48 real posts with
no continuation cursor. Permission, network, and continuation failures remain
errors; there are no direct table reads. Each feed RPC has an 8-second deadline.
Missing server configuration uses the decorative preview; real community content
requires the Setup variables below. The preview needs no backend configuration
or infrastructure release.

The hero background uses neutral dots spaced 32px apart. With a fine hover
pointer, dots within a 180px radius gently spread outward, enlarge, and brighten
with a restrained local glow: the radius grows by at most 0.35px, opacity
increases by 0.12, and displacement stays below 4px. Damped springs ease the
response in and out, preserving momentum as the pointer moves. Scrolling
releases the existing effect with a slower spring instead of clearing the canvas
state; hover resumes on fresh pointer movement after scrolling settles. The
effect is decorative and does not intercept links or affect image positions.
Frames stop after settling and while offscreen or in hidden tabs. Touch and
reduced-motion users retain the static CSS dot pattern; the same pattern is
available before hydration or without canvas.

The default radial composition places 25 larger square photos on two loose
rings, with six smaller accents at varied distances between them. These 31
decorative slots reuse the same poster set without another feed request. The
extra accents are hidden in the compact layout, which retains its 25-square
composition. Each radial photo has a fixed, distinct tilt between -18 and +18
degrees, mixing clockwise, counterclockwise, and nearly upright orientations
around each ring. Scrolling gently opens the rings outward, increases their size
by at most 8%, and rotates them by at most another eight degrees. A bounded
scroll progress eases into place over roughly 180ms; there is no scroll pinning,
hover response, or autonomous idle motion in this version. Animation frames stop
once the position settles and while offscreen or in hidden tabs. Reduced motion
keeps the composition at its resting position. The desktop image viewport has no
edge masks or bottom fade: photos remain fully visible up to the clipped section
bounds. The floating butterfly and wordmark use a soft, theme-aware drop shadow
for contrast as content scrolls behind them; there is no full-width header fade.
At widths of 768px and below, the same photos form the composed square mosaic
below the centered copy, with varied sizes, close consistent gutters, and no
rotation. Only this compact mosaic has a 48px top fade and 56px bottom fade,
blending into the copy area and next section while leaving the sides fully
visible. The mosaic translates upward by at most 24px on scroll as one surface,
preserving its spacing. Resizing switches between the mosaic and rings without
reloading images. Both layouts share the same poster set, loading/fallback
behavior, and server query.

The `?hero=mesh` comparison preserves the previous interactive mesh; all other
query values select radial. The following mesh motion details apply only to that
optional comparison. The hero uses a complete tiling of 25 true squares in three
sizes, with sides spanning approximately 2.10:1. The mix includes 12 medium, 3
larger, and 10 smaller squares; the size contrast remains restrained while the
enlarged tiles need fewer images. A single non-repeating composition distributes
the size hierarchy with staggered T-junctions, interrupting long horizontal and
vertical seams. Smaller squares fill the spaces around larger images, leaving a
consistent narrow gutter along every shared edge and no unfilled pockets. Slots
stay stable during image loading and interaction. Hover and idle pulses reshape
a coupled mesh of true squares. Precomputed responses preserve the resting
gutter along every shared edge, with diagonal junction constraints preventing
pinched corners. Neighbouring frames grow, shrink, and translate together; the
composition never repacks or switches separation axes. Each full square uses
compositor translation and scale, preserving source framing without zooming
inside the image. A damped spring (natural frequency 6 radians/second, damping
ratio 0.82) preserves momentum during hover handoff and release with a barely
perceptible settle.

Idle motion flows through a distributed nine-image sequence. Each 12-second
handoff gently settles the outgoing image while the next begins growing, with
complementary easing and no resting pause. At most two focus responses overlap;
their combined strength stays constant, preserving the shared gaps and avoiding
an extra swell during handoff. The largest relative size change is bounded to
approximately 2.9%; some connected squares respond together to retain their
shared spacing. Hover adds emphasis to the selected tile's current idle focus
and pauses the idle clock; release springs back to the idle sequence without
resetting its phase. The whole composition also drifts on 84/104-second cycles,
bounded to 24 pixels horizontally and 15.6 pixels vertically. Hover adds at most
6 pixels of eased pointer movement at the current drift position. Overscan keeps
the viewport covered. Motion pauses offscreen and in hidden tabs; reduced motion
keeps the mosaic static. The same poster set fills all slots without another
feed request. The grid has no caption or playback controls. Hover hit testing
samples the same fade artwork, so nearly transparent edges do not attract the
focus. Motion stops offscreen and in hidden tabs; reduced-motion preferences
render a static grid. The decorative hero reuses poster URLs from the same
24-post server result, with no additional feed query. Accessible discovery cards
are available on `/`. The page shell streams before that query finishes; the
hero starts with quiet skeleton tiles and gives Explore 1.2 seconds to load. An
empty or failed feed, failed image, or elapsed grace period selects bundled
decorative nature photography for unresolved tiles. Decoded Explore photos
crossfade in over 600 ms, including late arrivals, without rebuilding the grid.
Successfully loaded Explore tiles never download their fallback. Reduced motion
disables the fade as well as tile resizing. Fallback photos have no observation
labels, authors, or post links; their sources and license are recorded in
`public/assets/hero-nature/README.md`. Discovery cards emphasize square photos
with unframed captions, species labels, identification context, and public
author username handles. They render the current server-fetched public Explore
projection; an empty feed shows an explicit empty state rather than sample
observations. The decorative About fetch limit remains 24; the Explore feed
paginates at 48.

The “Discover nature, your way” feature row follows the hero. Five illustrative
previews cover identification, listening, keeping records, community discovery,
and choosing public posts. They use bundled decorative photos and CSS motion,
not real observation data, recordings, or production interface captures. Each
preview loops automatically while visible, without play/pause icons or button
semantics. Its loop pauses offscreen or in hidden tabs and resumes at the same
phase. Reduced motion keeps the illustrations static. The horizontal row
supports swipe/scroll and previous/next controls. Production clips can replace
each `FeaturePreview` without changing the card structure. The expanded footer
combines a large invitation, existing navigation links, and an explicitly
labeled, nonfunctional QR preview awaiting an approved app link. No login,
search, or store destination is invented for this presentation.

The shared header, mobile navigation, footer, and Mantine theme extend the
neutral identity to reference, share, and policy pages. Light/dark preferences
remain supported, with charcoal surfaces in dark mode and restrained forest
accents. The observation page places its square media carousel beside the
identification and author information on desktop, stacking them on mobile.
Supporting content uses readable sections separated by subtle rules. Hazard
notices, identification provenance, source links, media behavior, and reporting
remain available. Footer links point only to existing routes or homepage
anchors.

`ButterflyMark` renders the transparent butterfly in the header. The header
wordmark remains live text beside the butterfly at every screen size. A native
`<picture>` selects the animated WebP only for
`prefers-reduced-motion: no-preference`; reduced motion and browsers without a
matching source use the static PNG. Selection works before hydration and updates
when the system preference changes. The animation retains the two gentle
flutters and pause in a 4.7-second loop. The footer always uses the static PNG,
regardless of motion preference.

The header renders the mark at 40 CSS pixels on desktop and 28 on mobile.
Animated WebP sources at 40, 84, and 120 pixels let the browser select a
suitable resolution up to 3× density without downloading the original 512-pixel
export. All variants preserve the 50 fps motion samples, transparency, and loop
timing; the resting pose uses a single extended frame. Keep the `<source>` sizes
aligned with the header's rendered dimensions when changing its layout.

The existing Turnstile-protected waitlist form appears once on the homepage,
inside its closing invitation. Secondary pages open that same form in the header
modal. When the App Store URL is configured, download actions replace the beta
invitation. Public sharing and mandatory Scientific Data contribution remain
separate concepts in the homepage copy, with a link to the current privacy
choices. No data access, API, or deployment configuration changes accompany this
design.

## Setup

```bash
cd apps/web
cp .env.example .env.local
npm ci
npm run dev
```

If `npm run dev` reports `next: command not found`, install dependencies from
inside `apps/web` first:

```bash
cd apps/web
npm ci
```

Required server-side variables:

- `SUPABASE_URL`
- One privileged Supabase server key: `SUPABASE_SERVER_API_KEY=sb_secret_...` is
  preferred. The platform-managed `SUPABASE_SECRET_KEYS` dictionary is also
  supported when present; `SUPABASE_SERVICE_ROLE_KEY` remains a legacy
  service-role JWT migration fallback. The server-only client rejects public or
  malformed values and gives every Supabase SDK request a 30-second hard
  deadline. A configured malformed explicit override fails; once a valid
  higher-priority source is selected, an unrelated malformed lower migration
  source cannot veto it.
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
  header at the trusted ingress; never trust a client-appended forwarding chain.

Optional public variables:

- `NEXT_PUBLIC_SITE_URL` — set to `https://naturebook.earth` in production.
- `NEXT_PUBLIC_APP_STORE_URL` — leave unset before launch so the site retains
  its waitlist CTA. Once the listing is public, set the reviewed App Store
  Connect campaign link and update the matching iOS app-share TODO/contract.
- `NEXT_PUBLIC_SUPPORT_EMAIL` — set to `support@naturebook.earth` in production.
- `NEXT_PUBLIC_POSTHOG_API_KEY` — optional public ingestion key for privacy-safe
  web playback events

Optional server/public fallback variables:

- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`

Every privileged server-key format must stay server-side only. Do not prefix one
with `NEXT_PUBLIC_`.

### Environment Ownership Boundary

Configure only the variables listed above. Do not bulk-copy the GitHub
`Production` environment into Vercel. In particular, this web application does
not consume and must not receive:

- `DWCA_PSEUDONYM_HMAC_KEY_V1`
- `REVENUECAT_SECRET_API_KEY`
- `REVENUECAT_WEBHOOK_SECRET`
- `REVENUECAT_WEBHOOK_SIGNING_SECRET`
- `SUPABASE_ACCESS_TOKEN`
- `SUPABASE_DB_PASSWORD`
- `SUPABASE_DB_URL`

The deployment workflow uses the last three values to operate Supabase and
synchronizes the DwC-A and RevenueCat values into Supabase Edge. They are not
web application configuration. `SUPABASE_URL` above is the HTTPS project API
endpoint; do not substitute the privileged PostgreSQL `SUPABASE_DB_URL`.

Keep production server secrets in Vercel's Production environment only. Use a
separate staging Supabase project and Turnstile widget if preview deployments
need live backend behavior. See the canonical destination matrix in
[`docs/development-guides/05-keychain-and-secrets.md`](../../docs/development-guides/05-keychain-and-secrets.md#deployment-environment-ownership).

### Supabase client compatibility

Supabase JS is pinned to 2.117.2. Public and privileged clients retain their
separate credential boundaries; the privileged factory stays server-only and
removes only the opaque API-key-as-Bearer fallback.

See the
[SDK release notes](https://github.com/supabase/supabase-js/releases/tag/v2.117.2).
Dependency upgrades must preserve authentication, cookie, and request-transport
behavior.

### TypeScript compiler

Both `npm run typecheck` and Next.js builds use the pinned native TypeScript
7.0.2 CLI. `experimental.useTypeScriptCli: true` is explicit in
`next.config.ts`; keep build-time type checking enabled. TypeScript 7 does not
provide the legacy JavaScript compiler API. See Microsoft's
[TypeScript 7 migration guidance](https://devblogs.microsoft.com/typescript/announcing-typescript-7-0/#running-side-by-side-with-typescript-60).

### Dependency maintenance

All direct Mantine packages are pinned together at 9.6.2. Dependabot groups
minor and patch updates because Mantine uses exact peer versions. Node types
remain on the supported Node 24 major. React and React DOM are paired at 19.3.0
with matching 19.3 type declarations; Dependabot groups those packages and the
dependency tests reject mismatched runtime versions. The lockfile also resolves
`baseline-browser-mapping` to 2.11.25, above the 2.11.0 fix for
[invalid-input process termination](https://github.com/advisories/GHSA-w5vr-8v7q-w6rv).
Follow the
[dependency maintenance policy](../../docs/CONTRIBUTING.md#dependency-maintenance)
and retain the complete frozen-install, audit, test, type-check, and build gate.

### Web Security Boundary

The package pins the reviewed Next.js release exactly; do not replace it with a
range or `latest`. Use `npm ci` so CI and production consume the committed lock
file. Next.js 16.3.8 also fixes the
[next/og ImageResponse RCE](https://github.com/vercel/next.js/security/advisories/GHSA-vcvr-r3jv-pc5j).
It retains the fixes for the reviewed
[Windows-hosted RCE](https://github.com/advisories/GHSA-p293-qw3h-jr36) and
[AVIF image-optimization RCE](https://github.com/advisories/GHSA-2xp9-vwfh-vxw4).
Next still declares an older PostCSS release, so the manifest overrides that
edge and retains an exact reviewed Sharp pin. Do not remove security constraints
merely because image optimization is disabled or CSS inputs are currently
trusted.

The Next PostCSS 8.5.28 override covers both
[attacker-controlled source-map file reads](https://github.com/advisories/GHSA-6g55-p6wh-862q)
and the remaining
[source-map path traversal](https://github.com/advisories/GHSA-r28c-9q8g-f849).
The Sharp override tracks 0.35.5, which includes the patched librsvg release for
[SVG memory safety](https://github.com/advisories/GHSA-wq5f-xc86-pv6w) and
retains the earlier
[libheif fixes](https://github.com/advisories/GHSA-rgj7-g3m4-5g8c). The direct
Tiptap packages are pinned together at 3.31.3 to cover both the
[attribute prototype issue](https://github.com/advisories/GHSA-cp6q-959q-f8rh)
and [Markdown parser ReDoS](https://github.com/advisories/GHSA-j95f-988m-3j2f).
The lockfile also excludes the affected
[CSS selector parser releases](https://github.com/advisories/GHSA-w9m9-85wc-3x92).
`lib/dependencySecurity.test.ts` enforces the reviewed Next.js 16.4.6, PostCSS
8.5.25, Sharp 0.35.5, Tiptap core 3.30.5, and selector parser 7.1.3 floors,
explicit Next overrides, and the workflow audit step. Dependency update pull
requests must run the full dependency audit, test, type-check, and
production-build gate.

`proxy.ts` generates one cryptographically random nonce per request and places
the same nonce-based Content Security Policy on the request passed to Next.js
and the response returned to the browser. `app/layout.tsx` reads that nonce
through `headers()` and supplies it to the only intentional inline bootstrap
script. The policy uses `'strict-dynamic'`, rejects plugins and framing, limits
forms and base URLs to this origin, and upgrades mixed content in production.
This nonce contract intentionally makes application pages dynamically rendered.
Never add `'unsafe-inline'` to `script-src`; add a nonce-bearing Next `Script`
only when an inline script is unavoidable.

Every response also receives `Referrer-Policy`, `X-Content-Type-Options`,
`X-Frame-Options`, `Permissions-Policy`, and cross-origin isolation headers.
Production HTTPS responses additionally receive HSTS. Keep
`lib/securityHeaders.test.ts` synchronized with any policy change.

Supabase clients have two explicit trust levels:

- `lib/supabasePublic.ts` contains only the anonymous client used for explicitly
  public Data API reads such as species content. It is not an Explore fallback.
- `lib/supabaseAdmin.ts` imports `server-only` and is the sole owner of
  privileged server-key environment access. `lib/serverApiKey.ts` validates
  platform-shaped `sb_secret_...` values, including a URL-safe opaque suffix of
  at least 20 characters, and complete legacy HS256 `service_role` JWTs before a
  client can be created; a publishable, anon, user, truncated placeholder, or
  malformed selected value fails closed. Sources are evaluated independently at
  their priority points so stale lower migration fallbacks cannot veto a valid
  selected key.

Explore uses the privileged client only to invoke the two narrowly scoped
public-web RPCs. It must never use that client for direct Explore, scan, user,
or taxonomy table reads.

Do not merge these modules or export an admin-capable default client. Server
routes must import the admin module directly, while public projection readers
must use the anonymous module. `lib/supabaseBoundary.test.ts` prevents
service-role imports from crossing that boundary.

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
key. A successful challenge permits the separate `submit_beta_waitlist_signup`
call. Direct table access is revoked. PostgreSQL atomically enforces tighter
verified limits of 5 attempts per IP/10 minutes, 20 per IP/day, and 2,000 new
unique addresses globally/day. Duplicate addresses receive the same success copy
and consume only the verified IP budget, preventing address enumeration and
unbounded table growth. Turnstile tokens, raw IP addresses, and emails must not
appear in logs.

Errors use stable `code` and server-generated `request_id` fields, plus the same
ID in `X-Request-ID`. A `429` includes `Retry-After: 600`; internal database or
provider details are logged privately and never returned.

## Vercel Deployment

Configure the Vercel project as a monorepo app:

- **Root Directory**: `apps/web`
- **Framework Preset**: Next.js
- **Build Command**: `npm run build`
- **Install Command**: `npm ci --include=dev`
- **Canonical production domain**: `naturebook.earth`
- **Redirect aliases**: `naturebook.app`, `www.naturebook.app`,
  `www.naturebook.earth`, `merian.earth`, and `www.merian.earth`

All aliases must be assigned to the same Vercel project that builds from
`apps/web`; do not configure provider-level redirects in front of the app.
`naturebook.earth` must be the project's primary production domain. `proxy.ts`
issues permanent path- and query-preserving redirects to `naturebook.earth`. It
constructs every destination from the fixed canonical origin and assigns the
pathname and query independently, so path syntax cannot replace that origin. The
two Apple App Site Association paths on the exact `naturebook.earth` and
`merian.earth` hosts are served directly with HTTP 200. They must never pass
through a host redirect. A plain Vercel response like:

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
permanently redirect to the matching path and query on `naturebook.earth`. All
four AASA checks must return HTTP 200 directly with JSON content and no
redirect. The AASA payload must continue to use `TA8S64ST9W.app.merian.Merian`
with the exact path list `["/explore/post/*", "/species/*"]`.

For a real species UUID, also verify the UUID-only and stale-slug Naturebook
paths return a permanent redirect to the current UUID-plus-slug canonical path.

## Scripts

```bash
npm run dev
npm test
npm run typecheck
npm run build
npm run audit:dependencies
```

`.github/workflows/web-quality.yml` runs a frozen install that explicitly
includes the pinned TypeScript build toolchain, a registry-backed dependency
audit that blocks high and critical findings, unit tests, TypeScript, and a
production build when the web route, its security helpers, the waitlist
migration, or the workflow changes. A registry outage is a failed security gate,
not an implicit pass.

## Share URL Shape

Use this public URL in iOS share payloads:

```text
https://naturebook.earth/explore/post/{postId}
https://naturebook.earth/species/{speciesId}/{slug}
```

Universal Links are active, meaning the HTTPS URL opens the native iOS app when
installed, and gracefully falls back to the public web preview otherwise.

The web page includes a native-app CTA using:

```text
naturebook://explore/post/{postId}
naturebook://species/{speciesId}
```

Keep the HTTPS URL as the primary shared link so recipients without the app
still get a real page and a rich Open Graph preview.

## Theme Preference Bridge

Naturebook-owned links opened from the iOS app may append:

```text
?theme=light
?theme=dark
?theme=system
```

The web app maps `system` to Mantine's `auto` color scheme and stores the value
in Mantine's color scheme storage key before hydration. Public share links
should omit this parameter so recipients see their own browser/system
preference.

## Public Routes

- `/` — Naturebook homepage with decorative hero imagery, features, and beta
  invitation.
- `/explore` — recent public community discoveries with links to individual
  posts.
- `/explore/post/[postId]` — public Explore share page. The MVP is read-only:
  anonymous visitors can view post context and send a support-email report from
  the centered action below the Taxonomy card, but cannot like, comment, reply,
  follow, or edit from the web page. Engagement counts are intentionally omitted
  from the public detail presentation. Ordered image, video, and audio media
  appear in the detail carousel. Its active video autoplays muted and inline on
  a continuous loop with native controls, while inactive videos pause and
  rewind. The Explore grid remains poster-only and uses species reference images
  for audio posts. Audio detail slides retain their spectrogram, bottom-anchored
  controls, and optional browser-local Boost Audio toggle.
- `/species/[speciesId]/[slug]` — public Species Dictionary reference page. The
  lowercase ASCII slug is derived from the common name, with the scientific name
  and then `species` as fallbacks; it is descriptive only and never used for
  lookup. UUID-only and stale-slug requests permanently redirect to the current
  canonical path. Successful pages revalidate every five minutes, emit
  canonical/Open Graph/Twitter metadata, link similar species textually, and
  filter every rendered or metadata image through the shared attribution audit.
  Invalid IDs and missing species are non-indexable 404s; transient Edge
  failures remain server errors.
- `/api/explore/audio?url={canonicalWavUrl}` — range-capable same-origin stream
  used only by Boost Audio. It accepts canonical public Naturebook WAV URLs on
  the stable `media.merian.app` infrastructure host, is not a general media
  proxy, and stores no derived audio.
- `/apple-app-site-association` and `/.well-known/apple-app-site-association` —
  served Apple App Site Association file for iOS deep linking capabilities.
- `/privacy` — App Store privacy policy URL.
- `/privacy-choices` — App Store privacy choices URL, data deletion help, and
  the mandatory ownerless scientific-observation retention boundary.
- `/terms` — Terms of Service, including the mandatory Scientific Data
  contribution and account-deletion retention terms.
- `/guidelines` — Community Guidelines. `/community-guidelines` redirects here.
- `/support` — support/contact page.
- `/legal` — hub linking the legal and support pages.
- `/data-deletion` — redirects to `/privacy-choices`.

## Privacy Notes

The Explore page is server-rendered through the dedicated service-only
projections. `get_public_web_explore_post_detail(...)` independently requires
membership in canonical anonymous `explore_projected_post_cards(NULL)`, while
`get_public_web_explore_post_page(...)` returns card and detail from one
statement/MVCC snapshot. `fetchExplorePostPage(...)` uses only the combined
routine. Browser `anon` and `authenticated` roles cannot invoke any of these
server routines directly. Engagement counts are zero and viewer/ownership flags
are false.

Do not replace the combined routine with sequential calls or direct service-key
table reads. Exact-SHA promotion evidence is tracked in the
[release assurance record](../../docs/backend-and-data/14-dwca-and-public-web-release-hold-2026-07-27.md).

Every submitted scan contributes Scientific Data. Account deletion removes the
account, attribution, media, private notes, semantic/public location labels,
custom tags, and device context, but retains the ownerless observation's exact
coordinates/elevation, time, taxonomy, identification, environmental, quality,
and provenance facts in the restricted backend. This retention is a condition of
the Service without a separate opt-in or opt-out. Public surfaces remain
governed by geoprivacy, sensitive-taxon projection, and tombstone exclusion.

The page may consume the resulting public image, species labels, public author
identity, shared timestamp, privacy-filtered location/telemetry, public field
notes, normalized hashtags, reference images, overview text, conservation
status, taxonomy labels, and alternate names. If the projection supplies
`author_username`, render it as `@username` on Explore cards, post details, and
avatar alt text. Missing or blank usernames use "a Naturebook observer"; never
fall back to `author_name`. Do not expose exact coordinates, private field
notes, raw scan telemetry, auth data, private email, or server credentials.
Never reconstruct an Explore response with direct service-role table queries.

Species pages consume only the versioned public payload returned by the
`species-dictionary` Edge Function with `species_id`. Server code must not query
broad species, scan, profile, or Explore tables to reconstruct that payload.
Similar-species thumbnails are intentionally omitted because the current
lookalike payload does not carry the required license and attribution fields.

The Explore share page uses Mantine components with scoped observation layout
classes in `app/globals.css`. Post visibility must come exclusively from the
canonical card projection contract. In particular, do not bypass its
moderation/publication/media-health rules with the detail RPC, service-role
table queries, or cached page data.

See `../../docs/system-architecture/08-public-brand-compatibility.md` for the
permanent brand and compatibility contract,
`../../docs/development-guides/15-naturebook-rebrand-rollout.md` for production
rollout and rollback steps, and
`../../docs/features-and-hardware/17-public-web-share-pages.md` for the full web
and Universal Link implementation contract.

## Identification labels

Explore cards and post detail consume the optional public identification
rank/source projection through `lib/exploreIdentification.ts`. Broader groups,
observer selection and community labels are explicit; detail preserves original
AI labels separately. Malformed present metadata fails closed. Broader/community
labels cannot substitute a species reference thumbnail or reference carousel.
Legacy payloads with no identification metadata retain their presentation.

### Indexed source-map dependency floor

The frozen graph requires `source-map-js` 1.2.2 or newer to exclude the reviewed
[indexed source-map event-loop denial of service](https://github.com/advisories/GHSA-68fv-2mgg-jv7q).
The package security contract checks every resolved copy. Preserve the blocking
dependency audit and complete frozen-install, test, type-check and production
build sequence when updating this transitive dependency.

### Sharp native dependency floors

The Sharp security contract also checks every optional `@img/sharp-*` artifact,
including nested copies: native bindings must be at least 0.35.5 and bundled
libvips packages at least 1.3.4. A patched JavaScript wrapper alone does not
satisfy this decoder boundary.

The October 7, 2026 dependency review pins Next.js 16.3.8 for the
[security patch release](https://github.com/vercel/next.js/releases/tag/v16.3.8),
including Image Optimization SSRF and cache-isolation fixes. Existing PostCSS
and Sharp overrides remain unchanged; the dependency audit is not bypassed.

## Website review quarantine

The infrastructure release includes
`20261108185855_quarantine_public_web_explore.sql`. Public web card, pagination,
and detail readers exclude posts with an `open` or `in_review` post case or
identification case, plus scans whose `is_flagged` remains true. Native Explore
visibility and reporter-specific preferences are unchanged. The grouped review
case is authoritative: source report rows can still say `PENDING_REVIEW` after a
moderator dismisses the case. Clearing a case restores eligibility only if every
other publication, moderation, media, tombstone and identity rule passes.
Existing repeat-reporter behavior is preserved: additional evidence from the
same reporter does not reopen a cleared case; a new independent reporter does.

`get_public_web_explore_visibility(p_post_ids UUID[])` is service-only, accepts
1–128 non-null IDs, and returns only eligible IDs through the canonical
anonymous projection plus the website quarantine rule. It exposes no report or
case data. The website uses `GET /api/explore/visibility?ids=…` for bounded
rechecks and `GET /api/explore/changes?ids=…` for scoped SSE eligibility
snapshots. Both are no-store and validate the same UUID/count bounds. Streams
recheck those IDs every two seconds, end after 50 seconds with an explicit
reconnect event, cancel work on disconnect, and cap active streams at 16 per
server instance. Each database request has a three-second deadline; at most 32
visibility queries run concurrently per server instance. Sequential polling
rounds have a five-second total budget. This is bounded server polling delivered
through SSE, not a database Realtime subscription or a global moderation feed.
Deployment-level traffic/rate limits remain necessary for these public
endpoints.

Open canvas, HTML grid, About hero and post-detail pages use expiring visibility
approval. A removal unmounts detail media and disposes canvas textures/cancels
image requests while retaining the cell position with a decorative replacement.
There is no stock image attributed or linked to the removed post. Pages start
closed until checked, clear approval on stream/check failure or tab hiding, and
recheck on return/back-forward navigation. Streams normally deliver changes in
roughly two seconds plus request latency; six-second approval leases fail closed
if updates stall. Sessions over 128 IDs, or unavailable SSE, use sequential
128-ID requests every two seconds without overlapping checks. A stalled or
failed stream is closed before polling takes over, so queued old frames cannot
restore withdrawn content. Post details are dynamic/no-store, including
metadata, instead of retaining the former five-minute ISR cache.

This does not retract previously downloaded media, external social previews, or
copies saved by a visitor. The web support-email report link is not database
intake; quarantine starts when a report/flag is accepted into the existing
review system. Backend migration application must precede the frontend release.
A missing visibility RPC fails closed to decorative previews/unavailable detail;
there is no legacy visibility bypass. Prepare and validate locally; no
production migration or deployment is authorized by this implementation.
