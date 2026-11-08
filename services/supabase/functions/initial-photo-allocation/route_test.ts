import { assertEquals, assertRejects } from "@std/assert";
import type { User } from "@supabase/supabase-js";
import { initialPhotoAllocationRoute } from "./route.ts";
import { initialPhotoAllocation } from "./handler.ts";
import { allocationRepository } from "./db.ts";
import { ALLOCATION_BODY_LIMIT, parseAllocationRequest } from "./contract.ts";
import { allocated, create, status } from "./fixtures.ts";
import assignment from "../_shared/initialAnalysis/fixtures/cpm-photo-assignment-v1.json" with {
  type: "json",
};
const owner = "00000000-0000-4000-8000-000000000001";
const authenticated = () =>
  Promise.resolve({ user: { id: owner } as User, response: null });
const req = (body: unknown = create(), signal?: AbortSignal) =>
  new Request("https://synthetic.invalid/initial-photo-allocation", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
    signal,
  });
async function environment(work: () => Promise<void>) {
  const saved = new Map(
    ["SUPABASE_URL", "SUPABASE_SERVER_API_KEY"].map(
      (key) => [key, Deno.env.get(key)],
    ),
  );
  Deno.env.set("SUPABASE_URL", "https://synthetic.invalid");
  Deno.env.set(
    "SUPABASE_SERVER_API_KEY",
    "sb_secret_" + "synthetic_test_only".repeat(3),
  );
  try {
    await work();
  } finally {
    for (const [key, value] of saved) {
      if (value === undefined) Deno.env.delete(key);
      else Deno.env.set(key, value);
    }
  }
}
Deno.test("photo authenticated route fixes owner and one RPC per create/status; no assignment escapes", async () => {
  await environment(async () => {
    const original = globalThis.fetch;
    try {
      for (
        const body of [
          create(),
          status(),
          status(allocated().assignment_digest),
          { ...create(), version: 2 },
          { ...status(allocated().assignment_digest), version: 2 },
          { ...create(), version: 3 },
          { ...status(allocated().assignment_digest), version: 3 },
        ]
      ) {
        let calls = 0;
        globalThis.fetch = (url, init) => {
          calls++;
          assertEquals(
            String(url),
            "https://synthetic.invalid/rest/v1/rpc/" +
              (body.version === 3
                ? (body.action === "create"
                  ? "create_initial_cpm_photo_v3_allocation"
                  : "get_initial_cpm_photo_v3_status")
                : (body.action === "create"
                  ? "create_initial_preparation_intent"
                  : "get_initial_preparation_status")),
          );
          assertEquals(JSON.parse(String(init?.body)), {
            p_owner: owner,
            p_scan: parseAllocationRequest(body).scanID,
            ...(body.action === "create"
              ? { p_candidate: body.candidate_canonical }
              : {}),
          });
          assertEquals(init?.redirect, "error");
          assertEquals(init?.cache, "no-store");
          assertEquals(init?.credentials, "omit");
          return Promise.resolve(
            new Response(
              JSON.stringify(
                body.version === 3
                  ? {
                    ...allocated(),
                    version: 3,
                    backend_generation:
                      assignment.assignment.preparation.backend_generation,
                    backend_configuration_digest: "c".repeat(64),
                  }
                  : allocated(),
              ),
              { status: 200 },
            ),
          );
        };
        const response = await initialPhotoAllocationRoute(
          req(body),
          authenticated,
        );
        assertEquals(response.status, 200);
        assertEquals(
          response.headers.get("Cache-Control"),
          "private, no-store",
        );
        const receipt = await response.json();
        assertEquals(receipt.version, body.version);
        assertEquals("role_mapping" in receipt, body.version >= 2);
        assertEquals(receipt.assignment_digest, allocated().assignment_digest);
        assertEquals("assignment_canonical" in receipt, false);
        assertEquals("configuration" in receipt, false);
        assertEquals(calls, 1);
      }
    } finally {
      globalThis.fetch = original;
    }
  });
});
Deno.test("photo route auth/method/body/closed request failures never allocate", async () => {
  await environment(async () => {
    const original = globalThis.fetch;
    let calls = 0;
    globalThis.fetch = () => {
      calls++;
      throw new Error("unexpected network");
    };
    try {
      for (
        const [request, expected] of [
          [
            new Request("https://synthetic.invalid", { method: "OPTIONS" }),
            200,
          ],
          [new Request("https://synthetic.invalid"), 405],
          [
            new Request("https://synthetic.invalid", {
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body: "{",
            }),
            400,
          ],
          [req({ ...create(), owner_id: owner }), 400],
          [req("x".repeat(ALLOCATION_BODY_LIMIT)), 413],
        ] as const
      ) {
        const response = await initialPhotoAllocationRoute(
          request,
          authenticated,
        );
        assertEquals(response.status, expected);
        assertEquals(
          response.headers.get("Cache-Control"),
          "private, no-store",
        );
        await response.body?.cancel();
      }
      const denied = await initialPhotoAllocationRoute(
        req(),
        () =>
          Promise.resolve({
            user: null,
            response: new Response(null, { status: 401 }),
          }),
      );
      assertEquals(denied.status, 401);
      await denied.body?.cancel();
      assertEquals(calls, 0);
    } finally {
      globalThis.fetch = original;
    }
  });
});
Deno.test("photo route missing/foreign/deleted collapse to holds; SQL failures and lost replies never retry", async () => {
  await environment(async () => {
    const original = globalThis.fetch;
    try {
      for (const version of [1, 2, 3]) {
        for (
          const [wireStatus, wireBody, expected] of [
            [404, { code: "P0002", message: "private owner diagnostic" }, 200],
            [500, { message: "private SQL diagnostic" }, 503],
            [200, { ...allocated(), assignment_digest: "0".repeat(64) }, 503],
            [200, null, 503],
            [401, { message: "private auth" }, 503],
            [429, { message: "private capacity" }, 503],
          ] as const
        ) {
          let calls = 0;
          globalThis.fetch = () => {
            calls++;
            return Promise.resolve(
              new Response(JSON.stringify(wireBody), { status: wireStatus }),
            );
          };
          const response = await initialPhotoAllocationRoute(
            req({ ...status(), version }),
            authenticated,
          );
          assertEquals(response.status, expected);
          const result = await response.json();
          assertEquals(JSON.stringify(result).includes("private"), false);
          if (expected === 200) {
            assertEquals(result.outcome, "terminal_held");
            assertEquals(result.reason, "not_found");
            assertEquals(result.authority, "none");
          }
          assertEquals(calls, 1);
        }
      }
      let calls = 0;
      globalThis.fetch = () => {
        calls++;
        return Promise.reject(new Error("lost acknowledgement"));
      };
      const response = await initialPhotoAllocationRoute(req(), authenticated);
      assertEquals(response.status, 503);
      await response.body?.cancel();
      assertEquals(calls, 1);
    } finally {
      globalThis.fetch = original;
    }
  });
});
Deno.test("photo allocation checks cancellation before send and discards a late reply", async () => {
  for (const abortBefore of [true, false]) {
    const controller = new AbortController();
    if (abortBefore) controller.abort();
    let calls = 0;
    const response = await initialPhotoAllocation(
      req(create(), controller.signal),
      create(),
      owner,
      {
        call: () => {
          calls++;
          controller.abort();
          return Promise.resolve(allocated());
        },
      },
    );
    assertEquals(response.status, 503);
    await response.body?.cancel();
    assertEquals(calls, abortBefore ? 0 : 1);
  }
});
Deno.test("photo service transport bounds response, rejects credential destinations and pre-aborted work", async () => {
  await environment(async () => {
    for (
      const origin of [
        "https://synthetic.invalid/path",
        "https://user:pass@synthetic.invalid",
        "http://synthetic.invalid",
        "https://synthetic.invalid?x=1",
      ]
    ) {
      Deno.env.set("SUPABASE_URL", origin);
      let rejected = false;
      try {
        allocationRepository();
      } catch {
        rejected = true;
      }
      assertEquals(rejected, true);
    }
    Deno.env.set("SUPABASE_URL", "https://synthetic.invalid");
    let calls = 0;
    const repository = allocationRepository(() => {
      calls++;
      return Promise.resolve(new Response("x".repeat(524289)));
    });
    const signal = new AbortController();
    signal.abort();
    await assertRejects(() =>
      repository.call(owner, parseAllocationRequest(create()), signal.signal)
    );
    assertEquals(calls, 0);
    await assertRejects(() =>
      repository.call(
        owner,
        parseAllocationRequest(create()),
        new AbortController().signal,
      )
    );
    assertEquals(calls, 1);
  });
});
