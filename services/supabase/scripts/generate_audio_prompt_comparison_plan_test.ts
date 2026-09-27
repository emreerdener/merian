import { assertEquals } from "@std/assert";
import { audioPromptComparisonScanId } from "../functions/identify-multimodal/comparison/promptAssignment.ts";
import {
  renderAudioPromptComparisonPlan,
  renderSwiftAudioPromptComparisonPlan,
} from "./generate_audio_prompt_comparison_plan.ts";

Deno.test("runtime audio prompt comparison plan matches its immutable offline preparation", async () => {
  assertEquals(
    await Deno.readTextFile(
      new URL(
        "../functions/identify-multimodal/comparison/promptPlan.ts",
        import.meta.url,
      ),
    ),
    await renderAudioPromptComparisonPlan(),
  );
});

Deno.test("native prompt comparison slots and stable IDs match the server bindings", async () => {
  const rendered = await renderSwiftAudioPromptComparisonPlan();
  assertEquals(
    await Deno.readTextFile(
      new URL(
        "../../../apps/ios/Merian/Core/Network/Inference/DebugAudioPromptComparisonPlan.generated.swift",
        import.meta.url,
      ),
    ),
    rendered,
  );
  const ids = [...rendered.matchAll(/scanId: "([a-f0-9-]+)"/g)].map((match) =>
    match[1]
  );
  assertEquals(ids.length, 36);
  assertEquals(
    ids,
    await Promise.all(
      Array.from({ length: 36 }, (_, i) => audioPromptComparisonScanId(i + 1)),
    ),
  );
});
