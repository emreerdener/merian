/** Private original-result representation. Public Identify numbers stay numeric.
 * Both write and recovery enforce finite IEEE round trips; SQL additionally
 * validates its closed syntax/range/digest contract before durable writes. */
import type { ContractNode } from "../identify/contract.ts";
import {
  type CanonicalValue,
  initialDecimal,
  scalarString,
} from "./canonical.ts";

export const invalidInitialResult = () =>
  new Error("initial_analysis_result_invalid");

function fields(value: unknown) {
  if (
    !value || typeof value !== "object" ||
    Object.getPrototypeOf(value) !== Object.prototype
  ) throw invalidInitialResult();
  const descriptors = Object.getOwnPropertyDescriptors(value);
  if (
    Reflect.ownKeys(value).length !== Object.keys(descriptors).length ||
    Object.keys(descriptors).length > 128
  ) throw invalidInitialResult();
  for (const descriptor of Object.values(descriptors)) {
    if (!descriptor.enumerable || !("value" in descriptor)) {
      throw invalidInitialResult();
    }
  }
  return descriptors;
}

/** Schema traversal preserves omission/null/order and rejects unknown keys even
 * where the public parser would strip them. It never calls getters or toJSON. */
export function transformInitialResult(
  contract: ContractNode,
  value: unknown,
  direction: "encode" | "decode",
): CanonicalValue {
  let nodes = 0;
  function walk(
    node: ContractNode,
    input: unknown,
    depth: number,
  ): CanonicalValue {
    if (++nodes > 4096 || depth > 12) throw invalidInitialResult();
    if (input === null) {
      if (!node.nullable) throw invalidInitialResult();
      return null;
    }
    if (node.kind === "union") {
      const ds = fields(input);
      const discriminator: unknown = ds[node.discriminator]?.value;
      if (
        typeof discriminator !== "number" ||
        !Number.isSafeInteger(discriminator)
      ) throw invalidInitialResult();
      const variant = node.variants[discriminator];
      if (!variant) throw invalidInitialResult();
      return walk(variant, input, depth);
    }
    if (node.kind === "object") {
      const ds = fields(input);
      if (Object.keys(ds).some((key) => !Object.hasOwn(node.fields, key))) {
        throw invalidInitialResult();
      }
      const result: { [key: string]: CanonicalValue } = {};
      for (const [key, field] of Object.entries(node.fields)) {
        if (!Object.hasOwn(ds, key)) {
          if (field.required) throw invalidInitialResult();
          continue;
        }
        result[key] = walk(field.contract, ds[key].value, depth + 1);
      }
      return result;
    }
    if (node.kind === "array") {
      if (
        !Array.isArray(input) || input.length < (node.minItems ?? 0) ||
        input.length > Math.min(node.maxItems ?? 512, 512) ||
        Reflect.ownKeys(input).length !== input.length + 1
      ) throw invalidInitialResult();
      const ds = Object.getOwnPropertyDescriptors(input);
      const result: CanonicalValue[] = [];
      for (let index = 0; index < input.length; index++) {
        const d = ds[index];
        if (!d || !d.enumerable || !("value" in d)) {
          throw invalidInitialResult();
        }
        result.push(walk(node.items, d.value, depth + 1));
      }
      return result;
    }
    if (node.kind === "number") {
      let number: number;
      if (direction === "encode") {
        if (typeof input !== "number") throw invalidInitialResult();
        number = input;
      } else {
        if (
          typeof input !== "string" || input.length > 327 ||
          !/^-?(0|[1-9][0-9]*)(\.[0-9]*[1-9])?$/.test(input) || input === "-0"
        ) throw invalidInitialResult();
        number = Number(input);
        if (!Number.isFinite(number) || initialDecimal(number) !== input) {
          throw invalidInitialResult();
        }
      }
      if (!Number.isFinite(number) || Object.is(number, -0)) {
        throw invalidInitialResult();
      }
      validateScalarV1(node, number);
      return direction === "encode" ? initialDecimal(number) : number;
    }
    validateScalarV1(node, input);
    if (typeof input === "string") {
      if (!scalarString(input)) throw invalidInitialResult();
      return input;
    }
    if (typeof input === "number") {
      if (!Number.isSafeInteger(input) || Object.is(input, -0)) {
        throw invalidInitialResult();
      }
      return input;
    }
    if (typeof input === "boolean") return input;
    throw invalidInitialResult();
  }
  return walk(contract, value, 0);
}

/** Version-one scalar semantics, independent of the live public parser. */
function validateScalarV1(node: ContractNode, value: unknown): void {
  if (node.kind === "string") {
    if (
      typeof value !== "string" ||
      value.length < (node.minLength ?? 0) ||
      value.length > (node.maxLength ?? Infinity) ||
      (node.enum && !node.enum.includes(value)) ||
      (node.pattern && new RegExp(node.pattern).exec(value)?.[0] !== value)
    ) throw invalidInitialResult();
    return;
  }
  if (node.kind === "boolean") {
    if (
      typeof value !== "boolean" ||
      (node.const !== undefined && value !== node.const)
    ) throw invalidInitialResult();
    return;
  }
  if (node.kind === "number" || node.kind === "integer") {
    if (
      typeof value !== "number" || !Number.isFinite(value) ||
      (node.kind === "integer" && !Number.isSafeInteger(value)) ||
      value < node.minimum || value > node.maximum
    ) throw invalidInitialResult();
    return;
  }
  throw invalidInitialResult();
}
