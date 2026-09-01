# Insight Shared

`Shared` is intentionally narrow. It contains only presentation that is reused
by multiple Insights subareas and still depends on Insight-specific semantics.
The current owner is `Components/InsightDescriptionSheet.swift`.

Code used by another top-level feature does not belong here:

- Domain-neutral cards, feedback banners, the model-tier badge, and toolbar
  chrome live in `Core/UI`.
- Shared audio/video playback, fullscreen galleries, and media-export transport
  live in `Core/Media` and `Core/UI/Components/MediaCarousel`.
- Observation charts, habitat, heatmaps, taxonomy, lookalikes, and reference
  image loading live in `Features/SpeciesReference`.
- Private conversation UI, including `FieldChatToolbarButton`, lives in
  `Features/FieldChat`.

Do not use `Shared` as a holding area. A declaration belongs here only when it
has at least two Insights consumers, no consumer outside Insights, and no more
specific product-area owner.

## Complimentary result presentation

`Core/UI/Components/ModelTierBadge.swift` is a render-only cross-feature
component. `BiologicalView` derives `ModelTierBadgePresentation` from the
environment-provided RevenueCat and entitlement owners, and Insight Shell owns
the paywall presentation. The badge itself performs no singleton lookup and does
not own a sheet.

For a verified unpaid account, Results shows the server-reported Pro scans
remaining. After the third usable Pro result, it shows the existing upgrade
label; it does not hide or redact the stored Pro content. Paid accounts do not
see the complimentary prompt. See
[Three Complimentary Pro Scans](../../../../../../docs/backend-and-data/18-complimentary-pro-scans.md).
