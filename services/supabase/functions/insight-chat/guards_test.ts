import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  isInsightChatFeatureEnabled,
  isSafetyCriticalQuestion,
  normalizeAction,
  normalizeUserMessage,
  refusalAnswer,
} from "./guards.ts";

Deno.test("feature flag only enables on explicit true", () => {
  assertEquals(isInsightChatFeatureEnabled("true"), true);
  assertEquals(isInsightChatFeatureEnabled("false"), false);
  assertEquals(isInsightChatFeatureEnabled(undefined), false);
});

Deno.test("normalizeAction accepts only supported actions", () => {
  assertEquals(normalizeAction("load"), "load");
  assertEquals(normalizeAction("send"), "send");
  assertEquals(normalizeAction("delete"), "delete");
  assertThrows(() => normalizeAction("archive"));
});

Deno.test("normalizeUserMessage trims and caps text", () => {
  assertEquals(
    normalizeUserMessage("  What traits support this ID?  "),
    "What traits support this ID?",
  );
  assertThrows(() => normalizeUserMessage(""));
  assertThrows(() => normalizeUserMessage("x".repeat(601)));
});

Deno.test("safety classifier catches ingestion and treatment prompts", () => {
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
  assertEquals(isSafetyCriticalQuestion("Which traits support this ID?"), null);
});

Deno.test("refusal answers redirect to educational use", () => {
  const answer = refusalAnswer("foraging_or_ingestion");
  assertEquals(answer.includes("safe to eat"), true);
  assertEquals(answer.includes("visible traits"), true);
});
