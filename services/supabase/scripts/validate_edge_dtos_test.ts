import assert from "node:assert/strict";
import {
  canonicalSwiftDTOPath,
  collectContractPaths,
  ContractValidationError,
  GENERATED_SWIFT_BEGIN,
  GENERATED_SWIFT_END,
  iosSourceGraphRoot,
  renderGeneratedSwiftDTOBlock,
  replaceGeneratedSwiftDTOBlock,
  REQUIRED_IOS_PRODUCTION_SOURCE_ROOTS,
  REQUIRED_MODEL_PATHS,
  REQUIRED_WIRE_PATHS,
  validateAPIContracts,
  validateContractDefinitions,
  validateGeneratedSwiftSource,
  validateSwiftSourceOwnership,
} from "./validate_edge_dtos.ts";
import {
  identifyWireEnvelopeContract,
  merianModelContract,
} from "../functions/_shared/identify/contract.ts";

function capturedError(action: () => void): ContractValidationError {
  try {
    action();
  } catch (error) {
    assert(error instanceof ContractValidationError);
    return error;
  }
  throw new Error("Expected contract validation to fail.");
}

Deno.test("executable contracts contain every model and final wire sentinel", () => {
  const model = collectContractPaths(merianModelContract);
  const wire = collectContractPaths(identifyWireEnvelopeContract);

  for (const path of REQUIRED_MODEL_PATHS) {
    assert(model.paths.has(path), `Missing model path '${path}'.`);
  }
  for (const path of REQUIRED_WIRE_PATHS) {
    assert(wire.paths.has(path), `Missing wire path '${path}'.`);
  }
  assert.deepStrictEqual([...wire.ignoredSwiftPaths].sort(), [
    "data.ai_reasoning",
    "data.extracted_visual_traits",
  ]);
});

Deno.test("contract definitions fail closed through bounded numeric coverage", () => {
  const definitions = validateContractDefinitions();

  assert(definitions.model.numericPaths.has("confidence_score"));
  assert(definitions.model.numericPaths.has(
    "image_quality.overall_score",
  ));
  assert(definitions.wire.numericPaths.has("data.estimated_size_cm"));
  assert(definitions.wire.numericPaths.has("data.gbif_taxon_key"));
  assert.deepStrictEqual(definitions.generatedStructNames, [
    "EdgeResponse",
    "EdgeResponseWrapper",
    "IdentificationCandidate",
    "ImageQuality",
    "Insight",
    "PetIdentificationDTO",
    "SpeciesInsights",
    "Taxonomy",
  ]);
});

Deno.test("Swift generation owns nested structure, types, keys, and decoders", () => {
  const generated = renderGeneratedSwiftDTOBlock();

  assert(generated.startsWith(GENERATED_SWIFT_BEGIN));
  assert(generated.endsWith(GENERATED_SWIFT_END));
  assert.match(generated, /struct EdgeResponseWrapper: Codable/);
  assert.match(generated, /struct EdgeResponse: Codable/);
  assert.match(generated, /struct IdentificationCandidate: Codable/);
  assert.match(generated, /let confidence_score: Double\?/);
  assert.match(generated, /let individual_count: Int\?/);
  assert.doesNotMatch(generated, /\bUInt8\b/);
  assert.match(
    generated,
    /case speciesGroup = "species_group"/,
  );
  assert.match(
    generated,
    /init\(from decoder: Decoder\) throws/g,
  );
  assert.match(
    generated,
    /distinguishing_feature = try container\.decodeIfPresent\(String\.self/,
  );
});

Deno.test("checked-in Swift block must exactly match generated output", async () => {
  const source = await Deno.readTextFile(canonicalSwiftDTOPath);
  validateGeneratedSwiftSource(source);

  const renamed = source.replace(
    "let confidence_score: Double?",
    "let confidence_score: Bool?",
  );
  const renamedError = capturedError(() =>
    validateGeneratedSwiftSource(renamed)
  );
  assert.match(renamedError.message, /stale/);

  const decoderOverride = source.replace(
    "init(from decoder: Decoder) throws {",
    "init(from decoder: Decoder) throws {\n        // injected",
  );
  const decoderError = capturedError(() =>
    validateGeneratedSwiftSource(decoderOverride)
  );
  assert.match(decoderError.message, /stale/);

  const renamedNestedCandidate = source.replace(
    "let scientific_name: String\n        let confidence_score: Double",
    "let actual: String\n        let confidence_score: Double",
  );
  const nestedCandidateError = capturedError(() =>
    validateGeneratedSwiftSource(renamedNestedCandidate)
  );
  assert.match(nestedCandidateError.message, /stale/);
});

Deno.test("generated Swift validation rejects missing and duplicate markers", () => {
  const generated = renderGeneratedSwiftDTOBlock();
  const missingError = capturedError(() =>
    validateGeneratedSwiftSource(
      generated.replace(GENERATED_SWIFT_BEGIN, "// removed"),
    )
  );
  assert.match(missingError.message, /missing/);

  const duplicateError = capturedError(() =>
    validateGeneratedSwiftSource(`${generated}\n${generated}`)
  );
  assert.match(duplicateError.message, /duplicate/);
});

Deno.test("Swift regeneration replaces only the marked block", () => {
  const stale = [
    "import Foundation",
    GENERATED_SWIFT_BEGIN,
    "stale",
    GENERATED_SWIFT_END,
    "// Hand-written trailing DTOs stay intact.",
  ].join("\n");
  const regenerated = replaceGeneratedSwiftDTOBlock(stale);

  assert(regenerated.startsWith("import Foundation\n"));
  assert(regenerated.includes(renderGeneratedSwiftDTOBlock()));
  assert(regenerated.endsWith("// Hand-written trailing DTOs stay intact."));
  validateGeneratedSwiftSource(regenerated);
});

Deno.test("Swift ownership rejects direct extensions with decoder aliases", () => {
  const error = capturedError(() =>
    validateSwiftSourceOwnership([
      {
        path: "/tmp/Injected.swift",
        source: `
          typealias PayloadDecoder = Decoder
          extension EdgeResponse {
              init(from decoder: PayloadDecoder) throws {
                  self = try decoder.singleValueContainer().decode(Self.self)
              }
          }
        `,
      },
    ])
  );
  assert.match(error.message, /extends generated DTO 'EdgeResponse'/);
});

Deno.test("Swift ownership follows aliases used as extension targets", () => {
  const error = capturedError(() =>
    validateSwiftSourceOwnership([
      {
        path: "/tmp/Aliased.swift",
        source: `
          typealias ResponseAlias = EdgeResponse
          typealias PayloadDecoder = Decoder
          extension ResponseAlias {
              init(from decoder: PayloadDecoder) throws {
                  fatalError()
              }
          }
        `,
      },
    ])
  );
  assert.match(error.message, /extends generated DTO 'EdgeResponse'/);
});

Deno.test("Swift ownership follows qualified nested DTO aliases", () => {
  const error = capturedError(() =>
    validateSwiftSourceOwnership([
      {
        path: "/tmp/Nested.swift",
        source: `
          typealias CandidateAlias = EdgeResponse.IdentificationCandidate
          extension CandidateAlias {
              enum StaleKeys: String, CodingKey { case old }
          }
        `,
      },
    ])
  );
  assert.match(
    error.message,
    /extends generated DTO 'EdgeResponse\.IdentificationCandidate'/,
  );
});

Deno.test("Swift ownership follows aliases across source files", () => {
  const error = capturedError(() =>
    validateSwiftSourceOwnership([
      {
        path: "/tmp/Alias.swift",
        source: "typealias SharedResponseAlias = EdgeResponse",
      },
      {
        path: "/tmp/Extension.swift",
        source: `
          extension SharedResponseAlias {
              enum StaleKeys: String, CodingKey { case old }
          }
        `,
      },
    ])
  );
  assert.match(error.message, /extends generated DTO 'EdgeResponse'/);
});

Deno.test("Swift ownership cannot be redirected by a later alias binding", () => {
  const error = capturedError(() =>
    validateSwiftSourceOwnership([
      {
        path: "/tmp/Shadowed.swift",
        source: `
          typealias ResponseAlias = EdgeResponse
          typealias ResponseAlias = DecoyResponse
          extension ResponseAlias {
              enum StaleKeys: String, CodingKey { case old }
          }
        `,
      },
    ])
  );
  assert.match(error.message, /extends generated DTO 'EdgeResponse'/);
});

Deno.test("Swift ownership recognizes module-qualified generated targets", () => {
  const error = capturedError(() =>
    validateSwiftSourceOwnership([
      {
        path: "/tmp/Qualified.swift",
        source: `
          extension Merian.EdgeResponse.IdentificationCandidate {
              enum StaleKeys: String, CodingKey { case old }
          }
        `,
      },
    ])
  );
  assert.match(
    error.message,
    /extends generated DTO 'EdgeResponse\.IdentificationCandidate'/,
  );
});

Deno.test("Swift ownership scans handwritten code in the canonical DTO file", async () => {
  const canonical = await Deno.readTextFile(canonicalSwiftDTOPath);
  const error = capturedError(() =>
    validateSwiftSourceOwnership([
      {
        path: canonicalSwiftDTOPath,
        source: `${canonical}

          typealias CanonicalResponseAlias = EdgeResponse
          extension CanonicalResponseAlias {
              init(stale: Bool) {
                  fatalError()
              }
          }
        `,
      },
    ])
  );
  assert.match(error.message, /extends generated DTO 'EdgeResponse'/);
});

Deno.test("unrelated domain type with a nested DTO's simple name remains legal", () => {
  validateSwiftSourceOwnership([
    {
      path: "/tmp/Domain.swift",
      source: `
        struct IdentificationCandidate {
            let scientificName: String
        }
      `,
    },
  ]);
});

Deno.test("generated top-level DTO redeclarations are rejected", () => {
  const error = capturedError(() =>
    validateSwiftSourceOwnership([
      {
        path: "/tmp/Decoy.swift",
        source: "struct EdgeResponse { let decoy: String }",
      },
    ])
  );
  assert.match(error.message, /redeclares generated DTO 'EdgeResponse'/);
});

Deno.test("canonical validation scans the complete apps/ios graph", async () => {
  assert(iosSourceGraphRoot.endsWith("apps/ios"));
  const report = await validateAPIContracts();

  assert(report.swiftSourceCount > 400);
  assert(report.modelPathCount >= REQUIRED_MODEL_PATHS.length);
  assert(report.wirePathCount >= REQUIRED_WIRE_PATHS.length);
  assert(report.numericPathCount > 10);
  for (const root of REQUIRED_IOS_PRODUCTION_SOURCE_ROOTS) {
    assert(
      report.productionSourceRootCounts[root] > 0,
      `Production source root '${root}' was omitted.`,
    );
  }
});
