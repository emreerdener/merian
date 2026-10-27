/** Inactive content declarations only: no byte, admission or dispatch authority. */
import { decodeBase64, encodeBase64 } from "../encoding.ts";
import {
  hex,
  initialCanonicalText,
  invalidInitialInput,
  parseInitialCanonicalText,
} from "./canonical.ts";
import { matchesInitialSchema } from "./schema.ts";
import schema from "./cpm-photo-content-schema-v1.json" with { type: "json" };

type Role = {
  reference_id: string;
  byte_count: number;
  sha256: string;
  declared_content_type: string;
};
type Recipe = {
  format: "nativeStillImageV1" | "nativeCameraStillV1";
  is_pro: boolean;
  crop_display_size_bits: string | null;
  quarter_turns: number;
  scale_bits: string;
  offset_x_bits: string;
  offset_y_bits: string;
  camera_vertical_center_bits: string | null;
};
type Content = {
  photos: {
    ordinal: number;
    source: Role;
    ai: Role;
    display: Role;
    recipe: Recipe;
  }[];
  contexts: { text_utf8_base64: string }[];
};
const encoder = new TextEncoder();
const decoder = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true });
const MIB = 1_048_576;

/** Unsigned binary64 bit pattern, most significant hex digit first. */
function finiteBits(bits: string): number {
  const view = new DataView(new ArrayBuffer(8));
  view.setBigUint64(0, BigInt(`0x${bits}`), false);
  const value = view.getFloat64(0, false);
  if (!Number.isFinite(value)) return invalidInitialInput();
  return value;
}

function validateRecipe(recipe: Recipe): void {
  const size = recipe.crop_display_size_bits === null
    ? null
    : finiteBits(recipe.crop_display_size_bits);
  const center = recipe.camera_vertical_center_bits === null
    ? null
    : finiteBits(recipe.camera_vertical_center_bits);
  const scale = finiteBits(recipe.scale_bits);
  const x = finiteBits(recipe.offset_x_bits),
    y = finiteBits(recipe.offset_y_bits);
  if (scale < 1 || (size !== null && size <= 0)) return invalidInitialInput();
  if (
    size === null &&
    (recipe.quarter_turns !== 0 || scale !== 1 || x !== 0 || y !== 0)
  ) return invalidInitialInput();
  if (recipe.format === "nativeCameraStillV1") {
    if (center === null || center < 0 || center > 1 || size !== null) {
      return invalidInitialInput();
    }
  } else if (center !== null) return invalidInitialInput();
  // is_pro is saved client recipe provenance, never an entitlement.
}

function validateContexts(contexts: Content["contexts"]): void {
  let units = 0;
  for (const context of contexts) {
    const encoded = context.text_utf8_base64;
    let bytes: Uint8Array, text: string;
    try {
      bytes = decodeBase64(encoded);
      if (encodeBase64(bytes) !== encoded) return invalidInitialInput();
      text = decoder.decode(bytes);
    } catch {
      return invalidInitialInput();
    }
    // Strict UTF-8 preserves BOM, NUL, whitespace and normalization distinctions.
    if ([...text].length > 8192 || text.length > 16384) {
      return invalidInitialInput();
    }
    units += text.length;
    if (units > 32000) return invalidInitialInput();
  }
}

/** Validate and privately snapshot a declaration; it is still an unverified claim. */
export function validateInitialCpmPhotoContent(value: unknown): string {
  const text = initialCanonicalText(value);
  const frozen = parseInitialCanonicalText(text);
  if (!matchesInitialSchema(frozen, schema)) return invalidInitialInput();
  const content = frozen as unknown as Content;
  if (content.photos.length < 1) return invalidInitialInput();
  const references = new Set<string>();
  let originals = 0, ai = 0, display = 0;
  for (const [position, photo] of content.photos.entries()) {
    // Position is frozen cohort order, not acquisition or presentation order.
    if (photo.ordinal !== position) return invalidInitialInput();
    for (const role of [photo.source, photo.ai, photo.display]) {
      if (references.has(role.reference_id)) return invalidInitialInput();
      references.add(role.reference_id);
    }
    originals += photo.source.byte_count;
    ai += photo.ai.byte_count;
    display += photo.display.byte_count;
    validateRecipe(photo.recipe);
  }
  if (
    originals > 64 * MIB || ai > 5 * MIB || display > 8 * MIB ||
    originals + ai + display + encoder.encode(text).length > 96 * MIB
  ) return invalidInitialInput();
  validateContexts(content.contexts);
  return text;
}

/** Canonical wire decoding rejects duplicate keys and alternate spellings. */
export function parseInitialCpmPhotoContent(text: string): string {
  return validateInitialCpmPhotoContent(parseInitialCanonicalText(text));
}

/** Copies all caller input synchronously before the first await. No object escapes. */
export async function initialCpmPhotoContentDigest(
  value: unknown,
): Promise<string> {
  const text = validateInitialCpmPhotoContent(value);
  const bytes = encoder.encode(
    `merian.initial-analysis.cpm-photo-content.v1\n${text}`,
  );
  return hex(new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)));
}
