import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { jsonResponse } from "./http.ts";

Deno.test("jsonResponse merges extra headers with default JSON headers", async () => {
  const response = jsonResponse({ ok: true }, 200, {
    "Cache-Control": "public, max-age=300",
    "Vary": "Accept-Encoding",
  });

  assertEquals(response.status, 200);
  assertEquals(response.headers.get("Content-Type"), "application/json");
  assertEquals(response.headers.get("Cache-Control"), "public, max-age=300");
  assertEquals(response.headers.get("Vary"), "Accept-Encoding");
  assertEquals(await response.json(), { ok: true });
});
