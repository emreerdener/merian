import { assertEquals } from "@std/assert";

import { mapWithConcurrencyLimit } from "./concurrency.ts";

Deno.test("mapWithConcurrencyLimit preserves order and caps in-flight work", async () => {
  let inFlight = 0;
  let maxInFlight = 0;

  const results = await mapWithConcurrencyLimit(
    [0, 1, 2, 3, 4, 5],
    2,
    async (value) => {
      inFlight += 1;
      maxInFlight = Math.max(maxInFlight, inFlight);
      await new Promise((resolve) => setTimeout(resolve, 5));
      inFlight -= 1;
      return value * 10;
    },
  );

  assertEquals(results, [0, 10, 20, 30, 40, 50]);
  assertEquals(maxInFlight, 2);
});

Deno.test("mapWithConcurrencyLimit coerces invalid widths to one worker", async () => {
  let inFlight = 0;
  let maxInFlight = 0;

  await mapWithConcurrencyLimit([1, 2, 3], 0, async (value) => {
    inFlight += 1;
    maxInFlight = Math.max(maxInFlight, inFlight);
    await new Promise((resolve) => setTimeout(resolve, 1));
    inFlight -= 1;
    return value;
  });

  assertEquals(maxInFlight, 1);
});
