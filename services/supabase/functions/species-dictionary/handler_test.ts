import { assertEquals } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import { createSpeciesDictionaryHttpHandler } from "./index.ts";

function request(body: Record<string, unknown>): Request {
  return new Request(
    "https://test-project.supabase.co/functions/v1/species-dictionary",
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    },
  );
}

Deno.test("species-dictionary handler rejects retired and unknown modes before service access", async () => {
  let clientCreationCount = 0;
  const handler = createSpeciesDictionaryHttpHandler({
    createServiceRoleClient: () => {
      clientCreationCount += 1;
      throw new Error("service access must not occur");
    },
  });

  for (const mode of ["tree", "detail"]) {
    const response = await handler(request({ mode }));
    const payload = await response.json();

    assertEquals(response.status, 400);
    assertEquals(payload.code, "invalid_request");
    assertEquals(
      payload.error,
      "mode must be catalog or overview when provided.",
    );
    assertEquals(response.headers.get("Cache-Control"), "private, no-store");
    assertEquals(response.headers.get("X-Merian-Handler"), "1");
  }

  assertEquals(clientCreationCount, 0);
});

Deno.test("species-dictionary handler keeps public preflight independent of service access", async () => {
  let clientCreationCount = 0;
  const handler = createSpeciesDictionaryHttpHandler({
    createServiceRoleClient: () => {
      clientCreationCount += 1;
      return {} as SupabaseClient;
    },
  });
  const response = await handler(
    new Request(
      "https://test-project.supabase.co/functions/v1/species-dictionary",
      { method: "OPTIONS" },
    ),
  );

  assertEquals(response.status, 200);
  assertEquals(response.headers.get("X-Merian-Handler"), "1");
  assertEquals(response.headers.get("Access-Control-Allow-Origin"), "*");
  assertEquals(clientCreationCount, 0);
});
