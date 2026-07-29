import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  assertConversationHasRoom,
  isSafetyCriticalQuestion,
  normalizeAction,
  normalizeAssistantAnswer,
  normalizeFeatureFeedbackSentiment,
  normalizeUserMessage,
  refusalAnswer,
} from "./guards.ts";

Deno.test("normalizeAction accepts only supported actions", () => {
  assertEquals(normalizeAction("load"), "load");
  assertEquals(normalizeAction("send"), "send");
  assertEquals(normalizeAction("delete"), "delete");
  assertEquals(normalizeAction("feedback"), "feedback");
  assertEquals(normalizeAction("feature_feedback"), "feature_feedback");
  assertEquals(normalizeAction("summarize_notes"), "summarize_notes");
  assertEquals(normalizeAction("suggest_prompts"), "suggest_prompts");
  assertThrows(() => normalizeAction("list"));
  assertThrows(() => normalizeAction("create"));
  assertThrows(() => normalizeAction("archive"));
});

Deno.test("normalizeFeatureFeedbackSentiment accepts optional sentiment", () => {
  assertEquals(normalizeFeatureFeedbackSentiment("positive"), "positive");
  assertEquals(normalizeFeatureFeedbackSentiment("negative"), "negative");
  assertEquals(normalizeFeatureFeedbackSentiment(null), null);
  assertEquals(normalizeFeatureFeedbackSentiment(undefined), null);
  assertThrows(() => normalizeFeatureFeedbackSentiment("mixed"));
});

Deno.test("normalizeUserMessage trims and caps text", () => {
  assertEquals(
    normalizeUserMessage("  What traits support this ID?  "),
    "What traits support this ID?",
  );
  assertThrows(() => normalizeUserMessage(""));
  assertThrows(() => normalizeUserMessage("x".repeat(601)));
  assertEquals(
    normalizeAssistantAnswer("  saved answer  ", "fallback"),
    "saved answer",
  );
  assertEquals(normalizeAssistantAnswer(null, " fallback "), "fallback");
  assertEquals(
    normalizeAssistantAnswer("x".repeat(4001), "fallback").length,
    4000,
  );
  assertThrows(() => normalizeAssistantAnswer(null, "   "));
  assertConversationHasRoom(28);
  assertThrows(() => assertConversationHasRoom(29));
  assertThrows(() => assertConversationHasRoom(30));
  assertConversationHasRoom(29, 1);
  assertThrows(() => assertConversationHasRoom(30, 1));
  assertThrows(() => assertConversationHasRoom(-1));
});

Deno.test("safety classifier catches unsafe action intent", () => {
  assertEquals(
    isSafetyCriticalQuestion("Can I bake this berry in a pie?"),
    "foraging_or_ingestion",
  );
  assertEquals(
    isSafetyCriticalQuestion("What dosage treats this sting?"),
    "medical_or_veterinary",
  );
  assertEquals(
    isSafetyCriticalQuestion("How do I trap and relocate it?"),
    "dangerous_handling",
  );
  assertEquals(
    isSafetyCriticalQuestion("How should I harvest it?"),
    "legal_or_collection",
  );
  assertEquals(
    isSafetyCriticalQuestion("Is this safe to handle?"),
    "dangerous_handling",
  );
  assertEquals(
    isSafetyCriticalQuestion("Can this be harvested?"),
    "legal_or_collection",
  );
  assertEquals(
    isSafetyCriticalQuestion("Can I treat this rash?"),
    "medical_or_veterinary",
  );
  assertEquals(
    isSafetyCriticalQuestion("What should I do if I was stung?"),
    "medical_or_veterinary",
  );
  assertEquals(
    isSafetyCriticalQuestion("What is the best way to kill it?"),
    "dangerous_handling",
  );
  assertEquals(
    isSafetyCriticalQuestion("Show me how to collect it."),
    "legal_or_collection",
  );
  assertEquals(
    isSafetyCriticalQuestion("Give me instructions for handling it."),
    "dangerous_handling",
  );
});

Deno.test("safety classifier permits educational biology language", () => {
  for (
    const educational of [
      "What does this bird eat?",
      "How does this animal forage?",
      "What habitat does poison ivy prefer?",
      "Which traits distinguish tea plants?",
      "Why is handling this species discouraged?",
      "Do bees sting when defending their nest?",
      "How do researchers handle it during surveys?",
      "Can I treat this as a subspecies?",
      "Which traits support this ID?",
    ]
  ) {
    assertEquals(isSafetyCriticalQuestion(educational), null, educational);
  }
});

Deno.test("refusal answers redirect to educational use", () => {
  const answer = refusalAnswer("foraging_or_ingestion");
  assertEquals(answer.includes("safe to eat"), true);
  assertEquals(answer.includes("visible traits"), true);
});
