import { assertEquals, assertThrows } from "@std/assert";
import { ContractValueError } from "../functions/_shared/identify/contract.ts";
import { normalizeIdentification } from "../functions/_shared/identify/normalizeIdentification.ts";
import { syntheticCorpus } from "./identification_evaluation/fixtures.ts";
import { normalizeEvaluationDraft } from "./identification_evaluation/normalization.ts";

const draft = {
  is_biological_subject: true,
  is_live_capture: true,
  scientific_name: " cf. Danaus plexippus ",
  common_name: "Monarch",
  confidence_score: 0.99,
  ai_reasoning: "Synthetic identification fixture.",
  extracted_visual_traits: ["synthetic pattern"],
  candidates: [{
    scientific_name: "Danaus gilippus",
    confidence_score: 0.5,
    distinguishing_feature: "Synthetic alternative pattern.",
  }],
  image_quality: {
    sharpness: 10,
    framing: 10,
    diagnostic_utility: 10,
    overall_score: 100,
  },
};

Deno.test({
  name:
    "evaluation reuses production normalization for both profiles and every input group without I/O",
  permissions: "none",
  fn() {
    for (const profile of ["gemini_flash_free", "gemini_pro"] as const) {
      for (const { input } of syntheticCorpus().cases) {
        const hasVisualEvidence = input.inputGroup !== "audio" &&
          input.inputGroup !== "description";
        const hasAudioEvidence = input.inputGroup === "audio" ||
          input.inputGroup.endsWith("_audio");
        const value = {
          ...draft,
          ...(!hasVisualEvidence && hasAudioEvidence
            ? { audio_subject_type: "identified_non_human" }
            : {}),
        };
        const result = normalizeEvaluationDraft(value, input, profile);
        assertEquals(
          result,
          normalizeIdentification(value, {
            hasVisualEvidence,
            hasAudioEvidence,
            hasInvasiveLocationContext: false,
            inferenceTier: profile === "gemini_pro" ? "pro" : "flash",
          }),
        );
        assertEquals(result.clientCandidates, null);
        assertEquals(result.identification.scientific_name, "Danaus plexippus");
        assertEquals(
          result.identification.invasive_status_region,
          "Unavailable",
        );
      }
    }
  },
});

Deno.test("evaluation does not reinterpret coarse device context as invasive location evidence", () => {
  const input = syntheticCorpus().cases[0].input;
  const result = normalizeEvaluationDraft(draft, {
    ...input,
    context: { deviceRegion: "US", currentMonth: 9 },
  }, "gemini_pro");
  assertEquals(result.identification.is_invasive, false);
  assertEquals(result.identification.invasive_confidence, undefined);
  assertEquals(result.identification.invasive_status_region, "Unavailable");
});

Deno.test("evaluation rejects reference-bearing inputs and malformed drafts instead of inventing uncertainty", () => {
  const item = syntheticCorpus().cases[0];
  assertThrows(() => normalizeEvaluationDraft(draft, item, "gemini_pro"));
  assertThrows(
    () => normalizeEvaluationDraft({ invalid: true }, item.input, "gemini_pro"),
    ContractValueError,
  );
  assertThrows(() =>
    normalizeEvaluationDraft(draft, {
      ...item.input,
      reference: item.reference,
    }, "gemini_pro")
  );
});
