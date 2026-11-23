import { assertEquals, assertThrows } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import page from "../_shared/analysisHistory/fixtures/page-v8.json" with {
  type: "json",
};
import { requireParams } from "../_shared/http.ts";
import { hasInitialRecoveryRequest } from "./status.ts";
import {
  captureCompletionRequestBytes,
  decodeCaptureCompletion,
  readCaptureCompletionHttp,
} from "./captureCompletion.ts";

const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const owner = id(1), scan = id(2), generation = id(3);
const plan = () => ({
  schema_version: 1,
  scan_id: scan,
  generation,
  items: [{
    kind: "audio",
    source: {
      media_id: id(4),
      content_type: "audio/wav",
      byte_count: 100,
      sha256: "a".repeat(64),
    },
    prepared_media_id: id(5),
  }, { kind: "description", text: "Synthetic context 🦋" }],
});
const body = () => ({
  initial_recovery: {
    version: 1,
    phase: "capture-completion",
    capture_plan: plan(),
  },
});
function request(
  value: unknown = body(),
  headers: Record<string, string> = {},
  signal?: AbortSignal,
) {
  return new Request("https://fixture.invalid/check-scan-status", {
    method: "POST",
    signal,
    headers: {
      "content-type": "application/json",
      "x-merian-initial-recovery": "capture-completion-v1",
      ...headers,
    },
    body: JSON.stringify(value),
  });
}
function client(
  data: unknown = null,
  error: unknown = null,
  wait?: () => Promise<void>,
) {
  const calls: { name: string; args: unknown }[] = [];
  return {
    calls,
    value: {
      rpc(name: string, args: unknown) {
        calls.push({ name, args });
        return {
          async abortSignal(signal: AbortSignal) {
            signal.throwIfAborted();
            await wait?.();
            return { data, error };
          },
        };
      },
    } as unknown as SupabaseClient,
  };
}
function completed() {
  const saved = JSON.parse(page.items[0].snapshot);
  return {
    success: true,
    data: { ...saved.result, scan_id: scan },
    initial_evidence: {
      schema_version: 1,
      owner_id: owner,
      scan_id: scan,
      generation,
      evidence_digest: "a".repeat(64),
    },
  };
}

Deno.test("capture completion returns sealed proof or held through one exact read only", async () => {
  for (const completion of [null, completed()]) {
    const c = client(completion);
    const response = await readCaptureCompletionHttp(request(), owner, c.value);
    assertEquals(response.status, 200);
    assertEquals(response.headers.get("cache-control"), "no-store");
    const result = await response.json();
    assertEquals(
      Object.keys(result).sort(),
      [
        "version",
        "phase",
        "owner_id",
        "scan_id",
        "generation",
        "status",
        "completion",
      ].sort(),
    );
    assertEquals([
      result.version,
      result.phase,
      result.owner_id,
      result.scan_id,
      result.generation,
    ], [1, "capture-completion", owner, scan, generation]);
    assertEquals(result.status, completion === null ? "held" : "completed");
    assertEquals(
      result.completion?.initial_evidence ?? null,
      completion?.initial_evidence ?? null,
    );
    assertEquals(c.calls, [{
      name: "recover_private_capture_completion",
      args: { p_owner: owner, p_plan: plan() },
    }]);
  }
});

Deno.test("capture completion rejects legacy/mixed/unknown input before any RPC", async () => {
  const valid = body();
  for (
    const value of [
      null,
      {},
      { ...valid, scan_id: scan },
      { ...valid, scans: [] },
      { initial_recovery: { ...valid.initial_recovery, version: 2 } },
      { initial_recovery: { ...valid.initial_recovery, phase: "completion" } },
      { initial_recovery: { ...valid.initial_recovery, owner_id: owner } },
      {
        initial_recovery: {
          ...valid.initial_recovery,
          capture_plan: { ...plan(), generation: owner },
        },
      },
    ]
  ) {
    assertThrows(() => decodeCaptureCompletion(value, owner));
    const c = client();
    assertEquals(
      (await readCaptureCompletionHttp(request(value), owner, c.value)).status,
      503,
    );
    assertEquals(c.calls.length, 0);
  }
  assertEquals(hasInitialRecoveryRequest(valid), true);
  assertEquals(requireParams(valid, ["scan_id"]) instanceof Response, true);
});

Deno.test("capture completion refuses invalid headers and declared/actual byte bounds before reads", async () => {
  for (
    const headers of <Record<string, string>[]> [
      { "x-merian-initial-recovery": "observe-v1" },
      { "content-type": "text/plain" },
      { "content-encoding": "gzip" },
      { "content-length": "1" },
      { "content-length": "01" },
      { "content-length": String(captureCompletionRequestBytes + 1) },
    ]
  ) {
    const c = client();
    assertEquals(
      (await readCaptureCompletionHttp(
        request(body(), headers),
        owner,
        c.value,
      )).status,
      503,
    );
    assertEquals(c.calls.length, 0);
  }
  const c = client();
  assertEquals(
    (await readCaptureCompletionHttp(
      request("a".repeat(captureCompletionRequestBytes)),
      owner,
      c.value,
    )).status,
    503,
  );
  assertEquals(c.calls.length, 0);
});

Deno.test("capture completion refuses foreign, mismatched, unsealed and failed results without disclosure", async () => {
  const good = completed();
  for (
    const result of [
      { ...good, initial_evidence: undefined },
      {
        ...good,
        initial_evidence: { ...good.initial_evidence, owner_id: id(8) },
      },
      {
        ...good,
        initial_evidence: { ...good.initial_evidence, generation: id(8) },
      },
      { ...good, data: { ...good.data, scan_id: id(8) } },
      {},
    ]
  ) {
    const c = client(result);
    const response = await readCaptureCompletionHttp(request(), owner, c.value);
    assertEquals(response.status, 503);
    assertEquals(await response.json(), {
      error: "capture_completion_unavailable",
    });
  }
  const c = client(null, { message: "private backend diagnostic" });
  assertEquals(
    await (await readCaptureCompletionHttp(request(), owner, c.value)).json(),
    { error: "capture_completion_unavailable" },
  );
});

Deno.test("capture completion cancellation discards a late successful read", async () => {
  const controller = new AbortController();
  let entered!: () => void, finish!: () => void;
  const started = new Promise<void>((resolve) => entered = resolve);
  const waiting = new Promise<void>((resolve) => finish = resolve);
  const c = client(completed(), null, async () => {
    entered();
    await waiting;
  });
  const response = readCaptureCompletionHttp(
    request(body(), {}, controller.signal),
    owner,
    c.value,
  );
  await started;
  controller.abort();
  assertEquals((await response).status, 503);
  finish();
  await Promise.resolve();
  assertEquals(c.calls.length, 1);
});

Deno.test("capture completion bounds caller waiting when a read ignores cancellation", async () => {
  const c = client(null, null, () => new Promise<void>(() => {}));
  const response = await readCaptureCompletionHttp(request(), owner, c.value);
  assertEquals(response.status, 503);
  assertEquals(c.calls.length, 1);
});
