import { assertEquals, assertMatch } from "@std/assert";
import {
  identificationBundleDigest,
  renderIdentificationIdentity,
} from "./generate_identification_deployment_identity.ts";

Deno.test("identification runtime bundle digest is deterministic and current", async () => {
  const digest = await identificationBundleDigest();
  assertMatch(digest, /^[0-9a-f]{64}$/);
  assertEquals(await identificationBundleDigest(), digest);
  assertEquals(
    await Deno.readTextFile(
      new URL(
        "../functions/identify-multimodal/deploymentIdentity.ts",
        import.meta.url,
      ),
    ),
    renderIdentificationIdentity(digest),
  );
});
