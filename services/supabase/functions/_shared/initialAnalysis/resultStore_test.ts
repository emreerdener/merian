import { assert, assertEquals, assertRejects } from "@std/assert";
import { createInitialResultStore } from "./resultStore.ts";
import {
  persistInitialResult,
  snapshotCapturedInitialResult,
} from "./resultEvidence.ts";
import { capture, id, other } from "./fixtures/resultEvidence.ts";
import { initialDeadline } from "./transport.ts";

async function setup(options: {
  readOnly?: boolean;
  write?: (reply: Record<string, unknown>) => Promise<Response>;
  read?: (reply: Record<string, unknown>) => Promise<Response>;
  provenance?: string;
} = {}) {
  const evidence = await capture();
  const calls: { operation: string; args: Record<string, unknown> }[] = [];
  const scope = { ...evidence.reference };
  const store = createInitialResultStore({
    reference: scope,
    originalProvenanceCanonical: options.provenance ??
      evidence.provenance_canonical,
    ...(options.readOnly ? {} : { leaseToken: id }),
    origin: "https://project.supabase.co",
    serverApiKey: ["sb", "secret", "fixture", "a".repeat(20)].join("_"),
    fetcher: async (url, init) => {
      const operation = new URL(String(url)).pathname.split("/").at(-1)!;
      const args = JSON.parse(String(init?.body));
      calls.push({ operation, args });
      assertEquals(init?.redirect, "error");
      assertEquals(init?.credentials, "omit");
      assertEquals(init?.cache, "no-store");
      assertEquals(init?.method, "POST");
      if (operation === "record_initial_analysis_result") {
        const reply = {
          version: 1,
          outcome: "recorded",
          reference: evidence.reference,
          result_digest: evidence.result_digest,
          provenance_digest: evidence.provenance_digest,
        };
        return options.write
          ? await options.write(reply)
          : Response.json(reply);
      }
      assertEquals(operation, "read_initial_analysis_result");
      const reply = {
        version: 1,
        outcome: "found",
        reference: evidence.reference,
        result_digest: evidence.result_digest,
        evidence,
      };
      return options.read ? await options.read(reply) : Response.json(reply);
    },
  });
  const request = {
    ...evidence.reference,
    result_digest: evidence.result_digest,
  };
  return { store, evidence, calls, request, scope };
}
const signal = () => new AbortController().signal;
Deno.test("fixed result store writes original RPC arguments then reads exact digest with no lease in reads", async () => {
  const { store, evidence, calls, request, scope } = await setup();
  scope.owner_id = other;
  assertEquals(await persistInitialResult(store, evidence, signal()), "stored");
  assertEquals(calls.map((c) => c.operation), [
    "record_initial_analysis_result",
    "read_initial_analysis_result",
  ]);
  assertEquals(Object.keys(calls[0].args).sort(), [
    "p_invocation",
    "p_lease_token",
    "p_owner",
    "p_provenance",
    "p_result",
    "p_result_digest",
    "p_result_evidence",
    "p_scan",
    "p_submission_digest",
  ]);
  assertEquals(calls[0].args.p_owner, id);
  assertEquals(calls[0].args.p_result, evidence.result_canonical);
  assertEquals(Object.keys(calls[1].args).sort(), [
    "p_owner",
    "p_result_digest",
    "p_result_evidence",
    "p_scan",
    "p_submission_digest",
  ]);
  assertEquals(calls[1].args.p_result_digest, request.result_digest);
  const recovered = await store.read(request, signal());
  assertEquals(recovered, evidence);
  assert(Object.isFrozen(recovered) && Object.isFrozen(recovered?.reference));
});
Deno.test("fixed result store reconciles lost write acknowledgement without another write", async () => {
  const { store, evidence, calls } = await setup({
    write: () => Promise.reject(new Error("synthetic lost ack")),
  });
  assertEquals(await persistInitialResult(store, evidence, signal()), "stored");
  assertEquals(calls.map((c) => c.operation), [
    "record_initial_analysis_result",
    "read_initial_analysis_result",
  ]);
});
Deno.test("restart result store reads without a worker lease but cannot write", async () => {
  const { store, evidence, calls, request } = await setup({ readOnly: true });
  await assertRejects(() => store.write(evidence, signal()));
  assertEquals(calls, []);
  assertEquals(await store.read(request, signal()), evidence);
  assertEquals(calls.length, 1);
});
Deno.test("result store requires independently retained provenance before write and after read", async () => {
  const { store, evidence, calls, request } = await setup({ provenance: "{}" });
  await assertRejects(() => store.write(evidence, signal()));
  assertEquals(calls, []);
  await assertRejects(() => store.read(request, signal()));
  assertEquals(calls.length, 1);
});
for (
  const mode of [
    "version",
    "reference",
    "digest",
    "extra",
    "missing",
    "outcome",
    "recorded_array",
    "replay_array",
  ] as const
) {
  Deno.test(`fixed write reply ${mode} cannot acknowledge result persistence`, async () => {
    const { store, evidence, calls } = await setup({
      write: (r) => {
        if (mode === "version") r.version = 2;
        if (mode === "reference") {
          r.reference = { ...(r.reference as object), owner_id: other };
        }
        if (mode === "digest") {
          r.result_digest = "f".repeat(64);
        }
        if (mode === "extra") r.authority = "dispatch";
        if (mode === "missing") delete r.provenance_digest;
        if (mode === "outcome") r.outcome = "fresh";
        if (mode === "recorded_array") r.outcome = ["recorded"];
        if (mode === "replay_array") r.outcome = ["replay"];
        return Promise.resolve(Response.json(r));
      },
    });
    await assertRejects(() => store.write(evidence, signal()));
    assertEquals(calls.length, 1);
  });
}
Deno.test("only exactly correlated explicit absence becomes a null result", async () => {
  const { store, request } = await setup({
    read: (r) =>
      Promise.resolve(
        Response.json({ ...r, outcome: "absent", evidence: null }),
      ),
  });
  assertEquals(await store.read(request, signal()), null);
  const mismatch = await setup({
    read: (r) =>
      Promise.resolve(
        Response.json({
          ...r,
          outcome: "absent",
          evidence: null,
          reference: { ...(r.reference as object), owner_id: other },
        }),
      ),
  });
  await assertRejects(() => mismatch.store.read(mismatch.request, signal()));
});
for (
  const mode of [
    "extra",
    "reference",
    "digest",
    "inner_identity",
    "inner_digest",
    "inner_extra",
    "false_absence",
    "gateway",
    "invalid_utf8",
    "oversized",
  ] as const
) {
  Deno.test(`fixed read ${mode} stays unavailable rather than inventing success or absence`, async () => {
    const { store, request, calls } = await setup({
      read: (r) => {
        if (mode === "extra") r.authority = "dispatch";
        if (mode === "reference") {
          r.reference = { ...(r.reference as object), scan_id: other };
        }
        if (mode === "digest") {
          r.result_digest = "f".repeat(64);
        }
        if (mode === "inner_identity") {
          r.evidence = {
            ...(r.evidence as object),
            reference: { ...(r.reference as object), invocation_id: other },
          };
        }
        if (mode === "inner_digest") {
          r.evidence = {
            ...(r.evidence as object),
            provenance_digest: "f".repeat(64),
          };
        }
        if (mode === "inner_extra") {
          r.evidence = { ...(r.evidence as object), authority: "dispatch" };
        }
        if (mode === "false_absence") r.outcome = "absent";
        if (mode === "gateway") {
          return Promise.resolve(Response.json({}, { status: 404 }));
        }
        if (mode === "invalid_utf8") {
          return Promise.resolve(new Response(new Uint8Array([255])));
        }
        if (mode === "oversized") {
          return Promise.resolve(
            new Response(" ".repeat(2 * (1048576 + 65536) + 4097)),
          );
        }
        return Promise.resolve(Response.json(r));
      },
    });
    await assertRejects(() => store.read(request, signal()));
    assertEquals(calls.length, 1);
  });
}
Deno.test("closed evidence snapshot rejects getters before evaluating them", async () => {
  const { evidence, store, calls } = await setup();
  let accesses = 0;
  const altered = { ...evidence };
  Object.defineProperty(altered, "result_canonical", {
    enumerable: true,
    get() {
      accesses++;
      return evidence.result_canonical;
    },
  });
  await assertRejects(() => store.write(altered, signal()));
  assertEquals(accesses, 0);
  assertEquals(calls, []);
  assertEquals(snapshotCapturedInitialResult(evidence), evidence);
});
Deno.test("result requests reject extra fields and wrong original references before networking", async () => {
  const { store, request, calls, evidence } = await setup();
  await assertRejects(() =>
    store.read({ ...request, owner_id: other }, signal())
  );
  await assertRejects(() =>
    store.read({ ...request, result_digest: "invalid" }, signal())
  );
  await assertRejects(() =>
    store.write({
      ...evidence,
      reference: { ...evidence.reference, result_evidence_id: id },
    }, signal())
  );
  const extraRequest = { ...request, authority: "dispatch" };
  await assertRejects(() => store.read(extraRequest, signal()));
  assertEquals(calls, []);
});
Deno.test("result write snapshots mutable evidence before hash awaits", async () => {
  const { store, evidence, calls } = await setup();
  const mutable = { ...evidence, reference: { ...evidence.reference } };
  const pending = store.write(mutable, signal());
  mutable.result_canonical = "{}";
  mutable.provenance_canonical = "{}";
  mutable.result_digest = "f".repeat(64);
  mutable.reference.owner_id = other;
  await pending;
  assertEquals(calls.length, 1);
  assertEquals(calls[0].args.p_owner, evidence.reference.owner_id);
  assertEquals(calls[0].args.p_result, evidence.result_canonical);
  assertEquals(calls[0].args.p_provenance, evidence.provenance_canonical);
  assertEquals(calls[0].args.p_result_digest, evidence.result_digest);
});
Deno.test("result read timeout discards a late response and cannot retry automatically", async () => {
  const pending = Promise.withResolvers<Response>();
  let cancelled = 0;
  const { store, request, calls } = await setup({
    read: () => pending.promise,
  });
  await initialDeadline(signal(), 10, async (caller) => {
    await assertRejects(() => store.read(request, caller));
    pending.resolve(
      new Response(
        new ReadableStream({
          cancel() {
            cancelled++;
          },
        }),
      ),
    );
    await Promise.resolve();
    await Promise.resolve();
    await Promise.resolve();
  });
  assertEquals(calls.length, 1);
  assertEquals(cancelled, 1);
});
