import type { SupabaseClient, User } from "@supabase/supabase-js";
import {
  assert,
  assertEquals,
  assertRejects,
  assertStringIncludes,
} from "@std/assert";
import type { AIProviderQuotaLease } from "../_shared/aiQuota.ts";
import { AIQuotaError } from "../_shared/aiQuota.ts";
import type { TierResolution } from "../_shared/entitlement.ts";
import {
  FIELD_CHAT_DEPLOYMENT_CONTRACT_HEADER,
  FIELD_CHAT_DEPLOYMENT_CONTRACT_VERSION,
} from "../_shared/fieldChatReservation.ts";
import { PublicHttpError } from "../_shared/http.ts";
import {
  createSpeciesDictionaryChatHttpHandler,
  handleSpeciesDictionaryChat,
  type SpeciesDictionaryChatDependencies,
} from "./index.ts";
import type {
  ModelChatResult,
  SpeciesDictionaryChatContext,
  SpeciesDictionaryChatConversationRow,
  SpeciesDictionaryChatMessageRow,
} from "./types.ts";

const USER_ID = "550e8400-e29b-41d4-a716-446655440000";
const SPECIES_ID = "650e8400-e29b-41d4-a716-446655440000";
const CONVERSATION_ID = "750e8400-e29b-41d4-a716-446655440000";
const REQUEST_ID = "850e8400-e29b-41d4-a716-446655440000";
const USER_MESSAGE_ID = "950e8400-e29b-41d4-a716-446655440000";
const ASSISTANT_MESSAGE_ID = "a50e8400-e29b-41d4-a716-446655440000";
const CREATED_AT = "2026-08-24T12:00:00.000Z";

const supabaseAdmin = {} as SupabaseClient;
const authenticatedUser = { id: USER_ID, is_anonymous: false } as User;

const speciesContext: SpeciesDictionaryChatContext = {
  id: SPECIES_ID,
  scientificName: "Ardea alba",
  commonName: "Great Egret",
  alternativeCommonNames: ["Common Egret"],
  taxonomy: {
    kingdom: "Animalia",
    phylum: "Chordata",
    class: "Aves",
    order: "Pelecaniformes",
    family: "Ardeidae",
    genus: "Ardea",
  },
  overview: "A large white heron.",
  habitat: "Wetlands.",
  hazardType: null,
  conservationStatus: "Least Concern",
  groupTags: ["bird"],
  lookalikes: [],
};

const conversation: SpeciesDictionaryChatConversationRow = {
  id: CONVERSATION_ID,
  species_dictionary_id: SPECIES_ID,
  user_id: USER_ID,
  created_at: CREATED_AT,
  updated_at: CREATED_AT,
};

const proTier: TierResolution = {
  current_plan: "pro_paid",
  current_tier: "pro",
  is_paid: true,
  scans_remaining: 0,
  scans_available_to_start: 0,
  in_flight_count: 0,
  entitlement_version: 1,
  effective_tier: "pro",
  plan: "pro_paid",
  subscription_tier: "pro",
  trial_active: false,
  user_exists: true,
};

const freeTier: TierResolution = {
  ...proTier,
  current_plan: "free",
  current_tier: "free",
  is_paid: false,
  effective_tier: "free",
  plan: "free",
  subscription_tier: "free",
};

function request(
  action: string,
  extra: Record<string, unknown> = {},
): Request {
  return new Request("https://example.test/species-dictionary-chat", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ action, species_id: SPECIES_ID, ...extra }),
  });
}

function message(
  role: "user" | "assistant",
  options: {
    id?: string;
    text?: string;
    requestId?: string;
    refusalReason?: string | null;
  } = {},
): SpeciesDictionaryChatMessageRow {
  const requestId = options.requestId ?? REQUEST_ID;
  return {
    id: options.id ??
      (role === "user" ? USER_MESSAGE_ID : ASSISTANT_MESSAGE_ID),
    conversation_id: CONVERSATION_ID,
    species_dictionary_id: SPECIES_ID,
    user_id: USER_ID,
    role,
    message_text: options.text ??
      (role === "user" ? "Where does it live?" : "It favors wetlands."),
    client_message_id: role === "user" ? requestId : null,
    model: role === "assistant" ? "gemini-2.5-flash" : null,
    llm_prompt_tokens: null,
    llm_candidate_tokens: null,
    llm_thinking_tokens: null,
    llm_total_tokens: null,
    llm_cached_tokens: null,
    is_refusal: options.refusalReason != null,
    refusal_reason: options.refusalReason ?? null,
    safety_metadata: role === "assistant" ? { request_id: requestId } : null,
    created_at: CREATED_AT,
  };
}

function quotaLease(calls?: string[]): AIProviderQuotaLease {
  return {
    reservation: {
      id: "b50e8400-e29b-41d4-a716-446655440000",
      requestId: REQUEST_ID,
      leaseToken: "lease-token",
      leaseExpiresAt: "2026-08-24T12:02:00.000Z",
      attemptCount: 1,
      model: "gemini-2.5-flash",
      tier: proTier,
      policyVersion: 1,
      dailyLimit: 20,
      dailyRemaining: 16,
      originalAnalysisId: null,
      complimentaryClientScanId: null,
      flashFallbackUsed: false,
    },
    commit: () => {
      calls?.push("commit");
      return Promise.resolve();
    },
    refund: () => {
      calls?.push("refund");
      return Promise.resolve(true);
    },
    fail: () => {
      calls?.push("fail");
      return Promise.resolve(true);
    },
  };
}

function dependencies(
  overrides: SpeciesDictionaryChatDependencies = {},
): SpeciesDictionaryChatDependencies {
  return {
    fetchCanonicalSpeciesContext: () => Promise.resolve(speciesContext),
    resolveTierForUser: () => Promise.resolve(proTier),
    countAllFieldChatSendsToday: () => Promise.resolve(3),
    fetchConversation: () => Promise.resolve(conversation),
    deleteConversation: () => Promise.resolve(),
    fetchMessages: () => Promise.resolve([]),
    fetchAssistantMessage: () => Promise.resolve(null),
    upsertFeedback: () => Promise.resolve(),
    trackPostHogEvent: () => Promise.resolve(),
    waitForFieldChatRequestCompletion: () => Promise.resolve(null),
    reserveAIProviderCall: () => Promise.resolve(quotaLease()),
    recoverStaleFieldChatQuota: () => Promise.resolve(false),
    insertUserMessage: () => Promise.reject(new Error("unexpected admission")),
    generateAssistantReply: () =>
      Promise.resolve({
        answer: "It favors wetlands.",
        isRefusal: false,
        refusalReason: null,
        usage: null,
      }),
    insertAssistantMessage: () =>
      Promise.reject(new Error("unexpected assistant insert")),
    recordAIUsageBestEffort: () => {},
    ...overrides,
  };
}

async function withEdgeEnvironment<T>(operation: () => Promise<T>): Promise<T> {
  const previousUrl = Deno.env.get("SUPABASE_URL");
  const previousKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  Deno.env.set("SUPABASE_URL", "https://test-project.supabase.co");
  Deno.env.set(
    "SUPABASE_SERVICE_ROLE_KEY",
    [
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9",
      "eyJpc3MiOiJzdXBhYmFzZSIsInJvbGUiOiJzZXJ2aWNlX3JvbGUifQ",
      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    ].join("."),
  );

  try {
    return await operation();
  } finally {
    if (previousUrl === undefined) Deno.env.delete("SUPABASE_URL");
    else Deno.env.set("SUPABASE_URL", previousUrl);
    if (previousKey === undefined) Deno.env.delete("SUPABASE_SERVICE_ROLE_KEY");
    else Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", previousKey);
  }
}

Deno.test("HTTP wrapper authenticates before binding the Species Dictionary handler", async () => {
  const observed: string[] = [];
  const handler = createSpeciesDictionaryChatHttpHandler(
    dependencies({
      fetchConversation: (userId, speciesId) => {
        observed.push(`conversation:${userId}:${speciesId}`);
        return Promise.resolve(null);
      },
    }),
    {
      authenticate: (req) => {
        observed.push(`auth:${req.headers.get("Authorization")}`);
        return Promise.resolve({ user: authenticatedUser, response: null });
      },
    },
  );

  const response = await withEdgeEnvironment(() =>
    handler(
      new Request(
        "https://test-project.supabase.co/functions/v1/species-dictionary-chat",
        {
          method: "POST",
          headers: {
            "Authorization": "Bearer verified-user-token",
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ action: "load", species_id: SPECIES_ID }),
        },
      ),
    )
  );

  assertEquals(response.status, 200);
  assertEquals(response.headers.get("X-Merian-Handler"), "1");
  assertEquals(
    response.headers.get(FIELD_CHAT_DEPLOYMENT_CONTRACT_HEADER),
    FIELD_CHAT_DEPLOYMENT_CONTRACT_VERSION,
  );
  assertEquals(observed, [
    "auth:Bearer verified-user-token",
    `conversation:${USER_ID}:${SPECIES_ID}`,
  ]);
});

Deno.test("HTTP wrapper never reaches the route after authentication refusal", async () => {
  let contextCount = 0;
  const handler = createSpeciesDictionaryChatHttpHandler(
    dependencies({
      fetchCanonicalSpeciesContext: () => {
        contextCount += 1;
        return Promise.resolve(speciesContext);
      },
    }),
    {
      authenticate: () =>
        Promise.resolve({
          user: null,
          response: new Response(
            JSON.stringify({ code: "unauthorized", error: "Unauthorized" }),
            {
              status: 401,
              headers: { "Content-Type": "application/json" },
            },
          ),
        }),
    },
  );

  const response = await withEdgeEnvironment(() => handler(request("load")));
  assertEquals(response.status, 401);
  assertEquals(
    response.headers.get(FIELD_CHAT_DEPLOYMENT_CONTRACT_HEADER),
    FIELD_CHAT_DEPLOYMENT_CONTRACT_VERSION,
  );
  assertEquals(response.headers.get("X-Merian-Handler"), "1");
  assertEquals(contextCount, 0);
});

Deno.test("handler rejects unsupported, invalid, unavailable, and non-Pro requests", async () => {
  const unsupported = await handleSpeciesDictionaryChat(
    request("feature_feedback"),
    authenticatedUser,
    supabaseAdmin,
    dependencies(),
  );
  assertEquals(unsupported.status, 400);
  assertEquals((await unsupported.json()).code, "unsupported_action");

  const invalidError = await assertRejects(
    () =>
      handleSpeciesDictionaryChat(
        new Request("https://example.test/species-dictionary-chat", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ action: "load", species_id: "not-a-uuid" }),
        }),
        authenticatedUser,
        supabaseAdmin,
        dependencies(),
      ),
    PublicHttpError,
  );
  assertEquals(invalidError.status, 400);
  assertEquals(invalidError.code, "invalid_request");

  const unavailable = await handleSpeciesDictionaryChat(
    request("load"),
    authenticatedUser,
    supabaseAdmin,
    dependencies({
      fetchCanonicalSpeciesContext: () => Promise.resolve(null),
    }),
  );
  assertEquals(unavailable.status, 404);
  assertEquals((await unavailable.json()).code, "species_not_available");

  const nonPro = await handleSpeciesDictionaryChat(
    request("load"),
    authenticatedUser,
    supabaseAdmin,
    dependencies({
      resolveTierForUser: () => Promise.resolve(freeTier),
    }),
  );
  assertEquals(nonPro.status, 402);
  assertEquals((await nonPro.json()).code, "pro_required");
});

Deno.test("load and prompt actions return only the authenticated user's species thread", async () => {
  const seen: string[] = [];
  const existingMessages = [message("user"), message("assistant")];
  const deps = dependencies({
    fetchCanonicalSpeciesContext: (speciesId) => {
      seen.push(`context:${speciesId}`);
      return Promise.resolve(speciesContext);
    },
    resolveTierForUser: (userId) => {
      seen.push(`tier:${userId}`);
      return Promise.resolve(proTier);
    },
    countAllFieldChatSendsToday: (userId) => {
      seen.push(`usage:${userId}`);
      return Promise.resolve(3);
    },
    fetchConversation: (userId, speciesId) => {
      seen.push(`conversation:${userId}:${speciesId}`);
      return Promise.resolve(conversation);
    },
    fetchMessages: (conversationId) => {
      seen.push(`messages:${conversationId}`);
      return Promise.resolve(existingMessages);
    },
  });

  const loadResponse = await handleSpeciesDictionaryChat(
    request("load"),
    authenticatedUser,
    supabaseAdmin,
    deps,
  );
  assertEquals(loadResponse.status, 200);
  const loadPayload = await loadResponse.json();
  assertEquals(loadPayload.data.subject_id, SPECIES_ID);
  assertEquals(loadPayload.data.conversation_id, CONVERSATION_ID);
  assertEquals(loadPayload.data.messages.length, 2);
  assertEquals(loadPayload.data.limits.sends_remaining_today, 17);
  assert(seen.includes(`tier:${USER_ID}`));
  assert(seen.includes(`conversation:${USER_ID}:${SPECIES_ID}`));

  const promptResponse = await handleSpeciesDictionaryChat(
    request("suggest_prompts"),
    authenticatedUser,
    supabaseAdmin,
    deps,
  );
  assertEquals(promptResponse.status, 200);
  const promptPayload = await promptResponse.json();
  assertEquals(promptPayload.data.subject_id, SPECIES_ID);
  assert(promptPayload.data.prompts.length > 0);
});

Deno.test("delete and feedback bind every database action to the authenticated user", async () => {
  const calls: Record<string, unknown>[] = [];
  const assistant = message("assistant");
  const deps = dependencies({
    deleteConversation: (userId, speciesId) => {
      calls.push({ action: "delete", userId, speciesId });
      return Promise.resolve();
    },
    fetchAssistantMessage: (userId, speciesId, messageId) => {
      calls.push({ action: "fetch_feedback", userId, speciesId, messageId });
      return Promise.resolve(assistant);
    },
    upsertFeedback: (userId, ownedMessage, rating, note) => {
      calls.push({
        action: "save_feedback",
        userId,
        messageId: ownedMessage.id,
        rating,
        note,
      });
      return Promise.resolve();
    },
  });

  const deleteResponse = await handleSpeciesDictionaryChat(
    request("delete"),
    authenticatedUser,
    supabaseAdmin,
    deps,
  );
  assertEquals(deleteResponse.status, 200);
  assertEquals((await deleteResponse.json()).data.conversation_id, null);

  const feedbackResponse = await handleSpeciesDictionaryChat(
    request("feedback", {
      message_id: ASSISTANT_MESSAGE_ID,
      feedback_rating: "helpful",
      feedback_note: " Useful. ",
    }),
    authenticatedUser,
    supabaseAdmin,
    deps,
  );
  assertEquals(feedbackResponse.status, 200);
  assertEquals(calls, [
    { action: "delete", userId: USER_ID, speciesId: SPECIES_ID },
    {
      action: "fetch_feedback",
      userId: USER_ID,
      speciesId: SPECIES_ID,
      messageId: ASSISTANT_MESSAGE_ID,
    },
    {
      action: "save_feedback",
      userId: USER_ID,
      messageId: ASSISTANT_MESSAGE_ID,
      rating: "helpful",
      note: "Useful.",
    },
  ]);
});

Deno.test("feedback rejects a message outside the authenticated ownership projection", async () => {
  let saveCount = 0;
  const response = await handleSpeciesDictionaryChat(
    request("feedback", {
      message_id: ASSISTANT_MESSAGE_ID,
      feedback_rating: "wrong",
    }),
    authenticatedUser,
    supabaseAdmin,
    dependencies({
      fetchAssistantMessage: (userId, speciesId) => {
        assertEquals(userId, USER_ID);
        assertEquals(speciesId, SPECIES_ID);
        return Promise.resolve(null);
      },
      upsertFeedback: () => {
        saveCount += 1;
        return Promise.resolve();
      },
    }),
  );

  assertEquals(response.status, 404);
  assertEquals((await response.json()).code, "message_not_found");
  assertEquals(saveCount, 0);
});

Deno.test("completed sends replay exactly without another admission or provider call", async () => {
  let admissionCount = 0;
  let providerCount = 0;
  const completedMessages = [message("user"), message("assistant")];
  const response = await handleSpeciesDictionaryChat(
    request("send", {
      message_text: "Where does it live?",
      client_message_id: REQUEST_ID,
    }),
    authenticatedUser,
    supabaseAdmin,
    dependencies({
      fetchMessages: () => Promise.resolve(completedMessages),
      insertUserMessage: () => {
        admissionCount += 1;
        return Promise.reject(new Error("must not admit"));
      },
      reserveAIProviderCall: () => {
        providerCount += 1;
        return Promise.resolve(quotaLease());
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(
    response.headers.get("X-Merian-Idempotent-Replay"),
    "field-chat-message",
  );
  assertEquals(admissionCount, 0);
  assertEquals(providerCount, 0);
});

Deno.test("a reused request id with different text is rejected before provider use", async () => {
  let providerCount = 0;
  const response = await handleSpeciesDictionaryChat(
    request("send", {
      message_text: "What does it eat?",
      client_message_id: REQUEST_ID,
    }),
    authenticatedUser,
    supabaseAdmin,
    dependencies({
      fetchMessages: () => Promise.resolve([message("user")]),
      reserveAIProviderCall: () => {
        providerCount += 1;
        return Promise.resolve(quotaLease());
      },
    }),
  );

  assertEquals(response.status, 409);
  assertEquals(
    (await response.json()).code,
    "field_chat_idempotency_conflict",
  );
  assertEquals(providerCount, 0);
});

Deno.test("daily limit rejection never admits a row or reserves provider quota", async () => {
  let admissionCount = 0;
  let providerCount = 0;
  const response = await handleSpeciesDictionaryChat(
    request("send", {
      message_text: "Where does it live?",
      client_message_id: REQUEST_ID,
    }),
    authenticatedUser,
    supabaseAdmin,
    dependencies({
      countAllFieldChatSendsToday: () => Promise.resolve(20),
      fetchConversation: () => Promise.resolve(null),
      fetchMessages: () => Promise.resolve([]),
      insertUserMessage: () => {
        admissionCount += 1;
        return Promise.reject(new Error("must not admit"));
      },
      reserveAIProviderCall: () => {
        providerCount += 1;
        return Promise.resolve(quotaLease());
      },
    }),
  );

  assertEquals(response.status, 429);
  assertEquals((await response.json()).code, "daily_limit_reached");
  assertEquals(admissionCount, 0);
  assertEquals(providerCount, 0);
});

Deno.test("database cutover rejection refunds the unused lease before provider use", async () => {
  const order: string[] = [];
  let providerCount = 0;
  const responseError = await assertRejects(
    () =>
      handleSpeciesDictionaryChat(
        request("send", {
          message_text: "Where does it live?",
          client_message_id: REQUEST_ID,
        }),
        authenticatedUser,
        supabaseAdmin,
        dependencies({
          fetchConversation: () => Promise.resolve(null),
          fetchMessages: () => Promise.resolve([]),
          reserveAIProviderCall: () => {
            order.push("reserve");
            return Promise.resolve(quotaLease(order));
          },
          insertUserMessage: () =>
            Promise.reject(
              new PublicHttpError(
                503,
                "field_chat_admission_cutover_pending",
                "Field Chat is waiting for database activation.",
                60,
              ),
            ),
          generateAssistantReply: () => {
            providerCount += 1;
            return Promise.reject(new Error("must not call provider"));
          },
        }),
      ),
    PublicHttpError,
  );

  assertEquals(responseError.status, 503);
  assertEquals(responseError.code, "field_chat_admission_cutover_pending");
  assertEquals(order, ["reserve", "refund"]);
  assertEquals(providerCount, 0);
});

Deno.test("safety refusal is dictionary-specific and never reserves a provider call", async () => {
  let providerCount = 0;
  let usageOutcome = "";
  const storedMessages: SpeciesDictionaryChatMessageRow[] = [];
  const question = "Can I eat this?";
  const response = await handleSpeciesDictionaryChat(
    request("send", {
      message_text: question,
      client_message_id: REQUEST_ID,
    }),
    authenticatedUser,
    supabaseAdmin,
    dependencies({
      fetchMessages: () => Promise.resolve([...storedMessages]),
      reserveAIProviderCall: () => {
        providerCount += 1;
        return Promise.resolve(quotaLease());
      },
      insertUserMessage: () => {
        const userMessage = message("user", { text: question });
        storedMessages.push(userMessage);
        return Promise.resolve({
          conversationId: CONVERSATION_ID,
          message: userMessage,
          isReplay: false,
          sendsToday: 4,
        });
      },
      insertAssistantMessage: (
        _conversationId,
        _userId,
        _speciesId,
        _requestId,
        result,
      ) => {
        assertEquals(result.isRefusal, true);
        assertStringIncludes(result.answer, "Species Dictionary page");
        assertEquals(result.answer.includes("saved scan"), false);
        const assistant = message("assistant", {
          text: result.answer,
          refusalReason: result.refusalReason,
        });
        storedMessages.push(assistant);
        return Promise.resolve(assistant);
      },
      recordAIUsageBestEffort: (_admin, input) => {
        usageOutcome = input.outcome ?? "";
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(providerCount, 0);
  assertEquals(usageOutcome, "refusal");
  assertEquals((await response.json()).data.messages.length, 2);
});

Deno.test("successful sends commit quota before generation and persist both rows", async () => {
  const order: string[] = [];
  const storedMessages: SpeciesDictionaryChatMessageRow[] = [];
  const reply: ModelChatResult = {
    answer: "Great Egrets forage in shallow wetlands.",
    isRefusal: false,
    refusalReason: null,
    usage: null,
  };
  const response = await handleSpeciesDictionaryChat(
    request("send", {
      message_text: "Where does it forage?",
      client_message_id: REQUEST_ID,
    }),
    authenticatedUser,
    supabaseAdmin,
    dependencies({
      fetchMessages: () => Promise.resolve([...storedMessages]),
      reserveAIProviderCall: (_req, _admin, input) => {
        assertEquals(input.userId, USER_ID);
        assertEquals(input.requestId, REQUEST_ID);
        order.push("reserve");
        return Promise.resolve(quotaLease(order));
      },
      insertUserMessage: (
        conversationId,
        userId,
        speciesId,
        text,
        requestId,
      ) => {
        assertEquals(
          { conversationId, userId, speciesId, text, requestId },
          {
            conversationId: CONVERSATION_ID,
            userId: USER_ID,
            speciesId: SPECIES_ID,
            text: "Where does it forage?",
            requestId: REQUEST_ID,
          },
        );
        order.push("admit");
        const userMessage = message("user", { text });
        storedMessages.push(userMessage);
        return Promise.resolve({
          conversationId: CONVERSATION_ID,
          message: userMessage,
          isReplay: false,
          sendsToday: 4,
        });
      },
      generateAssistantReply: () => {
        order.push("generate");
        return Promise.resolve(reply);
      },
      insertAssistantMessage: (
        conversationId,
        userId,
        speciesId,
        requestId,
        result,
      ) => {
        assertEquals(
          { conversationId, userId, speciesId, requestId, result },
          {
            conversationId: CONVERSATION_ID,
            userId: USER_ID,
            speciesId: SPECIES_ID,
            requestId: REQUEST_ID,
            result: reply,
          },
        );
        order.push("save-assistant");
        const assistant = message("assistant", { text: result.answer });
        storedMessages.push(assistant);
        return Promise.resolve(assistant);
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(order, [
    "reserve",
    "admit",
    "commit",
    "generate",
    "save-assistant",
  ]);
  assertEquals((await response.json()).data.messages.length, 2);
});

Deno.test("completed quota without an answer performs exact stale recovery before retry", async () => {
  const order: string[] = [];
  const existingUser = message("user");
  const storedMessages = [existingUser];
  let reservationCount = 0;
  const response = await handleSpeciesDictionaryChat(
    request("send", {
      message_text: existingUser.message_text,
      client_message_id: REQUEST_ID,
    }),
    authenticatedUser,
    supabaseAdmin,
    dependencies({
      fetchMessages: () => Promise.resolve([...storedMessages]),
      reserveAIProviderCall: (_req, _admin, input) => {
        reservationCount += 1;
        order.push(`reserve-${reservationCount}`);
        assertEquals(input.requestId, REQUEST_ID);
        if (reservationCount === 1) {
          return Promise.reject(
            new AIQuotaError(
              409,
              "ai_request_already_completed",
              "Already completed.",
            ),
          );
        }
        return Promise.resolve(quotaLease(order));
      },
      waitForFieldChatRequestCompletion: () => {
        order.push("wait");
        return Promise.resolve(null);
      },
      recoverStaleFieldChatQuota: (_admin, input) => {
        order.push("recover");
        assertEquals(input, {
          userId: USER_ID,
          operation: "species_dictionary_chat_reply",
          requestId: REQUEST_ID,
          conversationId: CONVERSATION_ID,
          subjectId: SPECIES_ID,
        });
        return Promise.resolve(true);
      },
      insertUserMessage: () =>
        Promise.resolve({
          conversationId: CONVERSATION_ID,
          message: existingUser,
          isReplay: true,
          sendsToday: 4,
        }),
      generateAssistantReply: () =>
        Promise.resolve({
          answer: "It favors wetlands.",
          isRefusal: false,
          refusalReason: null,
          usage: null,
        }),
      insertAssistantMessage: (_a, _b, _c, _d, result) => {
        const assistant = message("assistant", { text: result.answer });
        storedMessages.push(assistant);
        order.push("save-assistant");
        return Promise.resolve(assistant);
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(order, [
    "reserve-1",
    "wait",
    "recover",
    "reserve-2",
    "commit",
    "save-assistant",
  ]);
  assertEquals(reservationCount, 2);
  assertEquals((await response.json()).data.messages.length, 2);
});
