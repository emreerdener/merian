import { assertEquals, assertRejects } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import page from "./fixtures/page-v8.json" with { type: "json" };
import { initialEvidenceRepository } from "./initialEvidenceRepository.ts";
import { HistoryError } from "./contract.ts";

function input() {
  const snapshot = JSON.parse(page.items[0].snapshot);
  return {
    result: snapshot.result,
    request: {
      schema_version: 1,
      scan_id: snapshot.observation_id,
      generation: snapshot.initial_evidence.generation,
      evidence_digest: snapshot.request_digest,
      evidence_manifest: snapshot.evidence_manifest,
    },
  };
}
type Call = {
  routine: string;
  args: Record<string, unknown>;
  signal: AbortSignal;
};
function fixture(
  reply: (call: Call) => Promise<{ data: unknown; error: unknown }>,
  onDispatch?: () => void,
) {
  const calls: Call[] = [];
  const client = {
    rpc(routine: string, args: Record<string, unknown>) {
      return {
        abortSignal(signal: AbortSignal) {
          const call = { routine, args, signal };
          calls.push(call);
          return reply(call);
        },
      };
    },
  } as unknown as SupabaseClient;
  return { repository: initialEvidenceRepository(client, onDispatch), calls };
}

Deno.test("initial binding uncertainty begins only after validation and cancellation checks", async () => {
  const { result, request } = input();
  let dispatched = 0;
  const f = fixture(
    () =>
      Promise.resolve({
        data: null,
        error: { message: "synthetic lost reply" },
      }),
    () => dispatched++,
  );
  await assertRejects(() =>
    f.repository.bindResult(
      page.owner_id,
      request,
      result,
      null,
      AbortSignal.abort(),
    )
  );
  await assertRejects(() =>
    f.repository.bindResult(
      page.owner_id,
      request,
      { ...result, scan_id: crypto.randomUUID() },
      null,
      new AbortController().signal,
    )
  );
  assertEquals(dispatched, 0);
  assertEquals(f.calls.length, 0);
  await assertRejects(() =>
    f.repository.bindResult(
      page.owner_id,
      request,
      result,
      null,
      new AbortController().signal,
    )
  );
  assertEquals(dispatched, 1);
  assertEquals(f.calls.length, 1);
});

Deno.test("initial result binding owns the original result before suspension", async () => {
  const { result, request } = input(), expected = structuredClone(result);
  const hash = "a".repeat(64);
  const f = fixture(() => Promise.resolve({ data: hash, error: null }));
  const binding = f.repository.bindResult(
    page.owner_id,
    request,
    result,
    null,
    new AbortController().signal,
  );
  result.scientific_name = "Later caller edit";
  assertEquals(await binding, hash);
  assertEquals(f.calls.length, 1);
  assertEquals(f.calls[0].routine, "bind_owned_initial_result");
  assertEquals(f.calls[0].args.p_result, expected);
  assertEquals(f.calls[0].args.p_request, request);
  assertEquals(f.calls[0].args.p_owner, page.owner_id);
});

Deno.test("initial result binding refuses mismatched scans and malformed receipts", async () => {
  const { result, request } = input();
  const f = fixture(() => Promise.resolve({ data: null, error: null }));
  await assertRejects(
    () =>
      f.repository.bindResult(
        page.owner_id,
        request,
        { ...result, scan_id: "00000000-0000-4000-8000-000000000099" },
        null,
        new AbortController().signal,
      ),
    HistoryError,
  );
  assertEquals(f.calls.length, 0);
  for (const data of [null, "a".repeat(63), "A".repeat(64), {}, true]) {
    const f = fixture(() => Promise.resolve({ data, error: null }));
    await assertRejects(
      () =>
        f.repository.bindResult(
          page.owner_id,
          request,
          result,
          null,
          new AbortController().signal,
        ),
      HistoryError,
    );
  }
});

Deno.test("initial result binding aborts even if an RPC transport ignores its signal", async () => {
  const { result, request } = input(), controller = new AbortController();
  let entered!: () => void;
  const started = new Promise<void>((resolve) => {
    entered = resolve;
  });
  const f = fixture(() => {
    entered();
    return new Promise(() => {});
  });
  const binding = f.repository.bindResult(
    page.owner_id,
    request,
    result,
    null,
    controller.signal,
  );
  await started;
  controller.abort();
  await assertRejects(
    () => binding,
    HistoryError,
    "analysis_history_unavailable",
  );
  assertEquals(f.calls[0].signal.aborted, true);
});

Deno.test("initial result binding preserves conflict but sanitizes other RPC errors", async () => {
  const { result, request } = input();
  for (
    const [message, expected] of [[
      "analysis_history_operation_conflict",
      "analysis_history_operation_conflict",
    ], ["private database detail", "analysis_history_unavailable"]]
  ) {
    const f = fixture(() =>
      Promise.resolve({ data: null, error: { message } })
    );
    await assertRejects(
      () =>
        f.repository.bindResult(
          page.owner_id,
          request,
          result,
          null,
          new AbortController().signal,
        ),
      HistoryError,
      expected,
    );
  }
});
