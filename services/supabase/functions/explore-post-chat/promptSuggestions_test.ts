import { assertEquals, assertLessOrEqual } from "@std/assert";
import { buildExplorePostChatPromptSuggestions } from "./promptSuggestions.ts";

Deno.test("Explore prompt suggestions preserve safe species names and categories", () => {
  assertEquals(
    buildExplorePostChatPromptSuggestions("  poison   ivy ", true),
    [
      {
        text: "How can I distinguish poison ivy from lookalikes?",
        category: "lookalike_compare",
      },
      {
        text: "What habitat does poison ivy prefer?",
        category: "habitat",
      },
      {
        text: "What is most interesting about poison ivy?",
        category: "ecology",
      },
    ],
  );
});

Deno.test("Explore prompt suggestions fall back before labels can overflow chips", () => {
  const prompts = buildExplorePostChatPromptSuggestions("x".repeat(65), false);
  assertEquals(
    prompts[0].text,
    "What traits are characteristic of this species?",
  );
  for (const prompt of prompts) {
    assertLessOrEqual(prompt.text.length, 120);
  }
});
