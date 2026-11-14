import { assertEquals } from "@std/assert";
import { handleGeminiReleaseSmoke } from "./index.ts";
import { serviceRoleRequestHeaders } from "../_shared/serviceRoleAuth.ts";

Deno.test("release smoke denies public callers, unknown cases and all caller overrides without dispatch", async () => {
  const keys = [
    "SUPABASE_SERVER_API_KEY",
    "MERIAN_SUPABASE_SERVER_API_KEY",
    "SUPABASE_SECRET_KEYS",
    "SUPABASE_SECRET_KEY",
    "SUPABASE_SERVICE_ROLE_KEY",
    "SUPABASE_URL",
  ];
  const prior = new Map(keys.map((k) => [k, Deno.env.get(k)]));
  const key = "sb_secret_" + "synthetic_smoke_test".repeat(3);
  const originalFetch = globalThis.fetch;
  let calls = 0;
  try {
    for (const k of keys) Deno.env.delete(k);
    Deno.env.set("SUPABASE_SERVER_API_KEY", key);
    Deno.env.set("SUPABASE_URL", "https://synthetic.invalid");
    globalThis.fetch = () => {
      calls++;
      throw new Error("Network forbidden");
    };
    const request = (body: unknown, authenticated = true) =>
      new Request("https://synthetic.invalid/gemini-release-smoke", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...(authenticated ? serviceRoleRequestHeaders(key) : {}),
        },
        body: JSON.stringify(body),
      });
    const ids = {
      release_id: "00000000-0000-4000-8000-000000000001",
      case_id: "unknown_case",
    };
    assertEquals(
      (await handleGeminiReleaseSmoke(request(ids, false))).status,
      401,
    );
    assertEquals((await handleGeminiReleaseSmoke(request(ids))).status, 400);
    for (
      const override of [
        "model",
        "prompt",
        "endpoint",
        "generationConfig",
        "media",
        "authorization",
      ]
    ) {
      assertEquals(
        (await handleGeminiReleaseSmoke(
          request({ ...ids, [override]: "caller value" }),
        )).status,
        400,
      );
    }
    for (
      const body of [[], null, { ...ids, release_id: "main" }, {
        ...ids,
        case_id: "../identify",
      }]
    ) {
      assertEquals((await handleGeminiReleaseSmoke(request(body))).status, 400);
    }
    assertEquals(calls, 0);
  } finally {
    globalThis.fetch = originalFetch;
    for (const [k, v] of prior) {
      if (v === undefined) Deno.env.delete(k);
      else Deno.env.set(k, v);
    }
  }
});
