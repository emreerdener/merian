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

Deno.test("serviceRoleRequestHeaders carries server keys in both headers", () => {
  assertEquals(serviceRoleRequestHeaders(CURRENT_SECRET_KEY), {
    apikey: CURRENT_SECRET_KEY,
    Authorization: `Bearer ${CURRENT_SECRET_KEY}`,
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

Deno.test("createServiceRoleClient uses Bearer token database transport", async () => {
  const headers = await databaseRequestHeaders(CURRENT_SECRET_KEY);

  assertEquals(headers.get("apikey"), CURRENT_SECRET_KEY);
  assertEquals(headers.get("Authorization"), `Bearer ${CURRENT_SECRET_KEY}`);
});

Deno.test("createServiceRoleClient uses Bearer token transport for Storage", async () => {
  const headers = await storageRequestHeaders(CURRENT_SECRET_KEY);
  assertEquals(headers.get("apikey"), CURRENT_SECRET_KEY);
  assertEquals(headers.get("Authorization"), `Bearer ${CURRENT_SECRET_KEY}`);
});
Deno.test("createServiceRoleClient uses Bearer token transport for Functions", async () => {
  const headers = await functionRequestHeaders(CURRENT_SECRET_KEY);
  assertEquals(headers.get("apikey"), CURRENT_SECRET_KEY);
  assertEquals(headers.get("Authorization"), null);
});
Deno.test("createServiceRoleClient uses Bearer token transport for AuthAdmin", async () => {
  const headers = await authAdminRequestHeaders(CURRENT_SECRET_KEY);
  assertEquals(headers.get("apikey"), CURRENT_SECRET_KEY);
  assertEquals(headers.get("Authorization"), `Bearer ${CURRENT_SECRET_KEY}`);
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
