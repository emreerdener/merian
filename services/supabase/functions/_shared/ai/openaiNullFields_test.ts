import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import type { IdentifyEvidence, MultimodalAIRequest } from "./contracts.ts";
import { createAIExecution } from "./execution.ts";
import { createOpenAIEvaluationAdapter } from "./openai.ts";
import {
  OPENAI_NULL_FIELDS_PROFILE,
  OPENAI_NULL_FIELDS_PROMPT,
  OPENAI_NULL_FIELDS_PROMPT_DIGEST,
  OPENAI_NULL_FIELDS_SCHEMA_DIGEST,
  openAINullFieldsInstructions,
} from "./openaiNullFields.ts";
import {
  buildOpenAIRequestParameters,
  decodeOpenAIDraft,
  openAIEvaluationSnapshot,
} from "./openaiRequest.ts";
import {
  openAIDraftFixture,
  openAIResponseFixture,
  openAITextFixture,
} from "./testing/openaiFixtures.ts";
import {
  getMerianResponseSchema,
  getSystemInstruction,
} from "../identify/schema.ts";
import { fingerprintJson } from "../../identify-multimodal/comparison/fingerprint.ts";

const photo = (order: number, index = 0): IdentifyEvidence => ({
  kind: "image",
  order,
  inputIndex: index,
  lineage: { kind: "image", sourceIndex: index },
  mimeType: "image/png",
  data: "AQID",
});
const visual = (): MultimodalAIRequest => ({
  ...openAITextFixture(),
  evidence: [photo(0)],
});
const native = (request: MultimodalAIRequest, candidate = false) =>
  buildOpenAIRequestParameters(
    request,
    candidate
      ? openAIEvaluationSnapshot(request, OPENAI_NULL_FIELDS_PROFILE)
      : openAIEvaluationSnapshot(request),
  );

Deno.test("OpenAI null-field candidate preserves complete visual evidence, settings and explanation schema", async () => {
  const text = openAITextFixture(), oldText = native(text);
  const shared = await fingerprintJson({
    prompt: getSystemInstruction(1),
    schema: getMerianResponseSchema(1),
  });
  const examples = [
    visual(),
    { ...text, evidence: [...text.evidence, photo(1)] },
    {
      ...text,
      evidence: [
        ...text.evidence,
        {
          kind: "text",
          order: 1,
          source: "visual_context",
          text: "Tentative focus on the first of two images.",
        } as const,
        photo(2),
        photo(3, 1),
        {
          kind: "text",
          order: 4,
          source: "capture_context",
          text: "Location unavailable; month unspecified.",
        } as const,
      ],
    },
  ];
  for (const request of examples) {
    const before = structuredClone(request),
      baseline = native(request),
      candidate = native(request, true);
    assertEquals(
      await fingerprintJson(baseline.instructions),
      "8f0d9c5e8ef5f2be03fe22696c307f74b0910624878e435728eb5cffda75542e",
    );
    assertEquals(
      await fingerprintJson(candidate.instructions),
      OPENAI_NULL_FIELDS_PROMPT_DIGEST,
    );
    assertEquals(
      await fingerprintJson(candidate.text.format.schema),
      OPENAI_NULL_FIELDS_SCHEMA_DIGEST,
    );
    assertEquals(
      { ...candidate, instructions: baseline.instructions },
      baseline,
    );
    assertEquals(
      candidate.text.format.schema.properties?.ai_reasoning,
      baseline.text.format.schema.properties?.ai_reasoning,
    );
    assert(
      !("prompt_cache_options" in baseline) &&
        !("prompt_cache_options" in candidate),
    );
    assertEquals(native(request), baseline);
    assertEquals(request, before);
  }
  assertEquals(native(text), oldText);
  assertEquals(
    await fingerprintJson({
      prompt: getSystemInstruction(1),
      schema: getMerianResponseSchema(1),
    }),
    shared,
  );
});
Deno.test("OpenAI null-field candidate rejects a changed shared prompt and whole unsupported inputs", () => {
  const baseline = native(visual()).instructions;
  assertThrows(() =>
    openAINullFieldsInstructions(
      baseline.replace(
        "All non-biological results MUST omit:",
        "Changed shared rule",
      ),
    )
  );
  assertThrows(() =>
    openAINullFieldsInstructions(
      baseline + "All non-biological results MUST omit:",
    )
  );
  const base = visual();
  for (
    const request of [
      openAITextFixture(),
      { ...base, capture: { ...base.capture, hasVideo: true } },
      {
        ...base,
        evidence: [
          {
            ...photo(0),
            lineage: { kind: "video_frame", clipIndex: 0, frameIndex: 0 },
          } as IdentifyEvidence,
        ],
      },
      {
        ...base,
        evidence: [
          ...base.evidence,
          {
            kind: "audio",
            order: 1,
            inputIndex: 0,
            lineage: null,
            mimeType: "audio/wav",
            data: "AQID",
          } as const,
        ],
      },
    ]
  ) {
    assertThrows(
      () => openAIEvaluationSnapshot(request, OPENAI_NULL_FIELDS_PROFILE),
      Error,
      "openai_input_unsupported",
    );
  }
  const snapshot = openAIEvaluationSnapshot(base, OPENAI_NULL_FIELDS_PROFILE);
  assertEquals(snapshot.prompt, OPENAI_NULL_FIELDS_PROMPT);
  assertThrows(
    () =>
      buildOpenAIRequestParameters(base, {
        ...snapshot,
        prompt: "openai_identify_vision_v1",
      }),
    Error,
    "openai_binding_mismatch",
  );
});
Deno.test("OpenAI null-field candidate has one native invocation and keeps strict null versus missing-key decoding", async () => {
  const request = visual();
  let calls = 0;
  const execution = createAIExecution(
    createOpenAIEvaluationAdapter("synthetic-null-fields", (_url, init) => {
      calls++;
      assertEquals(
        JSON.parse(String(init?.body)),
        JSON.parse(JSON.stringify(native(request, true))),
      );
      return Promise.resolve(Response.json(openAIResponseFixture()));
    }),
    request,
    openAIEvaluationSnapshot(request, OPENAI_NULL_FIELDS_PROFILE),
  );
  assertEquals(calls, 0);
  assertEquals((await execution.invoke()).kind, "draft");
  await assertRejects(
    () => execution.invoke(),
    Error,
    "ai_attempt_already_invoked",
  );
  assertEquals(calls, 1);
  const draft = openAIDraftFixture();
  const nullable = [
    "scientific_name",
    "common_name",
    "is_invasive",
    "invasive_status_region",
    "invasive_rationale",
    "invasive_confidence",
    "ecology_type",
    "life_stage",
    "reproductive_condition",
    "sex",
    "sex_confidence",
    "sex_evidence",
    "individual_count",
    "ecological_interactions",
  ];
  const schema = native(request, true).text.format.schema;
  for (const name of nullable) {
    assert(schema.required?.includes(name));
    assert(schema.properties?.[name].type.includes("null"));
    draft[name] = null;
  }
  draft.is_biological_subject = false;
  draft.is_live_capture = false;
  draft.candidates = [];
  decodeOpenAIDraft(draft);
  delete draft.scientific_name;
  assertThrows(() => decodeOpenAIDraft(draft));
});
