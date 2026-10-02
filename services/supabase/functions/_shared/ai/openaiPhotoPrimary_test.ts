import { assert, assertEquals, assertThrows } from "@std/assert";
import { isIdentificationProviderAssignment } from "./admission.ts";
import type { AIAttemptSnapshot } from "./contracts.ts";
import { prepareMultimodalResultPolicy } from "./multimodalResultPolicy.ts";
import { OPENAI_PHOTO_CONFIDENCE_RULE } from "./openaiConfidenceRules.ts";
import {
  buildOpenAIPhotoRequestParameters,
  openAIPhotoSnapshot,
} from "./openaiPhoto.ts";
import {
  buildOpenAIPhotoPrimaryRequest,
  openAIPhotoPrimarySnapshot,
  PHOTO_PRIMARY_PROFILE,
  PHOTO_PRIMARY_SCHEMA,
} from "./openaiPhotoPrimary.ts";
import { isOpenAIPhotoModelProfile } from "./openaiPhotoModels.ts";
import { isOpenAIProfile, type OpenAISchema } from "./openaiRequest.ts";
import { solPhotoPrimarySnapshot } from "./openaiSolPrimary.ts";
import { PRIMARY_IDENTIFICATION_SCHEMA } from "../identify/contract.ts";
import {
  openAIPhotoRequestFixture,
  openAITextFixture,
} from "./testing/openaiFixtures.ts";

const request = openAIPhotoRequestFixture();
const snapshot = openAIPhotoPrimarySnapshot(request);

function strict(schema: OpenAISchema) {
  if (schema.properties) {
    assertEquals(schema.required, Object.keys(schema.properties));
    assertEquals(schema.additionalProperties, false);
    Object.values(schema.properties).forEach(strict);
  }
  if (schema.items) strict(schema.items);
}

Deno.test("current-primary request changes only the named identification allowlist", () => {
  const base = buildOpenAIPhotoRequestParameters(
    request,
    openAIPhotoSnapshot(request, 1),
  );
  const candidate = buildOpenAIPhotoPrimaryRequest(request, snapshot);
  assertEquals({
    ...candidate,
    instructions: base.instructions,
    text: base.text,
  }, base);
  const b = base.text.format.schema, c = candidate.text.format.schema;
  const changed = new Set([
    "scientific_name",
    "common_name",
    "candidates",
    "resolution",
  ]);
  for (const [key, value] of Object.entries(b.properties!)) {
    if (!changed.has(key)) assertEquals(c.properties![key], value, key);
  }
  assertEquals(Object.keys(c.properties!), [
    ...Object.keys(b.properties!),
    "resolution",
  ]);
  assertEquals({ ...c, properties: b.properties, required: b.required }, b);
  assertEquals(
    { ...candidate.text.format, name: base.text.format.name, schema: b },
    base.text.format,
  );
  assertEquals(candidate.text.format.name, PHOTO_PRIMARY_SCHEMA);
  strict(c);
  assertEquals(c.properties!.resolution.enum, [
    "species",
    "genus",
    "family",
    "unresolved_biological",
    "non_biological",
  ]);
  assertEquals(c.properties!.candidates.type, ["array", "null"]);
  assertEquals(c.properties!.candidates.maxItems, 2);
  assertEquals(c.properties!.candidates.items!.properties!.taxon_rank.enum, [
    "species",
  ]);
  assertEquals(
    c.properties!.confidence_score.description,
    OPENAI_PHOTO_CONFIDENCE_RULE,
  );
  assert(candidate.instructions.includes(OPENAI_PHOTO_CONFIDENCE_RULE));
  for (const line of base.instructions.split("\n")) {
    if (
      line.includes("Extract one to three distinct") ||
      line.includes("**Explanation")
    ) {
      assert(candidate.instructions.includes(line));
    }
  }
  assert(
    candidate.instructions.includes(
      "unphotographed features are unknown, not absent",
    ),
  );
  assert(!candidate.instructions.includes("MUST populate exactly 2"));
  assertEquals(
    buildOpenAIPhotoRequestParameters(request, openAIPhotoSnapshot(request, 1)),
    base,
  );
});

Deno.test("current-primary identity is isolated from production and every historical profile", () => {
  assertEquals(isOpenAIProfile(PHOTO_PRIMARY_PROFILE), false);
  assertEquals(isOpenAIPhotoModelProfile(PHOTO_PRIMARY_PROFILE), false);
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
  assert(PHOTO_PRIMARY_SCHEMA as string !== PRIMARY_IDENTIFICATION_SCHEMA);
  assert(snapshot.prompt as string !== solPhotoPrimarySnapshot(request).prompt);
  assertEquals(snapshot.confidence, "openai_unqualified_v1");
  for (
    const change of [
      { profile: "old" },
      { binding: "openai_photo_v1" },
      { prompt: "old" },
      { schema: PRIMARY_IDENTIFICATION_SCHEMA },
      { safety: null },
      { contextKind: "user_request" },
      { policyVersion: 2 },
      { timeoutMs: 1 },
      { generation: { ...snapshot.generation, reasoningEffort: "high" } },
      { extra: true },
    ]
  ) {
    assertThrows(() =>
      buildOpenAIPhotoPrimaryRequest(
        request,
        { ...snapshot, ...change } as typeof snapshot,
      )
    );
  }
});

Deno.test("current-primary rejects text, audio and video observations before building a request", () => {
  assertThrows(() => openAIPhotoPrimarySnapshot(openAITextFixture()));
  assertThrows(() =>
    openAIPhotoPrimarySnapshot({
      ...request,
      capture: { ...request.capture, hasVideo: true },
    })
  );
  assertThrows(() =>
    openAIPhotoPrimarySnapshot({
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
});
