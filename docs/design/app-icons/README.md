# Naturebook app icons

The November 9, 2026 artwork is the clay-style green lowercase n with a monarch
butterfly, fern, mushroom, and stone. `masters/logo.png` is the product owner's
original 1024 × 1024 transparent PNG, preserved byte for byte. All native icons
derive from this one source, including its soft shadows. Exports composite and
resize the supplied pixels; they do not regenerate or redraw the artwork.

The superseded November 7 masters are retained in `archive/2026-11-07/` for
reference only and are not consumed by the exporter.

## Regeneration

On macOS, with Xcode and `jq` installed, run from the repository root:

```bash
bash scripts/generate-app-icons.sh
```

The exporter reads dimensions and scales from the existing `Contents.json`
manifests. The CoreGraphics helper composites the original over white for the
default appearance and black for tinted. The exporter preserves transparency for
dark, uses sRGB for color exports, and converts tinted to Gray Gamma 2.2. It
writes:

- Three 1024 × 1024 iPhone appearances in
  `apps/ios/Merian/Assets.xcassets/App/AppIcon.appiconset`.
- Eleven Watch exports in
  `apps/watch/MerianWatch/Assets.xcassets/AppIcon.appiconset`.
- Twelve Messages exports in
  `apps/ios/messages/MerianMessagesExtension/Assets.xcassets/iMessage App Icon.stickersiconset`.

Default, Watch, Messages, and tinted exports are opaque PNGs. The dark iPhone
export preserves the source alpha for the system-provided background. Watch uses
the default artwork with its original inset. Rectangular Messages exports fit
the square artwork proportionally and extend the white background sideways. Do
not stretch the n or bake rounded corners into the exported images.

These are asset-catalog icons, not a layered Icon Composer document. Clear
appearances use the system treatment. Review default, dark, and tinted icons on
a device, the Watch circle, and the Messages oval at small sizes before release.

After regeneration, run `make xcodegen`, `make validate-ios-project`, and a
simulator build through `make ios-local-build`; the main scheme embeds the Watch
and Messages targets. Distribution remains a separate release operation.
