import { requireParams } from "../_shared/http.ts";

function assertEquals<T>(actual: T, expected: T): void {
  if (actual !== expected) {
    throw new Error(`Assertion failed. Expected ${String(expected)}, received ${String(actual)}.`);
  }
}

Deno.test("requireParams treats boolean false as present", async () => {
  const result = requireParams({ liked: false }, ["liked"]);
  assertEquals(result, null);
});

Deno.test("requireParams treats numeric zero as present", async () => {
  const result = requireParams({ offset: 0 }, ["offset"]);
  assertEquals(result, null);
});

Deno.test("requireParams still rejects empty string values", async () => {
  const response = requireParams({ post_id: "   " }, ["post_id"]);
  const payload = await response?.json();

  assertEquals(response?.status, 400);
  assertEquals(payload?.error, "Missing required parameter: post_id");
});
