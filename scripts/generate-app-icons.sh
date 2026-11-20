#!/usr/bin/env bash
# Export the approved masters without redrawing or distorting the artwork.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

command -v sips >/dev/null
command -v jq >/dev/null
command -v xcrun >/dev/null

masters="docs/design/app-icons/masters"
srgb="/System/Library/ColorSync/Profiles/sRGB Profile.icc"
gray="/System/Library/ColorSync/Profiles/Generic Gray Gamma 2.2 Profile.icc"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/naturebook-icons.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

# Keep one exact transparent master for all appearances. Composite opaque
# backgrounds with CoreGraphics; there is no AI redraw or JPEG intermediate.
xcrun swift -module-cache-path "$scratch/modules" \
  scripts/render-app-icon-backgrounds.swift "$masters/logo.png" "$scratch"
sips --matchTo "$srgb" "$masters/logo.png" \
  --out "$scratch/dark.png" >/dev/null
sips --matchTo "$gray" "$scratch/tinted.png" >/dev/null

export_catalog() {
  local catalog="$1"
  local filename width height appearance side actual_width actual_height
  local count=0
  while IFS=$'\t' read -r filename width height appearance; do
    side="$height"
    if (( width < height )); then side="$width"; fi
    # Fit the square artwork inside rectangular Messages slots on white.
    # Watch and iPhone keep the original framing; the OS applies its mask.
    sips --resampleHeightWidth "$side" "$side" "$scratch/$appearance.png" \
      --out "$catalog/$filename" >/dev/null
    if (( width != height )); then
      sips --padToHeightWidth "$height" "$width" --padColor FFFFFF \
        "$catalog/$filename" --out "$scratch/padded.png" >/dev/null
      mv "$scratch/padded.png" "$catalog/$filename"
    fi
    actual_width="$(sips -g pixelWidth "$catalog/$filename" | awk '/pixelWidth:/ {print $2}')"
    actual_height="$(sips -g pixelHeight "$catalog/$filename" | awk '/pixelHeight:/ {print $2}')"
    if [[ "$actual_width" != "$width" || "$actual_height" != "$height" ]]; then
      printf 'Incorrect export dimensions: %s\n' "$catalog/$filename" >&2
      exit 1
    fi
    count=$((count + 1))
  done < <(jq -r '.images[] | select(.filename) |
    ((.scale // "1x") | rtrimstr("x") | tonumber) as $scale |
    (.size | split("x") | map(tonumber * $scale)) as $size |
    [.filename, $size[0], $size[1],
     (.appearances[0].value // "default")] | @tsv' "$catalog/Contents.json")
  printf 'Exported %s icons: %s\n' "$count" "$catalog"
}

export_catalog "apps/ios/Merian/Assets.xcassets/App/AppIcon.appiconset"
export_catalog "apps/watch/MerianWatch/Assets.xcassets/AppIcon.appiconset"
export_catalog "apps/ios/messages/MerianMessagesExtension/Assets.xcassets/iMessage App Icon.stickersiconset"
