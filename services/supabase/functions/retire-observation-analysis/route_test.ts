import { assertEquals } from "@std/assert";
import type { User } from "@supabase/supabase-js";
import { analysisRetirementRoute } from "./route.ts";
const owner = "00000000-0000-4000-8000-000000000001";
const observation = "00000000-0000-4000-8000-000000000002";
const operation = "00000000-0000-4000-8000-000000000003";
const request = {
  schema_version: 1,
  observation_id: observation,
  operation_id: operation,
  analysis_id: "00000000-0000-4000-8000-000000000004",
  source_analysis_id: null,
  request_digest: "a".repeat(64),
};
const authenticated = () =>
  Promise.resolve({ user: { id: owner } as User, response: null });
async function environment(work: () => Promise<void>) {
  const saved = new Map(
    ["SUPABASE_URL", "SUPABASE_SERVER_API_KEY"].map((
      key,
    ) => [key, Deno.env.get(key)]),
  );
  Deno.env.set("SUPABASE_URL", "https://synthetic.invalid");
  Deno.env.set(
    "SUPABASE_SERVER_API_KEY",
    "sb_secret_" + "synthetic_test_only".repeat(3),
  );
  try {
    await work();
  } finally {
    for (const [key, value] of saved) {
      if (value === undefined) Deno.env.delete(key);
      else Deno.env.set(key, value);
    }
  }
}
Deno.test("analysis retirement route covers preflight, auth, method and parser failures with private no-store", async () => {
  await environment(async () => {
    for (
      const [method, body, expected] of [
        ["OPTIONS", undefined, 200],
        ["GET", undefined, 405],
        ["POST", "{", 400],
        ["POST", "x".repeat(2049), 413],
      ] as const
    ) {
      const response = await analysisRetirementRoute(
        new Request("https://example.invalid", {
          method,
          body,
          headers: { "Content-Type": "application/json" },
        }),
        authenticated,
      );
      assertEquals(response.status, expected);
      assertEquals(response.headers.get("Cache-Control"), "private, no-store");
      await response.body?.cancel();
    }
    const denied = await analysisRetirementRoute(
      new Request("https://example.invalid", { method: "POST" }),
      () =>
        Promise.resolve({
          user: null,
          response: new Response(null, { status: 401 }),
        }),
    );
    assertEquals(denied.status, 401);
    assertEquals(denied.headers.get("Cache-Control"), "private, no-store");
    await denied.body?.cancel();
  });
});
Deno.test("analysis retirement authenticated route scopes actual RPC and conceals foreign/deleted records", async () => {
  await environment(async () => {
    const original = globalThis.fetch;
    let calls = 0;
    globalThis.fetch = (_url, init) => {
      calls++;
      assertEquals(
        String(_url).endsWith(
          "/rest/v1/rpc/retire_owned_observation_analysis_execution",
        ),
        true,
      );
      assertEquals(JSON.parse(String(init?.body)), {
        p_owner: owner,
        p_request: request,
        p_reader: 10,
      });
      return Promise.resolve(
        new Response(
          JSON.stringify({
            code: "P0002",
            message: "analysis_history_not_found",
          }),
          { status: 404 },
        ),
      );
    };
    try {
      const response = await analysisRetirementRoute(
        new Request("https://example.invalid", {
          method: "POST",
          body: JSON.stringify(request),
          headers: { "Content-Type": "application/json" },
        }),
        authenticated,
      );
      assertEquals(response.status, 404);
      assertEquals(response.headers.get("Cache-Control"), "private, no-store");
      assertEquals((await response.json()).code, "analysis_history_not_found");
      assertEquals(calls, 1);
    } finally {
      globalThis.fetch = original;
    }
  });
});
Deno.test("retirement route bounds actual RPC response and performs one attempt on upstream failures", async () => {
  await environment(async () => {
    const original = globalThis.fetch;
    try {
      for (const mode of ["oversized", "401", "503", "valid"] as const) {
        let calls = 0;
        globalThis.fetch = () => {
          calls++;
          const body = mode === "oversized"
            ? '"' + "x".repeat(4096) + '"'
            : mode === "valid"
            ? JSON.stringify({ ...request, state: "retired_before_dispatch" })
            : JSON.stringify({ message: "private upstream diagnostic" });
          // No Content-Length: enforce the streamed bytes, not just a header.
          return Promise.resolve(
            new Response(body, {
              status: mode === "401" ? 401 : mode === "503" ? 503 : 200,
            }),
          );
        };
        const response = await analysisRetirementRoute(
          new Request("https://synthetic.invalid", {
            method: "POST",
            body: JSON.stringify(request),
            headers: { "Content-Type": "application/json" },
          }),
          authenticated,
        );
        assertEquals(response.status, mode === "valid" ? 200 : 503);
        assertEquals(
          (await response.text()).includes("private upstream diagnostic"),
          false,
        );
        assertEquals(calls, 1);
      }
    } finally {
      globalThis.fetch = original;
    }
  });
});
Deno.test("retirement route five-second deadline ends even when upstream ignores abort", async () => {
  await environment(async () => {
    const originalFetch = globalThis.fetch;
    const originalTimeout = AbortSignal.timeout;
    const deadline = new AbortController();
    let calls = 0;
    const budgets: number[] = [];
    AbortSignal.timeout = (ms: number) => {
      budgets.push(ms);
      return deadline.signal;
    };
    globalThis.fetch = () => {
      calls++;
      queueMicrotask(() => deadline.abort());
      return new Promise(() => {});
    };
    try {
      const response = await analysisRetirementRoute(
        new Request("https://synthetic.invalid", {
          method: "POST",
          body: JSON.stringify(request),
          headers: { "Content-Type": "application/json" },
        }),
        authenticated,
      );
      assertEquals(response.status, 503);
      await response.body?.cancel();
      assertEquals(calls, 1);
      assertEquals(budgets.length > 0, true);
      assertEquals(budgets.every((ms) => ms === 5000), true);
    } finally {
      globalThis.fetch = originalFetch;
      AbortSignal.timeout = originalTimeout;
    }
  });
});
