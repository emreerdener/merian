/** Local coordinator/SQL integration with in-memory conditional storage only.
 * Synthetic attestations are not installed adapter or backend qualification. */
import { assert, assertEquals } from "@std/assert";
import { createDisposableHandoffBridge } from "./initial_media_handoff_bridge.ts";
import {
  executeOriginalMediaHandoff,
  type HandoffBridge,
  type HandoffExecutionDependencies,
} from "../functions/_shared/initialAnalysis/mediaHandoffExecution.ts";
import {
  decodeHandoffState,
  handoffIdentity,
} from "../functions/_shared/initialAnalysis/mediaHandoffRows.ts";
import { initialMediaHash } from "../functions/_shared/initialAnalysis/mediaBinding.ts";
import { initialCanonicalText } from "../functions/_shared/initialAnalysis/canonical.ts";
import {
  initialDeadline,
  readInitialStream,
} from "../functions/_shared/initialAnalysis/transport.ts";

let stage = "input";
const calls: string[] = [];
const storageCalls: string[] = [];
let maxSQLMs = 0;
let lastSQL = "none";
async function main(signal: AbortSignal) {
  const input = JSON.parse(new TextDecoder().decode(
    await readInitialStream(Deno.stdin.readable, 4096, signal),
  ));
  assert(input.mode === "lifecycle" || input.mode === "cancel_source");
  const id = handoffIdentity(input.identity);
  const bytes = Uint8Array.from(atob(input.png), (x) => x.charCodeAt(0));
  assertEquals(bytes.length, 68);
  const hash = await initialMediaHash(bytes);
  stage = "bridge_setup";
  const real = await createDisposableHandoffBridge(signal);
  const original = await decodeHandoffState(
    await real.readState(id, signal),
    id,
  );
  assertEquals(original.progress, null);
  assertEquals(original.mapping.items.length, 1);
  assertEquals(original.mapping.objects.length, 1);
  const aliases = original.mapping.items.flatMap((item) => [
    item.source,
    ...(item.prepared ? [item.prepared] : []),
  ]);
  const objects = new Map<string, Uint8Array<ArrayBuffer>>();
  const types = new Map<string, string>();
  const key = (namespace: string, object: string) =>
    `https://00000000000000000000000000000000.r2.cloudflarestorage.com/synthetic-only/${namespace}/${id.scan_id}/${object}`;
  for (const role of aliases) {
    assertEquals(role.bytes, {
      byte_count: bytes.length,
      sha256: hash,
      content_type: "image/png",
    });
    const url = key("initial-preparation/v2", role.original_object_id);
    objects.set(url, bytes.slice());
    types.set(url, "image/png");
  }
  const destination = original.mapping.objects[0];
  assertEquals(destination.bytes, {
    byte_count: bytes.length,
    sha256: hash,
    content_type: "image/png",
  });
  const destinationURL = key("initial-analysis/v1", destination.object_id);
  types.set(destinationURL, "image/png");
  let activeSQL = 0, activeIO = 0;
  const track = async (
    name: keyof HandoffBridge,
    run: () => Promise<unknown>,
  ) => {
    assertEquals(activeIO, 0);
    assertEquals(activeSQL, 0);
    activeSQL++;
    calls.push(name);
    lastSQL = name;
    const began = performance.now();
    try {
      // The real bridge returns only after the same transaction's COMMIT ACK.
      const result = await run();
      assert(performance.now() - began < 5000);
      return result;
    } finally {
      maxSQLMs = Math.max(maxSQLMs, performance.now() - began);
      activeSQL--;
    }
  };
  const bridge: HandoffBridge = {
    readState: (i, s) => track("readState", () => real.readState(i, s)),
    loadCopy: (i, s) => track("loadCopy", () => real.loadCopy(i, s)),
    loadVerification: (i, c, s) =>
      track("loadVerification", () => real.loadVerification(i, c, s)),
    beginCopy: (i, s) => track("beginCopy", () => real.beginCopy(i, s)),
    recordObject: (i, o, s) =>
      track("recordObject", () => real.recordObject(i, o, s)),
    completeCopy: (i, s) =>
      track("completeCopy", () => real.completeCopy(i, s)),
    claimVerification: (i, s) =>
      track("claimVerification", () => real.claimVerification(i, s)),
    settleVerification: (i, c, s) =>
      track("settleVerification", () => real.settleVerification(i, c, s)),
    transfer: (i, v, s) => track("transfer", () => real.transfer(i, v, s)),
  };
  const cancel = new AbortController();
  const caller = AbortSignal.any([signal, cancel.signal]);
  let delayed: Promise<void> | null = null;
  let sourceSettled = false;
  let attestations = 0;
  const deps: HandoffExecutionDependencies = {
    bridge,
    attest: (rows) => {
      assertEquals(rows.original, original.original);
      attestations++;
      return Promise.resolve({
        copy_adapter_digest: original.handoff.copy_adapter_digest,
        verification_adapter_digest:
          original.handoff.verification_adapter_digest,
        protocol_artifact_digest: original.handoff.protocol_artifact_digest,
      });
    },
    storage: {
      sign: (profile, request) => {
        assertEquals(profile, "synthetic_only");
        assertEquals(activeSQL, 0);
        return Promise.resolve(request);
      },
      fetch: async (input) => {
        const request = input as Request;
        assertEquals(activeSQL, 0);
        assertEquals(activeIO, 0);
        activeIO++;
        // Keep identities in memory; retained evidence contains categories only.
        storageCalls.push(
          request.method +
            (request.url === destinationURL ? " destination" : " source"),
        );
        try {
          assert(types.has(request.url));
          if (request.method === "PUT") {
            assertEquals(request.url, destinationURL);
            assertEquals(request.headers.get("if-none-match"), "*");
            assert(!objects.has(request.url));
            const uploaded = new Uint8Array(await request.arrayBuffer());
            assertEquals(uploaded, bytes);
            objects.set(request.url, uploaded);
            return new Response(null, { status: 200 });
          }
          assertEquals(request.method, "GET");
          if (request.url !== destinationURL && inputMode === "cancel_source") {
            assertEquals(delayed, null);
            delayed = new Promise<void>((resolve) => setTimeout(resolve, 200));
            setTimeout(() => cancel.abort(), 20);
            // Deliberately non-cooperative local transport settles after abort.
            await delayed;
            assert(cancel.signal.aborted);
            sourceSettled = true;
          }
          const value = objects.get(request.url);
          assert(value);
          return new Response(value.slice(), {
            headers: {
              "Content-Type": types.get(request.url)!,
              "Content-Length": String(value.length),
              "Cache-Control": "private, no-store",
            },
          });
        } finally {
          activeIO--;
        }
      },
    },
  };
  const inputMode = input.mode;
  stage = "coordinator";
  const began = performance.now();
  const result = await executeOriginalMediaHandoff(deps, id, caller);
  const coordinatorMs = Math.ceil(performance.now() - began);
  const callsAtReturn = [...calls];
  if (input.mode === "cancel_source") {
    assertEquals(result, { outcome: "unresolved", recovered: null });
    assert(cancel.signal.aborted);
    assert(!sourceSettled);
    assert(delayed);
    await delayed;
    await new Promise((resolve) => setTimeout(resolve, 50));
    assert(sourceSettled);
    assertEquals(calls, callsAtReturn);
    assertEquals(storageCalls, ["GET source"]);
    assert(!objects.has(destinationURL));
  } else {
    assertEquals(result.outcome, "transferred");
    assertEquals(storageCalls, [
      ...aliases.map(() => "GET source"),
      "PUT destination",
      "GET destination",
      "GET destination",
    ]);
    assertEquals(attestations, 2);
    for (
      const name of [
        "beginCopy",
        "recordObject",
        "completeCopy",
        "claimVerification",
        "settleVerification",
        "transfer",
      ]
    ) {
      assertEquals(calls.filter((x) => x === name).length, 1);
    }
  }
  stage = "durable_state";
  assertEquals(activeIO, 0);
  assertEquals(activeSQL, 0);
  const after = await decodeHandoffState(await real.readState(id, signal), id);
  assertEquals(
    initialCanonicalText(after.original),
    initialCanonicalText(original.original),
  );
  if (input.mode === "lifecycle") {
    assert(after.transfer && result.outcome === "transferred");
    assertEquals(after.transfer.digest, result.transferDigest);
    const priorCalls = [...calls];
    const priorIO = [...storageCalls];
    const replay = await executeOriginalMediaHandoff(deps, id, signal);
    assertEquals(replay, result);
    assertEquals(calls, [...priorCalls, "readState"]);
    assertEquals(storageCalls, priorIO);
  } else {
    assert(after.progress);
    assertEquals(JSON.parse(after.progress.completed_objects), []);
    assertEquals(after.progress.completed_at_ms, null);
    assertEquals([after.claim, after.verification, after.transfer], [
      null,
      null,
      null,
    ]);
    assertEquals(calls.filter((x) => !["readState", "loadCopy"].includes(x)), [
      "beginCopy",
    ]);
  }
  console.log(
    JSON.stringify({
      passed: true,
      mode: input.mode,
      coordinator_ms: coordinatorMs,
      max_sql_ms: Math.ceil(maxSQLMs),
      sql_calls: calls,
      storage_calls: storageCalls,
      aliases: aliases.length,
      destinations: 1,
      no_sql_during_io: true,
      original_preserved: true,
      late_sql_after_cancel: false,
    }),
  );
}
if (import.meta.main) {
  try {
    await initialDeadline(new AbortController().signal, 85000, main);
  } catch {
    console.log(
      JSON.stringify({
        passed: false,
        error: "local_coordinator_qualification_failed",
        stage,
        last_sql: lastSQL,
        max_sql_ms: Math.ceil(maxSQLMs),
        sql_calls: calls,
        storage_calls: storageCalls,
      }),
    );
    Deno.exitCode = 1;
  }
}
