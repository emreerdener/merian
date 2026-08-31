import { assertEquals, assertRejects, assertThrows } from "@std/assert";
import {
  authorizeServiceRoleRequest,
  ServerApiKeyConfigurationError,
  serviceRoleRequestHeaders,
} from "./serviceRoleAuth.ts";
import {
  createServiceRoleClient,
  createServiceRoleClientWithOptions,
  createServiceRoleFetchTransport,
  invokeServiceRoleJson,
  ServiceRoleFunctionInvocationError,
} from "./serviceRoleClient.ts";

const CURRENT_SECRET_KEY = [
  "sb",
  "secret",
  "worker",
  "a".repeat(20),
].join("_");
const STALE_SYNCHRONIZED_SECRET_KEY = [
  "sb",
  "secret",
  "stale-synchronized",
  "a".repeat(20),
].join("_");
const LEGACY_SERVICE_ROLE_KEY = [
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9",
  "eyJpc3MiOiJzdXBhYmFzZSIsInJvbGUiOiJzZXJ2aWNlX3JvbGUifQ",
  "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
].join(".");
const INVALID_SECRET_KEY = `${
  ["sb", "secret", "invalid", "a".repeat(20)].join("_")
}!`;

async function databaseRequestHeaders(
  serverApiKey: string,
): Promise<Headers> {
  let requestHeaders = new Headers();
  const client = createServiceRoleClient(
    "https://project.supabase.co",
    serverApiKey,
    (_input, init) => {
      const initHeaders = init && "headers" in init
        ? init.headers as HeadersInit
        : undefined;
      const sourceHeaders = initHeaders ??
        (_input instanceof Request ? _input.headers : undefined);
      requestHeaders = new Headers(sourceHeaders);
      return Promise.resolve(
        new Response("[]", {
          status: 200,
          headers: { "Content-Type": "application/json" },
        }),
      );
    },
  );

  const { error } = await client.from("taxonomy_import_runs").select("id")
    .limit(1);
  assertEquals(error, null);
  return requestHeaders;
}

async function storageRequestHeaders(
  serverApiKey: string,
): Promise<Headers> {
  let requestHeaders = new Headers();
  const client = createServiceRoleClient(
    "https://project.supabase.co",
    serverApiKey,
    (_input, init) => {
      const initHeaders = init && "headers" in init
        ? init.headers as HeadersInit
        : undefined;
      const sourceHeaders = initHeaders ??
        (_input instanceof Request ? _input.headers : undefined);
      requestHeaders = new Headers(sourceHeaders);
      return Promise.resolve(
        new Response("[]", {
          status: 200,
          headers: { "Content-Type": "application/json" },
        }),
      );
    },
  );

  const { error } = await client.storage.from("private").list();
  assertEquals(error, null);
  return requestHeaders;
}

async function functionRequestHeaders(
  serverApiKey: string,
): Promise<Headers> {
  let requestHeaders = new Headers();
  const client = createServiceRoleClient(
    "https://project.supabase.co",
    serverApiKey,
    (_input, init) => {
      const initHeaders = init && "headers" in init
        ? init.headers as HeadersInit
        : undefined;
      const sourceHeaders = initHeaders ??
        (_input instanceof Request ? _input.headers : undefined);
      requestHeaders = new Headers(sourceHeaders);
      return Promise.resolve(
        new Response("{}", {
          status: 200,
          headers: { "Content-Type": "application/json" },
        }),
      );
    },
  );

  const { error } = await client.functions.invoke("internal-worker", {
    body: {},
  });
  assertEquals(error, null);
  return requestHeaders;
}

async function authAdminRequestHeaders(
  serverApiKey: string,
): Promise<Headers> {
  let requestHeaders = new Headers();
  const client = createServiceRoleClient(
    "https://project.supabase.co",
    serverApiKey,
    (_input, init) => {
      const initHeaders = init && "headers" in init
        ? init.headers as HeadersInit
        : undefined;
      const sourceHeaders = initHeaders ??
        (_input instanceof Request ? _input.headers : undefined);
      requestHeaders = new Headers(sourceHeaders);
      return Promise.resolve(
        new Response(JSON.stringify({ users: [], aud: "authenticated" }), {
          status: 200,
          headers: { "Content-Type": "application/json" },
        }),
      );
    },
  );

  const { error } = await client.auth.admin.listUsers();
  assertEquals(error, null);
  return requestHeaders;
}

Deno.test("serviceRoleRequestHeaders uses apikey-only opaque transport", () => {
  assertEquals(serviceRoleRequestHeaders(CURRENT_SECRET_KEY), {
    apikey: CURRENT_SECRET_KEY,
  });
});

Deno.test("serviceRoleRequestHeaders preserves Bearer transport for legacy service-role JWTs", () => {
  assertEquals(
    serviceRoleRequestHeaders(LEGACY_SERVICE_ROLE_KEY),
    {
      apikey: LEGACY_SERVICE_ROLE_KEY,
      Authorization: `Bearer ${LEGACY_SERVICE_ROLE_KEY}`,
    },
  );
});

Deno.test("privileged transports reject public or malformed configured keys", () => {
  for (
    const invalidKey of [
      "sb_publishable_public",
      "sb_secret_placeholder",
      INVALID_SECRET_KEY,
      "not-a-server-key",
    ]
  ) {
    assertThrows(
      () => serviceRoleRequestHeaders(invalidKey),
      ServerApiKeyConfigurationError,
      "invalid_secret_key_configuration",
    );
    assertThrows(
      () => createServiceRoleFetchTransport(invalidKey),
      ServerApiKeyConfigurationError,
      "invalid_secret_key_configuration",
    );
  }
});

Deno.test("createServiceRoleClient keeps opaque keys out of database Bearer transport", async () => {
  const headers = await databaseRequestHeaders(CURRENT_SECRET_KEY);

  assertEquals(headers.get("apikey"), CURRENT_SECRET_KEY);
  assertEquals(headers.get("Authorization"), null);
});

Deno.test("request authorization preserves the matching key at the database transport", async () => {
  const auth = authorizeServiceRoleRequest(
    new Request("https://project.supabase.co/functions/v1/internal-worker", {
      headers: { apikey: CURRENT_SECRET_KEY },
    }),
    {
      envSynchronizedServerApiKey: STALE_SYNCHRONIZED_SECRET_KEY,
      envSecretKeys: JSON.stringify({ default: CURRENT_SECRET_KEY }),
    },
  );
  if (!auth.ok) throw new Error(`unexpected auth failure: ${auth.reason}`);

  const headers = await databaseRequestHeaders(auth.serverApiKey);
  assertEquals(headers.get("apikey"), CURRENT_SECRET_KEY);
  assertEquals(headers.get("Authorization"), null);
});

Deno.test("createServiceRoleClient keeps opaque keys out of Storage Bearer transport", async () => {
  const headers = await storageRequestHeaders(CURRENT_SECRET_KEY);
  assertEquals(headers.get("apikey"), CURRENT_SECRET_KEY);
  assertEquals(headers.get("Authorization"), null);
});

Deno.test("createServiceRoleClient uses apikey-only opaque transport for Functions", async () => {
  const headers = await functionRequestHeaders(CURRENT_SECRET_KEY);
  assertEquals(headers.get("apikey"), CURRENT_SECRET_KEY);
  assertEquals(headers.get("Authorization"), null);
});

Deno.test("opaque SDK Function transport passes the shared request boundary", async () => {
  const headers = await functionRequestHeaders(CURRENT_SECRET_KEY);
  assertEquals(
    authorizeServiceRoleRequest(
      new Request("https://project.supabase.co/functions/v1/internal-worker", {
        headers,
      }),
      {
        envSecretKeys: JSON.stringify({ default: CURRENT_SECRET_KEY }),
      },
    ),
    {
      ok: true,
      serverApiKey: CURRENT_SECRET_KEY,
    },
  );
});

Deno.test("privileged JSON Function invocation returns parsed success data", async () => {
  const client = createServiceRoleClient(
    "https://project.supabase.co",
    CURRENT_SECRET_KEY,
    () =>
      Promise.resolve(
        new Response(JSON.stringify({ success: true }), {
          headers: { "Content-Type": "application/json" },
        }),
      ),
  );

  assertEquals(
    await invokeServiceRoleJson<{ success: true }>(
      client,
      "internal-worker",
      {},
    ),
    { success: true },
  );
});

Deno.test("privileged JSON Function failures expose only safe routing metadata", async () => {
  for (
    const [handlerHeader, reachedMerianHandler] of [
      ["1", true],
      [null, false],
    ] as const
  ) {
    let bodyCancelled = false;
    const headers = new Headers({ "Content-Type": "application/json" });
    if (handlerHeader) headers.set("X-Merian-Handler", handlerHeader);
    const client = createServiceRoleClient(
      "https://project.supabase.co",
      CURRENT_SECRET_KEY,
      () =>
        Promise.resolve(
          new Response(
            new ReadableStream<Uint8Array>({
              start(controller) {
                controller.enqueue(
                  new TextEncoder().encode(
                    JSON.stringify({
                      error: "sensitive internal failure",
                      credential: CURRENT_SECRET_KEY,
                    }),
                  ),
                );
              },
              cancel() {
                bodyCancelled = true;
              },
            }),
            { status: 401, headers },
          ),
        ),
    );

    const error = await assertRejects(
      () => invokeServiceRoleJson(client, "internal-worker", {}),
      ServiceRoleFunctionInvocationError,
      "HTTP 401",
    );
    assertEquals(error.functionName, "internal-worker");
    assertEquals(error.status, 401);
    assertEquals(error.reachedMerianHandler, reachedMerianHandler);
    assertEquals(error.failureName, "FunctionsHttpError");
    assertEquals(error.message.includes("Response body withheld"), true);
    assertEquals(error.message.includes("sensitive internal failure"), false);
    assertEquals(error.message.includes(CURRENT_SECRET_KEY), false);
    assertEquals(bodyCancelled, true);
  }
});

Deno.test("privileged JSON Function fetch failures withhold the upstream error", async () => {
  const client = createServiceRoleClient(
    "https://project.supabase.co",
    CURRENT_SECRET_KEY,
    () =>
      Promise.reject(
        new TypeError(`sensitive network failure: ${CURRENT_SECRET_KEY}`),
      ),
  );

  const error = await assertRejects(
    () => invokeServiceRoleJson(client, "internal-worker", {}),
    ServiceRoleFunctionInvocationError,
    "HTTP status unavailable",
  );
  assertEquals(error.status, null);
  assertEquals(error.reachedMerianHandler, false);
  assertEquals(error.failureName, "FunctionsFetchError");
  assertEquals(error.message.includes("sensitive network failure"), false);
  assertEquals(error.message.includes(CURRENT_SECRET_KEY), false);
});

Deno.test("privileged JSON Function invocation rejects unsafe route names", async () => {
  const client = createServiceRoleClient(
    "https://project.supabase.co",
    CURRENT_SECRET_KEY,
    () => Promise.resolve(new Response("{}")),
  );

  await assertRejects(
    () => invokeServiceRoleJson(client, "../internal-worker", {}),
    TypeError,
    "Invalid Edge Function name",
  );
});

Deno.test("createServiceRoleClient keeps opaque keys out of AuthAdmin Bearer transport", async () => {
  const headers = await authAdminRequestHeaders(CURRENT_SECRET_KEY);
  assertEquals(headers.get("apikey"), CURRENT_SECRET_KEY);
  assertEquals(headers.get("Authorization"), null);
});

Deno.test("createServiceRoleClient preserves legacy service-role JWT transport", async () => {
  for (
    const headers of [
      await databaseRequestHeaders(LEGACY_SERVICE_ROLE_KEY),
      await storageRequestHeaders(LEGACY_SERVICE_ROLE_KEY),
      await functionRequestHeaders(LEGACY_SERVICE_ROLE_KEY),
      await authAdminRequestHeaders(LEGACY_SERVICE_ROLE_KEY),
    ]
  ) {
    assertEquals(headers.get("apikey"), LEGACY_SERVICE_ROLE_KEY);
    assertEquals(
      headers.get("Authorization"),
      `Bearer ${LEGACY_SERVICE_ROLE_KEY}`,
    );
  }
});

Deno.test("opaque-key transport preserves a distinct user access token", async () => {
  let observedHeaders = new Headers();
  const transport = createServiceRoleFetchTransport(
    CURRENT_SECRET_KEY,
    (input, init) => {
      const initHeaders = init && "headers" in init
        ? init.headers as HeadersInit
        : undefined;
      const sourceHeaders = initHeaders ??
        (input instanceof Request ? input.headers : undefined);
      observedHeaders = new Headers(sourceHeaders);
      return Promise.resolve(new Response("ok"));
    },
  );

  await transport(
    new Request("https://project.supabase.co/rest/v1/example", {
      headers: {
        apikey: CURRENT_SECRET_KEY,
        Authorization: "Bearer authenticated-user-jwt",
        "X-Request-Metadata": "preserved",
      },
    }),
  );

  assertEquals(observedHeaders.get("apikey"), CURRENT_SECRET_KEY);
  assertEquals(
    observedHeaders.get("Authorization"),
    "Bearer authenticated-user-jwt",
  );
  assertEquals(observedHeaders.get("X-Request-Metadata"), "preserved");
});

Deno.test("opaque-key transport removes only its inherited Bearer fallback", async () => {
  let observedHeaders = new Headers();
  const transport = createServiceRoleFetchTransport(
    CURRENT_SECRET_KEY,
    (input, init) => {
      const initHeaders = init && "headers" in init
        ? init.headers as HeadersInit
        : undefined;
      const sourceHeaders = initHeaders ??
        (input instanceof Request ? input.headers : undefined);
      observedHeaders = new Headers(sourceHeaders);
      return Promise.resolve(new Response("ok"));
    },
  );

  for (
    const authorization of [
      `Bearer ${CURRENT_SECRET_KEY}`,
      `bearer   ${CURRENT_SECRET_KEY} `,
    ]
  ) {
    await transport(
      new Request("https://project.supabase.co/rest/v1/example", {
        headers: {
          apikey: CURRENT_SECRET_KEY,
          Authorization: authorization,
          "X-Request-Metadata": "preserved",
        },
      }),
    );

    assertEquals(observedHeaders.get("apikey"), CURRENT_SECRET_KEY);
    assertEquals(observedHeaders.get("Authorization"), null);
    assertEquals(observedHeaders.get("X-Request-Metadata"), "preserved");
  }
});

Deno.test("service-role SDK transport attaches a hard request deadline", async () => {
  let observedSignal: AbortSignal | undefined;
  const transport = createServiceRoleFetchTransport(
    CURRENT_SECRET_KEY,
    (_input, init) => {
      observedSignal = init && "signal" in init
        ? init.signal ?? undefined
        : undefined;
      return Promise.resolve(new Response("ok"));
    },
  );

  await transport("https://project.supabase.co/rest/v1/example");

  assertEquals(observedSignal instanceof AbortSignal, true);
});

Deno.test("service-role SDK options enforce the response byte ceiling", async () => {
  const client = createServiceRoleClientWithOptions(
    "https://project.supabase.co",
    CURRENT_SECRET_KEY,
    {
      maximumResponseBytes: 8,
      fetchImplementation: (() =>
        Promise.resolve(
          new Response("123456789", {
            headers: {
              "Content-Length": "9",
              "Content-Type": "application/json",
            },
          }),
        )) as typeof fetch,
    },
  );

  const { data, error } = await client.from("example").select("id");
  assertEquals(data, null);
  assertEquals(
    error?.message,
    "RangeError: Response body exceeded its byte limit.",
  );
});
