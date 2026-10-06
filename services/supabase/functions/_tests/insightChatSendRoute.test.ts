import { assert, assertEquals, assertRejects } from "@std/assert";
import { createClient } from "@supabase/supabase-js";
import { insightChatRequiresContext } from "../insight-chat/sendRoute.ts";
const ownerId = "00000000-0000-4000-8000-000000000001",
  scanId = "00000000-0000-4000-8000-000000000002";
const client = (fetcher: typeof fetch) =>
  createClient("https://example.invalid", "synthetic-key", {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
    global: { fetch: fetcher },
  });
Deno.test("server route sends owner and observation only, independent of client ticket", async () => {
  for (const required of [false, true]) {
    let calls = 0;
    const db = client((url, init) => {
      calls++;
      assertEquals(
        new URL(String(url)).pathname,
        "/rest/v1/rpc/get_insight_chat_send_route",
      );
      assertEquals(JSON.parse(String(init?.body)), {
        p_user_id: ownerId,
        p_scan_id: scanId,
      });
      return Promise.resolve(
        new Response(JSON.stringify({ requires_context: required })),
      );
    });
    assertEquals(
      await insightChatRequiresContext(
        db,
        { ownerId, scanId },
        new AbortController().signal,
      ),
      required,
    );
    assertEquals(calls, 1);
  }
});
Deno.test("unknown, malformed or additive route never authorizes legacy", async () => {
  for (
    const value of [null, [], {}, { requires_context: 0 }, {
      requires_context: false,
      extra: true,
    }]
  ) {
    let calls = 0;
    const db = client(() => {
      calls++;
      return Promise.resolve(new Response(JSON.stringify(value)));
    });
    await assertRejects(
      () =>
        insightChatRequiresContext(
          db,
          { ownerId, scanId },
          new AbortController().signal,
        ),
      Error,
      "field_chat_context_unavailable",
    );
    assertEquals(calls, 1);
  }
});
Deno.test("route network failure and post-await cancellation never retry", async () => {
  for (const scenario of ["network", "503", "abort"]) {
    let calls = 0;
    const controller = new AbortController();
    const db = client(() => {
      calls++;
      if (scenario === "network") return Promise.reject(new Error("synthetic"));
      if (scenario === "abort") controller.abort();
      return Promise.resolve(
        new Response('{"requires_context":false}', {
          status: scenario === "503" ? 503 : 200,
        }),
      );
    });
    await assertRejects(() =>
      insightChatRequiresContext(db, { ownerId, scanId }, controller.signal)
    );
    assertEquals(calls, 1);
  }
});
Deno.test("HTTP send routing fences before all mutable context, tier and quota work", async () => {
  const source = await Deno.readTextFile(
    new URL("../insight-chat/index.ts", import.meta.url),
  );
  const start = source.indexOf('if (action === "send")');
  const route = source.indexOf("await insightChatRequiresContext", start);
  assert(start > 0 && route > start);
  for (
    const marker of [
      "await countUserSendsToday",
      "await fetchOwnedScan",
      "await resolveTierForUser",
      "await reserveAIProviderCall",
    ]
  ) assert(route < source.indexOf(marker), marker);
  assert(
    source.slice(start, source.indexOf("const sendsToday", start)).includes(
      '"field_chat_context_required"',
    ),
  );
});
