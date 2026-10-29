import { assertEquals, assertRejects, assertThrows } from "@std/assert";
import { createCpmPhotoClosureDb } from "./cpmPhotoClosureDb.ts";
import { initialCanonicalText } from "./canonical.ts";
import { initialMediaHash } from "./mediaBinding.ts";
import {
  closeInitialCpmPhotoWrite,
  cpmClosureTimestamp,
  type CpmWriteClosureInput,
} from "./cpmPhotoWriteClosure.ts";

const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const signal = () => new AbortController().signal;
const receipt = (marker = false) => ({
  attempt_id: id(1),
  outcome: marker ? "retired_marker" as const : "live_object" as const,
  policy_digest: "b".repeat(64),
  observed_at: "2026-01-01T00:00:01.123456Z",
  claim_digest: marker ? "c".repeat(64) : null,
});
async function environment(run: () => void | Promise<void>) {
  const names = ["SUPABASE_URL", "SUPABASE_SERVER_API_KEY"];
  const saved = names.map((name) => Deno.env.get(name));
  try {
    Deno.env.set(names[0], "https://trusted.invalid");
    Deno.env.set(names[1], "sb_secret_" + "x".repeat(40));
    await run();
  } finally {
    names.forEach((name, i) =>
      saved[i] === undefined
        ? Deno.env.delete(name)
        : Deno.env.set(name, saved[i]!)
    );
  }
}
async function snapshot(marker = false): Promise<CpmWriteClosureInput> {
  const configuration = {
    generation: id(4),
    provider: "r2",
    direct_endpoint:
      "https://00000000000000000000000000000000.r2.cloudflarestorage.com",
    private_bucket: "synthetic-private",
    namespace: "initial-preparation/v2",
    credential_profile: "synthetic_only",
    storage_protocol: "conditional_create_permanent_same_key_marker_v1",
  };
  const digest = await initialMediaHash(new TextEncoder().encode(
    `merian.initial-analysis.media.backend.v1\n${
      initialCanonicalText(configuration)
    }`,
  ));
  const now = Date.now();
  return {
    binding: {
      attempt_id: id(1),
      scan_id: id(2),
      object_id: id(3),
      assignment_digest: "a".repeat(64),
      backend_generation: id(4),
      backend_configuration_digest: digest,
      issued_at_ms: now - 1000,
      verification_policy_digest: "b".repeat(64),
    },
    target: marker ? { outcome: "retired_marker" } : {
      outcome: "live_object",
      role: "source",
      byte_count: 4,
      sha256: "a".repeat(64),
      content_type: "image/jpeg",
    },
    backend: { ...configuration, configuration_digest: digest },
    admission_expires_at_ms: now + 30_000,
    erasure_claim: marker
      ? { token: id(5), issued_at_ms: now - 1000, expires_at_ms: now + 59_000 }
      : null,
  };
}
const reply = (value: unknown) =>
  Promise.resolve(new Response(JSON.stringify(value)));

Deno.test("CPM receipt timestamps preserve microseconds and reject normalized dates", () => {
  assertEquals(
    cpmClosureTimestamp(receipt().observed_at),
    receipt().observed_at,
  );
  for (
    const invalid of [
      "2026-01-01T00:00:01.123Z",
      "2026-01-01T00:00:01.1234567Z",
      "2026-01-01T00:00:01.123456+00:00",
      "2026-02-30T00:00:00.000000Z",
      "0000-01-01T00:00:00.000000Z",
      "infinity",
      123,
    ]
  ) {
    assertThrows(() => cpmClosureTimestamp(invalid));
  }
});
Deno.test("CPM database pins destination and opaque credentials with one historical read", () =>
  environment(async () => {
    const calls: string[] = [];
    const db = createCpmPhotoClosureDb(null, (url, init) => {
      calls.push(String(url));
      assertEquals(init?.redirect, "error");
      assertEquals(init?.cache, "no-store");
      assertEquals(init?.credentials, "omit");
      assertEquals(init?.method, "POST");
      assertEquals(new Headers(init?.headers).has("authorization"), false);
      assertEquals(
        new Headers(init?.headers).get("apikey"),
        "sb_secret_" + "x".repeat(40),
      );
      assertEquals(JSON.parse(String(init?.body)), {
        p_attempt: id(1),
        p_outcome: "retired_marker",
      });
      return reply(receipt(true));
    });
    Deno.env.set("SUPABASE_URL", "https://changed.invalid");
    Deno.env.set("SUPABASE_SERVER_API_KEY", "sb_secret_" + "y".repeat(40));
    const result = await closeInitialCpmPhotoWrite(
      {
        bridge: db,
        storage: {
          sign: () => {
            throw new Error("historical replay must not sign");
          },
          fetch: () => {
            throw new Error("historical replay must not fetch");
          },
        },
      },
      id(1),
      "retired_marker",
      signal(),
    );
    assertEquals(result, { outcome: "replay", receipt: receipt(true) });
    assertEquals(calls, [
      "https://trusted.invalid/rest/v1/rpc/read_initial_cpm_photo_write_closure",
    ]);
  }));
Deno.test("CPM database rejects unsafe configured destinations before requests", () =>
  environment(() => {
    for (
      const url of [
        "https://user:password@trusted.invalid",
        "https://trusted.invalid/path",
        "http://remote.invalid",
        "https://trusted.invalid/?q=1",
        "https://trusted.invalid/#x",
      ]
    ) {
      Deno.env.set("SUPABASE_URL", url);
      assertThrows(() => createCpmPhotoClosureDb(null));
    }
  }));
Deno.test("CPM database load and recheck preserve original claim and whole snapshot", () =>
  environment(async () => {
    for (const marker of [false, true]) {
      const value = await snapshot(marker),
        sent: Record<string, unknown>[] = [];
      const db = createCpmPhotoClosureDb(marker ? id(5) : null, (url, init) => {
        assertEquals(
          new URL(String(url)).pathname,
          "/rest/v1/rpc/read_initial_cpm_photo_observation",
        );
        sent.push(JSON.parse(String(init?.body)));
        return reply(value);
      });
      const captured = await db.load(
        id(1),
        marker ? "retired_marker" : "live_object",
        signal(),
      );
      await db.requireCurrent(captured, signal());
      assertEquals(sent[0].p_expected, null);
      assertEquals(sent[1].p_expected, value);
      assertEquals(sent.map((s) => s.p_claim), [
        marker ? id(5) : null,
        marker ? id(5) : null,
      ]);
      for (
        const part of [
          captured,
          captured.binding,
          captured.target,
          captured.backend,
        ]
      ) assertEquals(Object.isFrozen(part), true);
    }
  }));
Deno.test("CPM fresh marker work cannot discover or replace the original token", () =>
  environment(async () => {
    let calls = 0;
    const missing = createCpmPhotoClosureDb(null, () => {
      ++calls;
      return reply(null);
    });
    await assertRejects(() => missing.load(id(1), "retired_marker", signal()));
    assertEquals(calls, 0);
    const value = await snapshot(true);
    value.erasure_claim!.token = id(6);
    const replaced = createCpmPhotoClosureDb(id(5), () => {
      ++calls;
      return reply(value);
    });
    await assertRejects(() => replaced.load(id(1), "retired_marker", signal()));
    assertEquals(calls, 1);
  }));
Deno.test("CPM database rejects malformed or changed authoritative snapshots", () =>
  environment(async () => {
    const original = await snapshot();
    for (
      const mutation of [
        { ...original, extra: true },
        { ...original, binding: { ...original.binding, object_id: "bad" } },
        { ...original, target: { ...original.target, byte_count: 33_554_433 } },
        {
          ...original,
          backend: { ...original.backend, private_bucket: "changed" },
        },
        {
          ...original,
          erasure_claim: { token: id(5), issued_at_ms: 1, expires_at_ms: 2 },
        },
      ]
    ) {
      const db = createCpmPhotoClosureDb(null, () => reply(mutation));
      await assertRejects(() => db.load(id(1), "live_object", signal()));
    }
    const db = createCpmPhotoClosureDb(
      null,
      () =>
        reply({
          ...original,
          admission_expires_at_ms: original.admission_expires_at_ms + 1,
        }),
    );
    await assertRejects(() => db.requireCurrent(original, signal()));
  }));
Deno.test("CPM database settlement transmits and checks exact original microseconds", () =>
  environment(async () => {
    const expected = receipt();
    let calls = 0;
    const db = createCpmPhotoClosureDb(null, (url, init) => {
      ++calls;
      assertEquals(
        new URL(String(url)).pathname,
        "/rest/v1/rpc/settle_initial_cpm_photo_write_closure",
      );
      assertEquals(JSON.parse(String(init?.body)), {
        p_attempt: id(1),
        p_outcome: "live_object",
        p_policy: expected.policy_digest,
        p_observed_at: expected.observed_at,
        p_claim: null,
      });
      return reply(expected);
    });
    assertEquals(await db.settle(expected, null, signal()), expected);
    assertEquals(calls, 1);
    const rounded = createCpmPhotoClosureDb(
      null,
      () => reply({ ...expected, observed_at: "2026-01-01T00:00:01.123000Z" }),
    );
    await assertRejects(() => rounded.settle(expected, null, signal()));
  }));
Deno.test("CPM database refuses wrong claim digest before settlement IO", () =>
  environment(async () => {
    let calls = 0;
    const db = createCpmPhotoClosureDb(id(5), () => {
      ++calls;
      return reply(receipt(true));
    });
    await assertRejects(() => db.settle(receipt(true), id(6), signal()));
    await assertRejects(() => db.settle(receipt(true), id(5), signal()));
    assertEquals(calls, 0);
    const expected = {
      ...receipt(true),
      claim_digest: await initialMediaHash(
        new TextEncoder().encode(
          `merian.initial-analysis.cpm-erasure-claim.v1\n${id(5)}`,
        ),
      ),
    };
    const exact = createCpmPhotoClosureDb(id(5), () => reply(expected));
    assertEquals(await exact.settle(expected, id(5), signal()), expected);
  }));
Deno.test("CPM database never retries HTTP failures or malformed receipts", () =>
  environment(async () => {
    for (
      const response of [
        () => new Response("{}", { status: 503 }),
        () => new Response("{}", { status: 401 }),
        () =>
          new Response("{}", {
            status: 302,
            headers: { location: "https://other.invalid" },
          }),
        () =>
          new Response(
            JSON.stringify({
              ...receipt(),
              observed_at: "2026-01-01T00:00:01.123Z",
            }),
          ),
        () => new Response(JSON.stringify([receipt()])),
        () => new Response(new Uint8Array(8193)),
        () => new Response(new Uint8Array([255])),
      ]
    ) {
      let calls = 0;
      const db = createCpmPhotoClosureDb(null, () => {
        ++calls;
        return Promise.resolve(response());
      });
      await assertRejects(() => db.readReceipt(id(1), "live_object", signal()));
      assertEquals(calls, 1);
    }
  }));
Deno.test("CPM database cancellation discards late response without another call", () =>
  environment(async () => {
    const controller = new AbortController();
    let calls = 0, cancelled = false;
    let release!: (response: Response) => void;
    let started!: () => void;
    const begun = new Promise<void>((r) => {
      started = r;
    });
    const db = createCpmPhotoClosureDb(null, () => {
      ++calls;
      started();
      return new Promise<Response>((r) => {
        release = r;
      });
    });
    const pending = db.readReceipt(id(1), "live_object", controller.signal);
    await begun;
    controller.abort();
    await assertRejects(() => pending);
    release(
      new Response(
        new ReadableStream({
          cancel() {
            cancelled = true;
          },
        }),
      ),
    );
    await new Promise((r) => setTimeout(r, 0));
    assertEquals(calls, 1);
    assertEquals(cancelled, true);
  }));

Deno.test("CPM production bridge recovers a lost settlement acknowledgement without repeating storage", () =>
  environment(async () => {
    const input = await snapshot();
    const bytes = new Uint8Array([255, 216, 255, 1]);
    if (input.target.outcome !== "live_object") throw new Error("fixture");
    input.target.sha256 = await initialMediaHash(bytes);
    let saved: ReturnType<typeof receipt> | null = null;
    const operations: string[] = [];
    const db = createCpmPhotoClosureDb(null, (url, init) => {
      const operation = new URL(String(url)).pathname.split("/").at(-1)!;
      operations.push(operation);
      const args = JSON.parse(String(init?.body));
      if (operation === "read_initial_cpm_photo_write_closure") {
        return reply(saved);
      }
      if (operation === "read_initial_cpm_photo_observation") {
        assertEquals(
          args.p_expected === null ||
            initialCanonicalText(args.p_expected) ===
              initialCanonicalText(input),
          true,
        );
        return reply(input);
      }
      if (operation !== "settle_initial_cpm_photo_write_closure") {
        throw new Error("unexpected RPC");
      }
      saved = {
        attempt_id: args.p_attempt,
        policy_digest: args.p_policy,
        observed_at: args.p_observed_at,
        outcome: args.p_outcome,
        claim_digest: null,
      };
      return Promise.reject(new Error("synthetic lost acknowledgement"));
    });
    let reads = 0;
    const result = await closeInitialCpmPhotoWrite(
      {
        bridge: db,
        storage: {
          sign: (_profile, request) => Promise.resolve(request),
          fetch: () => {
            ++reads;
            return Promise.resolve(
              new Response(bytes, {
                headers: {
                  "content-type": "image/jpeg",
                  "content-length": "4",
                  "cache-control": "private, no-store",
                },
              }),
            );
          },
        },
      },
      id(1),
      "live_object",
      signal(),
    );
    assertEquals(result.outcome, "replay");
    assertEquals<unknown>(result.receipt, saved);
    assertEquals(reads, 1);
    assertEquals(
      operations.filter((x) => x === "settle_initial_cpm_photo_write_closure")
        .length,
      1,
    );
    assertEquals(
      operations.filter((x) => x === "read_initial_cpm_photo_write_closure")
        .length,
      2,
    );
    assertEquals(operations[0], "read_initial_cpm_photo_write_closure");
  }));
