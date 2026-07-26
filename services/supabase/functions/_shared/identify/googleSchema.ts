import type { Schema } from "@google/genai";
import {
  type ContractNode,
  type PortableProviderSchema,
  providerSchemaFromContract,
} from "./contract.ts";

type GoogleSchemaType = NonNullable<Schema["type"]>;

const googleSchemaTypes = {
  ARRAY: "ARRAY",
  BOOLEAN: "BOOLEAN",
  INTEGER: "INTEGER",
  NUMBER: "NUMBER",
  OBJECT: "OBJECT",
  STRING: "STRING",
} as const satisfies Record<PortableProviderSchema["type"], string>;

function googleSchemaType(
  portable: PortableProviderSchema["type"],
): GoogleSchemaType {
  // The pinned SDK declares Schema.type as a string enum. Keep the cast
  // isolated here; every other field is structurally checked below.
  return googleSchemaTypes[portable] as GoogleSchemaType;
}

function googleSchemaFromPortable(
  portable: PortableProviderSchema,
): Schema {
  const {
    type,
    enum: enumValues,
    items,
    properties,
    required,
    ...scalarConstraints
  } = portable;

  return {
    ...scalarConstraints,
    type: googleSchemaType(type),
    ...(enumValues ? { enum: [...enumValues] } : {}),
    ...(items ? { items: googleSchemaFromPortable(items) } : {}),
    ...(properties
      ? {
        properties: Object.fromEntries(
          Object.entries(properties).map(([name, schema]) => [
            name,
            googleSchemaFromPortable(schema),
          ]),
        ),
      }
      : {}),
    ...(required ? { required: [...required] } : {}),
  };
}

/**
 * Typed provider adapter. The executable contract remains dependency-free,
 * while this seam fails compilation if the pinned Google SDK changes its
 * Schema field types. Only its string-enum `type` representation crosses the
 * narrow adapter above.
 */
export function googleSchemaFromContract(contract: ContractNode): Schema {
  return googleSchemaFromPortable(providerSchemaFromContract(contract));
}
