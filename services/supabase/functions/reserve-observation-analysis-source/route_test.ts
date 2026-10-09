import { assert, assertEquals } from "@std/assert";
import type { User } from "@supabase/supabase-js";
import { sourceReservationRoute } from "./route.ts";
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
const reserved = { ...identity, owner_id: owner, state: "reserved" };
const authenticated = () =>
  Promise.resolve({ user: { id: owner } as User, response: null });
const request = (body: unknown = candidate) =>
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
Deno.test("source reservation route denies auth/method/invalid and oversized bodies before RPC", async () => {
  await environment(async () => {
    let calls = 0;
    globalThis.fetch = () => {
      calls++;
      throw new Error("unexpected transport");
    };
    const denied = await sourceReservationRoute(
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
        [request({ ...candidate, owner_id: owner }), 400],
        [request({ ...candidate, fingerprint: "f".repeat(64) }), 400],
        [request("x".repeat(1_048_576)), 413],
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
      const result = await sourceReservationRoute(req, authenticated);
      assertEquals(result.status, status);
      assertEquals(result.headers.get("Cache-Control"), "private, no-store");
      await result.body?.cancel();
    }
    assertEquals(calls, 0);
  });
});
for (
  const reply of [reserved, {
    schema_version: 1,
    owner_id: owner,
    observation_id: identity.observation_id,
    source_analysis_id: identity.source_analysis_id,
    state: "held",
    reason: "source_occupied",
  }, {
    schema_version: 1,
    owner_id: owner,
    observation_id: identity.observation_id,
    source_analysis_id: identity.source_analysis_id,
    state: "unavailable",
  }]
) {
  Deno.test(`source reservation HTTP returns exact ${reply.state} observation with one owner-scoped RPC`, async () => {
    await environment(async () => {
      let calls = 0;
      globalThis.fetch = (url, init) => {
        calls++;
        assert(
          String(url).endsWith(
            "/rest/v1/rpc/reserve_owned_observation_analysis_source",
          ),
        );
        assertEquals(init?.method, "POST");
        assertEquals(JSON.parse(String(init?.body)), {
          p_owner: owner,
          p_request: candidate,
          p_reader: 11,
        });
        assert(init?.signal);
        return Promise.resolve(
          new Response(JSON.stringify(reply), {
            headers: { "Content-Type": "application/json" },
          }),
        );
      };
      const result = await sourceReservationRoute(request(), authenticated);
      assertEquals(result.status, 200);
      assertEquals(result.headers.get("Cache-Control"), "private, no-store");
      assertEquals(await result.json(), reply);
      assertEquals(calls, 1);
    });
  });
}
Deno.test("source reservation HTTP holds malformed, foreign, lost and database error answers without retry", async () => {
  await environment(async () => {
    for (
      const reply of [
        () =>
          Promise.resolve(
            new Response(
              JSON.stringify({
                ...reserved,
                owner_id: "00000000-0000-4000-8000-000000000091",
              }),
            ),
          ),
        () =>
          Promise.resolve(
            new Response(JSON.stringify({ ...reserved, may_dispatch: true })),
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
      const result = await sourceReservationRoute(request(), authenticated);
      assertEquals(result.status, 503);
      const text = await result.text();
      assert(!text.includes("private database detail"));
      assert(!text.includes("private lost reply detail"));
      assert(!text.includes("retired"));
      assertEquals(calls, 1);
    }
  });
});
Deno.test("source reservation HTTP bounds actual upstream bytes even without content length", async () => {
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
    const result = await sourceReservationRoute(request(), authenticated);
    assertEquals(result.status, 503);
    await result.body?.cancel();
    assertEquals(calls, 1);
    assert(cancelled);
  });
});

Deno.test("source reservation HTTP preserves conflict without release or replacement authority", async () => {
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
    const result = await sourceReservationRoute(request(), authenticated);
    assertEquals(result.status, 409);
    assert(
      (await result.text()).includes("analysis_history_operation_conflict"),
    );
    assertEquals(calls, 1);
  });
});
Deno.test("source reservation HTTP exits once on deadline despite uncooperative upstream", async () => {
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
      const response = await sourceReservationRoute(request(), authenticated);
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
