import {
  assert,
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  ContractValueError,
  merianDescribeModelContract,
  merianModelContract,
  parseDescribeIdentification,
  parseIdentifySuccessEnvelope,
  parseMerianIdentification,
  providerSchemaFromContract,
} from "./contract.ts";
import { getMerianResponseSchema } from "./schema.ts";
import { getDescribeResponseSchema } from "../../identify-describe/schema.ts";

function validModelResponse(): Record<string, unknown> {
  return {
    is_biological_subject: true,
    is_live_capture: true,
    scientific_name: "Danaus plexippus",
    common_name: "Monarch Butterfly",
    confidence_score: 0.87,
    ai_reasoning: "The wing pattern and venation support this identification.",
    extracted_visual_traits: [
      "orange wings",
      "black venation",
      "white marginal spots",
    ],
    candidates: [
      {
        scientific_name: "Danaus gilippus",
        confidence_score: 0.2,
        distinguishing_feature: "forewing veins differ",
      },
    ],
    image_quality: {
      sharpness: 8,
      framing: 7,
      diagnostic_utility: 9,
      overall_score: 82,
    },
    pet_identification: null,
  };
}

function validEnvelope(): Record<string, unknown> {
  const model = validModelResponse();
  return {
    success: true,
    data: {
      ...model,
      scan_id: "00000000-0000-4000-8000-000000000123",
      inference_tier: "flash",
      blur_score: 0.2,
      colors: [],
      estimated_size_cm: 8.5,
      insight_data: {
        ai_reasoning: model.ai_reasoning,
        hazard_type: "none",
      },
      taxonomy: {
        kingdom: "Animalia",
        phylum: "Arthropoda",
        class: "Insecta",
        order: "Lepidoptera",
        family: "Nymphalidae",
        genus: "Danaus",
      },
    },
  };
}

Deno.test("provider schema is generated from the executable model contract", () => {
  const schema = providerSchemaFromContract(merianModelContract);

  assertEquals(schema.type, "OBJECT");
  assertEquals(schema.properties?.confidence_score, {
    type: "NUMBER",
    minimum: 0,
    maximum: 1,
    description:
      "Calibrated confidence in the primary identification (0.0–1.0). ANCHORS: ≥0.95 = key diagnostic features are unambiguously visible in the visual evidence AND no visually confusable species shares those exact features in the same region and season; 0.80–0.94 = confident but one or more similar species cannot be definitively ruled out from the visual evidence alone; 0.60–0.79 = probable identification, multiple visually similar species remain plausible; <0.60 = uncertain, visual evidence lacks sufficient diagnostic detail for reliable species-level identification. CRITICAL: base confidence ONLY on morphological features visible in the visual evidence. NEVER inflate it because a species is locally common, seasonally expected, or habitat-appropriate — those factors resolve the primary identification but do not raise confidence. Most field photographs of common species warrant a score of 0.70–0.88.",
  });
  assert(schema.required?.includes("is_biological_subject"));
  assert(schema.required?.includes("image_quality"));
  assertEquals(schema.properties?.extracted_visual_traits?.minItems, "1");
  assertEquals(schema.properties?.extracted_visual_traits?.maxItems, "10");
  assertEquals(
    schema.properties?.scientific_name?.maxLength,
    "255",
  );
  assertEquals(
    schema.properties?.candidates?.items?.properties?.scientific_name
      ?.minLength,
    "1",
  );
  assert(Object.isFrozen(merianModelContract));
  assert(Object.isFrozen(merianModelContract.fields.confidence_score));
});

Deno.test("Identify exports the generated provider schema and caches by trigger", () => {
  const expected = providerSchemaFromContract(merianModelContract);
  const first = getMerianResponseSchema(0.85);
  const second = getMerianResponseSchema(0.85);

  assertEquals(first as unknown, expected);
  assert(first === second);
});

Deno.test("Describe exports and enforces its zero-quality contract", () => {
  const expected = providerSchemaFromContract(merianDescribeModelContract);
  assertEquals(getDescribeResponseSchema() as unknown, expected);

  const input = validModelResponse();
  input.is_live_capture = false;
  input.image_quality = {
    sharpness: 0,
    framing: 0,
    diagnostic_utility: 0,
    overall_score: 0,
  };
  const parsed = parseDescribeIdentification(input);
  assertEquals(parsed.image_quality.overall_score, 0);
  assertEquals(parsed.is_live_capture, false);

  (
    input.image_quality as Record<string, unknown>
  ).overall_score = 1;
  assertThrows(
    () => parseDescribeIdentification(input),
    ContractValueError,
    "between 0 and 0",
  );

  input.is_live_capture = true;
  assertThrows(
    () => parseDescribeIdentification(input),
    ContractValueError,
    "must be false",
  );
});

Deno.test("model parsing validates nested fields and strips provider extras", () => {
  const input = validModelResponse();
  input.provider_internal = "must not survive";
  const parsed = parseMerianIdentification(input) as unknown as Record<
    string,
    unknown
  >;

  assertEquals(parsed.provider_internal, undefined);
  assertEquals(parsed.scientific_name, "Danaus plexippus");
});

Deno.test("model parsing enforces numeric bounds and integer semantics at runtime", () => {
  const confidence = validModelResponse();
  confidence.confidence_score = 1.01;
  const confidenceError = assertThrows(
    () => parseMerianIdentification(confidence),
    ContractValueError,
  );
  assert(confidenceError.message.includes("model_response.confidence_score"));

  const quality = validModelResponse();
  (quality.image_quality as Record<string, unknown>).overall_score = 101;
  const qualityError = assertThrows(
    () => parseMerianIdentification(quality),
    ContractValueError,
  );
  assert(qualityError.message.includes(
    "model_response.image_quality.overall_score",
  ));
  assert(qualityError.message.includes("between 0 and 100"));

  const fractionalQuality = validModelResponse();
  (
    fractionalQuality.image_quality as Record<string, unknown>
  ).overall_score = 99.5;
  assertThrows(
    () => parseMerianIdentification(fractionalQuality),
    ContractValueError,
    "finite safe integer",
  );

  const candidate = validModelResponse();
  (candidate.candidates as Record<string, unknown>[])[0].confidence_score =
    -0.1;
  const candidateError = assertThrows(
    () => parseMerianIdentification(candidate),
    ContractValueError,
  );
  assert(candidateError.message.includes(
    "model_response.candidates[0].confidence_score",
  ));
});

Deno.test("model parsing fails closed on requiredness, arrays, and enums", () => {
  const missing = validModelResponse();
  delete missing.is_biological_subject;
  assertThrows(
    () => parseMerianIdentification(missing),
    ContractValueError,
    "required property is missing",
  );

  const oversized = validModelResponse();
  oversized.extracted_visual_traits = Array.from(
    { length: 11 },
    (_, index) => `trait-${index}`,
  );
  assertThrows(
    () => parseMerianIdentification(oversized),
    ContractValueError,
    "at most 10",
  );

  const invalidEnum = validModelResponse();
  invalidEnum.ecology_type = "oceanic";
  assertThrows(
    () => parseMerianIdentification(invalidEnum),
    ContractValueError,
    "expected one of",
  );
});

Deno.test("final envelope parsing validates server-added and nested fields", () => {
  const parsed = parseIdentifySuccessEnvelope(validEnvelope());

  assertEquals(parsed.success, true);
  assertEquals(parsed.data.taxonomy?.class, "Insecta");
  assertEquals(parsed.data.estimated_size_cm, 8.5);
  assert(Object.isFrozen(parsed));
  assert(Object.isFrozen(parsed.data));
  assert(Object.isFrozen(parsed.data.taxonomy));

  const malformed = validEnvelope();
  (
    (malformed.data as Record<string, unknown>).taxonomy as Record<
      string,
      unknown
    >
  ).class = false;
  const error = assertThrows(
    () => parseIdentifySuccessEnvelope(malformed),
    ContractValueError,
  );
  assert(error.message.includes("response.data.taxonomy.class"));
});

Deno.test("final envelope validates the literal success state and strips extras", () => {
  const input = validEnvelope();
  (input.data as Record<string, unknown>).unexpected_cache_column = "secret";
  const parsed = parseIdentifySuccessEnvelope(input) as unknown as {
    success: boolean;
    data: Record<string, unknown>;
  };
  assertEquals(parsed.data.unexpected_cache_column, undefined);

  input.success = false;
  assertThrows(
    () => parseIdentifySuccessEnvelope(input),
    ContractValueError,
    "must be true",
  );
});

Deno.test("final envelope requires fields emitted by every Identify route", () => {
  for (
    const property of [
      "blur_score",
      "colors",
      "candidates",
      "estimated_size_cm",
      "image_quality",
      "pet_identification",
    ] as const
  ) {
    const input = validEnvelope();
    delete (input.data as Record<string, unknown>)[property];
    const error = assertThrows(
      () => parseIdentifySuccessEnvelope(input),
      ContractValueError,
    );
    assert(error.message.includes(`response.data.${property}`));
    assert(error.message.includes("required property is missing"));
  }
});

Deno.test("final envelope rejects invalid server-added numeric and URL values", () => {
  const invalidTaxon = validEnvelope();
  (invalidTaxon.data as Record<string, unknown>).gbif_taxon_key = -1;
  assertThrows(
    () => parseIdentifySuccessEnvelope(invalidTaxon),
    ContractValueError,
    "between 0",
  );

  const oversizedUrl = validEnvelope();
  (oversizedUrl.data as Record<string, unknown>).wikipedia_url = `https://x/${
    "a".repeat(4_100)
  }`;
  assertThrows(
    () => parseIdentifySuccessEnvelope(oversizedUrl),
    ContractValueError,
    "at most 4096",
  );
});
