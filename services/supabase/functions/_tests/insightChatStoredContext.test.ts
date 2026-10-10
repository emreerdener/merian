import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import { createClient } from "@supabase/supabase-js";
import {
  parseStoredInsightChatResolution,
  validateStoredTurnRequest,
} from "../insight-chat/storedContext.ts";
import {
  resolveStoredInsightChatTurn,
  StoredInsightChatRecoveryError,
} from "../insight-chat/storedContextRepository.ts";
const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const request = {
  ownerId: id(1),
  scanId: id(2),
  clientMessageId: id(3),
  messageText: "Question",
  displayedTicket: {
    analysis_id: id(4),
    state_revision: 3,
    review_revision: 1,
  },
};
function response() {
  return {
    context_version: 1,
    found: true,
    message: {
      id: id(5),
      conversation_id: id(6),
      scan_id: id(2),
      user_id: id(1),
      role: "user",
      client_message_id: id(3),
      message_text: "Question",
    },
    context_snapshot: {
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
      conversation_prefix: [{ role: "assistant", text: "Original prefix" }],
    },
  };
}
Deno.test("stored context preserves missing V3 fields and freezes a detached tree", () => {
  const raw = response();
  const decoded = parseStoredInsightChatResolution(raw, request);
  assert(decoded.found);
  assert(!Object.hasOwn(decoded.context.scan_context, "timestamp"));
  assert(Object.isFrozen(decoded.context.scan_context));
  assert(Object.isFrozen(decoded.context.conversation_prefix[0]));
  raw.context_snapshot.conversation_prefix[0].text = "Changed";
  assertEquals(decoded.context.conversation_prefix[0].text, "Original prefix");
});
Deno.test("stored context accepts explicit missing and legacy null only", () => {
  assertEquals(
    parseStoredInsightChatResolution(
      { context_version: 1, found: false },
      request,
    ),
    { found: false },
  );
  const legacy = {
    ...response(),
    context_snapshot: {
      ...response().context_snapshot,
      source_kind: "legacy_scan_v1",
      displayed_ticket: null,
    },
  };
  assert(
    parseStoredInsightChatResolution(legacy, {
      ...request,
      displayedTicket: null,
    }).found,
  );
  for (
    const raw of [
      null,
      undefined,
      [],
      {},
      { found: false },
      { context_version: 2, found: false },
      { context_version: 1, found: false, message: {} },
      { ...response(), found: "true" },
    ]
  ) {
    assertThrows(
      () => parseStoredInsightChatResolution(raw, request),
      Error,
      "field_chat_context_unavailable",
    );
  }
});
Deno.test("stored context rejects mismatched association and ticket without rebasing", () => {
  for (
    const key of [
      "id",
      "conversation_id",
      "scan_id",
      "user_id",
      "client_message_id",
      "role",
      "message_text",
    ] as const
  ) {
    const raw = response();
    raw.message[key] = "wrong";
    assertThrows(() => parseStoredInsightChatResolution(raw, request));
  }
  for (
    const ticket of [null, { ...request.displayedTicket, state_revision: 4 }, {
      ...request.displayedTicket,
      review_revision: 2,
    }, { ...request.displayedTicket, analysis_id: id(9) }]
  ) {
    assertThrows(() =>
      parseStoredInsightChatResolution(response(), {
        ...request,
        displayedTicket: ticket,
      })
    );
  }
});
Deno.test("stored context rejects private/unrecognized fields and bounded-prefix violations", () => {
  for (
    const scan of [
      { ...response().context_snapshot.scan_context, field_notes: "private" },
      {
        ...response().context_snapshot.scan_context,
        image_storage_urls: ["private"],
      },
      {
        ...response().context_snapshot.scan_context,
        user_observation_context: { free_text: "ok", media: "private" },
      },
      { ...response().context_snapshot.scan_context, colors: [3] },
      {
        ...response().context_snapshot.scan_context,
        candidates: Array(7).fill({}),
      },
      {
        ...response().context_snapshot.scan_context,
        ai_reasoning: "x".repeat(4001),
      },
    ]
  ) {
    assertThrows(() =>
      parseStoredInsightChatResolution({
        ...response(),
        context_snapshot: {
          ...response().context_snapshot,
          scan_context: scan,
        },
      }, request)
    );
  }
  for (
    const prefix of [
      Array(13).fill({ role: "user", text: "x" }),
      [{ role: "system", text: "x" }],
      [{ role: "user", text: "x".repeat(901) }],
      [{ role: "user", text: "x", id: id(1) }],
    ]
  ) {
    assertThrows(() =>
      parseStoredInsightChatResolution({
        ...response(),
        context_snapshot: {
          ...response().context_snapshot,
          conversation_prefix: prefix,
        },
      }, request)
    );
  }
});
Deno.test("stored request validates exact normalized bounded input before any I/O", () => {
  for (
    const changed of [
      { ...request, messageText: " Question" },
      { ...request, messageText: "" },
      { ...request, messageText: "x".repeat(601) },
      { ...request, ownerId: "wrong" },
      {
        ...request,
        displayedTicket: { ...request.displayedTicket, state_revision: 0 },
      },
      {
        ...request,
        displayedTicket: {
          ...request.displayedTicket,
          analysis_id: request.scanId,
        },
      },
      { ...request, unexpected: true },
    ]
  ) assertThrows(() => validateStoredTurnRequest(changed));
  assertEquals(
    validateStoredTurnRequest({ ...request, messageText: "🌱".repeat(600) })
      .messageText.length,
    1200,
  );
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
Deno.test("stored resolver makes one exact read, preserves original request and never admits", async () => {
  let calls = 0;
  const mutable = structuredClone(request);
  const result = await resolveStoredInsightChatTurn(
    client((url, init) => {
      calls++;
      assertEquals(
        String(url),
        "https://example.invalid/rest/v1/rpc/get_insight_chat_turn_context",
      );
      assertEquals(init?.method, "POST");
      assert(init?.signal);
      assertEquals(JSON.parse(String(init?.body)), {
        p_user_id: id(1),
        p_scan_id: id(2),
        p_client_message_id: id(3),
        p_message_text: "Question",
        p_displayed_ticket: request.displayedTicket,
        p_context_version: 1,
      });
      mutable.displayedTicket.state_revision = 88;
      return Promise.resolve(Response.json(response()));
    }),
    mutable,
    new AbortController().signal,
  );
  assert(result.found);
  assertEquals(result.context.displayed_ticket, request.displayedTicket);
  assertEquals(calls, 1);
});
Deno.test("stored resolver classifies exact DB errors and never treats HTTP404 as missing", async () => {
  for (
    const [code, message, status, expected] of [
      [
        "P0002",
        "field_chat_subject_not_found",
        404,
        "field_chat_subject_not_found",
      ],
      [
        "55000",
        "field_chat_context_missing",
        409,
        "field_chat_context_missing",
      ],
      [
        "23505",
        "field_chat_idempotency_conflict",
        409,
        "field_chat_idempotency_conflict",
      ],
      ["PGRST202", "missing route", 503, "field_chat_context_unavailable"],
      ["55000", "raw database content", 503, "field_chat_context_unavailable"],
      [
        "P0002",
        "different subject error",
        503,
        "field_chat_context_unavailable",
      ],
    ] as const
  ) {
    let calls = 0;
    const error = await assertRejects(
      () =>
        resolveStoredInsightChatTurn(
          client(() => {
            calls++;
            return Promise.resolve(
              Response.json({ code, message }, { status: 404 }),
            );
          }),
          request,
          new AbortController().signal,
        ),
      StoredInsightChatRecoveryError,
      expected,
    );
    assertEquals(error.status, status);
    assertEquals(error.message, expected);
    assertEquals(calls, 1);
  }
});
Deno.test("stored resolver holds malformed success and transport failure without retry", async () => {
  for (
    const value of [null, [], {}, {
      context_version: 1,
      found: false,
      extra: true,
    }]
  ) {
    await assertRejects(
      () =>
        resolveStoredInsightChatTurn(
          client(() => Promise.resolve(Response.json(value))),
          request,
          new AbortController().signal,
        ),
      StoredInsightChatRecoveryError,
      "field_chat_context_unavailable",
    );
  }
  let calls = 0;
  await assertRejects(
    () =>
      resolveStoredInsightChatTurn(
        client(() => {
          calls++;
          throw new Error("private upstream detail");
        }),
        request,
        new AbortController().signal,
      ),
    StoredInsightChatRecoveryError,
    "field_chat_context_unavailable",
  );
  assertEquals(calls, 1);
});
Deno.test("stored resolver cancellation fences both dispatch and returned data", async () => {
  const before = new AbortController();
  before.abort();
  let calls = 0;
  await assertRejects(() =>
    resolveStoredInsightChatTurn(
      client(() => {
        calls++;
        return Promise.resolve(Response.json(response()));
      }),
      request,
      before.signal,
    ), DOMException);
  assertEquals(calls, 0);
  const after = new AbortController();
  await assertRejects(() =>
    resolveStoredInsightChatTurn(
      client(() => {
        after.abort();
        return Promise.resolve(Response.json(response()));
      }),
      request,
      after.signal,
    ), DOMException);
});

Deno.test("stored resolver never retries throttling or transient server failures", async () => {
  for (const status of [429, 503, 520]) {
    let calls = 0;
    await assertRejects(
      () =>
        resolveStoredInsightChatTurn(
          client(() => {
            calls++;
            return Promise.resolve(
              Response.json({ code: "unavailable", message: "upstream" }, {
                status,
                headers: { "Retry-After": "0" },
              }),
            );
          }),
          request,
          new AbortController().signal,
        ),
      StoredInsightChatRecoveryError,
      "field_chat_context_unavailable",
    );
    assertEquals(calls, 1);
  }
});

Deno.test("stored context preserves optional qualification and candidate nullness without upgrading old snapshots", () => {
  const base = response();
  for (
    const patch of [
      {},
      { metrics_qualified: true },
      { metrics_qualified: false },
      { candidates: null },
      {
        candidates: [{
          taxon_rank: "species",
          scientific_name: "Fixture species",
          confidence_score: 0.8,
        }],
      },
    ]
  ) {
    const scan = { ...base.context_snapshot.scan_context, ...patch };
    const parsed = parseStoredInsightChatResolution({
      ...base,
      context_snapshot: {
        ...base.context_snapshot,
        scan_context: scan,
      },
    }, request);
    assert(parsed.found);
    assertEquals(parsed.context.scan_context, scan);
  }
  for (const marker of [null, "true", 1, {}]) {
    assertThrows(() =>
      parseStoredInsightChatResolution({
        ...base,
        context_snapshot: {
          ...base.context_snapshot,
          scan_context: {
            ...base.context_snapshot.scan_context,
            metrics_qualified: marker,
          },
        },
      }, request)
    );
  }
});
