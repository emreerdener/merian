import { assertEquals, assertRejects, assertThrows } from "@std/assert";
import { parseFieldChatReply } from "../_shared/fieldChat/reply.ts";
import { decodeGeminiApplication } from "../_shared/ai/geminiTransport.ts";
import {
  parseFieldNotesResponse,
  parsePromptSuggestionsResponse,
} from "./providerResponses.ts";

Deno.test("Field Chat rejects malformed application values before recording acceptance", async () => {
  const valid = {
    answer: "Synthetic answer",
    is_refusal: false,
    refusal_reason: null,
  };
  for (
    const value of [
      {},
      { ...valid, extra: true },
      { ...valid, answer: 1 },
      { ...valid, answer: " " },
      { ...valid, answer: "x".repeat(4001) },
      { ...valid, is_refusal: "false" },
      { ...valid, refusal_reason: "inconsistent" },
      { ...valid, is_refusal: true, refusal_reason: "x".repeat(101) },
    ]
  ) {
    const outcomes: string[] = [];
    await assertRejects(() =>
      decodeGeminiApplication({
        beforeTransport: () => Promise.resolve(),
        recordResponse: () => Promise.resolve(),
        recordApplicationOutcome: (outcome) => {
          outcomes.push(outcome);
          return Promise.resolve();
        },
      }, () => parseFieldChatReply(JSON.stringify(value)))
    );
    assertEquals(outcomes, ["error"]);
  }
  assertEquals(parseFieldChatReply(JSON.stringify(valid)), valid);
  assertEquals(
    parseFieldChatReply(
      JSON.stringify({ ...valid, is_refusal: true, refusal_reason: "safety" }),
    ).refusal_reason,
    "safety",
  );
});
Deno.test("summary and suggestions reject schema errors instead of creating successful defaults", () => {
  for (
    const value of [{}, { summary_text: 1 }, { summary_text: "" }, {
      summary_text: "x".repeat(4001),
    }, { summary_text: "ok", extra: 1 }]
  ) {
    assertThrows(() => parseFieldNotesResponse(JSON.stringify(value)));
  }
  assertEquals(
    parseFieldNotesResponse('{"summary_text":" Synthetic note "}'),
    "Synthetic note",
  );
  const valid = { text: "What habitat is typical?", category: "habitat" };
  for (
    const value of [
      {},
      { prompts: null },
      { prompts: [valid], extra: 1 },
      { prompts: [valid, valid, valid, valid] },
      { prompts: [{ ...valid, category: "invented" }] },
      { prompts: [{ ...valid, extra: 1 }] },
      { prompts: [{ ...valid, text: 1 }] },
    ]
  ) {
    assertThrows(() => parsePromptSuggestionsResponse(JSON.stringify(value)));
  }
  assertEquals(
    parsePromptSuggestionsResponse(JSON.stringify({ prompts: [valid] })),
    [valid],
  );
  assertEquals(
    parsePromptSuggestionsResponse(
      '{"prompts":[{"text":"Can I eat this berry?","category":"hazard"}]}',
    ),
    [],
  );
});
