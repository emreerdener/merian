import { compareInitialDecimals } from "./decimal.ts";
import { initialDecimal } from "./canonical.ts";
import { assertInitialSemantics } from "./semantics.ts";
import schema from "./input-schema-v1.json" with { type: "json" };
import {
  initialCanonicalText,
  invalidInitialInput,
  parseInitialCanonicalText,
} from "./canonical.ts";

export type InitialSchemaRule = {
  type: string;
  nullable?: boolean;
  properties?: Record<string, InitialSchemaRule>;
  items?: InitialSchemaRule;
  max_items?: number;
  max_bytes?: number;
  enum?: string[];
  pattern?: string;
  minimum?: number | string;
  maximum?: number | string;
};
const bytes = new TextEncoder();
const decimal = /^-?(0|[1-9][0-9]*)(\.[0-9]*[1-9])?$/;
export function matchesInitialSchema(
  value: unknown,
  rule: InitialSchemaRule,
): boolean {
  if (value === null) return rule.nullable === true;
  switch (rule.type) {
    case "object": {
      if (typeof value !== "object" || Array.isArray(value)) return false;
      const object = value as Record<string, unknown>;
      const fields = rule.properties!;
      return Object.keys(object).length === Object.keys(fields).length &&
        Object.entries(fields).every(([key, child]) =>
          Object.hasOwn(object, key) && matchesInitialSchema(object[key], child)
        );
    }
    case "array":
      return Array.isArray(value) && value.length <= rule.max_items! &&
        value.every((v) => matchesInitialSchema(v, rule.items!));
    case "boolean":
      return typeof value === "boolean";
    case "integer":
      return typeof value === "number" && Number.isSafeInteger(value) &&
        value >= Number(rule.minimum) && value <= Number(rule.maximum);
    case "string":
      return typeof value === "string" &&
        bytes.encode(value).length <= rule.max_bytes! &&
        (!rule.enum || rule.enum.includes(value)) &&
        (!rule.pattern || new RegExp(rule.pattern).test(value));
    case "decimal":
      return typeof value === "string" &&
        bytes.encode(value).length <= rule.max_bytes! && decimal.test(value) &&
        value !== "-0" &&
        compareInitialDecimals(value, initialDecimal(Number(rule.minimum))) >=
          0 &&
        compareInitialDecimals(value, initialDecimal(Number(rule.maximum))) <=
          0;
    default:
      return false;
  }
}

/** Private preparation envelope, intentionally not installed in initial routes. */
export function validateInitialInput(value: unknown): string {
  const text = initialCanonicalText(value);
  const frozen = parseInitialCanonicalText(text);
  if (!matchesInitialSchema(frozen, schema as InitialSchemaRule)) {
    return invalidInitialInput();
  }
  assertInitialSemantics(frozen);
  return text;
}
