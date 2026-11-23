import { assertEquals } from "@std/assert";
import fixtures from "./fixtures/capture-plans-v1.json" with { type: "json" };
import {
  initialCapturePlanValue,
  parseInitialEvidenceCapturePlan,
} from "./initialEvidenceCapturePlan.ts";

Deno.test("native shared capture plans retain exact media, geometry, notes and pending DSP identities", () => {
  const counts = [4, 2, 3, 6];
  for (const [index, fixture] of fixtures.entries()) {
    const plan = parseInitialEvidenceCapturePlan(
      fixture.owner_id,
      fixture.plan,
    );
    assertEquals<unknown>(initialCapturePlanValue(plan), fixture.plan);
    assertEquals(plan.uploads.length, counts[index]);
    for (const audio of plan.audio) {
      assertEquals(
        plan.uploads.some((item) => item.media_id === audio.preparedID),
        false,
      );
    }
  }
});
