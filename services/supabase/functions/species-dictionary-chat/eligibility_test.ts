import { assert, assertFalse } from "@std/assert";
import { isSpeciesDictionaryChatContextAvailable } from "./eligibility.ts";
import type { SpeciesDictionaryChatContext } from "./types.ts";

const context = {
  id: "019fac20-2370-7911-8bb2-a136ce1ca9c7",
} as SpeciesDictionaryChatContext;

Deno.test("Species Dictionary Field Chat accepts canonical loaded context", () => {
  assert(isSpeciesDictionaryChatContextAvailable(context));
});

Deno.test("Species Dictionary Field Chat rejects unavailable species", () => {
  assertFalse(isSpeciesDictionaryChatContextAvailable(null));
});
