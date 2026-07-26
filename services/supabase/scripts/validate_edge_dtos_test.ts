import assert from "node:assert/strict";
import {
  canonicalIdentifySchemaPath,
  ContractValidationError,
  type ContractValidationPolicy,
  defaultValidationPolicy,
  extractSchemaContract,
  inferenceEdgeDTOsPath,
  validateAPIContracts,
  validateContractSources,
} from "./validate_edge_dtos.ts";

const SCHEMA_FIXTURE = `
const sharedProperties = () => ({
  alpha: { type: SchemaType.STRING },
  nested: {
    type: SchemaType.OBJECT,
    properties: {
      inner_value: { type: SchemaType.NUMBER },
    },
  },
});

export const getMerianResponseSchema = () => {
  const schema = {
    type: SchemaType.OBJECT,
    properties: {
      ...sharedProperties(),
      beta: {
        type: SchemaType.ARRAY,
        items: {
          type: SchemaType.OBJECT,
          properties: {
            leaf_value: { type: SchemaType.BOOLEAN },
          },
        },
      },
    },
  };
  return schema;
};
`;

const SWIFT_FIXTURE = `
struct EdgeResponse: Codable {
    let alpha: String?
    let nested: Nested?
    let beta: [Beta]?
}
`;

function fixturePolicy(
  overrides: Partial<ContractValidationPolicy> = {},
): ContractValidationPolicy {
  return {
    minimumSchemaProperties: 5,
    minimumTopLevelSchemaProperties: 3,
    minimumSwiftProperties: 3,
    requiredTopLevelProperties: ["alpha", "nested", "beta"],
    intentionallyServerOnlyProperties: new Set(),
    ...overrides,
  };
}

function capturedContractError(action: () => void): ContractValidationError {
  try {
    action();
  } catch (error) {
    assert(error instanceof ContractValidationError);
    return error;
  }
  throw new Error("Expected contract validation to fail.");
}

Deno.test("schema AST follows local factories, spreads, objects, and array items", () => {
  const contract = extractSchemaContract(SCHEMA_FIXTURE);

  assert.deepStrictEqual([...contract.topLevelProperties].sort(), [
    "alpha",
    "beta",
    "nested",
  ]);
  assert.deepStrictEqual([...contract.allProperties].sort(), [
    "alpha",
    "beta",
    "inner_value",
    "leaf_value",
    "nested",
  ]);
  assert.deepStrictEqual([...contract.propertyPaths].sort(), [
    "alpha",
    "beta",
    "beta[].leaf_value",
    "nested",
    "nested.inner_value",
  ]);
});

Deno.test("Swift extraction is scoped to direct EdgeResponse properties", () => {
  const report = validateContractSources(
    SCHEMA_FIXTURE,
    `${SWIFT_FIXTURE}
      struct Unrelated: Codable {
          let missing_schema_field: String?
      }
    `,
    fixturePolicy(),
  );

  assert.deepStrictEqual([...report.swiftProperties].sort(), [
    "alpha",
    "beta",
    "nested",
  ]);
});

Deno.test("contract validation fails closed when the schema resolves zero fields", () => {
  const emptySchema = `
    export const getMerianResponseSchema = () => ({
      type: SchemaType.OBJECT,
      properties: {},
    });
  `;

  const error = capturedContractError(() =>
    validateContractSources(
      emptySchema,
      SWIFT_FIXTURE,
      fixturePolicy(),
    )
  );
  assert.match(error.message, /resolved 0 unique schema properties/);
});

Deno.test("contract validation fails closed below a configured coverage floor", () => {
  const error = capturedContractError(() =>
    validateContractSources(
      SCHEMA_FIXTURE,
      SWIFT_FIXTURE,
      fixturePolicy({ minimumSchemaProperties: 6 }),
    )
  );
  assert.match(error.message, /expected at least 6/);
});

Deno.test("schema AST fails closed on syntax errors and unresolved definitions", () => {
  const syntaxError = capturedContractError(() =>
    extractSchemaContract(
      "export const getMerianResponseSchema = () => ({ properties: {",
    )
  );
  assert.match(syntaxError.message, /could not be parsed/);

  const unresolvedDefinition = capturedContractError(() =>
    extractSchemaContract(`
      export const getMerianResponseSchema = () => ({
        type: SchemaType.OBJECT,
        properties: {
          alpha: importedSchemaDefinition,
        },
      });
    `)
  );
  assert.match(
    unresolvedDefinition.message,
    /Unable to statically resolve a schema definition at 'alpha'/,
  );
});

Deno.test("contract validation rejects a top-level schema field absent from Swift", () => {
  const error = capturedContractError(() =>
    validateContractSources(
      SCHEMA_FIXTURE,
      SWIFT_FIXTURE.replace("let beta: [Beta]?", "let gamma: String?"),
      fixturePolicy(),
    )
  );
  assert.match(error.message, /'beta'/);
});

Deno.test("canonical validator reads the shared Identify schema and passes assurance floors", async () => {
  assert(canonicalIdentifySchemaPath.endsWith(
    "services/supabase/functions/_shared/identify/schema.ts",
  ));
  assert(inferenceEdgeDTOsPath.endsWith(
    "apps/ios/Merian/Core/AI/InferenceEdgeDTOs.swift",
  ));

  const report = await validateAPIContracts();
  assert(
    report.schemaContract.allProperties.size >=
      defaultValidationPolicy.minimumSchemaProperties,
  );
  assert(
    report.schemaContract.topLevelProperties.size >=
      defaultValidationPolicy.minimumTopLevelSchemaProperties,
  );
  assert(
    report.swiftProperties.size >=
      defaultValidationPolicy.minimumSwiftProperties,
  );
  for (const required of defaultValidationPolicy.requiredTopLevelProperties) {
    assert(report.schemaContract.topLevelProperties.has(required));
  }
});
