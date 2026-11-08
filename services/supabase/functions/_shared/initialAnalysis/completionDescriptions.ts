/** Inactive completion/History byte codec. No authorization, I/O or execution. */
import { decodeBase64, encodeBase64 } from "../encoding.ts";
import {
  hex,
  INITIAL_CANONICAL_LIMIT,
  initialCanonicalText,
  parseInitialCanonicalText,
} from "./canonical.ts";

export const COMPLETION_DESCRIPTION_PAGE_BYTES = 24_576;
export const COMPLETION_DESCRIPTION_WIRE_BYTES = 65_536;
const encoder = new TextEncoder();
const decoder = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true });
type InputVersion = 1 | 2;
export interface CompletionDescriptionReference {
  readonly version: 1;
  readonly input_schema_version: InputVersion;
  readonly ordered_description_digest: string;
  readonly ordered_description_count: number;
}
export interface CompletionDescriptionPage {
  readonly version: 1;
  readonly ordered_description_digest: string;
  readonly item_index: number;
  readonly total_byte_count: number;
  readonly byte_offset: number;
  readonly bytes_utf8_base64: string;
  readonly next_byte_offset: number | null;
}
function invalid(): never {
  throw new Error("initial_completion_descriptions_invalid");
}
function object(
  value: unknown,
  keys: readonly string[],
): Record<string, unknown> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    return invalid();
  }
  const row = value as Record<string, unknown>;
  if (Object.keys(row).sort().join(",") !== [...keys].sort().join(",")) {
    return invalid();
  }
  return row;
}
function integer(value: unknown, maximum: number): number {
  if (
    typeof value !== "number" || !Number.isSafeInteger(value) ||
    Object.is(value, -0) || value < 0 || value > maximum
  ) return invalid();
  return value;
}
function base64(value: unknown, maximum: number): Uint8Array {
  if (typeof value !== "string" || value.length > 4 * Math.ceil(maximum / 3)) {
    return invalid();
  }
  try {
    const bytes = decodeBase64(value);
    if (bytes.length > maximum || encodeBase64(bytes) !== value) {
      return invalid();
    }
    return bytes;
  } catch {
    return invalid();
  }
}
function maxItem(version: InputVersion): number {
  return version === 1 ? 65_530 : 32_768;
}
function representation(version: InputVersion, canonical: string) {
  if (version !== 1 && version !== 2) return invalid();
  const value = parseInitialCanonicalText(canonical);
  if (!Array.isArray(value) || value.length > 64) return invalid();
  let units = 0;
  const items = value.map((item) => {
    if (version === 1) {
      if (typeof item !== "string" || !item.trim()) return invalid();
      const bytes = encoder.encode(item);
      if (
        bytes.length > maxItem(version) ||
        encoder.encode(JSON.stringify(item)).length > 65_536
      ) return invalid();
      return { bytes, text: item };
    }
    const row = object(item, ["text_utf8_base64"]);
    const bytes = base64(row.text_utf8_base64, maxItem(version));
    let text: string;
    try {
      text = decoder.decode(bytes);
    } catch {
      return invalid();
    }
    if ([...text].length > 8192 || text.length > 16384) return invalid();
    units += text.length;
    if (units > 32000) return invalid();
    return { bytes, text };
  });
  return items;
}
async function digest(
  version: InputVersion,
  canonical: string,
): Promise<string> {
  const domain = version === 1
    ? "merian.initial-analysis.descriptions.v1"
    : "merian.initial-analysis.cpm-photo-contexts.v1";
  return hex(
    new Uint8Array(
      await crypto.subtle.digest(
        "SHA-256",
        encoder.encode(`${domain}\n${canonical}`),
      ),
    ),
  );
}
export function parseCompletionDescriptionReference(
  value: unknown,
): CompletionDescriptionReference {
  // Synchronous canonical copy rejects accessors, non-scalar values and extras.
  const row = object(parseInitialCanonicalText(initialCanonicalText(value)), [
    "version",
    "input_schema_version",
    "ordered_description_digest",
    "ordered_description_count",
  ]);
  if (
    row.version !== 1 ||
    (row.input_schema_version !== 1 && row.input_schema_version !== 2) ||
    typeof row.ordered_description_digest !== "string" ||
    !/^[0-9a-f]{64}$/.test(row.ordered_description_digest)
  ) return invalid();
  return Object.freeze({
    version: 1,
    input_schema_version: row.input_schema_version,
    ordered_description_digest: row.ordered_description_digest,
    ordered_description_count: integer(row.ordered_description_count, 64),
  });
}

/** The caller must separately prove the original immutable completion/owner. */
export async function snapshotCompletionDescriptions(
  version: InputVersion,
  canonical: string,
) {
  const items = representation(version, canonical);
  const reference: CompletionDescriptionReference = Object.freeze({
    version: 1,
    input_schema_version: version,
    ordered_description_digest: await digest(version, canonical),
    ordered_description_count: items.length,
  });
  return Object.freeze({ reference, canonical });
}

/** Offset is a byte position, not a Unicode/String index. Pages may split UTF-8. */
export async function completionDescriptionPage(
  referenceValue: unknown,
  canonical: string,
  itemIndex: number,
  byteOffset: number,
): Promise<string> {
  const reference = parseCompletionDescriptionReference(referenceValue);
  const items = representation(reference.input_schema_version, canonical);
  const index = integer(itemIndex, 63);
  const offset = integer(byteOffset, maxItem(reference.input_schema_version));
  const item = items[index];
  if (
    !item || items.length !== reference.ordered_description_count ||
    (item.bytes.length === 0 ? offset !== 0 : offset >= item.bytes.length)
  ) return invalid();
  if (
    await digest(reference.input_schema_version, canonical) !==
      reference.ordered_description_digest
  ) return invalid();
  const end = Math.min(
    offset + COMPLETION_DESCRIPTION_PAGE_BYTES,
    item.bytes.length,
  );
  const page: CompletionDescriptionPage = {
    version: 1,
    ordered_description_digest: reference.ordered_description_digest,
    item_index: index,
    total_byte_count: item.bytes.length,
    byte_offset: offset,
    bytes_utf8_base64: encodeBase64(item.bytes.subarray(offset, end)),
    next_byte_offset: end === item.bytes.length ? null : end,
  };
  return initialCanonicalText(page);
}

/** One immutable reference, strict contiguous pages, then full original digest.
 * Failed/incomplete collections never yield reusable descriptions. Account and
 * deletion fences belong to the transport on every page, not to this codec. */
export function createCompletionDescriptionCollector(referenceValue: unknown) {
  const reference = parseCompletionDescriptionReference(referenceValue);
  let failed = false, finished = false, index = 0, offset = 0;
  let current: Uint8Array | null = null, totalBytes = 0;
  const texts: string[] = [], encoded: { text_utf8_base64: string }[] = [];
  return Object.freeze({
    append(wire: string): void {
      try {
        if (
          failed || finished || typeof wire !== "string" ||
          wire.length > COMPLETION_DESCRIPTION_WIRE_BYTES ||
          encoder.encode(wire).length > COMPLETION_DESCRIPTION_WIRE_BYTES ||
          index >= reference.ordered_description_count
        ) return invalid();
        const row = object(parseInitialCanonicalText(wire), [
          "version",
          "ordered_description_digest",
          "item_index",
          "total_byte_count",
          "byte_offset",
          "bytes_utf8_base64",
          "next_byte_offset",
        ]);
        const total = integer(
          row.total_byte_count,
          maxItem(reference.input_schema_version),
        );
        if (
          row.version !== 1 ||
          row.ordered_description_digest !==
            reference.ordered_description_digest ||
          integer(row.item_index, 63) !== index ||
          integer(row.byte_offset, maxItem(reference.input_schema_version)) !==
            offset ||
          (current !== null && total !== current.length)
        ) return invalid();
        const bytes = base64(
          row.bytes_utf8_base64,
          COMPLETION_DESCRIPTION_PAGE_BYTES,
        );
        const end = offset + bytes.length;
        if (
          bytes.length !==
            Math.min(COMPLETION_DESCRIPTION_PAGE_BYTES, total - offset) ||
          end > total ||
          (bytes.length === 0 && (total !== 0 || offset !== 0)) ||
          row.next_byte_offset !== (end === total ? null : end)
        ) return invalid();
        if (current === null) {
          totalBytes += total;
          if (totalBytes > INITIAL_CANONICAL_LIMIT) return invalid();
          current = new Uint8Array(total);
        }
        current.set(bytes, offset);
        offset = end;
        if (row.next_byte_offset === null) {
          const text = decoder.decode(current);
          texts.push(text);
          encoded.push({ text_utf8_base64: encodeBase64(current) });
          index++;
          offset = 0;
          current = null;
        }
      } catch {
        failed = true;
        current = null;
        texts.length = 0;
        encoded.length = 0;
        return invalid();
      }
    },
    async finish() {
      if (
        failed || finished || current !== null ||
        index !== reference.ordered_description_count
      ) {
        failed = true;
        return invalid();
      }
      finished = true;
      const canonical = initialCanonicalText(
        reference.input_schema_version === 1 ? texts : encoded,
      );
      representation(reference.input_schema_version, canonical);
      if (
        await digest(reference.input_schema_version, canonical) !==
          reference.ordered_description_digest
      ) return invalid();
      return Object.freeze({
        reference,
        canonical,
        descriptions: Object.freeze([...texts]),
      });
    },
  });
}
