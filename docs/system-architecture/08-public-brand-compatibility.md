# Naturebook Public Brand and Compatibility Contract

Status: active  
Effective date: 2026-07-15  
Public product: Naturebook  
Permanent engineering identity: Merian

## Decision

Naturebook is the only product name presented to customers. Merian remains the
permanent technical identity of the existing application and its infrastructure.
This is an in-place rebrand of one app, not a new listing, bundle, account,
database, or subscription product.

Naturalist names may be used as internal release codenames. A codename must not
become a bundle identifier, module, target, database namespace, public domain,
analytics event, product identifier, or customer-facing label.

## Canonical Public Values

| Surface | Canonical value |
| --- | --- |
| Product | `Naturebook` |
| Subscription | `Naturebook Pro` |
| AI feature | `Naturebook AI` |
| Website | `https://naturebook.earth` |
| Support | `support@naturebook.earth` |
| Export sender | `Naturebook Data Exports <exports@naturebook.earth>` |
| Native URL scheme | `naturebook` |
| App Store primary category | Reference |
| App Store secondary category | Education |

The Foundation-only iOS source of truth is
`apps/ios/Shared/Branding/PublicBrand.swift`. Public web defaults live in
`apps/web/lib/site.ts` and `apps/web/.env.example`. New public values should use
these contracts instead of introducing local literals.

## Stable Technical Values

The following values intentionally remain Merian-based. Renaming them would
break update continuity, stored data, integrations, or operational history.

| Contract | Stable value or family |
| --- | --- |
| Xcode project and scheme | `Merian.xcodeproj`, `Merian` |
| Targets and modules | `Merian`, `MerianWatch`, `MerianExploreWidget`, `MerianMessagesExtension`, `merianTests`, `merianUITests` |
| Main bundle ID | `app.merian.Merian` |
| Extension bundle IDs | Existing `app.merian.Merian.*` identifiers |
| App Group | `group.app.merian.shared` |
| Keychain access group | `$(AppIdentifierPrefix)app.merian.shared` |
| SwiftData | `MerianSchemaV*`, `MerianMigrationPlan`, existing store names |
| Preferences and keychain | Existing `Merian_*`, `merian.*`, and related keys |
| Backend | Existing database, RPC, Edge Function, cron, storage, and source identifiers |
| Reference-image source | `source = 'merian'` |
| Durable media host | `media.merian.app` |
| Network headers | Existing `X-Merian-*` headers and technical User-Agent values |
| Analytics | Existing event names, properties, keys, and historical continuity |
| RevenueCat | Existing entitlement and product IDs |

Public labels derived from a technical value must still say Naturebook. For
example, a reference image may retain `source = 'merian'` while its visible
source label and license read `Naturebook` and
`Used with permission via Naturebook`.

## Display-Name Rules

- The iOS and Watch apps display `Naturebook` while `PRODUCT_NAME` remains
  `Merian` or `MerianWatch`.
- The Messages extension displays `Naturebook` while its executable and bundle
  ID remain unchanged.
- The widget feature name remains `Explore`; contextual copy uses phrases such
  as `Explore Naturebook`.
- App Intents, Siri phrases, notifications, permissions, onboarding, paywalls,
  sharing, accessibility, errors, exports, legal pages, support, and release
  notes use Naturebook.
- Subscription and IAP localizations use Naturebook Pro without changing
  product IDs.
- Legal text may retain the actual legal owner or Apple seller name where
  legally required. Product references in that text still use Naturebook.

The public rename is communicated through normal changelog and App Store
release notes. Do not introduce a forced rename modal.

## URL and Domain Contract

### Generation

New content emits only:

- `https://naturebook.earth/...` for share, referral, email, metadata, legal,
  and support links.
- `naturebook://...` when a native-only scheme is necessary.

HTTPS is preferred for user-to-user sharing because it provides a browser
fallback and link-preview metadata.

### Acceptance

The app accepts all four compatibility forms:

- `https://naturebook.earth/explore/post/{id}`
- `https://merian.earth/explore/post/{id}`
- `naturebook://explore/post/{id}`
- `merian://explore/post/{id}`

Species Dictionary links follow the same compatibility rule:

- `https://naturebook.earth/species/{speciesId}`
- `https://naturebook.earth/species/{speciesId}/{slug}`
- `https://merian.earth/species/{speciesId}`
- `https://merian.earth/species/{speciesId}/{slug}`
- `naturebook://species/{speciesId}`
- `merian://species/{speciesId}`

New species shares emit the canonical Naturebook HTTPS form with the normalized
dictionary UUID followed by a lowercase ASCII name slug. The UUID remains the
only identity and lookup key. UUID-only and stale-slug browser requests
permanently redirect to the current canonical path; native routing accepts the
optional slug but carries only the normalized UUID. Custom-scheme links remain
UUID-only.

Internal route types such as `MerianDeepLinkRoute` remain technical names.
Compatibility aliases are indefinite and must not be removed during ordinary
cleanup.

### Web hosts

`naturebook.earth` is the only canonical origin. These hosts permanently
redirect to the same path and query on the canonical origin:

- `naturebook.app`
- `www.naturebook.app`
- `www.naturebook.earth`
- `merian.earth`
- `www.merian.earth`

All hosts must be assigned to the same deployed Next.js project so
`apps/web/proxy.ts` can inspect the incoming host. A registrar-level redirect or
a Vercel domain redirect that runs before the application cannot implement the
AASA exception below.

### Apple App Site Association exception

The following endpoints must return HTTP 200 directly on both
`naturebook.earth` and `merian.earth`:

- `/apple-app-site-association`
- `/.well-known/apple-app-site-association`

They must not redirect. Both responses use app ID
`TA8S64ST9W.app.merian.Merian` and route the exact path list
`["/explore/post/*", "/species/*"]`. The app declares
`applinks:naturebook.earth` and retains `applinks:merian.earth`.
`naturebook.app` is redirect-only and is not an associated domain.

## Web and Metadata Contract

- Production sets `NEXT_PUBLIC_SITE_URL=https://naturebook.earth` and
  `NEXT_PUBLIC_SUPPORT_EMAIL=support@naturebook.earth`.
- Canonical, Open Graph, Twitter, structured-data, navigation, waitlist,
  support, legal, and native-open metadata use Naturebook.
- Public Explore pages consume only privacy-safe public projections. Public
  species pages consume only the existing versioned `species-dictionary` Edge
  response and publish only attribution-approved reference images.
- Public media continues to use `media.merian.app`; do not rewrite durable
  media URLs as part of the product rebrand.
- Alias redirects use HTTP 308 and preserve both path and query.

## Backend and Data Contract

- User-facing Edge Function responses and AI prompts use Naturebook.
- Darwin Core exports use Naturebook labels while preserving schema and source
  contracts.
- Outbound export mail uses the Naturebook sender after the domain is verified.
- The forward-only rebrand migration updates existing visible attribution,
  updates the generated reference-image attribution in the current refresh
  function, and reserves `naturebook` and `naturebookearth` while retaining
  `merian`.
- Historical migrations are immutable. Old Merian strings in an earlier
  migration remain historical evidence and are corrected by the forward
  migration.
- Do not rename tables, columns, RPCs, functions, cron jobs, storage paths,
  headers, analytics events, SwiftData schemas, preference keys, app groups,
  RevenueCat identifiers, or `source = 'merian'`.

## Apple Distribution Contract

The App ID description belongs to the Apple Developer identifier record under
Certificates, Identifiers & Profiles. It is not an App Store Connect metadata
field. There must be exactly one explicit App ID for the stable bundle ID:

| Apple Developer field | Value |
| --- | --- |
| App ID description | Naturebook iOS (Merian) |
| Bundle ID | `app.merian.Merian` |

If that App ID is not registered yet, register it with these values. If it
already exists, edit only its description. Never register a separate
Naturebook bundle identifier.

The existing App Store Connect record uses:

| Field | Value |
| --- | --- |
| Public app name | Naturebook |
| Bundle ID | `app.merian.Merian` |
| Primary category | Reference |
| Secondary category | Education |
| Marketing URL | `https://naturebook.earth` |
| Support URL | `https://naturebook.earth/support` |
| Privacy URL | `https://naturebook.earth/privacy` |

Apple documents the identifier description in
[Register an App ID](https://developer.apple.com/help/account/identifiers/register-an-app-id)
and the store name, immutable bundle ID, and categories in
[App information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/).

The listing remains the existing app. An update must install over an existing
Merian installation and retain the account, scans, subscriptions, App Group
data, Keychain state, SwiftData store, and preferences.

## Allowed Remaining Merian Occurrences

A repository-wide audit may retain a Merian occurrence only when it is one of:

1. A stable technical identifier listed in this document.
2. A legacy domain or URL-scheme compatibility alias.
3. An internal type, target, module, test target, file path, or operational log
   label.
4. An immutable historical migration or compatibility fixture.
5. The transition sentence: `Merian is now Naturebook...`.

Any occurrence in visible UI, generated links, email, metadata, support, legal,
attribution, exported content, or current release copy is a defect unless it is
the transition sentence.

## Change Review Checklist

When adding a new public surface:

1. Use `PublicBrand` or the web site configuration instead of a local product
   literal.
2. Emit only Naturebook URLs and the `naturebook` native scheme.
3. Preserve legacy parsing where the surface handles old links.
4. Keep technical identifiers unchanged unless a separate compatibility plan
   explicitly authorizes a migration.
5. Add focused generation and legacy-acceptance tests.
6. Update user-facing release notes when appropriate.
7. Run the branding audit in
   `docs/development-guides/15-naturebook-rebrand-rollout.md`.
