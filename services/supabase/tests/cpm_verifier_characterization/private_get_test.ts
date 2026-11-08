import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import { privateGetAdapter } from "./private_get.ts";

Deno.test("private GET signs fixed path once with redirects disabled; no implicit transport", async () => {
  let calls = 0;
  const options = {
    endpoint: `https://${"0".repeat(32)}.r2.cloudflarestorage.com/`,
    bucket: "merian-cpm-verifier-fixtures",
    run: "synthetic-run",
    accessKeyId: "synthetic-only-key",
    secretAccessKey: "synthetic-only-secret",
    fetchOnce: (request: Request) => {
      calls++;
      assertEquals(request.method, "GET");
      assertEquals(request.redirect, "error");
      assertEquals(
        new URL(request.url).pathname,
        "/merian-cpm-verifier-fixtures/cpm-verifier/synthetic-run/control.bin",
      );
      assert(
        request.headers.get("authorization")?.startsWith("AWS4-HMAC-SHA256 "),
      );
      return Promise.resolve(new Response(null, { status: 500 }));
    },
  };
  const get = privateGetAdapter(options);
  assertEquals(
    (await get("control", new AbortController().signal)).status,
    500,
  );
  assertEquals(calls, 1);
  const abort = new AbortController();
  abort.abort();
  await assertRejects(() => get("control", abort.signal));
  assertEquals(calls, 1);
  for (
    const change of [
      { endpoint: "http://localhost/" },
      { endpoint: options.endpoint + "escape" },
      { bucket: "merian-media" },
      { run: "../escape" },
      { endpoint: "https://user:pass@example.com" },
    ]
  ) assertThrows(() => privateGetAdapter({ ...options, ...change }));
});
