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

Deno.test("Management API lookup retries only the reviewed HTTP status classes", async () => {
  for (const status of [408, 425, 429, 500, 502, 599]) {
    let attempts = 0;
    const fetchImplementation: typeof fetch = () => {
      attempts += 1;
      if (attempts === 1) {
        return Promise.resolve(new Response(null, { status }));
      }
      return Promise.resolve(
        new Response(
          JSON.stringify([
            {
              type: "secret",
              name: "default",
              api_key: DEFAULT_SECRET,
            },
          ]),
        ),
      );
    };

    await fetchRevealedProjectApiKeys(
      "abcdefghijklmnopqrst",
      "management-access-token",
      fetchImplementation,
      {
        maximumAttempts: 2,
        random: () => 0,
        wait: () => Promise.resolve(),
      },
    );
    assertEquals(attempts, 2, `status ${status}`);
  }

  for (const status of [400, 401, 403, 404]) {
    let attempts = 0;
    const fetchImplementation: typeof fetch = () => {
      attempts += 1;
      return Promise.resolve(new Response(null, { status }));
    };

    await assertRejects(
      () =>
        fetchRevealedProjectApiKeys(
          "abcdefghijklmnopqrst",
          "management-access-token",
          fetchImplementation,
          {
            maximumAttempts: 2,
            wait: () => Promise.resolve(),
          },
        ),
      Error,
      `HTTP ${status}`,
    );
    assertEquals(attempts, 1, `status ${status}`);
  }
});

Deno.test("Management API lookup retries transient HTTP failures with bounded delay", async () => {
  let attempts = 0;
  const waits: number[] = [];
  const retries: unknown[] = [];
  const fetchImplementation: typeof fetch = () => {
    attempts += 1;
    if (attempts === 1) {
      return Promise.resolve(
        new Response(
          new ReadableStream<Uint8Array>({
            cancel() {
              throw new Error("response disposal failed");
            },
          }),
          { status: 502 },
        ),
      );
    }
    if (attempts === 2) {
      return Promise.resolve(
        new Response(null, {
          status: 429,
          headers: { "Retry-After": "60" },
        }),
      );
    }
    return Promise.resolve(
      new Response(
        JSON.stringify([
          {
            type: "secret",
            name: "default",
            api_key: DEFAULT_SECRET,
          },
        ]),
      ),
    );
  };

  const result = await fetchRevealedProjectApiKeys(
    "abcdefghijklmnopqrst",
    "management-access-token",
    fetchImplementation,
    {
      maximumAttempts: 3,
      random: () => 0,
      wait: (milliseconds) => {
        waits.push(milliseconds);
        return Promise.resolve();
      },
      onRetry: (retry) => retries.push(retry),
    },
  );

  assertEquals(result.server_api_key, DEFAULT_SECRET);
  assertEquals(attempts, 3);
  assertEquals(waits, [500, 8_000]);
  assertEquals(retries, [
    {
      attempt: 1,
      maximumAttempts: 3,
      delayMs: 500,
      reason: "http_502",
    },
    {
      attempt: 2,
      maximumAttempts: 3,
      delayMs: 8_000,
      reason: "http_429",
    },
  ]);
});

Deno.test("Management API lookup retries transport errors without exposing them", async () => {
  let attempts = 0;
  const waits: number[] = [];
  const fetchImplementation: typeof fetch = () => {
    attempts += 1;
    if (attempts === 1) {
      return Promise.reject(
        new TypeError("request failed with sensitive transport detail"),
      );
    }
    return Promise.resolve(
      new Response(
        JSON.stringify([
          {
            type: "secret",
            name: "default",
            api_key: DEFAULT_SECRET,
          },
        ]),
      ),
    );
  };

  assertEquals(
    (
      await fetchRevealedProjectApiKeys(
        "abcdefghijklmnopqrst",
        "management-access-token",
        fetchImplementation,
        {
          maximumAttempts: 2,
          random: () => 0,
          wait: (milliseconds) => {
            waits.push(milliseconds);
            return Promise.resolve();
          },
        },
      )
    ).server_api_key,
    DEFAULT_SECRET,
  );
  assertEquals(attempts, 2);
  assertEquals(waits, [500]);
});

Deno.test("Management API lookup stops after the bounded retry ceiling", async () => {
  let attempts = 0;
  const waits: number[] = [];
  const fetchImplementation: typeof fetch = () => {
    attempts += 1;
    return Promise.resolve(new Response(null, { status: 502 }));
  };

  await assertRejects(
    () =>
      fetchRevealedProjectApiKeys(
        "abcdefghijklmnopqrst",
        "management-access-token",
        fetchImplementation,
        {
          maximumAttempts: 3,
          random: () => 1,
          wait: (milliseconds) => {
            waits.push(milliseconds);
            return Promise.resolve();
          },
        },
      ),
    Error,
    "failed after 3 attempts with HTTP 502",
  );
  assertEquals(attempts, 3);
  assertEquals(waits, [1_000, 2_000]);

  await assertRejects(
    () =>
      fetchRevealedProjectApiKeys(
        "abcdefghijklmnopqrst",
        "management-access-token",
        fetchImplementation,
        { maximumAttempts: 6 },
      ),
    TypeError,
    "maximumAttempts must be between 1 and 5",
  );

  let transportFailureMessage = "";
  try {
    await fetchRevealedProjectApiKeys(
      "abcdefghijklmnopqrst",
      "management-access-token",
      () =>
        Promise.reject(
          new TypeError("sensitive upstream transport diagnostic"),
        ),
      {
        maximumAttempts: 2,
        random: () => 0,
        wait: () => Promise.resolve(),
      },
    );
  } catch (error) {
    transportFailureMessage = error instanceof Error
      ? error.message
      : String(error);
  }
  assertEquals(
    transportFailureMessage,
    "Supabase Management API key lookup failed after 2 attempts due to transport errors.",
  );
});

Deno.test("Management API lookup fails closed on authorization errors", async () => {
  let attempts = 0;
  const waits: number[] = [];
  const fetchImplementation: typeof fetch = () => {
    attempts += 1;
    return Promise.resolve(new Response(null, { status: 403 }));
  };

  await assertRejects(
    () =>
      fetchRevealedProjectApiKeys(
        "abcdefghijklmnopqrst",
        "management-access-token",
        fetchImplementation,
        {
          wait: (milliseconds) => {
            waits.push(milliseconds);
            return Promise.resolve();
          },
        },
      ),
    Error,
    "HTTP 403",
  );
  assertEquals(attempts, 1);
  assertEquals(waits, []);
});

Deno.test("Management API lookup rejects malformed UTF-8 before JSON parsing", async () => {
  let attempts = 0;
  const waits: number[] = [];
  const fetchImplementation: typeof fetch = () => {
    attempts += 1;
    return Promise.resolve(
      new Response(Uint8Array.of(0xff), {
        headers: { "Content-Type": "application/json" },
      }),
    );
  };

  await assertRejects(
    () =>
      fetchRevealedProjectApiKeys(
        "abcdefghijklmnopqrst",
        "management-access-token",
        fetchImplementation,
        {
          wait: (milliseconds) => {
            waits.push(milliseconds);
            return Promise.resolve();
          },
        },
      ),
    TypeError,
  );
  assertEquals(attempts, 1);
  assertEquals(waits, []);

  attempts = 0;
  const invalidJsonFetch: typeof fetch = () => {
    attempts += 1;
    return Promise.resolve(new Response("{"));
  };
  await assertRejects(
    () =>
      fetchRevealedProjectApiKeys(
        "abcdefghijklmnopqrst",
        "management-access-token",
        invalidJsonFetch,
        {
          wait: (milliseconds) => {
            waits.push(milliseconds);
            return Promise.resolve();
          },
        },
      ),
    Error,
    "invalid key JSON",
  );
  assertEquals(attempts, 1);
  assertEquals(waits, []);
});
