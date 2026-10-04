import { assertEquals, assertRejects } from "@std/assert";
import { publicationAbortable } from "./publicationDeadline.ts";
Deno.test("publication deadline regains control when a transport never acknowledges cancellation", async () => {
  const controller = new AbortController();
  let calls = 0;
  const pending = publicationAbortable(controller.signal, () => {
    calls++;
    return new Promise<never>(() => {});
  });
  await Promise.resolve();
  controller.abort();
  await assertRejects(() => pending);
  assertEquals(calls, 1);
});
Deno.test("publication deadline prevents an already expired mutation", async () => {
  const controller = new AbortController();
  controller.abort();
  let calls = 0;
  await assertRejects(() =>
    publicationAbortable(controller.signal, () => {
      calls++;
      return Promise.resolve();
    })
  );
  assertEquals(calls, 0);
});
Deno.test("publication deadline does not change a completed result", async () => {
  const controller = new AbortController();
  assertEquals(
    await publicationAbortable(controller.signal, () => Promise.resolve(1)),
    1,
  );
  controller.abort();
});
