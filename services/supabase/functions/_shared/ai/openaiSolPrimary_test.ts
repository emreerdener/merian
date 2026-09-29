import { assert, assertEquals, assertThrows } from "@std/assert";
import type { AIAttemptSnapshot } from "./contracts.ts";
import { isIdentificationProviderAssignment } from "./admission.ts";
import { prepareMultimodalResultPolicy } from "./multimodalResultPolicy.ts";
import {
  buildOpenAIPhotoRequestParameters,
  openAIPhotoSnapshot,
} from "./openaiPhoto.ts";
import {
  buildOpenAIPhotoModelRequestParameters,
  isOpenAIPhotoModelProfile,
  openAIPhotoModelSnapshot,
} from "./openaiPhotoModels.ts";
import {
  decodeOpenAIDraft,
  isOpenAIProfile,
  type OpenAISchema,
} from "./openaiRequest.ts";
import {
  buildSolPhotoPrimaryRequest,
  SOL_PRIMARY_PROFILE,
  SOL_PRIMARY_SCHEMA,
  solPhotoPrimarySnapshot,
} from "./openaiSolPrimary.ts";
import {
  decodeSolPhotoPrimaryDraft,
  solPhotoPrimaryModelContract,
} from "./openaiSolPrimaryContract.ts";
import { solPhotoPrimaryInstructions } from "./openaiSolPrimaryInstructions.ts";
import {
  identificationResultContract,
  merianModelContract,
  PRIMARY_IDENTIFICATION_SCHEMA,
} from "../identify/contract.ts";
import {
  openAIPhotoRequestFixture,
  openAITextFixture,
} from "./testing/openaiFixtures.ts";
import {
  solPrimaryAlternativeFixture,
  solPrimaryDraftFixture,
} from "./testing/openaiSolPrimaryFixtures.ts";
import {
  fingerprintBytes,
  fingerprintJson,
} from "../../identify-multimodal/comparison/fingerprint.ts";

const request = openAIPhotoRequestFixture();
const baseline = () =>
  buildOpenAIPhotoModelRequestParameters(
    request,
    openAIPhotoModelSnapshot(request, "openai_photo_sol_low_v1"),
  );
const candidate = () =>
  buildSolPhotoPrimaryRequest(request, solPhotoPrimarySnapshot(request));

Deno.test("explicit-primary candidate instruction/schema/configuration fingerprints stay frozen", async () => {
  const parameters = candidate();
  assertEquals(
    await fingerprintBytes(new TextEncoder().encode(parameters.instructions)),
    "f3800507909d5a9087092956690e2f75cc104fd79f07b399d5227f086f5bb5d8",
  );
  assertEquals(
    await fingerprintJson(parameters.text.format),
    "bb764f5a97c4d6a21e67aeeaae71d0cd73c9e54e69135ceebf92996c7960a9fb",
  );
  assertEquals(
    await fingerprintJson(solPhotoPrimarySnapshot(request)),
    "490e03841632b7209833ca2676c89e60d66a2b2b7fa5e83f37222611763999a3",
  );
});

function assertStrict(schema: OpenAISchema) {
  if (schema.properties) {
    assertEquals(schema.required, Object.keys(schema.properties));
    assertEquals(schema.additionalProperties, false);
    for (const child of Object.values(schema.properties)) assertStrict(child);
  }
  if (schema.items) assertStrict(schema.items);
}

Deno.test("explicit-primary Sol changes only its isolated instructions/schema and preserves the complete photo request", () => {
  const base = baseline();
  const result = candidate();
  const { instructions: _bi, text: _bt, ...b } = base;
  const { instructions: _ci, text: _ct, ...c } = result;
  assertEquals(c, b);
  assertEquals(result.model, "gpt-6-sol");
  assertEquals(result.reasoning, { effort: "low" });
  assertEquals(result.max_output_tokens, 8192);
  assertEquals(result.text.format.strict, true);
  assertEquals(result.text.format.name, SOL_PRIMARY_SCHEMA);
  assertStrict(result.text.format.schema);
  for (
    const key of [
      "ai_reasoning",
      "confidence_score",
      "image_quality",
      "pet_identification",
    ]
  ) {
    assertEquals(
      result.text.format.schema.properties![key],
      base.text.format.schema.properties![key],
    );
  }
  assertEquals(result.text.format.schema.properties!.resolution.enum, [
    "species",
    "genus",
    "family",
    "unresolved_biological",
    "non_biological",
  ]);
  assertEquals(result.text.format.schema.properties!.candidates.maxItems, 2);
  assertEquals(result.text.format.schema.properties!.candidates.type, [
    "array",
    "null",
  ]);
  assert(!("primary_identification" in result.text.format.schema.properties!));
  assert(!("resolution" in merianModelContract.fields));
  assert(
    !("taxon_rank" in
      merianModelContract.fields.candidates.contract.items.fields),
  );
  assert(
    Object.isFrozen(
      solPhotoPrimaryModelContract.fields.candidates.contract.items.fields,
    ),
  );
  assertEquals(baseline(), base);
});

Deno.test("explicit-primary instructions reject changed or duplicate anchors and retain explanation/geological/pet guidance", () => {
  const base = baseline().instructions;
  const text = candidate().instructions;
  assert(!text.includes("MUST populate exactly 2"));
  assert(!text.includes("use an empty `candidates` array"));
  assert(text.includes("Canis lupus familiaris"));
  assert(text.includes("existing 1–3 sentence explanation format"));
  assert(text.includes("unphotographed features are unknown, not absent"));
  assertEquals(
    text.split("\n").find((line) =>
      line.startsWith("- **Geological Exceptions:")
    ),
    base.split("\n").find((line) =>
      line.startsWith("- **Geological Exceptions:")
    ),
  );
  assertThrows(() =>
    solPhotoPrimaryInstructions(
      base.replace(
        "when not alive — identify these to the species level.",
        "drift",
      ),
    )
  );
  assertThrows(() =>
    solPhotoPrimaryInstructions(
      base + "when not alive — identify these to the species level.",
    )
  );
});

Deno.test("new profile cannot impersonate production, historical evaluators, confidence policy or a durable schema", () => {
  const snapshot = solPhotoPrimarySnapshot(request);
  assertEquals(isOpenAIProfile(SOL_PRIMARY_PROFILE), false);
  assertEquals(isOpenAIPhotoModelProfile(SOL_PRIMARY_PROFILE), false);
  assertEquals(
    isIdentificationProviderAssignment({
      provider: "openai",
      binding: snapshot.binding,
      inputProfile: "multimodal_photo_v1",
      permission: "openai",
    }),
    false,
  );
  assertThrows(() =>
    prepareMultimodalResultPolicy(snapshot as unknown as AIAttemptSnapshot)
  );
  assertThrows(() =>
    buildOpenAIPhotoRequestParameters(
      request,
      snapshot as unknown as ReturnType<typeof openAIPhotoSnapshot>,
    )
  );
  assertThrows(() =>
    buildOpenAIPhotoModelRequestParameters(
      request,
      snapshot as unknown as ReturnType<typeof openAIPhotoModelSnapshot>,
    )
  );
  assertThrows(() => decodeOpenAIDraft(solPrimaryDraftFixture()));
  assertEquals(identificationResultContract(SOL_PRIMARY_SCHEMA), "legacy");
  assert(SOL_PRIMARY_SCHEMA as string !== PRIMARY_IDENTIFICATION_SCHEMA);
  assertEquals(snapshot.confidence, "openai_unqualified_v1");
  for (
    const change of [
      { profile: "openai_photo_sol_low_v1" },
      { prompt: "changed" },
      { schema: PRIMARY_IDENTIFICATION_SCHEMA },
      { model: "gpt-6-luna" },
      { safety: null },
      { timeoutMs: 180000 },
      { confidence: "qualified" },
      { generation: { ...snapshot.generation, reasoningEffort: "high" } },
      { unexpected: true },
    ]
  ) {
    assertThrows(() =>
      buildSolPhotoPrimaryRequest(
        request,
        { ...snapshot, ...change } as typeof snapshot,
      )
    );
  }
});

Deno.test("explicit-primary input remains still-photo only with whole-observation rejection", () => {
  assertThrows(() => solPhotoPrimarySnapshot(openAITextFixture()));
  assertThrows(() =>
    solPhotoPrimarySnapshot({
      ...request,
      capture: { ...request.capture, hasVideo: true },
    })
  );
  assertThrows(() =>
    solPhotoPrimarySnapshot({
      ...request,
      evidence: [...request.evidence, {
        kind: "audio",
        order: 2,
        inputIndex: 0,
        lineage: null,
        mimeType: "audio/wav",
        data: "AQID",
      }],
    })
  );
  assertThrows(() =>
    solPhotoPrimarySnapshot({
      ...request,
      evidence: [{
        kind: "image",
        order: 0,
        inputIndex: 0,
        lineage: { kind: "video_frame", clipIndex: 0, frameIndex: 0 },
        mimeType: "image/png",
        data: "AQID",
      }],
    })
  );
});

Deno.test("strict primary decoding rejects every missing root key, unknown keys, unknown states and extra nested keys", () => {
  const value = solPrimaryDraftFixture();
  for (const key of Object.keys(value)) {
    const copy = { ...value };
    delete copy[key];
    assertThrows(
      () => decodeSolPhotoPrimaryDraft(copy),
      Error,
      "",
      key,
    );
  }
  for (
    const change of [
      { resolution: "subspecies" },
      { resolution: null },
      { unexpected: true },
      { primary_identification: {} },
      { confidence_score: 1.1 },
      {
        image_quality: {
          ...(value.image_quality as object),
          taxon_rank: "species",
        },
      },
    ]
  ) assertThrows(() => decodeSolPhotoPrimaryDraft({ ...value, ...change }));
});

Deno.test("species alternatives must each declare species rank and never exceed two", () => {
  const value = solPrimaryDraftFixture();
  const c = solPrimaryAlternativeFixture();
  assertEquals(
    decodeSolPhotoPrimaryDraft({ ...value, candidates: [c, c] }).candidates
      ?.length,
    2,
  );
  for (
    const candidates of [
      null,
      [c, c, c],
      [{ ...c, taxon_rank: "genus" }],
      [{ ...c, taxon_rank: null }],
      [{ ...c, extra: true }],
      [{
        scientific_name: c.scientific_name,
        confidence_score: c.confidence_score,
        distinguishing_feature: c.distinguishing_feature,
      }],
    ]
  ) assertThrows(() => decodeSolPhotoPrimaryDraft({ ...value, candidates }));
});
