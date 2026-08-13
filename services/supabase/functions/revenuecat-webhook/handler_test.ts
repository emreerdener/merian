import { SupabaseClient } from "@supabase/supabase-js";
import { assertEquals } from "@std/assert";
import { SEVEN_DAY_PASS_PRODUCT_ID } from "../_shared/subscriptionPass.ts";
import { createRevenueCatWebhookHandler } from "./handler.ts";
import { MAX_REVENUECAT_WEBHOOK_BYTES } from "./protocol.ts";
import { createRevenueCatSignature } from "./signature.ts";

const NOW_MS = 1_750_000_000_000;
const NOW_SECONDS = Math.floor(NOW_MS / 1000);
const AUTHORIZATION_SECRET = "authorization-secret-at-least-32-characters";
const SIGNING_SECRET = "signing-secret-at-least-32-characters";
const USER_ID = "550e8400-e29b-41d4-a716-446655440000";
const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function resolvedLegacyIdentityRows(args: Record<string, unknown>) {
  const subjects = args.p_subjects as Array<{
    subject_kind: string;
    identifiers: string[];
  }>;
  return subjects.flatMap((subject, index) => {
    const identity = subject.identifiers.find((candidate) =>
      UUID_RE.test(candidate)
    );
    return identity
      ? [{
        subject_position: index + 1,
        subject_kind: subject.subject_kind,
        lookup_app_user_id: identity,
        identity_kind: "legacy_user",
        identity_id: identity.toLowerCase(),
        allow_non_subscription_pass_grant: null,
      }]
      : [];
  });
}

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

Deno.test("valid webhook reconciles CustomerInfo before one entitlement transaction", async () => {
  const rpcCalls: Record<string, unknown>[] = [];
  const scheduleCalls: Record<string, unknown>[] = [];
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
      if (name === "resolve_revenuecat_identity_subjects") {
        return Promise.resolve({
          data: resolvedLegacyIdentityRows(args),
          error: null,
        });
      }
      if (name === "schedule_revenuecat_identity_reconciliation") {
        scheduleCalls.push(args);
        return Promise.resolve({ data: 1, error: null });
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
  const infoLogs: unknown[] = [];
  const originalInfo = console.info;
  console.info = (...args: unknown[]) => infoLogs.push(args[0]);
  let response: Response;
  try {
    response = await handler(await signedRequest(rawWebhook()));
  } finally {
    console.info = originalInfo;
  }
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
  assertEquals(scheduleCalls, [{
    p_subjects: [{
      subject_kind: "customer",
      lookup_app_user_id: USER_ID,
      identity_kind: "legacy_user",
      identity_id: USER_ID,
    }],
  }]);
  const rpcArguments = rpcCalls[0];
  assertEquals(rpcArguments.p_event_id, "event-123");
  assertEquals(rpcArguments.p_event_timestamp_ms, NOW_MS - 1_000);
  assertEquals(rpcArguments.p_subjects, [{
    subject_kind: "customer",
    lookup_app_user_id: USER_ID,
    identity_kind: "legacy_user",
    identity_id: USER_ID,
    authoritative_snapshot_at_ms: NOW_MS,
    target_store_tier: "pro",
    target_store_expires_at: "2026-08-01T00:00:00.000Z",
    target_account_grant_tier: "free",
    target_account_grant_expires_at: null,
    allow_non_subscription_pass_grant: null,
  }]);
  const serializedLogs = infoLogs.map(String).join("\n");
  assertEquals(serializedLogs.includes(USER_ID), false);
  assertEquals(serializedLogs.includes("event-123"), false);
  assertEquals(serializedLogs.includes("$RCAnonymousID"), false);
});

Deno.test("committed duplicate bypasses another CustomerInfo request", async () => {
  let fetchCount = 0;
  const supabaseAdmin = {
    rpc: (name: string, args: Record<string, unknown>) => {
      if (name === "resolve_revenuecat_identity_subjects") {
        return Promise.resolve({
          data: resolvedLegacyIdentityRows(args),
          error: null,
        });
      }
      return Promise.resolve({
        data: name === "schedule_revenuecat_identity_reconciliation" ? 1 : [{
          outcome: "duplicate",
          subject_count: 1,
          applied_count: 1,
          stale_count: 0,
        }],
        error: null,
      });
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
      fetchCount += 1;
      return Promise.resolve(customerInfoResponse());
    }) as typeof fetch,
    now: () => NOW_MS,
  });

  const infoLogs: unknown[] = [];
  const originalInfo = console.info;
  console.info = (...args: unknown[]) => infoLogs.push(args[0]);
  let response: Response;
  try {
    response = await handler(await signedRequest(rawWebhook()));
  } finally {
    console.info = originalInfo;
  }
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
  const serializedLogs = infoLogs.map(String).join("\n");
  assertEquals(serializedLogs.includes(USER_ID), false);
  assertEquals(serializedLogs.includes("event-123"), false);
  assertEquals(serializedLogs.includes("$RCAnonymousID"), false);
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

Deno.test("stale CustomerInfo cannot overwrite a newer entitlement snapshot", async () => {
  let applyCalls = 0;
  const supabaseAdmin = {
    rpc: (name: string, args: Record<string, unknown>) => {
      if (name === "get_revenuecat_webhook_event_result") {
        return Promise.resolve({ data: [], error: null });
      }
      if (name === "resolve_revenuecat_identity_subjects") {
        return Promise.resolve({
          data: resolvedLegacyIdentityRows(args),
          error: null,
        });
      }
      applyCalls += 1;
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
        new Response(
          JSON.stringify({
            request_date_ms: NOW_MS - 15 * 60 * 1_000 - 1,
            subscriber: { entitlements: {} },
          }),
          { status: 200 },
        ),
      )) as typeof fetch,
    now: () => NOW_MS,
  });

  const response = await handler(await signedRequest(rawWebhook()));
  const payload = await response.json();

  assertEquals(response.status, 503);
  assertEquals(payload.code, "entitlement_lookup_failed");
  assertEquals(applyCalls, 0);
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
    rpc: (name: string, args: Record<string, unknown>) => {
      rpcNames.push(name);
      if (name === "resolve_revenuecat_identity_subjects") {
        return Promise.resolve({
          data: resolvedLegacyIdentityRows(args),
          error: null,
        });
      }
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
  assertEquals(rpcNames, [
    "get_revenuecat_webhook_event_result",
    "resolve_revenuecat_identity_subjects",
  ]);
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

Deno.test("stable identity ambiguity is a terminal customer conflict", async () => {
  const supabaseAdmin = {
    rpc: (name: string) =>
      Promise.resolve(
        name === "get_revenuecat_webhook_event_result"
          ? { data: [], error: null }
          : {
            data: null,
            error: {
              message: "revenuecat_identity_mapping_ambiguous",
              code: "P0001",
            },
          },
      ),
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

  assertEquals(response.status, 409);
  assertEquals((await response.json()).code, "ambiguous_customer_mapping");
});

Deno.test("anonymous RevenueCat customer is durably ignored without a provider lookup", async () => {
  const rpcNames: string[] = [];
  let providerCalls = 0;
  const supabaseAdmin = {
    rpc: (name: string, args: Record<string, unknown>) => {
      rpcNames.push(name);
      if (name === "get_revenuecat_webhook_event_result") {
        return Promise.resolve({ data: [], error: null });
      }
      if (name === "resolve_revenuecat_identity_subjects") {
        return Promise.resolve({
          data: resolvedLegacyIdentityRows(args),
          error: null,
        });
      }
      if (name === "schedule_revenuecat_identity_reconciliation") {
        return Promise.resolve({ data: 0, error: null });
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
    "resolve_revenuecat_identity_subjects",
    "apply_revenuecat_identity_state",
    "schedule_revenuecat_identity_reconciliation",
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
      if (name === "resolve_revenuecat_identity_subjects") {
        return Promise.resolve({
          data: resolvedLegacyIdentityRows(args),
          error: null,
        });
      }
      if (name === "schedule_revenuecat_identity_reconciliation") {
        return Promise.resolve({ data: 2, error: null });
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
      lookup_app_user_id: sourceUserId,
      identity_kind: "legacy_user",
      identity_id: sourceUserId,
      authoritative_snapshot_at_ms: NOW_MS,
      target_store_tier: "free",
      target_store_expires_at: null,
      target_account_grant_tier: "free",
      target_account_grant_expires_at: null,
      allow_non_subscription_pass_grant: null,
    },
    {
      subject_kind: "transfer_destination",
      lookup_app_user_id: destinationUserId,
      identity_kind: "legacy_user",
      identity_id: destinationUserId,
      authoritative_snapshot_at_ms: NOW_MS,
      target_store_tier: "pro",
      target_store_expires_at: "2026-08-01T00:00:00.000Z",
      target_account_grant_tier: "free",
      target_account_grant_expires_at: null,
      allow_non_subscription_pass_grant: null,
    },
  ]);
});

Deno.test("TRANSFER provider failure prevents the multi-user mutation", async () => {
  const sourceUserId = "550e8400-e29b-41d4-a716-446655440010";
  const destinationUserId = "550e8400-e29b-41d4-a716-446655440011";
  const rpcNames: string[] = [];
  const supabaseAdmin = {
    rpc: (name: string, args: Record<string, unknown>) => {
      rpcNames.push(name);
      if (name === "resolve_revenuecat_identity_subjects") {
        return Promise.resolve({
          data: resolvedLegacyIdentityRows(args),
          error: null,
        });
      }
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
  assertEquals(rpcNames, [
    "get_revenuecat_webhook_event_result",
    "resolve_revenuecat_identity_subjects",
  ]);
});

Deno.test("stable TRANSFER inherits detached-pass policy only from its stable source", async () => {
  const sourcePrincipalId = "650e8400-e29b-41d4-a716-446655440010";
  const destinationPrincipalId = "650e8400-e29b-41d4-a716-446655440011";
  const sourceAppUserId = "MERIAN_PP_SOURCE";
  const destinationAppUserId = "MERIAN_PP_DESTINATION";
  const purchaseAtMs = NOW_MS - 24 * 60 * 60 * 1_000;
  const expiresAt = new Date(
    purchaseAtMs + 7 * 24 * 60 * 60 * 1_000,
  ).toISOString();
  const mutations: Record<string, unknown>[] = [];
  const supabaseAdmin = {
    rpc: (name: string) => {
      if (name === "get_revenuecat_webhook_event_result") {
        return Promise.resolve({ data: [], error: null });
      }
      if (name === "resolve_revenuecat_identity_subjects") {
        return Promise.resolve({
          data: [
            {
              subject_position: 1,
              subject_kind: "transfer_source",
              lookup_app_user_id: sourceAppUserId,
              identity_kind: "purchase_principal",
              identity_id: sourcePrincipalId,
              allow_non_subscription_pass_grant: true,
            },
            {
              subject_position: 2,
              subject_kind: "transfer_destination",
              lookup_app_user_id: destinationAppUserId,
              identity_kind: "purchase_principal",
              identity_id: destinationPrincipalId,
              allow_non_subscription_pass_grant: false,
            },
          ],
          error: null,
        });
      }
      if (name === "schedule_revenuecat_identity_reconciliation") {
        return Promise.resolve({ data: 2, error: null });
      }
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
  const fakeFetch = ((input: string | URL | Request) => {
    const isDestination = String(input).endsWith(destinationAppUserId);
    return Promise.resolve(
      new Response(JSON.stringify({
        request_date_ms: NOW_MS,
        subscriber: {
          entitlements: {},
          subscriptions: {},
          non_subscriptions: isDestination
            ? {
              [SEVEN_DAY_PASS_PRODUCT_ID]: [{
                id: "transferred-pass",
                purchase_date: new Date(purchaseAtMs).toISOString(),
                store: "app_store",
              }],
            }
            : {},
        },
      })),
    );
  }) as typeof fetch;
  const handler = createRevenueCatWebhookHandler({
    supabaseAdmin: {
      rpc: (name: string, args: Record<string, unknown>) => {
        if (name === "apply_revenuecat_identity_state") {
          mutations.push(args);
        }
        return supabaseAdmin.rpc(name);
      },
    } as unknown as SupabaseClient,
    config: {
      authorizationSecret: AUTHORIZATION_SECRET,
      signingSecret: SIGNING_SECRET,
      apiKey: "sk_test_secret",
    },
    fetchImpl: fakeFetch,
    now: () => NOW_MS,
  });
  const response = await handler(
    await signedRequest(rawWebhook({
      id: "stable-transfer-pass",
      type: "TRANSFER",
      app_user_id: undefined,
      original_app_user_id: undefined,
      aliases: undefined,
      product_id: undefined,
      transferred_from: [sourceAppUserId],
      transferred_to: [destinationAppUserId],
    })),
  );

  assertEquals(response.status, 200);
  assertEquals(mutations.length, 1);
  assertEquals(mutations[0].p_subjects, [
    {
      subject_kind: "transfer_source",
      lookup_app_user_id: sourceAppUserId,
      identity_kind: "purchase_principal",
      identity_id: sourcePrincipalId,
      authoritative_snapshot_at_ms: NOW_MS,
      target_store_tier: "free",
      target_store_expires_at: null,
      target_account_grant_tier: "free",
      target_account_grant_expires_at: null,
      allow_non_subscription_pass_grant: false,
    },
    {
      subject_kind: "transfer_destination",
      lookup_app_user_id: destinationAppUserId,
      identity_kind: "purchase_principal",
      identity_id: destinationPrincipalId,
      authoritative_snapshot_at_ms: NOW_MS,
      target_store_tier: "pro",
      target_store_expires_at: expiresAt,
      target_account_grant_tier: "free",
      target_account_grant_expires_at: null,
      allow_non_subscription_pass_grant: true,
    },
  ]);
});

Deno.test("stable TRANSFER destination history cannot enable a pass when the source policy is false", async () => {
  const sourcePrincipalId = "650e8400-e29b-41d4-a716-446655440020";
  const destinationPrincipalId = "650e8400-e29b-41d4-a716-446655440021";
  const sourceAppUserId = "MERIAN_PP_SOURCE_FALSE";
  const destinationAppUserId = "MERIAN_PP_DESTINATION_FALSE";
  const mutations: Record<string, unknown>[] = [];
  const supabaseAdmin = {
    rpc: (name: string, args: Record<string, unknown>) => {
      if (name === "get_revenuecat_webhook_event_result") {
        return Promise.resolve({ data: [], error: null });
      }
      if (name === "resolve_revenuecat_identity_subjects") {
        return Promise.resolve({
          data: [
            {
              subject_position: 1,
              subject_kind: "transfer_source",
              lookup_app_user_id: sourceAppUserId,
              identity_kind: "purchase_principal",
              identity_id: sourcePrincipalId,
              allow_non_subscription_pass_grant: false,
            },
            {
              subject_position: 2,
              subject_kind: "transfer_destination",
              lookup_app_user_id: destinationAppUserId,
              identity_kind: "purchase_principal",
              identity_id: destinationPrincipalId,
              allow_non_subscription_pass_grant: false,
            },
          ],
          error: null,
        });
      }
      if (name === "schedule_revenuecat_identity_reconciliation") {
        return Promise.resolve({ data: 2, error: null });
      }
      mutations.push(args);
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
  const fakeFetch = ((input: string | URL | Request) => {
    const isDestination = String(input).endsWith(destinationAppUserId);
    return Promise.resolve(
      new Response(JSON.stringify({
        request_date_ms: NOW_MS,
        subscriber: {
          entitlements: {},
          subscriptions: {},
          non_subscriptions: isDestination
            ? {
              [SEVEN_DAY_PASS_PRODUCT_ID]: [{
                id: "historical-refunded-pass",
                purchase_date: new Date(
                  NOW_MS - 24 * 60 * 60 * 1_000,
                ).toISOString(),
                store: "app_store",
              }],
            }
            : {},
        },
      })),
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
  const response = await handler(
    await signedRequest(rawWebhook({
      id: "stable-transfer-no-pass-authority",
      type: "TRANSFER",
      app_user_id: undefined,
      original_app_user_id: undefined,
      aliases: undefined,
      product_id: undefined,
      transferred_from: [sourceAppUserId],
      transferred_to: [destinationAppUserId],
    })),
  );

  assertEquals(response.status, 200);
  assertEquals(mutations.length, 1);
  assertEquals(
    (mutations[0].p_subjects as Array<Record<string, unknown>>)[1],
    {
      subject_kind: "transfer_destination",
      lookup_app_user_id: destinationAppUserId,
      identity_kind: "purchase_principal",
      identity_id: destinationPrincipalId,
      authoritative_snapshot_at_ms: NOW_MS,
      target_store_tier: "free",
      target_store_expires_at: null,
      target_account_grant_tier: "free",
      target_account_grant_expires_at: null,
      allow_non_subscription_pass_grant: null,
    },
  );
});

Deno.test("stable TRANSFER retries while an active source pass is missing at the destination", async () => {
  const sourcePrincipalId = "650e8400-e29b-41d4-a716-446655440030";
  const destinationPrincipalId = "650e8400-e29b-41d4-a716-446655440031";
  const sourceAppUserId = "MERIAN_PP_SOURCE_PENDING";
  const destinationAppUserId = "MERIAN_PP_DESTINATION_PENDING";
  const rpcNames: string[] = [];
  const supabaseAdmin = {
    rpc: (name: string) => {
      rpcNames.push(name);
      if (name === "get_revenuecat_webhook_event_result") {
        return Promise.resolve({ data: [], error: null });
      }
      if (name === "resolve_revenuecat_identity_subjects") {
        return Promise.resolve({
          data: [
            {
              subject_position: 1,
              subject_kind: "transfer_source",
              lookup_app_user_id: sourceAppUserId,
              identity_kind: "purchase_principal",
              identity_id: sourcePrincipalId,
              allow_non_subscription_pass_grant: true,
            },
            {
              subject_position: 2,
              subject_kind: "transfer_destination",
              lookup_app_user_id: destinationAppUserId,
              identity_kind: "purchase_principal",
              identity_id: destinationPrincipalId,
              allow_non_subscription_pass_grant: false,
            },
          ],
          error: null,
        });
      }
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
    fetchImpl: ((input: string | URL | Request) => {
      const isSource = String(input).endsWith(sourceAppUserId);
      return Promise.resolve(
        new Response(JSON.stringify({
          request_date_ms: NOW_MS,
          subscriber: {
            entitlements: {},
            subscriptions: {},
            non_subscriptions: isSource
              ? {
                [SEVEN_DAY_PASS_PRODUCT_ID]: [{
                  id: "source-pass-awaiting-transfer",
                  purchase_date: new Date(
                    NOW_MS - 24 * 60 * 60 * 1_000,
                  ).toISOString(),
                  store: "app_store",
                }],
              }
              : {},
          },
        })),
      );
    }) as typeof fetch,
    now: () => NOW_MS,
  });
  const response = await handler(
    await signedRequest(rawWebhook({
      id: "stable-transfer-provider-lag",
      type: "TRANSFER",
      app_user_id: undefined,
      original_app_user_id: undefined,
      aliases: undefined,
      product_id: undefined,
      transferred_from: [sourceAppUserId],
      transferred_to: [destinationAppUserId],
    })),
  );

  assertEquals(response.status, 503);
  assertEquals(rpcNames, [
    "get_revenuecat_webhook_event_result",
    "resolve_revenuecat_identity_subjects",
  ]);
});

Deno.test("stable TRANSFER with no active pass does not inherit stale pass policy", async () => {
  const sourcePrincipalId = "650e8400-e29b-41d4-a716-446655440040";
  const destinationPrincipalId = "650e8400-e29b-41d4-a716-446655440041";
  const sourceAppUserId = "MERIAN_PP_SOURCE_EXPIRED";
  const destinationAppUserId = "MERIAN_PP_DESTINATION_EXPIRED";
  const mutations: Record<string, unknown>[] = [];
  const supabaseAdmin = {
    rpc: (name: string, args: Record<string, unknown>) => {
      if (name === "get_revenuecat_webhook_event_result") {
        return Promise.resolve({ data: [], error: null });
      }
      if (name === "resolve_revenuecat_identity_subjects") {
        return Promise.resolve({
          data: [
            {
              subject_position: 1,
              subject_kind: "transfer_source",
              lookup_app_user_id: sourceAppUserId,
              identity_kind: "purchase_principal",
              identity_id: sourcePrincipalId,
              allow_non_subscription_pass_grant: true,
            },
            {
              subject_position: 2,
              subject_kind: "transfer_destination",
              lookup_app_user_id: destinationAppUserId,
              identity_kind: "purchase_principal",
              identity_id: destinationPrincipalId,
              allow_non_subscription_pass_grant: false,
            },
          ],
          error: null,
        });
      }
      if (name === "schedule_revenuecat_identity_reconciliation") {
        return Promise.resolve({ data: 2, error: null });
      }
      mutations.push(args);
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
  const handler = createRevenueCatWebhookHandler({
    supabaseAdmin,
    config: {
      authorizationSecret: AUTHORIZATION_SECRET,
      signingSecret: SIGNING_SECRET,
      apiKey: "sk_test_secret",
    },
    fetchImpl: (() =>
      Promise.resolve(
        new Response(JSON.stringify({
          request_date_ms: NOW_MS,
          subscriber: {
            entitlements: {},
            subscriptions: {},
            non_subscriptions: {},
          },
        })),
      )) as typeof fetch,
    now: () => NOW_MS,
  });
  const response = await handler(
    await signedRequest(rawWebhook({
      id: "stable-transfer-expired-pass-policy",
      type: "TRANSFER",
      app_user_id: undefined,
      original_app_user_id: undefined,
      aliases: undefined,
      product_id: undefined,
      transferred_from: [sourceAppUserId],
      transferred_to: [destinationAppUserId],
    })),
  );

  assertEquals(response.status, 200);
  assertEquals(mutations.length, 1);
  assertEquals(
    (mutations[0].p_subjects as Array<Record<string, unknown>>)[1],
    {
      subject_kind: "transfer_destination",
      lookup_app_user_id: destinationAppUserId,
      identity_kind: "purchase_principal",
      identity_id: destinationPrincipalId,
      authoritative_snapshot_at_ms: NOW_MS,
      target_store_tier: "free",
      target_store_expires_at: null,
      target_account_grant_tier: "free",
      target_account_grant_expires_at: null,
      allow_non_subscription_pass_grant: null,
    },
  );
});

Deno.test("stable pass revocation is durable and unrelated events cannot resurrect history", async () => {
  const principalId = "650e8400-e29b-41d4-a716-446655440000";
  const appUserId = "MERIAN_PP_00112233445566778899AABBCCDDEEFF";
  const purchaseDate = new Date(NOW_MS - 24 * 60 * 60 * 1_000).toISOString();
  const scenarios = [
    {
      event: {
        id: "event-pass-refund",
        type: "REFUND",
        product_id: SEVEN_DAY_PASS_PRODUCT_ID,
        transaction_id: "pass-transaction",
      },
      storedPolicy: true,
      expectedPolicyUpdate: false,
    },
    {
      event: {
        id: "event-unrelated-renewal",
        type: "RENEWAL",
        product_id: "merian_pro_annual",
        transaction_id: undefined,
      },
      storedPolicy: false,
      expectedPolicyUpdate: null,
    },
  ];

  for (const scenario of scenarios) {
    const mutations: Record<string, unknown>[] = [];
    const supabaseAdmin = {
      rpc: (name: string, args: Record<string, unknown>) => {
        if (name === "get_revenuecat_webhook_event_result") {
          return Promise.resolve({ data: [], error: null });
        }
        if (name === "resolve_revenuecat_identity_subjects") {
          return Promise.resolve({
            data: [{
              subject_position: 1,
              subject_kind: "customer",
              lookup_app_user_id: appUserId,
              identity_kind: "purchase_principal",
              identity_id: principalId,
              allow_non_subscription_pass_grant: scenario.storedPolicy,
            }],
            error: null,
          });
        }
        if (name === "schedule_revenuecat_identity_reconciliation") {
          return Promise.resolve({ data: 1, error: null });
        }
        mutations.push(args);
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
    const handler = createRevenueCatWebhookHandler({
      supabaseAdmin,
      config: {
        authorizationSecret: AUTHORIZATION_SECRET,
        signingSecret: SIGNING_SECRET,
        apiKey: "sk_test_secret",
      },
      fetchImpl: (() =>
        Promise.resolve(
          new Response(JSON.stringify({
            request_date_ms: NOW_MS,
            subscriber: {
              entitlements: {},
              subscriptions: {},
              non_subscriptions: {
                [SEVEN_DAY_PASS_PRODUCT_ID]: [{
                  id: "pass-transaction",
                  purchase_date: purchaseDate,
                  store: "app_store",
                }],
              },
            },
          })),
        )) as typeof fetch,
      now: () => NOW_MS,
    });

    const response = await handler(
      await signedRequest(rawWebhook({
        ...scenario.event,
        app_user_id: appUserId,
        original_app_user_id: appUserId,
        aliases: [],
      })),
    );

    assertEquals(response.status, 200);
    assertEquals(mutations.length, 1);
    assertEquals(
      (mutations[0].p_subjects as Array<Record<string, unknown>>)[0],
      {
        subject_kind: "customer",
        lookup_app_user_id: appUserId,
        identity_kind: "purchase_principal",
        identity_id: principalId,
        authoritative_snapshot_at_ms: NOW_MS,
        target_store_tier: "free",
        target_store_expires_at: null,
        target_account_grant_tier: "free",
        target_account_grant_expires_at: null,
        allow_non_subscription_pass_grant: scenario.expectedPolicyUpdate,
      },
    );
  }
});
