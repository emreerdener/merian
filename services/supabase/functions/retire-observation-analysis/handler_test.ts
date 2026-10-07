import { assertEquals, assertRejects } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import { HistoryError } from "../_shared/analysisHistory/contract.ts";
import { parseAnalysisRetirementRequest } from "../_shared/analysisHistory/executionRetirement.ts";
import { analysisRetirementRepository } from "./db.ts";
import { retireObservationAnalysis } from "./handler.ts";
const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const input = parseAnalysisRetirementRequest({
  schema_version: 1,
  operation_id: id(1),
  observation_id: id(2),
  analysis_id: id(3),
  source_analysis_id: null,
  request_digest: "a".repeat(64),
});
const receipt = { ...input, state: "retired_before_dispatch" };
const request = () =>
  new Request("https://synthetic.invalid", { method: "POST" });
Deno.test("retirement handler returns only exact proof and preserves replay identity", async () => {
  let calls = 0;
  for (let i = 0; i < 2; i++) {
    const response = await retireObservationAnalysis(request(), input, id(4), {
      retire(owner, saved, signal) {
        calls++;
        assertEquals(owner, id(4));
        assertEquals(saved, input);
        assertEquals(signal.aborted, false);
        return Promise.resolve(receipt);
      },
    });
    assertEquals(response.status, 200);
    assertEquals(await response.json(), receipt);
    assertEquals(response.headers.get("Cache-Control"), "private, no-store");
  }
  assertEquals(calls, 2);
});
Deno.test("retirement handler rejects owner injection before I/O and malformed proof after I/O", async () => {
  let calls = 0;
  const deps = {
    retire() {
      calls++;
      return Promise.resolve(receipt);
    },
  };
  const invalid = await retireObservationAnalysis(
    request(),
    { ...input, owner_id: id(9) },
    id(4),
    deps,
  );
  assertEquals(invalid.status, 400);
  await invalid.body?.cancel();
  assertEquals(calls, 0);
  for (
    const answer of [null, { ...receipt, state: "absent" }, {
      ...receipt,
      operation_id: id(8),
    }, { ...receipt, private: "hidden" }]
  ) {
    const response = await retireObservationAnalysis(request(), input, id(4), {
      retire: () => Promise.resolve(answer),
    });
    assertEquals(response.status, 503);
    assertEquals((await response.text()).includes("hidden"), false);
  }
});
Deno.test("retirement public failures never claim proof or leak internal diagnostics", async () => {
  for (
    const [error, status] of [
      [new HistoryError("analysis_history_deleted"), 404],
      [new HistoryError("analysis_history_operation_conflict"), 409],
      [new Error("private diagnostic"), 503],
    ] as const
  ) {
    const response = await retireObservationAnalysis(request(), input, id(4), {
      retire: () => Promise.reject(error),
    });
    assertEquals(response.status, status);
    const body = await response.text();
    assertEquals(body.includes("private diagnostic"), false);
    assertEquals(body.includes("retired_before_dispatch"), false);
  }
});
Deno.test("retirement repository fixes reader/owner/identity and never retries failed mutation", async () => {
  for (
    const message of [
      null,
      "analysis_history_operation_conflict",
      "private diagnostic",
    ]
  ) {
    let calls = 0;
    const client = {
      rpc(name: string, args: unknown) {
        calls++;
        assertEquals(name, "retire_owned_observation_analysis_execution");
        assertEquals(args, { p_owner: id(4), p_request: input, p_reader: 10 });
        return {
          abortSignal(signal: AbortSignal) {
            assertEquals(signal.aborted, false);
            return Promise.resolve({
              data: receipt,
              error: message ? { message } : null,
            });
          },
        };
      },
    } as unknown as SupabaseClient;
    const run = () =>
      analysisRetirementRepository(client).retire(
        id(4),
        input,
        new AbortController().signal,
      );
    if (message) {
      await assertRejects(
        run,
        HistoryError,
        message === "private diagnostic"
          ? "analysis_history_unavailable"
          : message,
      );
    } else assertEquals(await run(), receipt);
    assertEquals(calls, 1);
  }
});
Deno.test("retirement abort before dispatch makes no call; abort during stalled call returns without retry", async () => {
  let calls = 0;
  const client = {
    rpc() {
      calls++;
      return { abortSignal: () => new Promise(() => {}) };
    },
  } as unknown as SupabaseClient;
  const controller = new AbortController();
  controller.abort();
  await assertRejects(
    () =>
      analysisRetirementRepository(client).retire(
        id(4),
        input,
        controller.signal,
      ),
    HistoryError,
  );
  assertEquals(calls, 0);
  const running = new AbortController();
  const result = analysisRetirementRepository(client).retire(
    id(4),
    input,
    running.signal,
  );
  running.abort();
  await assertRejects(() => result, HistoryError);
  assertEquals(calls, 1);
});
