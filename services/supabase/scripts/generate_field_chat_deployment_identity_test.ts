import { assertEquals, assertMatch, assertStringIncludes } from "@std/assert";
import {
  computeFieldChatBundleDigests,
  FIELD_CHAT_FUNCTION_NAMES,
  renderFieldChatDeploymentIdentity,
} from "./generate_field_chat_deployment_identity.ts";

Deno.test("Field Chat bundle identities are deterministic and checked in", async () => {
  const first = await computeFieldChatBundleDigests();
  const second = await computeFieldChatBundleDigests();
  assertEquals(first, second);

  const generated = await Deno.readTextFile(
    new URL(
      "../functions/_shared/fieldChatDeploymentIdentity.ts",
      import.meta.url,
    ),
  );
  assertEquals(generated, renderFieldChatDeploymentIdentity(first));
  for (const functionName of FIELD_CHAT_FUNCTION_NAMES) {
    assertMatch(first[functionName], /^[0-9a-f]{64}$/);
    assertStringIncludes(generated, `"${functionName}"`);
  }
});

Deno.test("Field Chat bundle identities do not collapse across routes", async () => {
  const digests = await computeFieldChatBundleDigests();
  assertEquals(new Set(Object.values(digests)).size, 3);
});
