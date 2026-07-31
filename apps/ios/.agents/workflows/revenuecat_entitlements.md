---
description: Configure and verify Naturebook App Store products and RevenueCat offerings
---

# RevenueCat Products and Offerings

Use the existing App Store Connect app and permanent bundle ID
`app.merian.Merian`. A new in-app purchase or subscription is a product under
that app; it is never a reason to create another app record, bundle ID,
RevenueCat app, customer identity, or Supabase entitlement namespace.

The canonical product, identity, store-testing, and webhook contract is
[`02-revenue-and-identity.md`](../../../../docs/features-and-hardware/02-revenue-and-identity.md).
The iOS release path is canonical in
[`14-ios-release-versioning.md`](../../../../docs/development-guides/14-ios-release-versioning.md).

## Current Product Contract

`RevenueCatOfferingPolicy` requires the current offering to resolve both
existing App Store product identifiers:

- `pro_week`: seven-day non-renewing pass; intentionally not a RevenueCat
  entitlement
- `pro_annual`: recurring subscription mapped to the existing `pro`
  entitlement

Do not rename these identifiers, the `pro` entitlement, the current offering,
or package mappings for a routine pricing or localization change. Existing
customers and webhook history depend on stable identities.

## Adding or Changing a Product

1. Make the product change under the existing Naturebook App Store Connect app.
   Complete agreements, tax/banking, localization, pricing, and product
   readiness before diagnosing client fetches.
2. Import/map the exact product in the existing RevenueCat iOS app. Attach it to
   an explicit package in the approved current offering and preserve the
   Supabase Auth UUID as RevenueCat App User ID.
3. If the identifier changes the two-product client policy, update
   `RevenueCatOfferingPolicy`, paywall presentation, webhook reconciliation,
   documentation, and unit tests in one reviewed pull request. Dashboard-only
   changes must not silently diverge from the checked-in policy.
4. Never put `REVENUECAT_SECRET_API_KEY`, webhook bearer/HMAC values, Apple
   signing material, or App Store Connect API keys into the iOS target or an
   app-facing `.xcconfig` file.

## Verification

Choose one store source deliberately:

- local Debug may use RevenueCat Test Store products with a `test_` SDK key;
- an intentionally attached local `.storekit` file uses the production iOS
  `appl_` key and the exact policy identifiers; and
- physical Apple sandbox and TestFlight use the production `appl_` key with
  App Store Connect products imported into RevenueCat.

The shared scheme currently has no `.storekit` file attached. A successful
RevenueCat login proves customer identity only. Complete verification requires
both packages to load in Settings → Plan, purchase and restore to succeed, the
matching customer to appear under the Supabase Auth UUID, and the signed
RevenueCat webhook to update durable Supabase access.

Publish any distributable test only with the serialized **iOS TestFlight
Publisher** after exact-SHA compiled CI passes. Never use a local archive,
Fastlane lane, or dashboard change as proof that the final signed product
mapping works.
