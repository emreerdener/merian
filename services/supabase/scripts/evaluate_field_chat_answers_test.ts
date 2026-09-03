import { assertEquals, assertStringIncludes } from "@std/assert";
import { buildFieldChatAnswerCases } from "./field_chat_answer_cases.ts";
import {
  assessFieldChatAnswer,
  evaluateFieldChatAnswers,
} from "./evaluate_field_chat_answers.ts";

const generalAnswer = {
  answer:
    "Usually not. Desert Rose flowers tend to be unscented, though some cultivated varieties can be fragrant.",
  is_refusal: false,
  refusal_reason: null,
};

const individualAnswer = {
  answer:
    "I can't tell how strong this particular flower smells right now. Its species' usual fragrance does not establish this flower's current scent.",
  is_refusal: false,
  refusal_reason: null,
};

Deno.test("answer cases exercise every host after missing reference values", () => {
  const cases = buildFieldChatAnswerCases();
  assertEquals(cases.length, 9);
  assertEquals(
    new Set(cases.map((testCase) => testCase.id.split("/")[0])),
    new Set([
      "insight-chat",
      "explore-post-chat",
      "species-dictionary-chat",
    ]),
  );
  for (const testCase of cases) {
    const requestText = JSON.stringify(testCase.request);
    assertStringIncludes(requestText, "Adenium obesum");
    assertStringIncludes(requestText, "[ANSWERING RULES]");
    assertStringIncludes(requestText, "Do they smell good?");
    assertEquals(
      requestText.includes("00000000-0000-4000-8000-000000000001"),
      false,
    );
  }
});

Deno.test("answer assessment rejects the reported deflection pattern", () => {
  assertEquals(
    assessFieldChatAnswer("general", {
      answer:
        "The saved scan context does not include information about its fragrance.",
      is_refusal: false,
      refusal_reason: null,
    }),
    ["record_missing_deflection", "typical_fragrance_not_explained"],
  );
  assertEquals(assessFieldChatAnswer("general", generalAnswer), []);
  assertEquals(assessFieldChatAnswer("individual", individualAnswer), []);
  assertEquals(
    assessFieldChatAnswer("individual", {
      ...generalAnswer,
      answer: "This particular flower has a strong sweet scent right now.",
    }),
    ["individual_scent_not_known"],
  );
});

Deno.test("bounded evaluator reports outcomes without retaining answers", async () => {
  const reports: Array<{ id: string; failures: string[] }> = [];
  let index = 0;
  const cases = buildFieldChatAnswerCases().slice(0, 3);
  const passed = await evaluateFieldChatAnswers(
    cases,
    () =>
      Promise.resolve({
        text: JSON.stringify(index++ < 2 ? generalAnswer : individualAnswer),
      }),
    (result) => reports.push(result),
  );
  assertEquals(passed, true);
  assertEquals(
    reports,
    cases.map((testCase) => ({ id: testCase.id, failures: [] })),
  );
  assertEquals(JSON.stringify(reports).includes("Desert Rose"), false);
});
