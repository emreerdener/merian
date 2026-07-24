import { SupabaseClient } from "@supabase/supabase-js";
import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { createRevenueCatWebhookHandler } from "./handler.ts";
import { MAX_REVENUECAT_WEBHOOK_BYTES } from "./protocol.ts";
import { createRevenueCatSignature } from "./signature.ts";

const NOW_MS = 1_750_000_000_000;
const NOW_SECONDS = Math.floor(NOW_MS / 1000);
const AUTHORIZATION_SECRET = "authorization-secret-at-least-32-characters";
const SIGNING_SECRET = "signing-secret-at-least-32-characters";
const USER_ID = "550e8400-e29b-41d4-a716-446655440000";

function rawWebhook(overrides: Record<string, unknown> = {}): string {
  return JSON.stringify({
    api_version: "1.0",
    event: {
      id: "event-123",
      type: "RENEWAL",
      event_timestamp_ms: NOW_MS - 1_000,
      app_user_id: USER_ID,
      original_app_user_id: "$RCAnonymousID:original",
      aliases: [],
      product_id: "merian_pro_annual",
      ...overrides,
    },
  });
}

async function signedRequest(
  rawBody: string,
  timestampSeconds = NOW_SECONDS,
): Promise<Request> {
  return new Request("https://example.test/revenuecat-webhook", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${AUTHORIZATION_SECRET}`,
      "Content-Type": "application/json",
      "X-RevenueCat-Webhook-Signature": await createRevenueCatSignature(
        SIGNING_SECRET,
        timestampSeconds,
        rawBody,
      ),
    },
    body: rawBody,
  });
}

function customerInfoResponse(): Response {
  return new Response(
    JSON.stringify({
      request_date_ms: NOW_MS,
      subscriber: {
        entitlements: {
          pro: { expires_date: "2026-08-01T00:00:00.000Z" },
        },
      },
    }),
    { status: 200 },
  );
}

Deno.test("valid webhook reconciles CustomerInfo before one transactional RPC", async () => {
  const rpcCalls: Record<string, unknown>[] = [];
  let lookupCount = 0;
  let fetchCount = 0;
  const supabaseAdmin = {
    rpc: (
      name: string,
      args: Record<string, unknown>,
    ) => {
      if (name === "get_revenuecat_webhook_event_result") {
        lookupCount += 1;
        return Promise.resolve({ data: [], error: null });
      }
      rpcCalls.push(args);
      return Promise.resolve({
        data: [{
          outcome: "applied",
          subject_count: 1,
          applied_count: 1,
          stale_count: 0,
        }],
        error: null,
      });
    },
  } as unknown as SupabaseClient;
  const fakeFetch = (() => {
    fetchCount += 1;
    return Promise.resolve(customerInfoResponse());
  }) as typeof fetch;

  const handler = createRevenueCatWebhookHandler({
    supabaseAdmin,
    config: {
      authorizationSecret: AUTHORIZATION_SECRET,
      signingSecret: SIGNING_SECRET,
      apiKey: "sk_test_secret",
    },
    fetchImpl: fakeFetch,
    now: () => NOW_MS,
  });
  const response = await handler(await signedRequest(rawWebhook()));
  const payload = await response.json();

  assertEquals(response.status, 200);
  assertEquals(payload, {
    success: true,
    outcome: "applied",
    subject_count: 1,
    applied_count: 1,
    stale_count: 0,
  });
  assertEquals(lookupCount, 1);
  assertEquals(fetchCount, 1);
  assertEquals(rpcCalls.length, 1);
  const rpcArguments = rpcCalls[0];
  assertEquals(rpcArguments.p_event_id, "event-123");
  assertEquals(rpcArguments.p_event_timestamp_ms, NOW_MS - 1_000);
  assertEquals(rpcArguments.p_subjects, [{
    subject_kind: "customer",
    candidate_user_ids: [USER_ID],
    authoritative_snapshot_at_ms: NOW_MS,
    target_tier: "pro",
    target_expires_at: null,
  }]);
});

Deno.test("committed duplicate bypasses another CustomerInfo request", async () => {
  let fetchCount = 0;
  const supabaseAdmin = {
    rpc: () =>
      Promise.resolve({
        data: [{
          outcome: "duplicate",
          subject_count: 1,
          applied_count: 1,
          stale_count: 0,
        }],
        error: null,
      }),
  } as unknown as SupabaseClient;
  const handler = createRevenueCatWebhookHandler({
    supabaseAdmin,
    config: {
      authorizationSecret: AUTHORIZATION_SECRET,
      signingSecret: SIGNING_SECRET,
      apiKey: "sk_test_secret",
    },
    fetchImpl: (() => {
      fetchCount += 1;
      return Promise.resolve(customerInfoResponse());
    }) as typeof fetch,
    now: () => NOW_MS,
  });

  const response = await handler(await signedRequest(rawWebhook()));
  const payload = await response.json();

  assertEquals(response.status, 200);
  assertEquals(payload, {
    success: true,
    outcome: "duplicate",
    subject_count: 1,
    applied_count: 1,
    stale_count: 0,
  });
  assertEquals(fetchCount, 0);
});

Deno.test("expired signature is rejected before API or database work", async () => {
  let externalCalls = 0;
  const supabaseAdmin = {
    rpc: () => {
      externalCalls += 1;
      return Promise.resolve({ data: [], error: null });
    },
  } as unknown as SupabaseClient;
  const fakeFetch = (() => {
    externalCalls += 1;
    return Promise.resolve(customerInfoResponse());
  }) as typeof fetch;
  const handler = createRevenueCatWebhookHandler({
    supabaseAdmin,
    config: {
      authorizationSecret: AUTHORIZATION_SECRET,
      signingSecret: SIGNING_SECRET,
      apiKey: "sk_test_secret",
    },
    fetchImpl: fakeFetch,
    now: () => NOW_MS,
  });

  const response = await handler(
    await signedRequest(rawWebhook(), NOW_SECONDS - 301),
  );

  assertEquals(response.status, 401);
  assertEquals(externalCalls, 0);
});

Deno.test("invalid Authorization is rejected before body or HMAC work", async () => {
  let externalCalls = 0;
  const handler = createRevenueCatWebhookHandler({
    supabaseAdmin: {
      rpc: () => {
        externalCalls += 1;
        return Promise.resolve({ data: [], error: null });
      },
    } as unknown as SupabaseClient,
    config: {
      authorizationSecret: AUTHORIZATION_SECRET,
      signingSecret: SIGNING_SECRET,
      apiKey: "sk_test_secret",
    },
    fetchImpl: (() => {
      externalCalls += 1;
      return Promise.resolve(customerInfoResponse());
    }) as typeof fetch,
    now: () => NOW_MS,
  });
  const request = new Request("https://example.test/revenuecat-webhook", {
    method: "POST",
    headers: {
      Authorization: "Bearer wrong-secret",
      "X-RevenueCat-Webhook-Signature": "invalid",
    },
    body: rawWebhook(),
  });

  const response = await handler(request);

  assertEquals(response.status, 401);
  assertEquals(externalCalls, 0);
});

Deno.test("client SDK API key fails closed before request processing", async () => {
  let externalCalls = 0;
  const handler = createRevenueCatWebhookHandler({
    supabaseAdmin: {
      rpc: () => {
        externalCalls += 1;
        return Promise.resolve({ data: [], error: null });
      },
    } as unknown as SupabaseClient,
    config: {
      authorizationSecret: AUTHORIZATION_SECRET,
      signingSecret: SIGNING_SECRET,
      apiKey: "appl_public_client_key",
    },
    fetchImpl: (() => {
      externalCalls += 1;
      return Promise.resolve(customerInfoResponse());
    }) as typeof fetch,
    now: () => NOW_MS,
  });

  const response = await handler(await signedRequest(rawWebhook()));

  assertEquals(response.status, 503);
  assertEquals(externalCalls, 0);
});

Deno.test("future event timestamp cannot poison the ordering watermark", async () => {
  let externalCalls = 0;
  const supabaseAdmin = {
    rpc: () => {
      externalCalls += 1;
      return Promise.resolve({ data: [], error: null });
    },
  } as unknown as SupabaseClient;
  const handler = createRevenueCatWebhookHandler({
    supabaseAdmin,
    config: {
      authorizationSecret: AUTHORIZATION_SECRET,
      signingSecret: SIGNING_SECRET,
      apiKey: "sk_test_secret",
    },
    fetchImpl: (() => {
      externalCalls += 1;
      return Promise.resolve(customerInfoResponse());
    }) as typeof fetch,
    now: () => NOW_MS,
  });
  const rawBody = rawWebhook({
    event_timestamp_ms: NOW_MS + 5 * 60 * 1_000 + 1,
  });

  const response = await handler(await signedRequest(rawBody));

  assertEquals(response.status, 400);
  assertEquals(externalCalls, 0);
});

Deno.test("chunked oversized body is stopped before full allocation or HMAC work", async () => {
  let externalCalls = 0;
  const supabaseAdmin = {
    rpc: () => {
      externalCalls += 1;
      return Promise.resolve({ data: [], error: null });
    },
  } as unknown as SupabaseClient;
  const handler = createRevenueCatWebhookHandler({
    supabaseAdmin,
    config: {
      authorizationSecret: AUTHORIZATION_SECRET,
      signingSecret: SIGNING_SECRET,
      apiKey: "sk_test_secret",
    },
    fetchImpl: (() => {
      externalCalls += 1;
      return Promise.resolve(customerInfoResponse());
    }) as typeof fetch,
    now: () => NOW_MS,
  });
  const chunk = new Uint8Array(Math.floor(MAX_REVENUECAT_WEBHOOK_BYTES / 2));
  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(chunk);
      controller.enqueue(chunk);
      controller.enqueue(new Uint8Array([1]));
      controller.close();
    },
  });
  const request = new Request("https://example.test/revenuecat-webhook", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${AUTHORIZATION_SECRET}`,
      "Content-Type": "application/json",
      "X-RevenueCat-Webhook-Signature": "invalid",
    },
    body: stream,
  });

  const response = await handler(request);

  assertEquals(response.status, 413);
  assertEquals(externalCalls, 0);
});

Deno.test("authoritative lookup failure fails closed before the mutation RPC", async () => {
  const rpcNames: string[] = [];
  const supabaseAdmin = {
    rpc: (name: string) => {
      rpcNames.push(name);
      return Promise.resolve({ data: [], error: null });
    },
  } as unknown as SupabaseClient;
  const handler = createRevenueCatWebhookHandler({
    supabaseAdmin,
    config: {
      authorizationSecret: AUTHORIZATION_SECRET,
      signingSecret: SIGNING_SECRET,
      apiKey: "sk_test_secret",
    },
    fetchImpl: (() =>
      Promise.resolve(
        new Response("unavailable", {
          status: 503,
        }),
      )) as typeof fetch,
    now: () => NOW_MS,
  });

  const response = await handler(await signedRequest(rawWebhook()));

  assertEquals(response.status, 503);
  assertEquals(response.headers.get("Retry-After"), "30");
  assertEquals(rpcNames, ["get_revenuecat_webhook_event_result"]);
});

Deno.test("transient database failure returns retryable service unavailable", async () => {
  const supabaseAdmin = {
    rpc: () =>
      Promise.resolve({
        data: null,
        error: { message: "statement timeout", code: "57014" },
      }),
  } as unknown as SupabaseClient;
  const handler = createRevenueCatWebhookHandler({
    supabaseAdmin,
    config: {
      authorizationSecret: AUTHORIZATION_SECRET,
      signingSecret: SIGNING_SECRET,
      apiKey: "sk_test_secret",
    },
    fetchImpl: (() => Promise.resolve(customerInfoResponse())) as typeof fetch,
    now: () => NOW_MS,
  });

  const response = await handler(await signedRequest(rawWebhook()));

  assertEquals(response.status, 503);
  assertEquals(response.headers.get("Retry-After"), "30");
});

Deno.test("anonymous RevenueCat customer is durably ignored without a provider lookup", async () => {
  const rpcNames: string[] = [];
  let providerCalls = 0;
  const supabaseAdmin = {
    rpc: (name: string) => {
      rpcNames.push(name);
      if (name === "get_revenuecat_webhook_event_result") {
        return Promise.resolve({ data: [], error: null });
      }
      return Promise.resolve({
        data: [{
          outcome: "ignored",
          subject_count: 0,
          applied_count: 0,
          stale_count: 0,
        }],
        error: null,
      });
    },
  } as unknown as SupabaseClient;
  const fakeFetch = (() => {
    providerCalls += 1;
    return Promise.resolve(customerInfoResponse());
  }) as typeof fetch;
  const handler = createRevenueCatWebhookHandler({
    supabaseAdmin,
    config: {
      authorizationSecret: AUTHORIZATION_SECRET,
      signingSecret: SIGNING_SECRET,
      apiKey: "sk_test_secret",
    },
    fetchImpl: fakeFetch,
    now: () => NOW_MS,
  });
  const rawBody = rawWebhook({
    app_user_id: "$RCAnonymousID:current",
    original_app_user_id: "$RCAnonymousID:original",
    aliases: [],
  });

  const response = await handler(await signedRequest(rawBody));
  const payload = await response.json();

  assertEquals(response.status, 200);
  assertEquals(payload, {
    success: true,
    outcome: "ignored",
    subject_count: 0,
    applied_count: 0,
    stale_count: 0,
  });
  assertEquals(providerCalls, 0);
  assertEquals(rpcNames, [
    "get_revenuecat_webhook_event_result",
    "apply_revenuecat_customer_state",
  ]);
});

Deno.test("TRANSFER reconciles source and destination before one atomic RPC", async () => {
  const sourceUserId = "550e8400-e29b-41d4-a716-446655440010";
  const destinationUserId = "550e8400-e29b-41d4-a716-446655440011";
  const requestedCustomers: string[] = [];
  const mutationArguments: Record<string, unknown>[] = [];
  const supabaseAdmin = {
    rpc: (name: string, args: Record<string, unknown>) => {
      if (name === "get_revenuecat_webhook_event_result") {
        return Promise.resolve({ data: [], error: null });
      }
      mutationArguments.push(args);
      return Promise.resolve({
        data: [{
          outcome: "applied",
          subject_count: 2,
          applied_count: 2,
          stale_count: 0,
        }],
        error: null,
      });
    },
  } as unknown as SupabaseClient;
  const fakeFetch = ((
    input: string | URL | Request,
  ) => {
    const customer = decodeURIComponent(
      String(input).split("/subscribers/")[1] ?? "",
    );
    requestedCustomers.push(customer);
    const hasPro = customer === destinationUserId;
    return Promise.resolve(
      new Response(
        JSON.stringify({
          request_date_ms: NOW_MS,
          subscriber: {
            entitlements: hasPro
              ? { pro: { expires_date: "2026-08-01T00:00:00.000Z" } }
              : {},
          },
        }),
        { status: 200 },
      ),
    );
  }) as typeof fetch;
  const handler = createRevenueCatWebhookHandler({
    supabaseAdmin,
    config: {
      authorizationSecret: AUTHORIZATION_SECRET,
      signingSecret: SIGNING_SECRET,
      apiKey: "sk_test_secret",
    },
    fetchImpl: fakeFetch,
    now: () => NOW_MS,
  });
  const rawBody = rawWebhook({
    type: "TRANSFER",
    app_user_id: undefined,
    original_app_user_id: undefined,
    aliases: undefined,
    product_id: undefined,
    transferred_from: [sourceUserId],
    transferred_to: [destinationUserId],
  });

  const response = await handler(await signedRequest(rawBody));
  const payload = await response.json();

  assertEquals(response.status, 200);
  assertEquals(payload, {
    success: true,
    outcome: "applied",
    subject_count: 2,
    applied_count: 2,
    stale_count: 0,
  });
  assertEquals(requestedCustomers.sort(), [
    sourceUserId,
    destinationUserId,
  ]);
  assertEquals(mutationArguments.length, 1);
  assertEquals(mutationArguments[0].p_subjects, [
    {
      subject_kind: "transfer_source",
      candidate_user_ids: [sourceUserId],
      authoritative_snapshot_at_ms: NOW_MS,
      target_tier: "free",
      target_expires_at: null,
    },
    {
      subject_kind: "transfer_destination",
      candidate_user_ids: [destinationUserId],
      authoritative_snapshot_at_ms: NOW_MS,
      target_tier: "pro",
      target_expires_at: null,
    },
  ]);
});

Deno.test("TRANSFER provider failure prevents the multi-user mutation", async () => {
  const sourceUserId = "550e8400-e29b-41d4-a716-446655440010";
  const destinationUserId = "550e8400-e29b-41d4-a716-446655440011";
  const rpcNames: string[] = [];
  const supabaseAdmin = {
    rpc: (name: string) => {
      rpcNames.push(name);
      return Promise.resolve({ data: [], error: null });
    },
  } as unknown as SupabaseClient;
  const fakeFetch = ((
    input: string | URL | Request,
  ) => {
    const isSource = String(input).endsWith(sourceUserId);
    return Promise.resolve(
      isSource
        ? new Response("unavailable", { status: 503 })
        : customerInfoResponse(),
    );
  }) as typeof fetch;
  const handler = createRevenueCatWebhookHandler({
    supabaseAdmin,
    config: {
      authorizationSecret: AUTHORIZATION_SECRET,
      signingSecret: SIGNING_SECRET,
      apiKey: "sk_test_secret",
    },
    fetchImpl: fakeFetch,
    now: () => NOW_MS,
  });
  const rawBody = rawWebhook({
    type: "TRANSFER",
    app_user_id: undefined,
    original_app_user_id: undefined,
    aliases: undefined,
    product_id: undefined,
    transferred_from: [sourceUserId],
    transferred_to: [destinationUserId],
  });

  const response = await handler(await signedRequest(rawBody));

  assertEquals(response.status, 503);
  assertEquals(rpcNames, ["get_revenuecat_webhook_event_result"]);
});
