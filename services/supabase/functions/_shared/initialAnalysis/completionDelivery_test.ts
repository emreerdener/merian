import { assertEquals, assertRejects } from "@std/assert";
import { initialCanonicalText } from "./canonical.ts";
import { binding as dispatch, capture } from "./fixtures/resultEvidence.ts";
import { projection, receipt } from "./fixtures/completionDocuments.ts";
import { createInitialResultStore } from "./resultStore.ts";
import type { InitialCompletionRequestBinding } from "./completionDelivery.ts";

async function fixture() {
  const evidence = await capture();
  const p = projection();
  Object.assign(p, {
    owner_id: evidence.reference.owner_id,
    scan_id: evidence.reference.scan_id,
    result_evidence_id: evidence.reference.result_evidence_id,
    result_digest: evidence.result_digest,
  });
  p.capture_context.submission_digest = evidence.reference.submission_digest;
  const r = await receipt(p);
  Object.assign(r, {
    owner_id: p.owner_id,
    scan_id: p.scan_id,
    operation_id: p.scan_id,
    result_evidence_id: p.result_evidence_id,
    result_digest: p.result_digest,
    config_digest: evidence.reference.config_digest,
    funding_binding_id: dispatch.funding_binding_id,
    funding_binding_digest: evidence.reference.funding_binding_digest,
  });
  const binding: InitialCompletionRequestBinding = {
    route: "identify-multimodal",
    input_schema_version: 2,
    funding_binding_id: dispatch.funding_binding_id,
    funding_binding_version: 1,
    ordered_description_digest: r.ordered_description_digest,
    ordered_description_count: 0,
  };
  const reply = {
    version: 1,
    outcome: "found",
    reference: evidence.reference,
    completion: {
      receipt_canonical: initialCanonicalText(r),
      projection_canonical: initialCanonicalText(p),
    },
    result: evidence,
  };
  return {
    evidence,
    binding,
    reply,
    request: { ...evidence.reference, result_digest: evidence.result_digest },
  };
}
const signal = () => new AbortController().signal;
function store(
  f: Awaited<ReturnType<typeof fixture>>,
  calls: string[],
  read: () => Response | Promise<Response>,
  includeBinding = true,
) {
  return createInitialResultStore({
    reference: f.evidence.reference,
    originalProvenanceCanonical: f.evidence.provenance_canonical,
    ...(includeBinding ? { completionBinding: f.binding } : {}),
    origin: "https://project.supabase.co",
    serverApiKey: ["sb", "secret", "fixture", "a".repeat(20)].join("_"),
    fetcher: async (url, init) => {
      calls.push(new URL(String(url)).pathname);
      assertEquals(init?.redirect, "error");
      assertEquals(init?.cache, "no-store");
      assertEquals(init?.credentials, "omit");
      assertEquals(JSON.parse(String(init?.body)), {
        p_owner: f.request.owner_id,
        p_scan: f.request.scan_id,
        p_submission: f.request.submission_digest,
        p_result: f.request.result_evidence_id,
        p_result_digest: f.request.result_digest,
      });
      return await read();
    },
  });
}
Deno.test("completion delivery reads exact saved result/receipt once without a lease or execution", async () => {
  const f = await fixture(), calls: string[] = [];
  const reader = store(f, calls, () => Promise.resolve(Response.json(f.reply)));
  const result = await reader.readCompletion(f.request, signal());
  assertEquals(result, { ...f.reply.completion, result: f.evidence });
  assertEquals(calls, ["/rest/v1/rpc/read_initial_completion_v1"]);
});
Deno.test("completion absence is observed once and never promotes or retries", async () => {
  const f = await fixture(), calls: string[] = [];
  const reader = store(
    f,
    calls,
    () =>
      Promise.resolve(
        Response.json({
          ...f.reply,
          outcome: "absent",
          completion: null,
          result: null,
        }),
      ),
  );
  assertEquals(await reader.readCompletion(f.request, signal()), null);
  assertEquals(calls, ["/rest/v1/rpc/read_initial_completion_v1"]);
});
Deno.test("completion reads require saved binding and snapshot it before dispatch", async () => {
  const f = await fixture(), calls: string[] = [];
  const missing = store(
    f,
    calls,
    () => Promise.resolve(Response.json(f.reply)),
    false,
  );
  await assertRejects(() => missing.readCompletion(f.request, signal()));
  assertEquals(calls, []);
  const reader = store(f, calls, () => Promise.resolve(Response.json(f.reply)));
  Reflect.set(f.binding, "route", "identify");
  await reader.readCompletion(f.request, signal());
  await assertRejects(() =>
    reader.readCompletion({
      ...f.request,
      owner_id: "00000000-0000-4000-8000-00000000ffff",
    }, signal())
  );
  assertEquals(calls.length, 1);
});
Deno.test("completion delivery rejects mismatched saved scope, original texts and retained result", async (t) => {
  for (
    const field of [
      "route",
      "input_schema_version",
      "funding_binding_id",
      "funding_binding_version",
      "ordered_description_digest",
      "ordered_description_count",
      "config_digest",
      "funding_binding_digest",
      "result_digest",
      "owner_id",
      "scan_id",
      "result_evidence_id",
    ]
  ) {
    await t.step(field, async () => {
      const f = await fixture(), calls: string[] = [];
      const changed = JSON.parse(f.reply.completion.receipt_canonical);
      changed[field] = typeof changed[field] === "number"
        ? changed[field] + 1
        : field === "route"
        ? "identify"
        : "f".repeat(64);
      f.reply.completion.receipt_canonical = initialCanonicalText(changed);
      const reader = store(
        f,
        calls,
        () => Promise.resolve(Response.json(f.reply)),
      );
      await assertRejects(() => reader.readCompletion(f.request, signal()));
      assertEquals(calls.length, 1);
    });
  }
  for (
    const mode of [
      "result",
      "provenance",
      "extra",
      "absent_result",
      "absent_completion",
    ]
  ) {
    await t.step(mode, async () => {
      const f = await fixture(), calls: string[] = [];
      const reply = structuredClone(f.reply);
      if (mode === "result") {
        reply.result = { ...reply.result, result_canonical: "{}" };
      }
      if (mode === "provenance") {
        reply.result = { ...reply.result, provenance_canonical: "{}" };
      }
      if (mode === "extra") {
        Reflect.set(reply.completion, "url", "https://invalid.example");
      }
      if (mode.startsWith("absent")) {
        reply.outcome = "absent";
        Reflect.set(
          reply,
          mode === "absent_result" ? "completion" : "result",
          null,
        );
      }
      const reader = store(
        f,
        calls,
        () => Promise.resolve(Response.json(reply)),
      );
      await assertRejects(() => reader.readCompletion(f.request, signal()));
      assertEquals(calls.length, 1);
    });
  }
});
Deno.test("completion lost reads, bad bodies and cancellation remain uncertain without retry", async (t) => {
  for (const mode of ["lost", "status", "json", "oversize", "cancel"]) {
    await t.step(mode, async () => {
      const f = await fixture(), calls: string[] = [];
      const controller = new AbortController();
      const reader = store(f, calls, () => {
        if (mode === "lost") throw new Error("synthetic lost read");
        if (mode === "status") return new Response("", { status: 503 });
        if (mode === "json") return new Response("{");
        if (mode === "oversize") {
          return new Response(
            "x".repeat(2 * (1048576 + 65536 + 16384 + 65536) + 6145),
          );
        }
        controller.abort();
        return Response.json(f.reply);
      });
      await assertRejects(() =>
        reader.readCompletion(f.request, controller.signal)
      );
      assertEquals(calls.length, 1);
    });
  }
});
