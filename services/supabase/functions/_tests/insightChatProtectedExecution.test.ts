import { assertEquals, assertRejects, assertThrows } from "@std/assert";
import { createClient } from "@supabase/supabase-js";
import {
  grantProtectedChatDispatch,
  parseProtectedChatDispatch,
  parseProtectedChatQuota,
  ProtectedChatExecutionUnknown,
  reserveProtectedChatQuota,
} from "../insight-chat/protectedExecution.ts";
const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const dispatch = {
  ownerId: id(1),
  scanId: id(2),
  clientMessageId: id(3),
  reservationId: id(4),
  leaseToken: id(5),
};
const request = {
  ownerId: id(1),
  scanId: id(2),
  clientMessageId: id(3),
  messageText: "Question",
  displayedTicket: null,
};
const receipt = {
  status: "reserved",
  reservation_id: id(4),
  lease_token: id(5),
  lease_expires_at: "2026-10-06T10:00:00.123456+00:00",
  model: "gemini-2.5-flash",
};
function client(fetcher: typeof fetch) {
  return createClient("https://example.invalid", "synthetic-key", {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
    global: { fetch: fetcher },
  });
}
Deno.test("protected quota accepts only narrow lease and held shapes", () => {
  assertEquals(parseProtectedChatQuota(receipt).status, "reserved");
  assertEquals(parseProtectedChatQuota({ status: "held" }), { status: "held" });
  for (
    const value of [
      null,
      [],
      { status: "reserved", quota: receipt },
      { ...receipt, attempt_count: 1 },
      { ...receipt, model: "unknown" },
      { ...receipt, lease_token: "bad" },
      { ...receipt, lease_expires_at: "today" },
      { status: "held", lease_token: id(5) },
    ]
  ) assertThrows(() => parseProtectedChatQuota(value));
});
Deno.test("protected dispatch grants no reusable capability on held or additive reply", () => {
  assertEquals(
    parseProtectedChatDispatch({
      status: "dispatch_granted",
      model: "gemini-2.5-flash",
    }).status,
    "dispatch_granted",
  );
  assertEquals(parseProtectedChatDispatch({ status: "held" }), {
    status: "held",
  });
  for (
    const value of [
      true,
      null,
      [],
      { status: "committed" },
      { status: "dispatch_granted", model: "unknown" },
      { status: "held", model: "gemini-2.5-flash" },
      {
        status: "dispatch_granted",
        model: "gemini-2.5-flash",
        lease_token: id(5),
      },
    ]
  ) assertThrows(() => parseProtectedChatDispatch(value));
});
Deno.test("protected fixed RPCs transmit the exact owner, original identities and ticket once", async () => {
  const calls: { path: string; body: unknown }[] = [];
  const db = client((url, init) => {
    calls.push({ path: String(url), body: JSON.parse(String(init?.body)) });
    return Promise.resolve(
      new Response(
        JSON.stringify(
          calls.length === 1
            ? receipt
            : { status: "dispatch_granted", model: "gemini-2.5-flash" },
        ),
      ),
    );
  });
  assertEquals(
    (await reserveProtectedChatQuota(
      db,
      request,
      "a".repeat(64),
      new AbortController().signal,
    )).status,
    "reserved",
  );
  assertEquals(
    (await grantProtectedChatDispatch(
      db,
      dispatch,
      new AbortController().signal,
    )).status,
    "dispatch_granted",
  );
  assertEquals(calls.map((x) => new URL(x.path).pathname), [
    "/rest/v1/rpc/reserve_protected_insight_chat_quota",
    "/rest/v1/rpc/grant_protected_insight_chat_dispatch",
  ]);
  assertEquals(calls[1].body, {
    p_user_id: id(1),
    p_scan_id: id(2),
    p_client_message_id: id(3),
    p_reservation_id: id(4),
    p_lease_token: id(5),
  });
});
for (const scenario of ["network", "503", "malformed", "abort after reply"]) {
  Deno.test(`protected dispatch ${scenario} is unknown without retry or provider permission`, async () => {
    let calls = 0;
    const controller = new AbortController();
    const db = client(() => {
      calls++;
      if (scenario === "network") {
        return Promise.reject(new Error("synthetic transport failure"));
      }
      if (scenario === "abort after reply") controller.abort();
      return Promise.resolve(
        new Response(
          JSON.stringify(
            scenario === "malformed"
              ? { status: "dispatch_granted" }
              : { status: "dispatch_granted", model: "gemini-2.5-flash" },
          ),
          { status: scenario === "503" ? 503 : 200 },
        ),
      );
    });
    await assertRejects(
      () => grantProtectedChatDispatch(db, dispatch, controller.signal),
      ProtectedChatExecutionUnknown,
    );
    assertEquals(calls, 1);
  });
}
Deno.test("protected execution rejects malformed request or precancel before network", async () => {
  let calls = 0;
  const db = client(() => {
    calls++;
    return Promise.resolve(new Response("{}"));
  });
  await assertRejects(() =>
    grantProtectedChatDispatch(
      db,
      { ...dispatch, leaseToken: "bad" },
      new AbortController().signal,
    )
  );
  const controller = new AbortController();
  controller.abort();
  await assertRejects(() =>
    grantProtectedChatDispatch(db, dispatch, controller.signal)
  );
  await assertRejects(() =>
    reserveProtectedChatQuota(db, request, "bad", new AbortController().signal)
  );
  assertEquals(calls, 0);
});
