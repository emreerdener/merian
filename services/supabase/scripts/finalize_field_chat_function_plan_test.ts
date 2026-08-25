import { assertEquals, assertThrows } from "@std/assert";
import { finalizeFunctionPlanForFieldChatCutover } from "./finalize_field_chat_function_plan.ts";

Deno.test("ready cutover forces all Field Chat bundles after a successful pending baseline", () => {
  assertEquals(
    finalizeFunctionPlanForFieldChatCutover("unrelated-function\n", "ready"),
    {
      functions: [
        "explore-post-chat",
        "insight-chat",
        "species-dictionary-chat",
        "unrelated-function",
      ],
      forcedFieldChatBundles: true,
    },
  );
});

Deno.test("pending and active cutovers preserve the affected-function plan", () => {
  for (const status of ["pending", "active"] as const) {
    assertEquals(
      finalizeFunctionPlanForFieldChatCutover(
        "insight-chat\nother-function\ninsight-chat\n",
        status,
      ),
      {
        functions: ["insight-chat", "other-function"],
        forcedFieldChatBundles: false,
      },
    );
  }
});

Deno.test("final plan rejects unknown status and unsafe names", () => {
  assertThrows(() =>
    finalizeFunctionPlanForFieldChatCutover(
      "valid-function\n",
      "unknown" as never,
    )
  );
  assertThrows(() =>
    finalizeFunctionPlanForFieldChatCutover("../unsafe\n", "ready")
  );
});
