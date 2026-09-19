import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import {
  type HostedAuthConfig,
  validateHostedAuthConfig,
  verifyHostedAuth,
} from "./verify_field_chat_hosted_auth.ts";

const projectRef = "abcdefghijklmnopqrst";
function token(values: Record<string, unknown>) {
  const part = (value: unknown) =>
    btoa(JSON.stringify(value)).replaceAll("=", "");
  return `${part({ alg: "HS256" })}.${part(values)}.${
    btoa("synthetic-signature")
  }`;
}
function config(): HostedAuthConfig {
  return {
    projectRef,
    candidateSha: "a".repeat(40),
    publicKey: "sb_publishable_synthetic",
    userToken: token({
      role: "authenticated",
      iss: `https://${projectRef}.supabase.co/auth/v1`,
      sub: "synthetic-user",
      exp: Math.floor(Date.now() / 1000) + 3600,
    }),
    digests: {
      "insight-chat": "b".repeat(64),
      "explore-post-chat": "c".repeat(64),
      "species-dictionary-chat": "d".repeat(64),
    },
  };
}
function transportFor(
  settings: HostedAuthConfig,
  modify: (response: Response, url: string) => Response = (response) =>
    response,
) {
  return (url: string, init: RequestInit): Promise<Response> => {
    assertEquals(init.redirect, "error");
    assert(init.signal instanceof AbortSignal);
    const headers = new Headers(init.headers);
    assertEquals(headers.get("apikey"), settings.publicKey);
    let response: Response;
    if (url.endsWith("/auth/v1/user")) {
      assertEquals(init.method ?? "GET", "GET");
      response = Response.json({ id: "synthetic-user" });
    } else {
      assertEquals(init.method, "POST");
      // No subject identifier, provider action, or caller-selected identity.
      assertEquals(init.body, '{"action":"load"}');
      const route = url.split("/").at(-1) as keyof typeof settings.digests;
      const status = headers.get("Authorization") ===
          `Bearer ${settings.userToken}`
        ? 400
        : 401;
      response = Response.json({ code: "invalid_request" }, {
        status,
        headers: {
          "X-Merian-Handler": "1",
          "X-Merian-Field-Chat-Contract": "atomic-admission-v1",
          "X-Merian-Field-Chat-Bundle-SHA256": settings.digests[route],
        },
      });
    }
    return Promise.resolve(modify(response, url));
  };
}

Deno.test("hosted auth probe checks all three boundaries and emits redacted evidence", async () => {
  const settings = config();
  const evidence = await verifyHostedAuth(settings, transportFor(settings));
  assertEquals(evidence.checks.length, 9);
  assertEquals(evidence.scope, "real_token_http_auth_boundary_only");
  assertEquals(evidence.checks.map((check) => check.status), [
    401,
    401,
    400,
    401,
    401,
    400,
    401,
    401,
    400,
  ]);
  const serialized = JSON.stringify(evidence);
  for (
    const secret of [settings.userToken, settings.publicKey, "synthetic-user"]
  ) {
    assert(!serialized.includes(secret));
  }
});

Deno.test("hosted auth probe rejects production, malformed targets and server keys before transport", async () => {
  for (
    const overrides of [
      { projectRef: "qlarqavoqhkuwzmevrmf" },
      { projectRef: "attacker.example/path" },
      { candidateSha: "main" },
      { publicKey: token({ role: "service_role", ref: projectRef }) },
      { publicKey: token({ role: "anon", ref: "another-project" }) },
      { userToken: token({ role: "service_role" }) },
      { userToken: token({ role: "authenticated", exp: 0 }) },
      { userToken: "malformed" },
      { digests: { ...config().digests, "insight-chat": "missing" } },
    ]
  ) {
    let calls = 0;
    await assertRejects(() =>
      verifyHostedAuth({ ...config(), ...overrides }, () => {
        calls++;
        return Promise.resolve(new Response());
      })
    );
    assertEquals(calls, 0);
  }
  const settings = config();
  settings.publicKey = token({ role: "anon", ref: projectRef });
  validateHostedAuthConfig(settings);
  settings.userToken = token({
    role: "authenticated",
    sub: "synthetic",
    exp: 4_000_000_000,
    iss: "https://another-project.supabase.co/auth/v1",
  });
  assertThrows(() => validateHostedAuthConfig(settings));
});

Deno.test("hosted auth fails closed on wrong user, stale bundle, wrong status or missing handler", async () => {
  const settings = config();
  for (
    const modify of [
      (response: Response, url: string) =>
        url.endsWith("/user")
          ? Response.json({ id: "different-user" })
          : response,
      (response: Response, url: string) =>
        url.endsWith("/user") ? new Response(null, { status: 401 }) : response,
      (response: Response, url: string) => {
        if (!url.endsWith("/user")) response.headers.delete("X-Merian-Handler");
        return response;
      },
      (response: Response, url: string) => {
        if (!url.endsWith("/user")) {
          response.headers.set(
            "X-Merian-Field-Chat-Bundle-SHA256",
            "f".repeat(64),
          );
        }
        return response;
      },
      (response: Response, url: string) =>
        url.endsWith("/user")
          ? response
          : new Response(null, { status: 200, headers: response.headers }),
      (response: Response) =>
        response.status === 400
          ? Response.json({ code: "unrelated_error" }, {
            status: 400,
            headers: response.headers,
          })
          : response,
    ]
  ) {
    await assertRejects(() =>
      verifyHostedAuth(settings, transportFor(settings, modify))
    );
  }
});

Deno.test("hosted auth bounds bodies and redacts transport errors", async () => {
  const settings = config();
  const error = await assertRejects(() =>
    verifyHostedAuth(settings, () => {
      throw new Error(`upstream sensitive ${settings.userToken}`);
    })
  );
  assert(error instanceof Error);
  assert(!error.message.includes(settings.userToken));
  await assertRejects(() =>
    verifyHostedAuth(
      settings,
      () => Promise.resolve(new Response("x".repeat(32_769))),
    )
  );
  await assertRejects(() =>
    verifyHostedAuth(settings, () => Promise.resolve(new Response("not json")))
  );
});
