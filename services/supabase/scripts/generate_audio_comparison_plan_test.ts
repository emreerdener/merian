import { assertEquals } from "@std/assert";
import { renderAudioComparisonPlan } from "./generate_audio_comparison_plan.ts";

Deno.test("runtime audio comparison plan matches its immutable offline preparation", async () => {
  assertEquals(
    await Deno.readTextFile(
      new URL(
        "../functions/identify-multimodal/comparison/plan.ts",
        import.meta.url,
      ),
    ),
    await renderAudioComparisonPlan(),
  );
});
