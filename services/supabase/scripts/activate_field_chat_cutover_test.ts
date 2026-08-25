import { assertEquals, assertThrows } from "@std/assert";
import {
  REQUIRED_FIELD_CHAT_BUNDLES,
  validateFieldChatActivationPlan,
} from "./activate_field_chat_cutover.ts";

Deno.test("Field Chat activation requires all three reviewed bundles", () => {
  assertEquals(
    validateFieldChatActivationPlan(
      `insight-chat\nexplore-post-chat\nspecies-dictionary-chat\nother-function\n`,
    ),
    [
      "explore-post-chat",
      "insight-chat",
      "other-function",
      "species-dictionary-chat",
    ],
  );
  assertEquals(REQUIRED_FIELD_CHAT_BUNDLES.length, 3);
});

Deno.test("Field Chat activation fails closed for incomplete plans", () => {
  for (
    const plan of [
      "",
      "insight-chat\n",
      "insight-chat\nexplore-post-chat\n",
      "insight-chat\nspecies-dictionary-chat\n",
    ]
  ) {
    assertThrows(() => validateFieldChatActivationPlan(plan));
  }
});
