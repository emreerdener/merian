import { HERO_TILES, heroGridLayout } from "./heroFocus.ts";

// Mix both tilt directions around each ring instead of progressing through
// similar angles. Fixed values keep the composition stable across renders.
const ANCHOR_ROTATIONS = [
  -13,
  7,
  -3,
  15,
  -8,
  2,
  -16,
  10,
  -5,
  18,
  -11,
  4,
  -18,
  12,
  -1,
  9,
  -14,
  3,
  17,
  -6,
  11,
  -17,
  5,
  -10,
  14,
];

// Smaller accents fill perimeter gaps, leaving the copy and CTA area open.
const RADIAL_ACCENTS = [
  { angle: 249, radius: 0.38, scale: 0.48, rotation: -9 },
  { angle: 282, radius: 0.36, scale: 0.43, rotation: 6 },
  { angle: 180, radius: 0.49, scale: 0.46, rotation: 8 },
  { angle: 357, radius: 0.49, scale: 0.5, rotation: -12 },
  { angle: 101, radius: 0.41, scale: 0.44, rotation: -7 },
  { angle: 69, radius: 0.4, scale: 0.47, rotation: 16 },
];
export const HERO_RADIAL_TILE_COUNT = HERO_TILES.length + RADIAL_ACCENTS.length;

/** Progress follows the hero passing beneath the 76px navigation area. */
export function heroScrollProgress(top: number, height: number) {
  return height > 0 ? Math.max(0, Math.min(1, (76 - top) / height)) : 0;
}

/** Two loose rings open outward with scrolling; pointer position is irrelevant. */
export function heroRadialLayout(width: number, height: number, progress = 0) {
  const amount = Math.max(0, Math.min(1, progress));
  // Leave room for rotated corners throughout the rings' scroll movement.
  const size = Math.min(width * (width < 768 ? 0.225 : 0.1125), height * 0.225) *
    0.85;
  return {
    tiles: Array.from({ length: HERO_RADIAL_TILE_COUNT }, (_, index) => {
      const accent = RADIAL_ACCENTS[index - HERO_TILES.length];
      const inner = index >= 15;
      const count = inner ? 10 : 15;
      const position = inner ? index - 15 : index;
      const direction = inner ? -1 : 1;
      const angle = (accent
        ? accent.angle * Math.PI / 180
        : position / count * Math.PI * 2 + (inner ? 0.23 : -0.16)) +
        amount * 0.08 * direction;
      const radius = (accent?.radius ?? (inner ? 0.39 : 0.59)) *
        (1 + amount * 0.18);
      const side = size * (accent?.scale ?? (0.76 + (index * 7 % 9) / 25)) *
        (1 + amount * 0.08);
      return {
        x: width * 0.5 + Math.cos(angle) * width * radius - side / 2,
        y: height * 0.46 + Math.sin(angle) * height * radius - side / 2 -
          height * amount * 0.07,
        width: side,
        height: side,
        rotation: (accent?.rotation ?? ANCHOR_ROTATIONS[index]) +
          amount * 8 * direction,
      };
    }),
  };
}

/** Compact screens use the composed square tiling, moving as a single surface. */
export function heroResponsiveLayout(
  width: number,
  height: number,
  progress = 0,
) {
  if (width > 768) return heroRadialLayout(width, height, progress);
  const offset = Math.max(0, Math.min(1, progress)) * 24;
  return {
    tiles: heroGridLayout(width, height).tiles.map((tile) => ({
      ...tile,
      y: tile.y - offset,
      rotation: 0,
    })),
  };
}
