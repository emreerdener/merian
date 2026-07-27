import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import {
  ServerApiKeyConfigurationError,
  serviceRoleRequestHeaders,
} from "./serviceRoleAuth.ts";
import {
  createServiceRoleClient,
  createServiceRoleFetchTransport,
} from "./serviceRoleClient.ts";

const LEGACY_SERVICE_ROLE_KEY = [
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9",
  "eyJpc3MiOiJzdXBhYmFzZSIsInJvbGUiOiJzZXJ2aWNlX3JvbGUifQ",
  "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
].join(".");
const CURRENT_SECRET_KEY = [
  "sb",
  "secret",
  "worker",
  "a".repeat(20),
].join("_");
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
      requestHeaders = new Headers(
        init && "headers" in init ? init.headers as HeadersInit : undefined,
      );
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
      requestHeaders = new Headers(
        init && "headers" in init ? init.headers as HeadersInit : undefined,
      );
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
      requestHeaders = new Headers(
        init && "headers" in init ? init.headers as HeadersInit : undefined,
      );
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
      requestHeaders = new Headers(
        init && "headers" in init ? init.headers as HeadersInit : undefined,
      );
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

Deno.test("serviceRoleRequestHeaders keeps non-JWT secret keys out of Bearer transport", () => {
  assertEquals(
    serviceRoleRequestHeaders(CURRENT_SECRET_KEY),
    {
      apikey: CURRENT_SECRET_KEY,
    },
  );
});

Deno.test("serviceRoleRequestHeaders carries legacy service-role JWTs in both headers", () => {
  assertEquals(serviceRoleRequestHeaders(LEGACY_SERVICE_ROLE_KEY), {
    apikey: LEGACY_SERVICE_ROLE_KEY,
    Authorization: `Bearer ${LEGACY_SERVICE_ROLE_KEY}`,
  });
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

Deno.test("createServiceRoleClient keeps non-JWT secret keys out of database Bearer transport", async () => {
  const headers = await databaseRequestHeaders(
    CURRENT_SECRET_KEY,
  );

  assertEquals(headers.get("apikey"), CURRENT_SECRET_KEY);
  assertEquals(headers.get("Authorization"), null);
});

Deno.test("createServiceRoleClient preserves legacy service-role JWT database transport", async () => {
  const headers = await databaseRequestHeaders(LEGACY_SERVICE_ROLE_KEY);

  assertEquals(headers.get("apikey"), LEGACY_SERVICE_ROLE_KEY);
  assertEquals(
    headers.get("Authorization"),
    `Bearer ${LEGACY_SERVICE_ROLE_KEY}`,
  );
});

Deno.test("createServiceRoleClient keeps non-JWT secret keys out of Storage, Functions, and Auth Bearer transport", async () => {
  for (
    const headers of [
      await storageRequestHeaders(CURRENT_SECRET_KEY),
      await functionRequestHeaders(CURRENT_SECRET_KEY),
      await authAdminRequestHeaders(CURRENT_SECRET_KEY),
    ]
  ) {
    assertEquals(headers.get("apikey"), CURRENT_SECRET_KEY);
    assertEquals(headers.get("Authorization"), null);
  }
});

Deno.test("createServiceRoleClient preserves legacy JWT transport for Storage, Functions, and Auth", async () => {
  for (
    const headers of [
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

Deno.test("service-role transport preserves headers inherited from a Request", async () => {
  let observedHeaders = new Headers();
  const transport = createServiceRoleFetchTransport(
    CURRENT_SECRET_KEY,
    (_input, init) => {
      observedHeaders = new Headers(
        init && "headers" in init ? init.headers as HeadersInit : undefined,
      );
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

  assertEquals(
    observedHeaders.get("apikey"),
    CURRENT_SECRET_KEY,
  );
  assertEquals(
    observedHeaders.get("Authorization"),
    "Bearer authenticated-user-jwt",
  );
  assertEquals(observedHeaders.get("X-Request-Metadata"), "preserved");
});

Deno.test("service-role transport removes only its exact fallback inherited from a Request", async () => {
  let observedHeaders = new Headers();
  const transport = createServiceRoleFetchTransport(
    CURRENT_SECRET_KEY,
    (_input, init) => {
      observedHeaders = new Headers(
        init && "headers" in init ? init.headers as HeadersInit : undefined,
      );
      return Promise.resolve(new Response("ok"));
    },
  );

  await transport(
    new Request("https://project.supabase.co/rest/v1/example", {
      headers: {
        apikey: CURRENT_SECRET_KEY,
        Authorization: `Bearer ${CURRENT_SECRET_KEY}`,
        "X-Request-Metadata": "preserved",
      },
    }),
  );

  assertEquals(
    observedHeaders.get("apikey"),
    CURRENT_SECRET_KEY,
  );
  assertEquals(observedHeaders.get("Authorization"), null);
  assertEquals(observedHeaders.get("X-Request-Metadata"), "preserved");
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
