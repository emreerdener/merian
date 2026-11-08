import { assert, assertEquals } from "@std/assert";
import type { User } from "@supabase/supabase-js";
import { sourceRetirementRoute } from "./route.ts";
import { sourceReservationIdentity } from "../_shared/analysisHistory/sourceReservation.ts";
import vectors from "../_shared/analysisHistory/fixtures/source-fingerprint-v1.json" with {
  type: "json",
};
const owner = "00000000-0000-4000-8000-000000000090";
const candidate = {
  schema_version: 1,
  input: vectors[0].input,
  fingerprint_version: 1,
  fingerprint: vectors[0].sha256,
};
const identity = await sourceReservationIdentity(candidate);
const operation = "00000000-0000-4000-8000-000000000092";
const envelope = { schema_version: 1, candidate, operation_id: operation };
const retired = {
  ...identity,
  owner_id: owner,
  operation_id: operation,
  state: "retired_unfunded",
};
const authenticated = () =>
  Promise.resolve({ user: { id: owner } as User, response: null });
const request = (body: unknown = envelope) =>
  new Request("https://synthetic.invalid", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
async function environment(work: () => Promise<void>) {
  const keys = ["SUPABASE_URL", "SUPABASE_SERVER_API_KEY"];
  const previous = keys.map((key) => Deno.env.get(key));
  Deno.env.set(keys[0], "https://synthetic.invalid");
  Deno.env.set(keys[1], "sb_secret_" + "synthetic_test_only".repeat(3));
  const fetch = globalThis.fetch;
  try {
    await work();
  } finally {
    globalThis.fetch = fetch;
    keys.forEach((key, i) =>
      previous[i] === undefined
        ? Deno.env.delete(key)
        : Deno.env.set(key, previous[i]!)
    );
  }
}
Deno.test("source retirement route denies auth/method/invalid and oversized bodies before RPC", async () => {
  await environment(async () => {
    let calls = 0;
    globalThis.fetch = () => {
      calls++;
      throw new Error("unexpected transport");
    };
    const denied = await sourceRetirementRoute(
      request(),
      () =>
        Promise.resolve({
          user: null,
          response: new Response(null, { status: 401 }),
        }),
    );
    assertEquals(denied.status, 401);
    await denied.body?.cancel();
    for (
      const [req, status] of [
        [new Request("https://synthetic.invalid", { method: "OPTIONS" }), 200],
        [new Request("https://synthetic.invalid"), 405],
        [request({ ...envelope, owner_id: owner }), 400],
        [
          request({
            ...envelope,
            candidate: { ...candidate, fingerprint: "f".repeat(64) },
          }),
          400,
        ],
        [request("x".repeat(1_048_663)), 413],
        [
          new Request("https://synthetic.invalid", {
            method: "POST",
            body: "{",
            headers: { "Content-Type": "application/json" },
          }),
          400,
        ],
      ] as const
    ) {
      const result = await sourceRetirementRoute(req, authenticated);
      assertEquals(result.status, status);
      assertEquals(result.headers.get("Cache-Control"), "private, no-store");
      await result.body?.cancel();
    }
    assertEquals(calls, 0);
  });
});
for (const reply of [retired]) {
  Deno.test(`source retirement HTTP returns exact ${reply.state} observation with one owner-scoped RPC`, async () => {
    await environment(async () => {
      let calls = 0;
      globalThis.fetch = (url, init) => {
        calls++;
        assert(
          String(url).endsWith(
            "/rest/v1/rpc/retire_owned_observation_analysis_source",
          ),
        );
        assertEquals(init?.method, "POST");
        assertEquals(JSON.parse(String(init?.body)), {
          p_owner: owner,
          p_request: { ...identity, operation_id: operation },
          p_reader: 11,
        });
        assert(init?.signal);
        return Promise.resolve(
          new Response(JSON.stringify(reply), {
            headers: { "Content-Type": "application/json" },
          }),
        );
      };
      const result = await sourceRetirementRoute(request(), authenticated);
      assertEquals(result.status, 200);
      assertEquals(result.headers.get("Cache-Control"), "private, no-store");
      assertEquals(await result.json(), reply);
      assertEquals(calls, 1);
    });
  });
}
Deno.test("source retirement HTTP holds malformed, foreign, lost and database error answers without retry", async () => {
  await environment(async () => {
    for (
      const reply of [
        () =>
          Promise.resolve(
            new Response(
              JSON.stringify({
                ...retired,
                owner_id: "00000000-0000-4000-8000-000000000091",
              }),
            ),
          ),
        () =>
          Promise.resolve(
            new Response(JSON.stringify({ ...retired, may_dispatch: true })),
          ),
        () => Promise.resolve(new Response("{}")),
        () =>
          Promise.resolve(
            new Response(
              JSON.stringify({ message: "private database detail" }),
              { status: 503 },
            ),
          ),
        () => Promise.reject(new Error("private lost reply detail")),
      ]
    ) {
      let calls = 0;
      globalThis.fetch = () => {
        calls++;
        return reply();
      };
      const result = await sourceRetirementRoute(request(), authenticated);
      assertEquals(result.status, 503);
      const text = await result.text();
      assert(!text.includes("private database detail"));
      assert(!text.includes("private lost reply detail"));
      assert(!text.includes("retired"));
      assertEquals(calls, 1);
    }
  });
});
Deno.test("source retirement HTTP bounds actual upstream bytes even without content length", async () => {
  await environment(async () => {
    let cancelled = false;
    let calls = 0;
    globalThis.fetch = () => {
      calls++;
      return Promise.resolve(
        new Response(
          new ReadableStream<Uint8Array>({
            pull(controller) {
              controller.enqueue(new Uint8Array(2049));
            },
            cancel() {
              cancelled = true;
            },
          }),
        ),
      );
    };
    const result = await sourceRetirementRoute(request(), authenticated);
    assertEquals(result.status, 503);
    await result.body?.cancel();
    assertEquals(calls, 1);
    assert(cancelled);
  });
});

Deno.test("source retirement HTTP preserves conflict without release or replacement authority", async () => {
  await environment(async () => {
    let calls = 0;
    globalThis.fetch = () => {
      calls++;
      return Promise.resolve(
        new Response(
          JSON.stringify({
            code: "P0001",
            message: "analysis_history_operation_conflict",
          }),
          { status: 400 },
        ),
      );
    };
    const result = await sourceRetirementRoute(request(), authenticated);
    assertEquals(result.status, 409);
    assert(
      (await result.text()).includes("analysis_history_operation_conflict"),
    );
    assertEquals(calls, 1);
  });
});
Deno.test("source retirement HTTP exits once on deadline despite uncooperative upstream", async () => {
  await environment(async () => {
    const originalTimeout = AbortSignal.timeout;
    const deadline = new AbortController();
    const budgets: number[] = [];
    let calls = 0;
    AbortSignal.timeout = (ms: number) => {
      budgets.push(ms);
      return deadline.signal;
    };
    globalThis.fetch = () => {
      calls++;
      queueMicrotask(() => deadline.abort());
      return new Promise(() => {});
    };
    try {
      const response = await sourceRetirementRoute(request(), authenticated);
      assertEquals(response.status, 503);
      await response.body?.cancel();
      assertEquals(calls, 1);
      assert(budgets.length > 0);
      assert(budgets.every((ms) => ms === 5000));
    } finally {
      AbortSignal.timeout = originalTimeout;
    }
  });
});
Deno.test("unfunded retirement HTTP accepts exact envelope byte cap and rejects one more byte", async () => {
  await environment(async () => {
    let calls = 0;
    globalThis.fetch = () => {
      calls++;
      return Promise.resolve(new Response(JSON.stringify(retired)));
    };
    const raw = JSON.stringify(envelope);
    const padded = raw +
      " ".repeat(1_048_663 - new TextEncoder().encode(raw).length);
    for (
      const [body, status] of [[padded, 200], [padded + " ", 413]] as const
    ) {
      const response = await sourceRetirementRoute(
        new Request("https://synthetic.invalid", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body,
        }),
        authenticated,
      );
      assertEquals(response.status, status);
      await response.body?.cancel();
    }
    assertEquals(calls, 1);
  });
});
Deno.test("unfunded retirement explicit recovery retains full candidate and original operation after loss", async () => {
  await environment(async () => {
    const bodies: unknown[] = [];
    globalThis.fetch = (_url, init) => {
      bodies.push(JSON.parse(String(init?.body)));
      return bodies.length === 1
        ? Promise.reject(new Error("lost after commit"))
        : Promise.resolve(new Response(JSON.stringify(retired)));
    };
    const first = await sourceRetirementRoute(request(), authenticated);
    assertEquals(first.status, 503);
    await first.body?.cancel();
    assertEquals(bodies.length, 1);
    const recovered = await sourceRetirementRoute(request(), authenticated);
    assertEquals(recovered.status, 200);
    assertEquals(await recovered.json(), retired);
    assertEquals(bodies.length, 2);
    assertEquals(bodies[0], bodies[1]);
  });
});
Deno.test("unfunded retirement HTTP rejects SQL tuples, UUID aliases and foreign response variants", async () => {
  await environment(async () => {
    let calls = 0;
    globalThis.fetch = () => {
      calls++;
      return Promise.resolve(new Response(JSON.stringify(retired)));
    };
    for (
      const body of [
        { ...identity, operation_id: operation },
        { ...envelope, schema_version: 2 },
        { ...envelope, operation_id: identity.analysis_id },
        { ...envelope, operation_id: identity.source_analysis_id },
        { ...envelope, operation_id: identity.observation_id },
        { ...envelope, candidate: { ...candidate, fingerprint_version: 2 } },
      ]
    ) {
      const response = await sourceRetirementRoute(
        request(body),
        authenticated,
      );
      assertEquals(response.status, 400);
      await response.body?.cancel();
    }
    assertEquals(calls, 0);
    for (
      const state of [
        "retired_before_dispatch",
        "reserved",
        "held",
        "unavailable",
      ]
    ) {
      globalThis.fetch = () => {
        calls++;
        return Promise.resolve(
          new Response(JSON.stringify({ ...retired, state })),
        );
      };
      const response = await sourceRetirementRoute(request(), authenticated);
      assertEquals(response.status, 503);
      await response.body?.cancel();
    }
    assertEquals(calls, 4);
  });
});
