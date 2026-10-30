import { assert, assertEquals } from "@std/assert";
import type { User } from "@supabase/supabase-js";
import { publicErrorResponse } from "../_shared/http.ts";
import { initialPhotoTransferRoute } from "./route.ts";
import { transferPolicyCatalog } from "./catalog.ts";
import { TRANSFER_BODY_LIMIT } from "./contract.ts";
import { attempt, fixture, owner } from "./fixtures.ts";

const authenticated = () =>
  Promise.resolve({ user: { id: owner } as User, response: null });
const req = (body: unknown, contentType = "application/json") =>
  new Request("https://synthetic.invalid/initial-photo-transfer", {
    method: "POST",
    headers: { "Content-Type": contentType },
    body: JSON.stringify(body),
  });
async function environment(work: () => Promise<void>) {
  const keys = ["SUPABASE_URL", "SUPABASE_SERVER_API_KEY"];
  const saved = new Map(keys.map((key) => [key, Deno.env.get(key)]));
  Deno.env.set("SUPABASE_URL", "https://synthetic.invalid");
  Deno.env.set(
    "SUPABASE_SERVER_API_KEY",
    "sb_secret_" + "synthetic_test_only".repeat(3),
  );
  const previous = globalThis.fetch;
  try {
    await work();
  } finally {
    globalThis.fetch = previous;
    for (const [key, value] of saved) {
      if (value === undefined) Deno.env.delete(key);
      else Deno.env.set(key, value);
    }
  }
}

Deno.test("dormant authenticated facade uses exact existing RPCs and verified owner", async () => {
  await environment(async () => {
    for (const role of [0, 1, 2]) {
      const f = await fixture(role), calls: string[] = [];
      globalThis.fetch = (url, init) => {
        const operation = String(url).split("/").at(-1)!;
        calls.push(operation);
        assertEquals(init?.method, "POST");
        assertEquals(init?.redirect, "error");
        assertEquals(init?.cache, "no-store");
        assertEquals(init?.credentials, "omit");
        const body = JSON.parse(String(init?.body));
        if (operation === "get_initial_cpm_photo_v3_status") {
          assertEquals(body, { p_owner: owner, p_scan: f.request.scan_id });
          return Promise.resolve(Response.json(f.recovered));
        }
        if (operation === "begin_initial_cpm_photo_write") {
          assertEquals(body, {
            p_owner: owner,
            p_scan: f.request.scan_id,
            p_digest: f.request.assignment_digest,
            p_object: f.request.object_id,
            p_policy: f.entry.policy_digest,
          });
          return Promise.resolve(Response.json(f.fresh));
        }
        assertEquals(operation, "read_initial_cpm_photo_observation");
        assertEquals(body, {
          p_attempt: attempt,
          p_outcome: "live_object",
          p_claim: null,
          p_expected: f.fresh.observation,
        });
        return Promise.resolve(Response.json(f.fresh.observation));
      };
      const response = await initialPhotoTransferRoute(
        req(f.request),
        f.deps.catalog,
        authenticated,
      );
      assertEquals(response.status, 200);
      assertEquals(response.headers.get("X-Merian-Handler"), "1");
      assertEquals(response.headers.get("Cache-Control"), "private, no-store");
      const result = await response.json();
      assertEquals(result.outcome, "issued");
      assertEquals(result.role, f.fresh.observation.target.role);
      for (
        const forbidden of [
          "owner",
          "candidate_canonical",
          "assignment_canonical",
          "access_key_id",
          "secret_access_key",
          "policy",
        ]
      ) {
        assertEquals(Object.hasOwn(result, forbidden), false);
      }
      assertEquals(calls, [
        "get_initial_cpm_photo_v3_status",
        "begin_initial_cpm_photo_write",
        "read_initial_cpm_photo_observation",
        "read_initial_cpm_photo_observation",
      ]);
    }
  });
});

Deno.test("dormant route lost RPC reply recovers status after catalog removal with no reissue", async () => {
  await environment(async () => {
    const f = await fixture(), calls: string[] = [];
    globalThis.fetch = (url, init) => {
      const operation = String(url).split("/").at(-1)!;
      calls.push(operation);
      if (operation === "get_initial_cpm_photo_v3_status") {
        return Promise.resolve(Response.json(f.recovered));
      }
      if (operation === "begin_initial_cpm_photo_write") {
        return Promise.resolve(new Response("{", { status: 200 }));
      }
      assertEquals(operation, "read_initial_cpm_photo_write_status");
      assertEquals(JSON.parse(String(init?.body)), {
        p_owner: owner,
        p_scan: f.request.scan_id,
        p_digest: f.request.assignment_digest,
        p_object: f.request.object_id,
      });
      return Promise.resolve(
        Response.json({
          version: 1,
          authority: "none",
          scan_id: f.request.scan_id,
          assignment_digest: f.request.assignment_digest,
          object_id: f.request.object_id,
          attempt: {
            attempt_id: attempt,
            state: "may_have_issued",
            created_at_ms: f.fresh.created_at_ms,
            capability_expires_at_ms: f.fresh.capability_expires_at_ms,
            write_closed: false,
          },
        }),
      );
    };
    assertEquals(
      (await initialPhotoTransferRoute(
        req(f.request),
        f.deps.catalog,
        authenticated,
      )).status,
      503,
    );
    const result = await initialPhotoTransferRoute(
      req(f.status),
      transferPolicyCatalog([]),
      authenticated,
    );
    assertEquals(result.status, 200);
    assertEquals((await result.json()).attempt.attempt_id, attempt);
    assertEquals(calls, [
      "get_initial_cpm_photo_v3_status",
      "begin_initial_cpm_photo_write",
      "read_initial_cpm_photo_write_status",
    ]);
  });
});

Deno.test("dormant route authenticates and bounds input before dependency work", async () => {
  await environment(async () => {
    const f = await fixture();
    let calls = 0;
    const dependencies = () => {
      calls++;
      return f.deps;
    };
    const denied = (request: Request) =>
      Promise.resolve({
        user: null,
        response: publicErrorResponse(
          request,
          401,
          "unauthorized",
          "Authentication required.",
        ),
      });
    assertEquals(
      (await initialPhotoTransferRoute(
        req(f.request),
        f.deps.catalog,
        denied,
        dependencies,
      )).status,
      401,
    );
    assertEquals(
      (await initialPhotoTransferRoute(
        new Request("https://synthetic.invalid", { method: "GET" }),
        f.deps.catalog,
        authenticated,
        dependencies,
      )).status,
      405,
    );
    assertEquals(
      (await initialPhotoTransferRoute(
        req(f.request, "text/plain"),
        f.deps.catalog,
        authenticated,
        dependencies,
      )).status,
      415,
    );
    assertEquals(
      (await initialPhotoTransferRoute(
        req({ ...f.request, owner }),
        f.deps.catalog,
        authenticated,
        dependencies,
      )).status,
      400,
    );
    const large = req({
      candidate_canonical: "x".repeat(TRANSFER_BODY_LIMIT + 1),
    });
    assertEquals(
      (await initialPhotoTransferRoute(
        large,
        f.deps.catalog,
        authenticated,
        dependencies,
      )).status,
      413,
    );
    assertEquals(calls, 0);
  });
});

Deno.test("dormant route keeps SQL owner and policy denials opaque without retry", async () => {
  await environment(async () => {
    for (const stage of ["allocation", "begin", "status"]) {
      const f = await fixture(), calls: string[] = [];
      globalThis.fetch = (url) => {
        const operation = String(url).split("/").at(-1)!;
        calls.push(operation);
        if (
          operation === "get_initial_cpm_photo_v3_status" && stage === "begin"
        ) return Promise.resolve(Response.json(f.recovered));
        return Promise.resolve(
          Response.json({
            message: "synthetic private SQL policy/owner details",
          }, { status: 403 }),
        );
      };
      const response = await initialPhotoTransferRoute(
        req(stage === "status" ? f.status : f.request),
        f.deps.catalog,
        authenticated,
      );
      assertEquals(response.status, 503);
      assert(!JSON.stringify(await response.json()).includes("private SQL"));
      assertEquals(calls.length, stage === "begin" ? 2 : 1);
      assertEquals(new Set(calls).size, calls.length);
    }
  });
});
