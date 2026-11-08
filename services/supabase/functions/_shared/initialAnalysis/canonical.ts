/** Private IC-1 encoding. This is not a public request/response DTO. */
export type CanonicalValue =
  | null
  | boolean
  | number
  | string
  | readonly CanonicalValue[]
  | { readonly [key: string]: CanonicalValue };

const encoder = new TextEncoder();
export const INITIAL_CANONICAL_LIMIT = 1_048_576;
export function invalidInitialInput(): never {
  throw new Error("initial_analysis_input_invalid");
}

export function scalarString(value: string): boolean {
  return !value.includes("\u0000") && ![...value].some((c) => {
    const point = c.codePointAt(0)!;
    return point >= 0xd800 && point <= 0xdfff;
  });
}

/** Sorted ASCII keys; exact Unicode scalar strings; safe integers only.
 * Fractions have field-specific decimal-string types in the semantic schema.
 * No normalization, object-toJSON hook, sparse array or undefined coercion.
 */
export function initialCanonicalText(value: unknown): string {
  let nodes = 0;
  const visit = (v: unknown, depth: number): string => {
    if (++nodes > 4096 || depth > 12) return invalidInitialInput();
    if (v === null || typeof v === "boolean") return String(v);
    if (typeof v === "number") {
      if (!Number.isSafeInteger(v) || Object.is(v, -0)) {
        return invalidInitialInput();
      }
      return String(v);
    }
    if (typeof v === "string") {
      if (
        !scalarString(v) || encoder.encode(v).length > INITIAL_CANONICAL_LIMIT
      ) {
        return invalidInitialInput();
      }
      return JSON.stringify(v);
    }
    if (!v || typeof v !== "object") return invalidInitialInput();
    if (Array.isArray(v)) {
      if (
        v.length > 512 || Object.keys(v).length !== v.length ||
        Reflect.ownKeys(v).length !== v.length + 1 ||
        Object.entries(Object.getOwnPropertyDescriptors(v)).some((
          [key, field],
        ) => key !== "length" && (!field.enumerable || !("value" in field)))
      ) {
        return invalidInitialInput();
      }
      return `[${Array.from(v, (item) => visit(item, depth + 1)).join(",")}]`;
    }
    if (Object.getPrototypeOf(v) !== Object.prototype) {
      return invalidInitialInput();
    }
    const fields = Object.getOwnPropertyDescriptors(v);
    const keys = Object.keys(fields).sort();
    if (keys.length > 128 || Reflect.ownKeys(v).length !== keys.length) {
      return invalidInitialInput();
    }
    return `{${
      keys.map((key) => {
        const field = fields[key];
        if (
          !/^[a-z][a-z0-9_]*$/.test(key) || key.length > 64 ||
          !field.enumerable || !("value" in field)
        ) return invalidInitialInput();
        return `${JSON.stringify(key)}:${visit(field.value, depth + 1)}`;
      }).join(",")
    }}`;
  };
  const text = visit(value, 0);
  if (encoder.encode(text).length > INITIAL_CANONICAL_LIMIT) {
    return invalidInitialInput();
  }
  return text;
}

export function parseInitialCanonicalText(text: string): CanonicalValue {
  if (
    typeof text !== "string" ||
    encoder.encode(text).length > INITIAL_CANONICAL_LIMIT
  ) {
    return invalidInitialInput();
  }
  let value: unknown;
  try {
    value = JSON.parse(text);
  } catch {
    return invalidInitialInput();
  }
  // Rejects duplicate keys, alternate escapes, spaces and numeric spellings
  // before the parsed value can become admission authority.
  if (initialCanonicalText(value) !== text) return invalidInitialInput();
  return value as CanonicalValue;
}

export async function initialDigest(
  domain: "input" | "configuration" | "funding" | "descriptions" | "assets",
  text: string,
): Promise<string> {
  const bytes = encoder.encode(`merian.initial-analysis.${domain}.v1\n${text}`);
  return hex(new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)));
}

export function hex(bytes: Uint8Array): string {
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

/** Normalize accepted numeric metadata once before admission, not in SQL.
 * Expanded decimal notation avoids JS/Postgres exponent formatting differences.
 */
export function initialDecimal(value: number): string {
  if (!Number.isFinite(value)) return invalidInitialInput();
  if (Object.is(value, -0)) return "0";
  const raw = String(value);
  if (!raw.includes("e")) return raw;
  const [mantissa, exponent] = raw.split("e");
  const sign = mantissa.startsWith("-") ? "-" : "";
  const unsigned = mantissa.replace(/^-/, "");
  const digits = unsigned.replace(".", "");
  const position = (unsigned.split(".")[0].length) + Number(exponent);
  return sign +
    (position <= 0
      ? `0.${"0".repeat(-position)}${digits}`
      : position >= digits.length
      ? digits + "0".repeat(position - digits.length)
      : `${digits.slice(0, position)}.${digits.slice(position)}`);
}
