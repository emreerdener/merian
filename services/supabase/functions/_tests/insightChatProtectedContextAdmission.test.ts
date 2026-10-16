import { assert, assertEquals, assertRejects } from "@std/assert";
import { createClient } from "@supabase/supabase-js";
import { InsightChatContextAdmissionError } from "../insight-chat/contextAdmission.ts";
import {
  admitOrRecoverProtectedInsightChatContext,
  admitProtectedInsightChatContext,
} from "../insight-chat/protectedContextAdmission.ts";
const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
function request() {
  return {
    ownerId: id(1),
    scanId: id(2),
    clientMessageId: id(3),
    conversationId: id(4),
    messageText: "Question",
    displayedTicket: null,
    reservationId: id(5),
    leaseToken: id(6),
  };
}
function context() {
  return {
    context_version: 1,
    source_kind: "legacy_scan_v1",
    displayed_ticket: null,
    scan_context: {
      extracted_visual_traits: [],
      colors: [],
      ecological_interactions: [],
      primary_identification: null,
      confirmed_species_identity: null,
      identification_provenance: null,
      ai_identification_review: null,
      user_observation_context: null,
      pet_identification: null,
      candidates: null,
      species_dictionary: null,
      confirmed_species: null,
    },
    conversation_prefix: [],
  };
}
function message() {
  return {
    id: id(7),
    conversation_id: id(8),
    user_id: id(1),
    scan_id: id(2),
    client_message_id: id(3),
    role: "user",
    message_text: "Question",
  };
}
function admitted(replay = false) {
  return [{
    conversation_id: id(8),
    message: message(),
    is_replay: replay,
    sends_today: 1,
    context_snapshot: context(),
  }];
}
function recovered() {
  return {
    context_version: 1,
    found: true,
    message: message(),
    context_snapshot: context(),
  };
}
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
const response = (value: unknown, status = 200) =>
  new Response(JSON.stringify(value), { status });
Deno.test("funded context sends only original funding pair to fixed nine-argument RPC", async () => {
  const calls: { path: string; body: unknown }[] = [];
  const db = client((url, init) => {
    calls.push({
      path: new URL(String(url)).pathname,
      body: JSON.parse(String(init?.body)),
    });
    return Promise.resolve(response(admitted()));
  });
  const result = await admitProtectedInsightChatContext(
    db,
    request(),
    new AbortController().signal,
  );
  assertEquals(result.conversationId, id(8));
  assertEquals(calls, [{
    path: "/rest/v1/rpc/reserve_protected_insight_chat_send_with_context",
    body: {
      p_user_id: id(1),
      p_scan_id: id(2),
      p_conversation_id: id(4),
      p_client_message_id: id(3),
      p_message_text: "Question",
      p_displayed_ticket: null,
      p_context_version: 1,
      p_reservation_id: id(5),
      p_lease_token: id(6),
    },
  }]);
});
Deno.test("funded context distinguishes original replay from fresh admission", async () => {
  const db = client(() => Promise.resolve(response(admitted(true))));
  const result = await admitOrRecoverProtectedInsightChatContext(
    db,
    request(),
    new AbortController().signal,
  );
  assertEquals(result.kind, "replayed");
  assert(!("leaseToken" in result));
});
Deno.test("funded context rejects damaged request before any network", async () => {
  let calls = 0;
  const db = client(() => {
    calls++;
    return Promise.resolve(response(admitted()));
  });
  for (
    const input of [
      { ...request(), leaseToken: "bad" },
      { ...request(), reservationId: "bad" },
      { ...request(), extra: 1 },
      { ...request(), messageText: " Changed " },
    ]
  ) {
    await assertRejects(() =>
      admitProtectedInsightChatContext(db, input, new AbortController().signal)
    );
  }
  assertEquals(calls, 0);
});
Deno.test("funded context exact known rejection performs no recovery, refund or grant", async () => {
  const calls: string[] = [];
  const db = client((url) => {
    calls.push(String(url));
    return Promise.resolve(
      response({ code: "55000", message: "field_chat_execution_held" }, 400),
    );
  });
  const error = await assertRejects(
    () =>
      admitOrRecoverProtectedInsightChatContext(
        db,
        request(),
        new AbortController().signal,
      ),
    InsightChatContextAdmissionError,
  );
  assertEquals(error.transactionOutcome, "rejected");
  assertEquals(calls.length, 1);
});
for (const scenario of ["network", "malformed", "503"]) {
  Deno.test(`funded context ${scenario} allows one exact read, never another write`, async () => {
    const calls: { path: string; body: Record<string, unknown> }[] = [];
    const input = request();
    const db = client((url, init) => {
      calls.push({
        path: new URL(String(url)).pathname,
        body: JSON.parse(String(init?.body)),
      });
      if (calls.length === 1) {
        input.messageText = "Changed";
        input.clientMessageId = id(9);
        input.reservationId = id(10);
        input.leaseToken = id(11);
        if (scenario === "network") {
          return Promise.reject(new Error("synthetic lost reply"));
        }
        return Promise.resolve(
          response(
            scenario === "malformed" ? [] : { code: "503", message: "unknown" },
            scenario === "503" ? 503 : 200,
          ),
        );
      }
      return Promise.resolve(response(recovered()));
    });
    const result = await admitOrRecoverProtectedInsightChatContext(
      db,
      input,
      new AbortController().signal,
    );
    assertEquals(result.kind, "recovered");
    assertEquals(calls.length, 2);
    assertEquals(calls[1].path, "/rest/v1/rpc/get_insight_chat_turn_context");
    assertEquals(calls[1].body.p_client_message_id, id(3));
    assertEquals(calls[1].body.p_message_text, "Question");
    assert(!("p_reservation_id" in calls[1].body));
  });
}
Deno.test("funded lost reply plus absent or broken recovery stays unknown", async () => {
  for (
    const recovery of [{ context_version: 1, found: false }, {
      context_version: 1,
      found: true,
    }, null]
  ) {
    let calls = 0;
    const db = client(() => {
      calls++;
      return Promise.resolve(response(calls === 1 ? [] : recovery));
    });
    const error = await assertRejects(
      () =>
        admitOrRecoverProtectedInsightChatContext(
          db,
          request(),
          new AbortController().signal,
        ),
      InsightChatContextAdmissionError,
    );
    assertEquals(error.transactionOutcome, "unknown");
    assertEquals(calls, 2);
  }
});
Deno.test("funded cancellation after reply holds without another read", async () => {
  let calls = 0;
  const controller = new AbortController();
  const db = client(() => {
    calls++;
    controller.abort();
    return Promise.resolve(response(admitted()));
  });
  const error = await assertRejects(
    () =>
      admitOrRecoverProtectedInsightChatContext(
        db,
        request(),
        controller.signal,
      ),
    InsightChatContextAdmissionError,
  );
  assertEquals(error.transactionOutcome, "unknown");
  assertEquals(calls, 1);
});
Deno.test("funded malformed owner or message evidence is never a decoded admission", async () => {
  for (
    const mismatch of [{ user_id: id(9) }, { scan_id: id(9) }, {
      client_message_id: id(9),
    }, { message_text: "Changed" }]
  ) {
    const row = admitted();
    Object.assign(row[0].message, mismatch);
    const db = client(() => Promise.resolve(response(row)));
    const error = await assertRejects(
      () =>
        admitProtectedInsightChatContext(
          db,
          request(),
          new AbortController().signal,
        ),
      InsightChatContextAdmissionError,
    );
    assertEquals(error.transactionOutcome, "unknown");
  }
});
