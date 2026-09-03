import { assertEquals } from "@std/assert";
import {
  buildFieldChatReplyRequest,
  extractFieldChatReplyJson,
} from "./fieldChatReply.ts";

Deno.test("Field Chat replies share the deployed Gemini request configuration", () => {
  const request = buildFieldChatReplyRequest(
    "synthetic system instruction",
    "synthetic user question",
    "gemini-2.5-flash",
  );
  assertEquals(request, {
    model: "gemini-2.5-flash",
    contents: [{
      role: "user",
      parts: [{ text: "synthetic user question" }],
    }],
    config: {
      systemInstruction: "synthetic system instruction",
      temperature: 0.2,
      maxOutputTokens: 700,
      responseMimeType: "application/json",
      responseSchema: {
        type: "OBJECT",
        properties: {
          answer: { type: "STRING" },
          is_refusal: { type: "BOOLEAN" },
          refusal_reason: { type: "STRING", nullable: true },
        },
        required: ["answer", "is_refusal", "refusal_reason"],
      },
      thinkingConfig: { thinkingBudget: 0 },
    },
  });
});

Deno.test("Field Chat reply extraction retains structured-output compatibility", () => {
  assertEquals(
    extractFieldChatReplyJson('```json\n{"answer":"ok"}\n```'),
    { answer: "ok" },
  );
});
