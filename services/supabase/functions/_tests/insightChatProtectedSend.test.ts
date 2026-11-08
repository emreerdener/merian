import {
  assert,
  assertEquals,
  assertStringIncludes,
  assertThrows,
} from "@std/assert";
import { createClient } from "@supabase/supabase-js";
import { deriveFieldChatAssistantMessageId } from "../_shared/fieldChat/response.ts";
import type { TierResolution } from "../_shared/entitlement.ts";
import { handleProtectedChatSend } from "../insight-chat/protectedSendHandler.ts";
import { parseProtectedChatReply } from "../insight-chat/protectedReply.ts";
import { refusalAnswer } from "../insight-chat/guards.ts";
import { parseInsightChatCompletion } from "../insight-chat/exactCompletion.ts";
import {
  parseProtectedChatSend,
  protectedChatSendPayload,
} from "../insight-chat/protectedSendContract.ts";
import { savedIdentityFixture } from "./primaryIdentityTestHelpers.ts";
const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const body = () => ({
  action: "send",
  context_version: 1,
  scan_id: id(2),
  conversation_id: id(4),
  client_message_id: id(3),
  message_text: "Question",
  displayed_ticket: {
    analysis_id: id(9),
    state_revision: 4,
    review_revision: 0,
  },
});
const prepared = () => ({
  context_version: 1,
  source_kind: "analysis_history_v1",
  displayed_ticket: body().displayed_ticket,
  scan_context: {
    ...savedIdentityFixture(),
    ai_identification_review: null,
    user_observation_context: null,
    extracted_visual_traits: [],
    colors: [],
    ecological_interactions: [],
    species_dictionary: null,
    confirmed_species: null,
  },
});
const context = () => ({
  ...prepared(),
  conversation_prefix: [{ role: "user", text: "Frozen earlier question" }],
});
const user = (question = "Question") => ({
  id: id(7),
  conversation_id: id(4),
  user_id: id(1),
  scan_id: id(2),
  client_message_id: id(3),
  role: "user",
  message_text: question,
});
async function receipt(local = false) {
  return {
    context_version: 1,
    completed: true,
    message: {
      id: await deriveFieldChatAssistantMessageId(id(4), id(3)),
      conversation_id: id(4),
      scan_id: id(2),
      role: "assistant",
      text: local ? refusalAnswer("foraging_or_ingestion") : "Synthetic answer",
      client_message_id: id(3),
      model: local ? null : "gemini-2.5-flash",
      is_refusal: local,
      refusal_reason: local ? "foraging_or_ingestion" : null,
      created_at: "2026-10-06T12:00:00Z",
    },
  };
}
const reply = () =>
  parseProtectedChatReply({
    answer: "Synthetic answer",
    model: "gemini-2.5-flash",
    is_refusal: false,
    refusal_reason: null,
    usage: null,
  });
async function scenario(kind: string) {
  const paths: string[] = [];
  let provider = 0;
  let tierCalls = 0;
  let tick = kind === "budget_pre" ? 20_000 : 0;
  const payload = body();
  const local = kind.startsWith("local");
  if (local) payload.message_text = "Can I eat this?";
  const done = await receipt(local);
  let recoveries = 0;
  let writes = 0;
  const db = createClient("https://example.invalid", "synthetic-key", {
    global: {
      fetch: (url, init) => {
        const name = String(url).split("/").at(-1)!;
        paths.push(name);
        const args = JSON.parse(String(init?.body));
        assertEquals(args.p_user_id, id(1));
        let data: unknown;
        if (name === "get_insight_chat_turn_context") {
          recoveries++;
          data = (kind.startsWith("recover") ||
              (["local_unknown_found", "admission_unknown_found"].includes(
                kind,
              ) && recoveries > 1))
            ? {
              context_version: 1,
              found: true,
              message: user(payload.message_text),
              context_snapshot: context(),
            }
            : { context_version: 1, found: false };
        } else if (name === "get_insight_chat_turn_completion") {
          data = kind === "recover_incomplete"
            ? { context_version: 1, completed: false }
            : done;
        } else if (
          name === "get_insight_chat_no_admission" ||
          name === "seal_unadmitted_insight_chat_request"
        ) {
          if (kind === "seal_read_unknown" || kind === "stale_unknown") {
            if (kind === "seal_read_unknown" || name.startsWith("seal_")) {
              return Promise.resolve(
                Response.json({ message: "unknown" }, { status: 503 }),
              );
            }
          }
          data =
            kind === "sealed" || (kind === "stale" && name.startsWith("seal_"))
              ? {
                status: "not_admitted",
                context_version: 1,
                scan_id: id(2),
                conversation_id: id(4),
                client_message_id: id(3),
                reason: "displayed_identification_changed",
              }
              : kind === "seal_read_held" ||
                  (kind === "stale_held" && name.startsWith("seal_"))
              ? { status: "held" }
              : { status: "fresh_candidate" };
        } else if (name === "prepare_insight_chat_send_context") {
          if (kind.startsWith("stale")) {
            return Promise.resolve(
              Response.json({
                code: "40001",
                message: "field_chat_context_conflict",
              }, { status: 409 }),
            );
          }
          data = kind === "ineligible"
            ? {
              ...prepared(),
              scan_context: {
                ...prepared().scan_context,
                primary_identification: null,
                identification_provenance: null,
                is_biological_subject: false,
              },
            }
            : prepared();
        } else if (name === "reserve_protected_insight_chat_quota") {
          if (kind === "quota_gate_closed") {
            return Promise.resolve(Response.json({
              code: "55000",
              message: "field_chat_execution_unavailable",
            }, { status: 400 }));
          }
          if (kind === "quota_unknown") {
            return Promise.resolve(
              Response.json({ message: "unknown" }, { status: 503 }),
            );
          }
          data = {
            status: "reserved",
            reservation_id: id(5),
            lease_token: id(6),
            lease_expires_at: "2026-10-06T15:00:00Z",
            model: "gemini-2.5-flash",
          };
        } else if (
          name === "reserve_protected_insight_chat_send_with_context"
        ) {
          if (kind === "budget") tick = 30_000;
          if (kind.startsWith("admission_unknown")) {
            return Promise.resolve(
              Response.json({ message: "unknown" }, { status: 503 }),
            );
          }
          data = [{
            conversation_id: id(4),
            message: user(),
            is_replay: kind === "admission_replay",
            sends_today: 1,
            context_snapshot: context(),
          }];
        } else if (name === "grant_protected_insight_chat_dispatch") {
          if (kind === "grant_late") tick = 31_000;
          if (kind === "grant_unknown") {
            return Promise.resolve(
              Response.json({ message: "unknown" }, { status: 503 }),
            );
          }
          data = kind === "grant_held"
            ? { status: "held" }
            : { status: "dispatch_granted", model: "gemini-2.5-flash" };
        } else if (name === "admit_insight_chat_local_refusal") {
          writes++;
          if (kind.startsWith("local_unknown")) {
            return Promise.resolve(
              Response.json({ message: "unknown" }, { status: 503 }),
            );
          }
          data = done;
        } else if (name === "complete_protected_insight_chat_reply") {
          writes++;
          if (kind === "completion_unknown") {
            return Promise.resolve(
              Response.json({ message: "unknown" }, { status: 503 }),
            );
          }
          data = done;
        } else if (name === "get_protected_insight_chat_reply") data = done;
        else throw new Error(`Unexpected boundary ${name}`);
        return Promise.resolve(Response.json(data));
      },
    },
  });
  const response = await handleProtectedChatSend(
    new Request("https://example.invalid/insight-chat", { method: "POST" }),
    db,
    id(1),
    payload,
    0,
    {
      now: () => tick,
      tier: () => {
        tierCalls++;
        return Promise.resolve(
          {
            effective_tier: kind === "free" ? "free" : "pro",
          } as TierResolution,
        );
      },
      ipHash: () => Promise.resolve("a".repeat(64)),
      provider: (system, prompt, model) => {
        assertStringIncludes(system, "Fixtureus");
        assertStringIncludes(prompt, "Frozen earlier question");
        assertEquals(model, "gemini-2.5-flash");
        return () => {
          provider++;
          if (kind === "provider_unknown") {
            throw new Error("private diagnostic");
          }
          return Promise.resolve(reply());
        };
      },
    },
  );
  return { response, paths, provider, tierCalls, writes };
}
Deno.test("protected fresh send uses saved prefix, one grant and one completion", async () => {
  const r = await scenario("fresh");
  assertEquals(r.response.status, 200);
  assertEquals(r.response.headers.get("cache-control"), "no-store");
  assertEquals(r.provider, 1);
  assertEquals(r.writes, 1);
  assertEquals(r.paths, [
    "get_insight_chat_turn_context",
    "get_insight_chat_no_admission",
    "prepare_insight_chat_send_context",
    "reserve_protected_insight_chat_quota",
    "reserve_protected_insight_chat_send_with_context",
    "grant_protected_insight_chat_dispatch",
    "complete_protected_insight_chat_reply",
  ]);
  const data = await r.response.json();
  assertEquals(Object.keys(data.data).sort(), [
    "completed",
    "context_version",
    "message",
  ]);
});
Deno.test("stored turns recover before entitlement and never dispatch", async () => {
  for (const kind of ["recover_complete", "recover_incomplete"]) {
    const r = await scenario(kind);
    assertEquals(r.response.status, kind === "recover_complete" ? 200 : 503);
    assertEquals(r.tierCalls, 0);
    assertEquals(r.provider, 0);
    assertEquals(r.paths, [
      "get_insight_chat_turn_context",
      "get_insight_chat_turn_completion",
    ]);
  }
});
Deno.test("eligibility and Pro deny before admission or quota", async () => {
  for (const kind of ["ineligible", "free"]) {
    const r = await scenario(kind);
    assertEquals(r.response.status, kind === "free" ? 402 : 400);
    assertEquals(r.provider, 0);
    assert(!r.paths.some((v) => v.startsWith("reserve_")));
  }
});
Deno.test("local safety admission and lost-response recovery consume no provider quota", async () => {
  for (const kind of ["local", "local_unknown_found", "local_unknown_absent"]) {
    const r = await scenario(kind);
    assertEquals(
      r.response.status,
      kind === "local_unknown_absent" ? 503 : 200,
    );
    assertEquals(r.writes, 1);
    assertEquals(r.provider, 0);
    assert(!r.paths.some((v) => v.includes("quota") || v.includes("dispatch")));
  }
});
Deno.test("replayed admission, low budget and uncertain grants cannot dispatch", async () => {
  for (
    const kind of [
      "admission_replay",
      "budget",
      "budget_pre",
      "quota_unknown",
      "admission_unknown_found",
      "admission_unknown_absent",
      "grant_unknown",
      "grant_held",
    ]
  ) {
    const r = await scenario(kind);
    assertEquals(r.provider, 0);
    assertEquals(
      r.response.status,
      ["admission_replay", "admission_unknown_found"].includes(kind)
        ? 200
        : 503,
    );
    if (kind === "budget") {
      assert(!r.paths.includes("grant_protected_insight_chat_dispatch"));
    }
  }
});
Deno.test("provider uncertainty never refunds and completion uncertainty reads once", async () => {
  for (const kind of ["provider_unknown", "completion_unknown"]) {
    const r = await scenario(kind);
    assertEquals(r.provider, 1);
    assertEquals(r.response.status, kind === "completion_unknown" ? 200 : 503);
    assert(
      !r.paths.some((v) => v.includes("finalize") || v.includes("refund")),
    );
    if (kind === "completion_unknown") {
      assertEquals(r.writes, 1);
      assertEquals(r.paths.at(-1), "get_protected_insight_chat_reply");
    }
  }
});
Deno.test("missing explicit ticket never reaches storage or legacy", async () => {
  let calls = 0;
  const db = createClient("https://example.invalid", "synthetic-key", {
    global: {
      fetch: () => {
        calls++;
        throw new Error("unexpected");
      },
    },
  });
  const { displayed_ticket: _, ...missing } = body();
  const r = await handleProtectedChatSend(
    new Request("https://example.invalid"),
    db,
    id(1),
    missing,
    0,
  );
  assertEquals(r.status, 400);
  assertEquals(calls, 0);
});

Deno.test("a delayed fresh grant invokes exactly once within remaining provider window", async () => {
  const result = await scenario("grant_late");
  assertEquals(result.provider, 1);
  assertEquals(result.writes, 1);
  assertEquals(result.response.status, 200);
});

Deno.test("protected receipt rejects impossible model and refusal combinations", async () => {
  const original = parseProtectedChatSend(id(1), body());
  for (
    const changes of [
      { model: "other-model" },
      { model: null },
      { refusal_reason: "unexpected" },
      { model: null, is_refusal: true, refusal_reason: "unknown-local-reason" },
    ]
  ) {
    const raw = await receipt();
    Object.assign(raw.message, changes);
    const parsed = await parseInsightChatCompletion(raw, original.turn, id(4));
    assert(parsed.completed);
    assertThrows(() => protectedChatSendPayload(parsed));
  }
  const local = await parseInsightChatCompletion(
    await receipt(true),
    original.turn,
    id(4),
  );
  assert(local.completed);
  assertEquals(protectedChatSendPayload(local).data.message.model, null);
});

Deno.test("sealed and newly proven stale requests return only an exact no-admission receipt", async () => {
  for (const kind of ["sealed", "stale"]) {
    const r = await scenario(kind);
    assertEquals(r.response.status, 200);
    assertEquals(r.tierCalls, 0);
    assertEquals(r.provider, 0);
    assertEquals(r.writes, 0);
    assertEquals(r.response.headers.get("cache-control"), "no-store");
    assertEquals(await r.response.json(), {
      data: {
        context_version: 1,
        outcome: "not_admitted",
        scan_id: id(2),
        conversation_id: id(4),
        client_message_id: id(3),
        reason: "displayed_identification_changed",
      },
    });
    assertEquals(r.paths, [
      "get_insight_chat_turn_context",
      "get_insight_chat_no_admission",
      ...(kind === "stale"
        ? [
          "prepare_insight_chat_send_context",
          "seal_unadmitted_insight_chat_request",
        ]
        : []),
    ]);
  }
});
Deno.test("held and uncertain seal reads or writes never create proof or call a provider", async () => {
  for (
    const kind of [
      "seal_read_held",
      "seal_read_unknown",
      "stale_held",
      "stale_unknown",
    ]
  ) {
    const r = await scenario(kind);
    assertEquals(r.response.status, 503);
    assertEquals(r.tierCalls, 0);
    assertEquals(r.provider, 0);
    assert(
      !r.paths.some((p) => p.includes("reserve_") || p.includes("dispatch")),
    );
    assert(r.paths.filter((p) => p.startsWith("seal_")).length <= 1);
  }
});

Deno.test("closed protected execution gate holds without provider, admission or legacy fallback", async () => {
  const r = await scenario("quota_gate_closed");
  assertEquals(r.response.status, 503);
  assertEquals(r.provider, 0);
  assertEquals(r.writes, 0);
  assertEquals(r.paths, [
    "get_insight_chat_turn_context",
    "get_insight_chat_no_admission",
    "prepare_insight_chat_send_context",
    "reserve_protected_insight_chat_quota",
  ]);
});
