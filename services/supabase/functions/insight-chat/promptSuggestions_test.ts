import {
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import {
  isUnsafeFieldChatPromptSuggestion,
  sanitizePromptSuggestions,
} from "./promptSuggestions.ts";

Deno.test("prompt safety rejects action advice without rejecting ecology or species names", () => {
  for (
    const unsafe of [
      "Can I eat this berry?",
      "Could we safely handle this snake?",
      "How should I harvest it?",
      "Is this edible?",
      "What dosage should treat the sting?",
      "Is it legal to collect this species?",
      "Where exactly are its GPS coordinates?",
      "Can you identify this human face?",
    ]
  ) {
    assertEquals(isUnsafeFieldChatPromptSuggestion(unsafe), true, unsafe);
  }

  for (
    const educational of [
      "What does this bird eat?",
      "How does this animal forage?",
      "What habitat does poison ivy prefer?",
      "Which traits distinguish tea plants?",
      "Why is handling this species discouraged?",
    ]
  ) {
    assertFalse(isUnsafeFieldChatPromptSuggestion(educational), educational);
  }
});

Deno.test("prompt sanitizer normalizes, deduplicates, bounds, and categorizes suggestions", () => {
  assertEquals(
    sanitizePromptSuggestions([
      { text: "  Which   trait matters? ", category: "evidence" },
      { text: "which trait matters?", category: "habitat" },
      { text: "What habitat does poison ivy prefer?", category: "habitat" },
      { text: "Can I forage this?", category: "generic" },
      { text: "What should I inspect next?", category: "future" },
      { text: "A fourth safe prompt?", category: "generic" },
    ]),
    [
      { text: "Which trait matters?", category: "evidence" },
      { text: "What habitat does poison ivy prefer?", category: "habitat" },
      { text: "What should I inspect next?", category: "generic" },
    ],
  );
  assertEquals(sanitizePromptSuggestions(null), []);
  assertEquals(
    sanitizePromptSuggestions([
      { text: "x".repeat(121), category: "generic" },
      { text: "", category: "generic" },
      { category: "generic" },
    ]),
    [],
  );
});
