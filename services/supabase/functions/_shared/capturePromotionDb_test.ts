import { assert, assertEquals, assertThrows } from "@std/assert";
import {
  type CapturePromotionTransfer,
  createCapturePromotionDb,
} from "./capturePromotionDb.ts";
import { captureObjectBackendDigest } from "./captureObjectRetirement.ts";

async function environment(run: () => Promise<void> | void) {
  const names = ["SUPABASE_URL", "SUPABASE_SERVER_API_KEY"];
  const saved = names.map((n) => Deno.env.get(n));
  try {
    Deno.env.set(names[0], "https://database.invalid");
    Deno.env.set(names[1], "sb_secret_" + "x".repeat(40));
    await run();
  } finally {
    names.forEach((n, i) =>
      saved[i] === undefined ? Deno.env.delete(n) : Deno.env.set(n, saved[i]!)
    );
  }
}
const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const json = (value: unknown) =>
  new Response(JSON.stringify(value), {
    headers: { "Content-Type": "application/json" },
  });
const signal = () => new AbortController().signal;
async function fixture() {
  const backend = {
    endpoint: "https://storage.invalid",
    bucketName: "synthetic",
  };
  const bytes = new Uint8Array([1, 2, 3, 4]);
  const hash = [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))]
    .map((v) => v.toString(16).padStart(2, "0")).join("");
  const binding = {
    operationId: id(1),
    ownerId: id(2),
    scanId: id(3),
    assetId: id(4),
    sessionId: id(5),
    backendSHA256: await captureObjectBackendDigest(backend),
    sourceKey: `staging/${id(2)}/fixture.webp`,
    destinationKey: `public_uploads/free/${id(2)}/capture-promotion-${id(1)}`,
    contentType: "image/webp",
    byteCount: bytes.length,
    sha256: hash,
  };
  const input: CapturePromotionTransfer = {
    cohortId: id(6),
    operationId: id(1),
    manifestSHA256: "a".repeat(64),
    requestSHA256: "b".repeat(64),
    bindings: [binding],
  };
  const events: string[] = [];
  let issued = false, retired = false, target: Uint8Array | null = null;
  let saved: Record<string, unknown> | undefined;
  let fail = "", status = 200;
  let rpcHook:
    | ((
      name: string,
      args: Record<string, unknown>,
    ) => Promise<Response | undefined>)
    | undefined;
  let storageHook: ((request: Request) => void) | undefined;
  const rpc: typeof fetch = async (url, init) => {
    assertEquals(new URL(String(url)).origin, "https://database.invalid");
    assertEquals(init?.redirect, "error");
    assertEquals(init?.credentials, "omit");
    assertEquals(new Headers(init?.headers).get("Authorization"), null);
    assertEquals(
      new Headers(init?.headers).get("apikey"),
      "sb_secret_" + "x".repeat(40),
    );
    const name = String(url).split("/").at(-1)!;
    events.push(name);
    const args = JSON.parse(String(init?.body));
    const override = await rpcHook?.(name, args);
    if (override) return override;
    if (name === "register_capture_promotion_ingestion") {
      assertEquals(args.p_bindings, [binding]);
      assertEquals(args.p_manifest, "a".repeat(64));
      if (fail === "registration") {
        throw new Error("synthetic lost registration");
      }
      return json({
        cohortId: id(6),
        jobId: id(7),
        cohortSHA256: "c".repeat(64),
      });
    }
    assertEquals(args.p_binding, binding);
    if (retired) return new Response(null, { status: 500 });
    if (name === "authorize_capture_promotion_action") {
      const allowed = args.p_action === "read_destination" ? issued : !issued;
      if (args.p_action === "write_destination") issued = true;
      return json(allowed);
    }
    if (name === "authorize_capture_promotion_recovery") return json(issued);
    assertEquals(name, "record_capture_promotion_verification");
    saved ??= {
      operationId: id(1),
      cohortId: id(6),
      verifiedAt: "2026-11-20T15:00:00.123456+00:00",
      origin: args.p_origin,
    };
    if (fail === "receipt") throw new Error("synthetic lost receipt reply");
    return json(saved);
  };
  const storage = {
    backend,
    sign: (request: Request) => Promise.resolve(request),
    fetch: async (request: RequestInfo | URL, _init?: RequestInit) => {
      assert(request instanceof Request);
      events.push(request.method);
      storageHook?.(request);
      if (request.method === "PUT") {
        const content = new Uint8Array(await request.arrayBuffer());
        assertEquals(content, bytes);
        target ??= content;
        if (fail === "write") throw new Error("synthetic lost write reply");
        return new Response(null, { status });
      }
      const content = request.url.endsWith(binding.sourceKey) ? bytes : target;
      return content
        ? new Response(content.slice(), {
          headers: {
            "Content-Type": binding.contentType,
            "Content-Length": "4",
          },
        })
        : new Response(null, { status: 404 });
    },
  };
  const db = createCapturePromotionDb(rpc);
  return {
    input,
    binding,
    storage,
    events,
    db,
    run: (s = signal()) => db.transfer(input, storage, s),
    recover: (s = signal()) =>
      db.recover({ cohortId: id(6), binding }, storage, s),
    fail: (value: string) => fail = value,
    status: (value: number) => status = value,
    target: (value: Uint8Array) => target = value,
    retire: () => retired = true,
    rpcHook: (value: typeof rpcHook) => rpcHook = value,
    storageHook: (value: typeof storageHook) => storageHook = value,
  };
}

Deno.test("capture composition persists verified bytes and recovery preserves first receipt", () =>
  environment(async () => {
    const f = await fixture();
    const fresh = await f.run();
    assertEquals(fresh.outcome, "verified");
    assertEquals(f.events, [
      "register_capture_promotion_ingestion",
      "authorize_capture_promotion_action",
      "GET",
      "authorize_capture_promotion_action",
      "PUT",
      "authorize_capture_promotion_action",
      "GET",
      "record_capture_promotion_verification",
    ]);
    f.events.length = 0;
    assertEquals(await f.recover(), fresh);
    assertEquals(f.events, [
      "authorize_capture_promotion_recovery",
      "GET",
      "record_capture_promotion_verification",
    ]);
  }));
Deno.test("capture composition holds unknown writes/receipts then recovers without registration or PUT", () =>
  environment(async () => {
    for (const failure of ["write", "receipt"]) {
      const f = await fixture();
      f.fail(failure);
      assertEquals(await f.run(), { outcome: "held" });
      f.fail("");
      f.events.length = 0;
      const result = await f.recover();
      assertEquals(result.outcome, "verified");
      if (result.outcome === "verified") {
        assertEquals(
          result.receipt.origin,
          failure === "write" ? "destination_recovery" : "write_acknowledged",
        );
      }
      assertEquals(f.events, [
        "authorize_capture_promotion_recovery",
        "GET",
        "record_capture_promotion_verification",
      ]);
    }
  }));
Deno.test("capture composition never attests mismatched destination bytes", () =>
  environment(async () => {
    const f = await fixture();
    f.target(new Uint8Array([9, 9, 9, 9]));
    f.status(412);
    assertEquals(await f.run(), { outcome: "held" });
    assertEquals(await f.recover(), { outcome: "held" });
    assertEquals(
      f.events.includes("record_capture_promotion_verification"),
      false,
    );
  }));
Deno.test("capture composition records verified precondition failure with the correct origin", () =>
  environment(async () => {
    const f = await fixture();
    f.target(new Uint8Array([1, 2, 3, 4]));
    f.status(412);
    const result = await f.run();
    assertEquals(result.outcome, "verified");
    if (result.outcome === "verified") {
      assertEquals(result.receipt.origin, "write_precondition_failed");
    }
  }));
Deno.test("capture composition holds retirement between GET and receipt", () =>
  environment(async () => {
    const f = await fixture();
    f.storageHook((request) => {
      if (
        request.method === "GET" &&
        request.url.endsWith(f.binding.destinationKey)
      ) f.retire();
    });
    assertEquals(await f.run(), { outcome: "held" });
    f.events.length = 0;
    assertEquals(await f.recover(), { outcome: "held" });
    assertEquals(f.events, ["authorize_capture_promotion_recovery"]);
  }));
Deno.test("capture composition refuses missing write authority and uncertain registration before object I/O", () =>
  environment(async () => {
    const f = await fixture();
    assertEquals(await f.recover(), { outcome: "held" });
    f.fail("registration");
    assertEquals(await f.run(), { outcome: "held" });
    assertEquals(f.events.some((e) => e === "GET" || e === "PUT"), false);
  }));
Deno.test("capture composition closes registration and receipt response shapes", () =>
  environment(async () => {
    for (
      const response of [null, true, [], {}, {
        cohortId: id(99),
        jobId: id(7),
        cohortSHA256: "c".repeat(64),
      }, {
        cohortId: id(6),
        jobId: id(7),
        cohortSHA256: "c".repeat(64),
        extra: true,
      }]
    ) {
      const f = await fixture();
      f.rpcHook((name) =>
        Promise.resolve(
          name === "register_capture_promotion_ingestion"
            ? json(response)
            : undefined,
        )
      );
      assertEquals(await f.run(), { outcome: "held" });
      assertEquals(f.events.length, 1);
    }
    for (
      const changes of [
        { operationId: id(9) },
        { cohortId: id(9) },
        { verifiedAt: "yesterday" },
        { origin: "HEAD" },
        { origin: ["write_acknowledged"] },
        { verifiedAt: "2026-02-31T15:00:00Z" },
        { extra: true },
      ]
    ) {
      const f = await fixture();
      f.rpcHook((name) =>
        Promise.resolve(
          name === "record_capture_promotion_verification"
            ? json({
              operationId: id(1),
              cohortId: id(6),
              verifiedAt: "2026-11-20T15:00:00Z",
              origin: "write_acknowledged",
              ...changes,
            })
            : undefined,
        )
      );
      assertEquals(await f.run(), { outcome: "held" });
    }
  }));
Deno.test("capture composition refuses malformed or partial local identities before RPC", () =>
  environment(async () => {
    for (
      const change of [
        { bindings: [] },
        { bindings: Array(9).fill(null) },
        { cohortId: "bad" },
        { operationId: id(99) },
        { extra: true },
      ]
    ) {
      const f = await fixture();
      assertEquals(
        await f.db.transfer({ ...f.input, ...change }, f.storage, signal()),
        { outcome: "held" },
      );
      assertEquals(f.events, []);
    }
    const f = await fixture();
    assertEquals(
      await f.db.transfer(
        { ...f.input, bindings: [f.binding, f.binding] },
        f.storage,
        signal(),
      ),
      { outcome: "held" },
    );
    assertEquals(
      await f.db.recover(
        {
          cohortId: id(6),
          binding: {
            ...f.binding,
            destinationKey: `public_uploads/free/${id(2)}/arbitrary`,
          },
        },
        f.storage,
        signal(),
      ),
      { outcome: "held" },
    );
    assertEquals(f.events, []);
  }));
Deno.test("capture composition snapshots cohort and storage dependencies before the first await", () =>
  environment(async () => {
    const f = await fixture();
    const expected = structuredClone(f.binding);
    let release!: (r: Response) => void;
    f.rpcHook((name, args) => {
      if (name === "register_capture_promotion_ingestion") {
        assertEquals(args.p_bindings, [expected]);
        return new Promise((resolve) => release = resolve);
      }
      assertEquals(args.p_binding, expected);
      if (name === "authorize_capture_promotion_action") {
        return Promise.resolve(json(true));
      }
      return Promise.resolve(
        json({
          operationId: expected.operationId,
          cohortId: id(6),
          verifiedAt: "2026-11-20T15:00:00Z",
          origin: "write_acknowledged",
        }),
      );
    });
    const running = f.run();
    await new Promise((r) => setTimeout(r, 0));
    Object.assign(f.input, { cohortId: id(99), bindings: [] });
    // The test storage implementation uses the fixture binding; mutate only the
    // input array/identity and dependency functions, not its private byte fixture.
    f.storage.fetch = () => {
      throw new Error("replacement fetch used");
    };
    f.storage.sign = () => {
      throw new Error("replacement signer used");
    };
    release(
      json({ cohortId: id(6), jobId: id(7), cohortSHA256: "c".repeat(64) }),
    );
    assertEquals((await running).outcome, "verified");
  }));
Deno.test("capture composition bounds RPC bodies and cancels late responses after abort", () =>
  environment(async () => {
    const f = await fixture();
    let cancelled = false;
    f.rpcHook(() =>
      Promise.resolve(
        new Response(
          new ReadableStream({
            start(c) {
              c.enqueue(new Uint8Array(8193));
            },
            cancel() {
              cancelled = true;
            },
          }),
          { headers: { "Content-Type": "application/json" } },
        ),
      )
    );
    assertEquals(await f.run(), { outcome: "held" });
    assertEquals(cancelled, true);
    const g = await fixture();
    const abort = new AbortController();
    let late!: (r: Response) => void;
    g.rpcHook(() => new Promise((resolve) => late = resolve));
    const running = g.run(abort.signal);
    await new Promise((r) => setTimeout(r, 0));
    abort.abort();
    assertEquals(await running, { outcome: "held" });
    let disposed = false;
    late(
      new Response(
        new ReadableStream({
          cancel() {
            disposed = true;
          },
        }),
        { headers: { "Content-Type": "application/json" } },
      ),
    );
    await new Promise((r) => setTimeout(r, 0));
    assertEquals(disposed, true);
    assertEquals(g.events.length, 1);
  }));
Deno.test("capture composition rejects remote plaintext and URL credential configuration", () =>
  environment(() => {
    for (
      const value of [
        "http://remote.invalid",
        "https://user:password@database.invalid",
        "https://database.invalid/path",
        "https://database.invalid/?query",
      ]
    ) {
      Deno.env.set("SUPABASE_URL", value);
      assertThrows(() => createCapturePromotionDb());
    }
  }));
