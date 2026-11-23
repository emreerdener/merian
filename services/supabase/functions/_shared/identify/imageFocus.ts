/** Bounds in the exact prepared image, with a top-left origin. Manual selection
 * expresses the user's intended subject; automatic saliency is only a hint.
 * Parsing metadata grants no media, admission or execution authority.
 */
export interface ImageFocusRegion {
  readonly x: number;
  readonly y: number;
  readonly width: number;
  readonly height: number;
  readonly source: "vision_objectness" | "user_selection";
}

export function parseImageFocusRegion(value: unknown): ImageFocusRegion | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const region = value as Record<string, unknown>;
  const keys = ["x", "y", "width", "height", "source"];
  if (
    Object.keys(region).length !== keys.length ||
    !keys.every((key) => Object.hasOwn(region, key))
  ) return null;
  const { x, y, width, height, source } = region;
  if (
    typeof x !== "number" || !Number.isFinite(x) ||
    typeof y !== "number" || !Number.isFinite(y) ||
    typeof width !== "number" || !Number.isFinite(width) ||
    typeof height !== "number" || !Number.isFinite(height) ||
    (source !== "vision_objectness" && source !== "user_selection") ||
    x < 0 || y < 0 || width <= 0 || height <= 0 ||
    x + width > 1 || y + height > 1
  ) return null;
  return Object.freeze({ x, y, width, height, source });
}

/** Fingerprint V2 encodes IEEE754 binary64 rather than runtime-specific decimal
 * spellings. Zero has one representation; the validated submitted rectangle is
 * otherwise unchanged. PostgreSQL uses float8send and Swift uses bitPattern.
 */
export function imageFocusFingerprintFields(value: unknown): readonly string[] {
  const focus = parseImageFocusRegion(value);
  if (!focus) throw new Error("invalid_image_focus");
  const binary64 = (coordinate: number) => {
    const bytes = new Uint8Array(8);
    new DataView(bytes.buffer).setFloat64(
      0,
      coordinate === 0 ? 0 : coordinate,
      false,
    );
    return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join(
      "",
    );
  };
  return Object.freeze([
    ...[focus.x, focus.y, focus.width, focus.height].map(binary64),
    focus.source,
  ]);
}
