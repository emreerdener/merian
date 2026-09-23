import { assertEquals } from "@std/assert";
import { audioComparisonScanId } from "../functions/identify-multimodal/comparison/assignment.ts";
import {
  renderAudioComparisonPlan,
  renderSwiftAudioComparisonPlan,
} from "./generate_audio_comparison_plan.ts";

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

Deno.test("native comparison slots and stable IDs match the server bindings", async () => {
  const rendered = await renderSwiftAudioComparisonPlan();
  assertEquals(
    await Deno.readTextFile(
      new URL(
        "../../../apps/ios/Merian/Core/Network/Inference/DebugAudioComparisonPlan.generated.swift",
        import.meta.url,
      ),
    ),
    rendered,
  );
  const ids = [...rendered.matchAll(/scanId: "([a-f0-9-]+)"/g)].map((match) =>
    match[1]
  );
  assertEquals(ids.length, 12);
  assertEquals(
    ids,
    await Promise.all(
      Array.from({ length: 12 }, (_, i) => audioComparisonScanId(i + 1)),
    ),
  );
});
