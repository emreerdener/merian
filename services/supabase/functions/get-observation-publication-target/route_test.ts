import { assertEquals } from "@std/assert";
import type { User } from "@supabase/supabase-js";
import { publicationTargetRoute } from "./route.ts";
const owner = "00000000-0000-4000-8000-000000000001";
const observation = "00000000-0000-4000-8000-000000000002";
const request = {
  schema_version: 1,
  observation_id: observation,
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
Deno.test("publication target route covers preflight, auth, method and parser failures with private no-store", async () => {
  await environment(async () => {
    for (
      const [method, body, expected] of [
        ["OPTIONS", undefined, 200],
        ["GET", undefined, 405],
        ["POST", "{", 400],
        ["POST", "x".repeat(1025), 413],
      ] as const
    ) {
      const response = await publicationTargetRoute(
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
    const denied = await publicationTargetRoute(
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
Deno.test("publication target authenticated route scopes actual RPC and conceals foreign/deleted records", async () => {
  await environment(async () => {
    const original = globalThis.fetch;
    let calls = 0;
    globalThis.fetch = (_url, init) => {
      calls++;
      assertEquals(
        String(_url).endsWith(
          "/rest/v1/rpc/read_owned_observation_publication_target",
        ),
        true,
      );
      assertEquals(JSON.parse(String(init?.body)), {
        p_owner: owner,
        p_observation: observation,
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
      const response = await publicationTargetRoute(
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

Deno.test("publication target route requires an explicit database envelope before returning vacancy", async () => {
  await environment(async () => {
    const original = globalThis.fetch;
    try {
      for (
        const [body, status, expected] of [
          ["", 200, 503],
          [null, 204, 503],
          ["null", 200, 503],
          [JSON.stringify({ schema_version: 1, operation: null }), 200, 200],
        ] as const
      ) {
        globalThis.fetch = () =>
          Promise.resolve(
            new Response(body, {
              status,
              headers: { "Content-Type": "application/json" },
            }),
          );
        const response = await publicationTargetRoute(
          new Request("https://example.invalid", {
            method: "POST",
            body: JSON.stringify(request),
            headers: { "Content-Type": "application/json" },
          }),
          authenticated,
        );
        assertEquals(response.status, expected);
        assertEquals(
          response.headers.get("Cache-Control"),
          "private, no-store",
        );
        if (expected === 200) assertEquals(await response.json(), null);
        else {assertEquals(
            (await response.json()).code,
            "analysis_history_unavailable",
          );}
      }
    } finally {
      globalThis.fetch = original;
    }
  });
});
