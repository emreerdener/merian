export type HeroMask = Pick<ImageData, "width" | "height" | "data">;
export type HeroLayout = "desktop" | "stacked" | "centered" | "radial";

/** Sample only the bundled fade artwork, never Explore photos. */
export async function loadHeroMask(
  layout: HeroLayout,
): Promise<HeroMask | undefined> {
  try {
    const image = new Image();
    image.src = `/assets/hero-fade-${layout}.svg`;
    await image.decode();
    const canvas = document.createElement("canvas");
    canvas.width = canvas.height = 256;
    const context = canvas.getContext("2d", { willReadFrequently: true });
    if (!context) return;
    context.drawImage(image, 0, 0, canvas.width, canvas.height);
    return context.getImageData(0, 0, canvas.width, canvas.height);
  } catch {
    // If sampling is unavailable, keep drifting instead of pausing invisible tiles.
    return;
  }
}

export function isHeroPointVisible(
  mask: HeroMask | undefined,
  layout: HeroLayout,
  x: number,
  y: number,
): boolean {
  if (
    !mask || !Number.isFinite(x) || !Number.isFinite(y) ||
    x < 0 || x >= 1 || y < 0 || y >= 1
  ) return false;
  const index = (Math.floor(y * mask.height) * mask.width +
        Math.floor(x * mask.width)) * 4 + 3;
  // Include the narrow seam feathers composed with the SVG in ExploreHero CSS.
  const feather = Math.min(1, (1 - y) / 0.05) *
    (layout === "stacked"
      ? Math.min(1, y / 0.05)
      : layout === "desktop"
      ? Math.min(1, x / 0.04)
      : 1);
  return mask.data[index] / 255 * feather >= 0.3;
}
