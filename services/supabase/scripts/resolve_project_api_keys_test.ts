import {
  assertEquals,
  assertRejects,
  assertThrows,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import {
  fetchRevealedProjectApiKeys,
  resolveProjectApiKeys,
} from "./resolve_project_api_keys.ts";

const DEFAULT_SECRET = `sb_secret_${"a".repeat(32)}`;
const WORKER_SECRET = `sb_secret_${"b".repeat(32)}`;
const DEFAULT_PUBLISHABLE = `sb_publishable_${"c".repeat(32)}`;
const LEGACY_SERVICE_ROLE = [
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9",
  "eyJpc3MiOiJzdXBhYmFzZSIsInJvbGUiOiJzZXJ2aWNlX3JvbGUifQ",
  "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
].join(".");
const LEGACY_ANON = [
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9",
  "eyJpc3MiOiJzdXBhYmFzZSIsInJvbGUiOiJhbm9uIn0",
  "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
].join(".");

Deno.test("resolver prefers a revealed default secret and returns all exact public keys", () => {
  assertEquals(
    resolveProjectApiKeys([
      {
        type: "legacy",
        name: "service_role",
        api_key: LEGACY_SERVICE_ROLE,
      },
      {
        type: "secret",
        name: "worker",
        api_key: WORKER_SECRET,
      },
      {
        type: "secret",
        name: "default",
        api_key: DEFAULT_SECRET,
      },
      {
        type: "publishable",
        name: "default",
        api_key: DEFAULT_PUBLISHABLE,
      },
      { type: "legacy", name: "anon", api_key: LEGACY_ANON },
    ]),
    {
      server_api_key: DEFAULT_SECRET,
      public_api_keys: [DEFAULT_PUBLISHABLE, LEGACY_ANON],
    },
  );
});

Deno.test("resolver rejects masked keys and loosely named legacy keys", () => {
  assertThrows(
    () =>
      resolveProjectApiKeys([
        { type: "secret", name: "default", api_key: "sb_secret_..." },
        {
          type: "legacy",
          name: "service_role_backup",
          api_key: LEGACY_SERVICE_ROLE,
        },
        {
          type: "legacy",
          name: "service_role",
          api_key: "aaa.bbb.ccc",
        },
      ]),
    Error,
    "no revealed secret or exact legacy service-role key",
  );
});

Deno.test("resolver falls back to the exact legacy service-role key", () => {
  assertEquals(
    resolveProjectApiKeys([
      {
        type: "legacy",
        name: "service_role",
        api_key: LEGACY_SERVICE_ROLE,
      },
    ]),
    {
      server_api_key: LEGACY_SERVICE_ROLE,
      public_api_keys: [],
    },
  );
});

Deno.test("resolver ignores malformed public-key candidates", () => {
  assertEquals(
    resolveProjectApiKeys([
      {
        type: "secret",
        name: "default",
        api_key: DEFAULT_SECRET,
      },
      {
        type: "publishable",
        name: "default",
        api_key: "sb_publishable_...",
      },
      {
        type: "legacy",
        name: "anon",
        api_key: "ddd.eee.fff",
      },
    ]),
    {
      server_api_key: DEFAULT_SECRET,
      public_api_keys: [],
    },
  );
});

Deno.test("Management API lookup explicitly reveals keys without logging credentials", async () => {
  let requestedUrl = "";
  let authorization = "";
  const fetchImplementation: typeof fetch = (input, init) => {
    requestedUrl = String(input);
    const headers = (init as { headers?: HeadersInit } | undefined)?.headers;
    authorization = new Headers(headers).get("Authorization") ?? "";
    return Promise.resolve(
      new Response(
        JSON.stringify([
          {
            type: "secret",
            name: "default",
            api_key: DEFAULT_SECRET,
          },
        ]),
        {
          headers: { "Content-Type": "application/json" },
        },
      ),
    );
  };

  const result = await fetchRevealedProjectApiKeys(
    "abcdefghijklmnopqrst",
    "management-access-token",
    fetchImplementation,
  );

  assertEquals(
    requestedUrl,
    "https://api.supabase.com/v1/projects/abcdefghijklmnopqrst/api-keys?reveal=true",
  );
  assertEquals(authorization, "Bearer management-access-token");
  assertEquals(result.server_api_key, DEFAULT_SECRET);
});

Deno.test("Management API lookup fails closed on authorization errors", async () => {
  const fetchImplementation: typeof fetch = () =>
    Promise.resolve(new Response(null, { status: 403 }));

  await assertRejects(
    () =>
      fetchRevealedProjectApiKeys(
        "abcdefghijklmnopqrst",
        "management-access-token",
        fetchImplementation,
      ),
    Error,
    "HTTP 403",
  );
});

Deno.test("Management API lookup rejects malformed UTF-8 before JSON parsing", async () => {
  const fetchImplementation: typeof fetch = () =>
    Promise.resolve(
      new Response(Uint8Array.of(0xff), {
        headers: { "Content-Type": "application/json" },
      }),
    );

  await assertRejects(
    () =>
      fetchRevealedProjectApiKeys(
        "abcdefghijklmnopqrst",
        "management-access-token",
        fetchImplementation,
      ),
    TypeError,
  );
});
