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
      inner_value: {
        type: SchemaType.NUMBER,
        minimum: -1000000,
        maximum: 1000000,
      },
    },
    required: ["inner_value"],
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
          required: ["leaf_value"],
        },
      },
    },
    required: ["alpha", "nested", "beta"],
  };
  return schema;
};
`;

const SWIFT_FIXTURE = `
struct EdgeResponse: Codable {
    let alpha: String?
    let nested: Nested?
    let beta: [Beta]?

    struct Nested: Codable {
        let innerValue: Double

        enum CodingKeys: String, CodingKey {
            case innerValue = "inner_value"
        }
    }

    struct Beta: Codable {
        let leafValue: Bool

        enum CodingKeys: String, CodingKey {
            case leafValue = "leaf_value"
        }
    }
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
    intentionallyServerAddedSwiftPaths: new Set(),
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
  assert.equal(contract.root.kind, "object");
  assert.equal(contract.root.properties.get("alpha")?.required, true);
  assert.equal(
    contract.root.properties.get("nested")?.properties.get("inner_value")
      ?.kind,
    "number",
  );
  assert.equal(
    contract.root.properties.get("beta")?.items?.properties.get("leaf_value")
      ?.required,
    true,
  );
});

Deno.test("Swift extraction is scoped to direct EdgeResponse properties while structural paths follow nested DTOs", () => {
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
  assert.deepStrictEqual([...report.swiftContract.propertyPaths].sort(), [
    "alpha",
    "beta",
    "beta[].leaf_value",
    "nested",
    "nested.inner_value",
  ]);
  assert.deepStrictEqual(report.validatedSchemaPaths, [
    "alpha",
    "beta",
    "beta[]",
    "beta[].leaf_value",
    "nested",
    "nested.inner_value",
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
    /Unable to structurally resolve schema definition at 'alpha'/,
  );
});

Deno.test("schema AST resolves identifiers by lexical TypeScript symbol", () => {
  const shadowedSchema = `
    const fields = {
      actual: { type: SchemaType.STRING },
    };
    const requiredFields = ["actual"];

    function unrelatedScope() {
      const fields = {
        decoy: { type: SchemaType.STRING },
      };
      const requiredFields = ["decoy"];
      return { fields, requiredFields };
    }

    export const getMerianResponseSchema = () => ({
      type: SchemaType.OBJECT,
      properties: fields,
      required: requiredFields,
    });
  `;
  const policy = fixturePolicy({
    minimumSchemaProperties: 1,
    minimumTopLevelSchemaProperties: 1,
    minimumSwiftProperties: 1,
    requiredTopLevelProperties: ["actual"],
  });
  const report = validateContractSources(
    shadowedSchema,
    "struct EdgeResponse: Codable { let actual: String }",
    policy,
  );
  assert.deepStrictEqual(report.validatedSchemaPaths, ["actual"]);

  const staleSwiftError = capturedContractError(() =>
    validateContractSources(
      shadowedSchema,
      "struct EdgeResponse: Codable { let decoy: String }",
      policy,
    )
  );
  assert.match(staleSwiftError.message, /schema 'actual'/);
  assert.match(staleSwiftError.message, /EdgeResponse\.decoy/);
});

Deno.test("schema AST fails closed on ambiguous local value declarations", () => {
  const ambiguousSchema = `
    function fields() {
      return { alpha: { type: SchemaType.STRING } };
    }
    function fields() {
      return { beta: { type: SchemaType.STRING } };
    }
    export const getMerianResponseSchema = () => ({
      type: SchemaType.OBJECT,
      properties: fields(),
    });
  `;
  const error = capturedContractError(() =>
    extractSchemaContract(ambiguousSchema)
  );
  assert.match(error.message, /Ambiguous TypeScript binding 'fields'/);
  assert.match(error.message, /2 local value declarations/);
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

Deno.test("contract validation rejects a renamed required nested field", () => {
  const renamedSchema = SCHEMA_FIXTURE.replaceAll(
    "leaf_value",
    "renamed_required_field",
  );
  const error = capturedContractError(() =>
    validateContractSources(
      renamedSchema,
      SWIFT_FIXTURE,
      fixturePolicy(),
    )
  );
  assert.match(error.message, /beta\[\]\.renamed_required_field/);
  assert.match(error.message, /EdgeResponse\.Beta\.leafValue/);
});

Deno.test("contract validation rejects nested primitive and array type drift", () => {
  const primitiveError = capturedContractError(() =>
    validateContractSources(
      SCHEMA_FIXTURE.replace(
        "leaf_value: { type: SchemaType.BOOLEAN }",
        "leaf_value: { type: SchemaType.STRING }",
      ),
      SWIFT_FIXTURE,
      fixturePolicy(),
    )
  );
  assert.match(primitiveError.message, /is 'string', but Swift uses 'Bool'/);

  const arrayError = capturedContractError(() =>
    validateContractSources(
      SCHEMA_FIXTURE,
      SWIFT_FIXTURE.replace("let beta: [Beta]?", "let beta: Beta?"),
      fixturePolicy(),
    )
  );
  assert.match(arrayError.message, /is an array, but Swift uses 'Beta\?'/);
});

Deno.test("contract validation rejects requiredness and nullability that Swift cannot decode", () => {
  const requirednessError = capturedContractError(() =>
    validateContractSources(
      SCHEMA_FIXTURE.replace('required: ["leaf_value"],', "required: [],"),
      SWIFT_FIXTURE,
      fixturePolicy(),
    )
  );
  assert.match(requirednessError.message, /may be absent/);
  assert.match(requirednessError.message, /requires non-optional 'Bool'/);

  const nullabilityError = capturedContractError(() =>
    validateContractSources(
      SCHEMA_FIXTURE.replace(
        "leaf_value: { type: SchemaType.BOOLEAN }",
        "leaf_value: { type: SchemaType.BOOLEAN, nullable: true }",
      ),
      SWIFT_FIXTURE,
      fixturePolicy(),
    )
  );
  assert.match(nullabilityError.message, /may be null/);
});

Deno.test("contract validation resolves CodingKeys and rejects stale aliases", () => {
  validateContractSources(
    SCHEMA_FIXTURE,
    SWIFT_FIXTURE,
    fixturePolicy(),
  );

  const error = capturedContractError(() =>
    validateContractSources(
      SCHEMA_FIXTURE,
      SWIFT_FIXTURE.replace(
        'case innerValue = "inner_value"',
        'case innerValue = "stale_inner_value"',
      ),
      fixturePolicy(),
    )
  );
  assert.match(error.message, /nested\.inner_value/);
  assert.match(error.message, /EdgeResponse\.Nested\.innerValue/);
});

Deno.test("custom decoders fail closed because their data flow is not statically provable", () => {
  const schema = `
    export const getMerianResponseSchema = () => ({
      type: SchemaType.OBJECT,
      properties: {
        pet_item: {
          type: SchemaType.OBJECT,
          properties: {
            snake_value: { type: SchemaType.STRING },
          },
          required: ["snake_value"],
        },
      },
      required: ["pet_item"],
    });
  `;
  const swift = `
    struct EdgeResponse: Decodable {
        let pet_item: PetItem?
    }

    struct PetItem: Decodable {
        let camelValue: String

        enum CodingKeys: String, CodingKey {
            case camelValue
        }
        enum SnakeCodingKeys: String, CodingKey {
            case camelValue = "snake_value"
        }

        init(from decoder: Decoder) throws {
            let camel = try decoder.container(keyedBy: CodingKeys.self)
            let snake = try decoder.container(keyedBy: SnakeCodingKeys.self)
            camelValue = try camel.decodeIfPresent(
                String.self,
                forKey: .camelValue
            ) ?? snake.decode(String.self, forKey: .camelValue)
        }
    }
  `;
  const policy = fixturePolicy({
    minimumSchemaProperties: 2,
    minimumTopLevelSchemaProperties: 1,
    minimumSwiftProperties: 1,
    requiredTopLevelProperties: ["pet_item"],
  });
  const error = capturedContractError(() =>
    validateContractSources(schema, swift, policy)
  );
  assert.match(error.message, /custom init\(from:\)/);
});

Deno.test("custom decoders outside the schema-backed graph do not affect Identify validation", () => {
  validateContractSources(
    SCHEMA_FIXTURE,
    `${SWIFT_FIXTURE}
      struct Unrelated: Decodable {
          let value: String

          enum AlternateKeys: String, CodingKey {
              case value = "alternate_value"
          }

          init(from decoder: Decoder) throws {
              let container = try decoder.container(
                  keyedBy: AlternateKeys.self
              )
              value = try container.decode(String.self, forKey: .value)
          }
      }
    `,
    fixturePolicy(),
  );
});

Deno.test("custom decoders in separate Swift extensions fail closed", () => {
  const extensionSource = `
    extension EdgeResponse.Beta {
        enum CodingKeys: String, CodingKey {
            case leafValue = "stale_leaf_value"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            leafValue = try container.decode(Bool.self, forKey: .leafValue)
        }
    }
  `;
  const error = capturedContractError(() =>
    validateContractSources(
      SCHEMA_FIXTURE,
      SWIFT_FIXTURE,
      fixturePolicy(),
      "schema.ts",
      extensionSource,
    )
  );
  assert.match(error.message, /EdgeResponse\.Beta/);
  assert.match(error.message, /custom init\(from:\)/);
});

Deno.test("CodingKeys declared in Swift extensions fail closed", () => {
  const extensionSource = `
    extension EdgeResponse.Nested {
        enum CodingKeys: String, CodingKey {
            case innerValue = "stale_inner_value"
        }
    }
  `;
  const error = capturedContractError(() =>
    validateContractSources(
      SCHEMA_FIXTURE,
      SWIFT_FIXTURE,
      fixturePolicy(),
      "schema.ts",
      extensionSource,
    )
  );
  assert.match(error.message, /EdgeResponse\.Nested/);
  assert.match(error.message, /extension EdgeResponse\.Nested\.CodingKeys/);
});

Deno.test("Swift extension syntax inside strings cannot affect decoder scanning", () => {
  validateContractSources(
    SCHEMA_FIXTURE,
    SWIFT_FIXTURE,
    fixturePolicy(),
    "schema.ts",
    `
      let documentation =
        "extension EdgeResponse.Beta { init(from decoder: Decoder) throws }"
      let rawDocumentation =
        #"extension EdgeResponse.Nested { enum CodingKeys: String, CodingKey {} }"#
    `,
  );
});

Deno.test("integer compatibility requires explicit safe bounds", () => {
  const integerSchema = (
    bounds: string,
  ) => `
    export const getMerianResponseSchema = () => ({
      type: SchemaType.OBJECT,
      properties: {
        count: {
          type: SchemaType.INTEGER,
          ${bounds}
        },
      },
      required: ["count"],
    });
  `;
  const policy = fixturePolicy({
    minimumSchemaProperties: 1,
    minimumTopLevelSchemaProperties: 1,
    minimumSwiftProperties: 1,
    requiredTopLevelProperties: ["count"],
  });
  const unboundedError = capturedContractError(() =>
    validateContractSources(
      integerSchema(""),
      "struct EdgeResponse: Codable { let count: UInt8 }",
      policy,
    )
  );
  assert.match(
    unboundedError.message,
    /must declare finite minimum and maximum/,
  );

  validateContractSources(
    integerSchema("minimum: 0, maximum: 255,"),
    "struct EdgeResponse: Codable { let count: UInt8 }",
    policy,
  );

  for (
    const bounds of [
      "minimum: -1, maximum: 255,",
      "minimum: 0, maximum: 256,",
    ]
  ) {
    const rangeError = capturedContractError(() =>
      validateContractSources(
        integerSchema(bounds),
        "struct EdgeResponse: Codable { let count: UInt8 }",
        policy,
      )
    );
    assert.match(rangeError.message, /Swift uses 'UInt8'/);
  }
});

Deno.test("integer bounds resolve lexical constants and reject unsafe ranges", () => {
  const schema = `
    const MIN_COUNT = 1;
    const MAX_COUNT = 99999;
    function unrelatedScope() {
      const MIN_COUNT = -999;
      const MAX_COUNT = 1e30;
      return { MIN_COUNT, MAX_COUNT };
    }
    export const getMerianResponseSchema = () => ({
      type: SchemaType.OBJECT,
      properties: {
        count: {
          type: SchemaType.INTEGER,
          minimum: MIN_COUNT,
          maximum: MAX_COUNT,
        },
      },
      required: ["count"],
    });
  `;
  const policy = fixturePolicy({
    minimumSchemaProperties: 1,
    minimumTopLevelSchemaProperties: 1,
    minimumSwiftProperties: 1,
    requiredTopLevelProperties: ["count"],
  });
  validateContractSources(
    schema,
    "struct EdgeResponse: Codable { let count: Int }",
    policy,
  );

  const unsafeError = capturedContractError(() =>
    validateContractSources(
      schema.replace("const MAX_COUNT = 99999;", "const MAX_COUNT = 1e30;"),
      "struct EdgeResponse: Codable { let count: Int }",
      policy,
    )
  );
  assert.match(unsafeError.message, /must be JavaScript safe integers/);
});

Deno.test("JSON number compatibility permits Double but rejects narrower wire types", () => {
  const schema = `
    export const getMerianResponseSchema = () => ({
      type: SchemaType.OBJECT,
      properties: {
        score: { type: SchemaType.NUMBER, minimum: 0, maximum: 1 },
      },
      required: ["score"],
    });
  `;
  const policy = fixturePolicy({
    minimumSchemaProperties: 1,
    minimumTopLevelSchemaProperties: 1,
    minimumSwiftProperties: 1,
    requiredTopLevelProperties: ["score"],
  });
  const unboundedError = capturedContractError(() =>
    validateContractSources(
      schema.replace(", minimum: 0, maximum: 1", ""),
      "struct EdgeResponse: Codable { let score: Double }",
      policy,
    )
  );
  assert.match(
    unboundedError.message,
    /must declare finite minimum and maximum/,
  );
  validateContractSources(
    schema,
    "struct EdgeResponse: Codable { let score: Double }",
    policy,
  );
  for (const type of ["Float", "CGFloat", "Decimal"]) {
    const error = capturedContractError(() =>
      validateContractSources(
        schema,
        `struct EdgeResponse: Codable { let score: ${type} }`,
        policy,
      )
    );
    assert.match(error.message, new RegExp(`Swift uses '${type}'`));
  }
});

Deno.test("contract validation permits Swift to decode schema-required values optionally", () => {
  validateContractSources(
    SCHEMA_FIXTURE,
    SWIFT_FIXTURE
      .replace("let innerValue: Double", "let innerValue: Double?")
      .replace("let leafValue: Bool", "let leafValue: Bool?"),
    fixturePolicy(),
  );
});

Deno.test("Swift-only fields require an explicit server-added path decision", () => {
  const swiftWithServerField = SWIFT_FIXTURE.replace(
    "let beta: [Beta]?",
    "let server_value: String?\n    let beta: [Beta]?",
  );
  const error = capturedContractError(() =>
    validateContractSources(
      SCHEMA_FIXTURE,
      swiftWithServerField,
      fixturePolicy(),
    )
  );
  assert.match(error.message, /server_value/);
  assert.match(error.message, /not an approved server-added path/);

  validateContractSources(
    SCHEMA_FIXTURE,
    swiftWithServerField,
    fixturePolicy({
      intentionallyServerAddedSwiftPaths: new Set(["server_value"]),
    }),
  );
});

Deno.test("contract exception allowlists fail closed when stale", () => {
  const serverOnlyError = capturedContractError(() =>
    validateContractSources(
      SCHEMA_FIXTURE,
      SWIFT_FIXTURE,
      fixturePolicy({
        intentionallyServerOnlyProperties: new Set(["missing_schema_field"]),
      }),
    )
  );
  assert.match(serverOnlyError.message, /exception 'missing_schema_field'/);

  const serverAddedError = capturedContractError(() =>
    validateContractSources(
      SCHEMA_FIXTURE,
      SWIFT_FIXTURE,
      fixturePolicy({
        intentionallyServerAddedSwiftPaths: new Set(["missing_swift_field"]),
      }),
    )
  );
  assert.match(serverAddedError.message, /exception 'missing_swift_field'/);
});

Deno.test("canonical candidate-field rename cannot pass structural validation", async () => {
  const [schemaSource, swiftSource] = await Promise.all([
    Deno.readTextFile(canonicalIdentifySchemaPath),
    Deno.readTextFile(inferenceEdgeDTOsPath),
  ]);
  const candidatesStart = schemaSource.indexOf("  candidates: {");
  const candidatesEnd = schemaSource.indexOf(
    "  image_quality: {",
    candidatesStart,
  );
  assert(candidatesStart >= 0);
  assert(candidatesEnd > candidatesStart);

  const candidatesSource = schemaSource.slice(
    candidatesStart,
    candidatesEnd,
  );
  const renamedCandidates = candidatesSource
    .replace(
      "scientific_name: { type: SchemaType.STRING }",
      "renamed_scientific_name: { type: SchemaType.STRING }",
    )
    .replace('"scientific_name"', '"renamed_scientific_name"');
  assert.notEqual(renamedCandidates, candidatesSource);

  const renamedSchema = schemaSource.slice(0, candidatesStart) +
    renamedCandidates +
    schemaSource.slice(candidatesEnd);
  const error = capturedContractError(() =>
    validateContractSources(
      renamedSchema,
      swiftSource,
      defaultValidationPolicy,
      canonicalIdentifySchemaPath,
    )
  );
  assert.match(
    error.message,
    /schema 'candidates\[\]\.renamed_scientific_name' has no Swift property/,
  );
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
    report.swiftExtensionSourceCount > 1,
    "Canonical validation must scan the iOS Swift source graph for DTO extensions.",
  );
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
  for (
    const requiredPath of [
      "candidates[].scientific_name",
      "candidates[].confidence_score",
      "image_quality.overall_score",
      "pet_identification.species_group",
      "pet_identification.label_type",
    ]
  ) {
    assert(report.validatedSchemaPaths.includes(requiredPath));
  }
});
