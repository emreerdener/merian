import { assertStringIncludes } from "@std/assert";
import { getSystemInstruction } from "./schema.ts";

Deno.test("vision instruction rejects incidental background biology", () => {
  const instruction = getSystemInstruction(0.99);

  assertStringIncludes(
    instruction,
    "determine the ONE intended primary visual subject",
  );
  assertStringIncludes(
    instruction,
    "focus-region hint is tentative and non-authoritative",
  );
  assertStringIncludes(
    instruction,
    "Do not select an organism merely because it is visible",
  );
  assertStringIncludes(
    instruction,
    "A laptop or room filling the frame does not become a plant observation",
  );
  assertStringIncludes(instruction, "return `is_biological_subject=false`");
});
