import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import { createClient } from "@supabase/supabase-js";
import {
  InsightChatContextPreflightError,
  parsePreparedInsightChatContext,
  prepareInsightChatSendContext,
} from "../insight-chat/preparedContext.ts";
const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const request = {
  ownerId: id(1),
  scanId: id(2),
  displayedTicket: {
    analysis_id: id(3),
    state_revision: 1,
    review_revision: 0,
  },
};
function prepared() {
  return {
    context_version: 1,
    source_kind: "analysis_history_v1",
    displayed_ticket: { ...request.displayedTicket },
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
      candidates: [],
      species_dictionary: null,
      confirmed_species: null,
    },
  };
}
Deno.test("fresh context never fabricates missing fields, a message or a prefix", () => {
  const raw = prepared(),
    result = parsePreparedInsightChatContext(raw, request);
  assert(!Object.hasOwn(result, "conversation_prefix"));
  assert(!Object.hasOwn(result.scan_context, "timestamp"));
  assert(Object.isFrozen(result.scan_context.colors));
  raw.displayed_ticket.state_revision = 9;
  assertEquals(result.displayed_ticket, request.displayedTicket);
  assertEquals(
    parsePreparedInsightChatContext({
      ...prepared(),
      source_kind: "legacy_scan_v1",
      displayed_ticket: null,
    }, { ...request, displayedTicket: null }).displayed_ticket,
    null,
  );
});
Deno.test("fresh context rejects invented prefix, private payloads and changed authority", () => {
  for (
    const value of [
      null,
      [],
      {},
      { ...prepared(), conversation_prefix: [] },
      { ...prepared(), message: {} },
      { ...prepared(), context_version: 2 },
      { ...prepared(), source_kind: "legacy_scan_v1" },
      {
        ...prepared(),
        displayed_ticket: { ...request.displayedTicket, state_revision: 2 },
      },
      {
        ...prepared(),
        displayed_ticket: { ...request.displayedTicket, review_revision: 1 },
      },
      {
        ...prepared(),
        scan_context: { ...prepared().scan_context, field_notes: "private" },
      },
      {
        ...prepared(),
        scan_context: {
          ...prepared().scan_context,
          colors: Array(11).fill("green"),
        },
      },
    ]
  ) assertThrows(() => parsePreparedInsightChatContext(value, request));
});
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
Deno.test("fresh preflight sends only original owner/scan/ticket and no message identity", async () => {
  const mutable = structuredClone(request);
  let calls = 0;
  const value = await prepareInsightChatSendContext(
    client((url, init) => {
      calls++;
      assertEquals(
        String(url),
        "https://example.invalid/rest/v1/rpc/prepare_insight_chat_send_context",
      );
      assertEquals(JSON.parse(String(init?.body)), {
        p_user_id: id(1),
        p_scan_id: id(2),
        p_displayed_ticket: request.displayedTicket,
        p_context_version: 1,
      });
      assert(init?.signal);
      mutable.displayedTicket.state_revision = 9;
      return Promise.resolve(Response.json(prepared()));
    }),
    mutable,
    new AbortController().signal,
  );
  assertEquals(value.displayed_ticket, request.displayedTicket);
  assertEquals(calls, 1);
});
Deno.test("fresh preflight maps exact denials and never retries uncertain failures", async () => {
  for (
    const [code, message, http, status] of [
      ["P0002", "field_chat_subject_not_found", 404, 404],
      ["40001", "field_chat_context_conflict", 400, 409],
      ["40001", "unrelated serialization failure", 400, 503],
      ["PGRST202", "missing route", 404, 503],
      ["unknown", "private upstream detail", 503, 503],
      ["unknown", "private upstream detail", 520, 503],
    ] as const
  ) {
    let calls = 0;
    const error = await assertRejects(
      () =>
        prepareInsightChatSendContext(
          client(() => {
            calls++;
            return Promise.resolve(
              Response.json({ code, message }, {
                status: http,
                headers: { "Retry-After": "0" },
              }),
            );
          }),
          request,
          new AbortController().signal,
        ),
      InsightChatContextPreflightError,
    );
    assertEquals(error.status, status);
    assertEquals(calls, 1);
    if (status === 503) {
      assertEquals(error.message, "field_chat_context_unavailable");
    }
  }
});
Deno.test("fresh preflight rejects malformed success and cancellation around await", async () => {
  for (const value of [null, { context_version: 1, found: false }]) {
    await assertRejects(
      () =>
        prepareInsightChatSendContext(
          client(() => Promise.resolve(Response.json(value))),
          request,
          new AbortController().signal,
        ),
      InsightChatContextPreflightError,
    );
  }
  let calls = 0;
  const before = new AbortController();
  before.abort();
  await assertRejects(() =>
    prepareInsightChatSendContext(
      client(() => {
        calls++;
        return Promise.resolve(Response.json(prepared()));
      }),
      request,
      before.signal,
    ), DOMException);
  assertEquals(calls, 0);
  const after = new AbortController();
  await assertRejects(() =>
    prepareInsightChatSendContext(
      client(() => {
        after.abort();
        return Promise.resolve(Response.json(prepared()));
      }),
      request,
      after.signal,
    ), DOMException);
  await assertRejects(
    () =>
      prepareInsightChatSendContext(
        client(() => {
          throw new Error("private");
        }),
        request,
        new AbortController().signal,
      ),
    InsightChatContextPreflightError,
    "field_chat_context_unavailable",
  );
});
Deno.test("fresh preflight refuses malformed request before I/O", async () => {
  let calls = 0;
  const network = client(() => {
    calls++;
    return Promise.resolve(Response.json(prepared()));
  });
  for (
    const input of [{ ...request, ownerId: "wrong" }, {
      ...request,
      displayedTicket: {
        ...request.displayedTicket,
        analysis_id: request.scanId,
      },
    }, { ...request, extra: true }]
  ) {
    await assertRejects(() =>
      prepareInsightChatSendContext(
        network,
        input,
        new AbortController().signal,
      )
    );
  }
  assertEquals(calls, 0);
});
