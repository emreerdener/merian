/** One-off, offline review evidence. No provider invocation or profile registration. */
import { assert, assertEquals, assertThrows } from "@std/assert";
import {
  buildOpenAIRequestParameters,
  decodeOpenAIDraft,
  isOpenAIProfile,
  openAIEvaluationSnapshot,
} from "../../../../services/supabase/functions/_shared/ai/openaiRequest.ts";
import {
  openAIDraftFixture,
  openAITextFixture,
} from "../../../../services/supabase/functions/_shared/ai/testing/openaiFixtures.ts";
import {
  getMerianResponseSchema,
  getSystemInstruction,
} from "../../../../services/supabase/functions/_shared/identify/schema.ts";
import { fingerprintJson } from "../../../../services/supabase/functions/identify-multimodal/comparison/fingerprint.ts";
import type {
  IdentifyEvidence,
  MultimodalAIRequest,
} from "../../../../services/supabase/functions/_shared/ai/contracts.ts";
const manifest = JSON.parse(
  await Deno.readTextFile(new URL("./prompt-edits.json", import.meta.url)),
);
const baselineText = openAITextFixture();
const textNative = buildOpenAIRequestParameters(
  baselineText,
  openAIEvaluationSnapshot(baselineText),
);
const sharedBefore = await fingerprintJson({
  prompt: getSystemInstruction(1),
  schema: getMerianResponseSchema(1),
});
const photo = (order: number, index = 0): IdentifyEvidence => ({
  kind: "image",
  order,
  inputIndex: index,
  lineage: { kind: "image", sourceIndex: index },
  mimeType: "image/png",
  data: "AQID",
});
const base = openAITextFixture();
const cases: MultimodalAIRequest[] = [
  { ...base, evidence: [photo(0)] },
  { ...base, evidence: [...base.evidence, photo(1)] },
  {
    ...base,
    evidence: [
      ...base.evidence,
      {
        kind: "text",
        order: 1,
        source: "visual_context",
        text:
          "Two still photos from the same observation. Tentative focus hint.",
      },
      photo(2),
      photo(3, 1),
      {
        kind: "text",
        order: 4,
        source: "capture_context",
        text: "Location: unavailable. Region: unavailable. Month: unspecified.",
      },
    ],
  },
];
const allNullableFields = [
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
let candidatePromptDigest = "", promptBytesBefore = 0, promptBytesAfter = 0;
for (const request of cases) {
  const inputBefore = JSON.stringify(request);
  const native = buildOpenAIRequestParameters(
    request,
    openAIEvaluationSnapshot(request),
  );
  assertEquals(native.model, "gpt-6-sol");
  assertEquals(native.reasoning, { effort: "low" });
  assertEquals(native.max_output_tokens, 8192);
  assert(!("prompt_cache_options" in native));
  assertEquals(
    await fingerprintJson(native.instructions),
    manifest.baselinePromptDigest,
  );
  assertEquals(
    await fingerprintJson(native.text.format.schema),
    manifest.schemaDigest,
  );
  let changed = native.instructions;
  for (const edit of manifest.replacements) {
    assertEquals(changed.split(edit.before).length - 1, 1);
    changed = changed.replace(edit.before, edit.after);
  }
  const candidate = { ...structuredClone(native), instructions: changed };
  assertEquals(
    Object.keys(native).filter((k) =>
      JSON.stringify(native[k as keyof typeof native]) !==
        JSON.stringify(candidate[k as keyof typeof candidate])
    ),
    ["instructions"],
  );
  let reversed = changed;
  for (const edit of [...manifest.replacements].reverse()) {
    assertEquals(reversed.split(edit.after).length - 1, 1);
    reversed = reversed.replace(edit.after, edit.before);
  }
  assertEquals(reversed, native.instructions);
  assert(changed.includes('omit "(Linnaeus, 1758)"'));
  assertEquals((changed.match(/\bomit\b/gi) ?? []).length, 1);
  for (const name of allNullableFields) {
    assert(native.text.format.schema.required?.includes(name));
    assert(native.text.format.schema.properties?.[name].type.includes("null"));
  }
  assertEquals(
    candidate.text.format.schema.properties?.ai_reasoning,
    native.text.format.schema.properties?.ai_reasoning,
  );
  assertEquals(JSON.stringify(request), inputBefore);
  assertEquals(
    buildOpenAIRequestParameters(request, openAIEvaluationSnapshot(request)),
    native,
  );
  candidatePromptDigest = await fingerprintJson(changed);
  promptBytesBefore = new TextEncoder().encode(native.instructions).length;
  promptBytesAfter = new TextEncoder().encode(changed).length;
}
assertEquals(
  buildOpenAIRequestParameters(
    baselineText,
    openAIEvaluationSnapshot(baselineText),
  ),
  textNative,
);
assertEquals(
  await fingerprintJson({
    prompt: getSystemInstruction(1),
    schema: getMerianResponseSchema(1),
  }),
  sharedBefore,
);
assert(!isOpenAIProfile(manifest.proposedProfile));
assertThrows(
  () => openAIEvaluationSnapshot(cases[0], manifest.proposedProfile),
  Error,
  "openai_binding_mismatch",
);
const draft = openAIDraftFixture();
for (const name of allNullableFields) draft[name] = null;
draft.is_biological_subject = false;
draft.is_live_capture = false;
draft.candidates = [];
decodeOpenAIDraft(draft);
delete draft.scientific_name;
assertThrows(() => decodeOpenAIDraft(draft));
assertEquals(
  candidatePromptDigest,
  "8d8c5ab7f612555a0a275ade42de7615f327314c644502ab5d2217c1bab1f948",
);
assertEquals(promptBytesBefore, 11065);
assertEquals(promptBytesAfter, 11121);
console.log(JSON.stringify(
  {
    version: "openai_prompt_offline_review_v1",
    reviewedSourceSha: manifest.sourceSha,
    syntheticVisualRequestsChecked: cases.length,
    descriptionBaselinePreserved: true,
    exactReplacementSites: manifest.replacements.length,
    nullableFieldsChecked: allNullableFields.length,
    changedNativeRequestKeys: ["instructions"],
    sourceRequestMutation: false,
    schemaPreserved: true,
    explanationDefinitionPreserved: true,
    sharedGeminiProjectionPreserved: true,
    unregisteredIdentityRejected: true,
    nullDraftAcceptedMissingKeyRejected: true,
    baselinePromptDigest: manifest.baselinePromptDigest,
    candidatePromptDigest,
    schemaDigest: manifest.schemaDigest,
    promptBytesBefore,
    promptBytesAfter,
    providerCalls: 0,
  },
  null,
  2,
));
