import { assertEquals, assertRejects } from "@std/assert";
import { evidenceWorkerReceipt } from "./receipt.ts";

const counts = {
  retired: 0,
  video_retired: 0,
  retirement_failures: 0,
  claimed: 0,
  marked: 0,
  acknowledged: 0,
};
const dispatch = "00000000-0000-4000-8000-00000000ee01";
function request(value?: string) {
  return new Request("https://example.invalid", {
    method: "POST",
    headers: value === undefined ? {} : { "X-Merian-Evidence-Dispatch": value },
  });
}

Deno.test("legacy scheduler retains six counters; new scheduler receives exact correlation", async () => {
  for (const value of [undefined, dispatch]) {
    let calls = 0;
    const response = await evidenceWorkerReceipt(request(value), () => {
      calls++;
      return Promise.resolve(counts);
    });
    assertEquals(calls, 1);
    assertEquals(response.status, 200);
    assertEquals(response.headers.get("Cache-Control"), "no-store");
    assertEquals(
      await response.json(),
      value === undefined
        ? counts
        : { schema_version: 2, dispatch_id: dispatch, ...counts },
    );
  }
});

Deno.test("present invalid correlation never falls back or starts worker operations", async () => {
  for (
    const value of [
      "",
      "invalid",
      dispatch.toUpperCase(),
      dispatch.replace("4000", "1000"),
      dispatch.replace("8000", "7000"),
      `${dispatch}, ${dispatch}`,
      "a".repeat(4096),
    ]
  ) {
    let calls = 0;
    const response = await evidenceWorkerReceipt(request(value), () => {
      calls++;
      return Promise.resolve(counts);
    });
    assertEquals(calls, 0);
    assertEquals(response.status, 400);
    assertEquals(response.headers.get("Cache-Control"), "private, no-store");
    assertEquals((await response.json()).dispatch_id, undefined);
  }
});

Deno.test("work failure cannot emit a correlated terminal receipt", async () => {
  await assertRejects(
    () =>
      evidenceWorkerReceipt(
        request(dispatch),
        () => Promise.reject(new Error("synthetic")),
      ),
    Error,
    "synthetic",
  );
});
