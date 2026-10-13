/** Current-profile maximum transport cohorts; local synthetic storage only.
 * Resource measurements include this in-memory fixture, not installed storage. */
import { assert, assertEquals } from "@std/assert";
import { createDisposableHandoffBridge } from "./initial_media_handoff_bridge.ts";
import {
  executeOriginalMediaHandoff,
  type HandoffBridge,
} from "../functions/_shared/initialAnalysis/mediaHandoffExecution.ts";
import {
  decodeHandoffState,
  handoffIdentity,
} from "../functions/_shared/initialAnalysis/mediaHandoffRows.ts";
import {
  initialDeadline,
  readInitialStream,
} from "../functions/_shared/initialAnalysis/transport.ts";

const calls: { name: string; ms: number; acknowledged: boolean }[] = [];
const io: string[] = [];
let stage = "input";
const peak = { rss: 0, heapUsed: 0, external: 0 };
function sample() {
  const m = Deno.memoryUsage();
  for (const k of ["rss", "heapUsed", "external"] as const) {
    peak[k] = Math.max(peak[k], m[k]);
  }
}
async function main(signal: AbortSignal) {
  const input = JSON.parse(
    new TextDecoder().decode(
      await readInitialStream(Deno.stdin.readable, 8192, signal),
    ),
  );
  assert(
    ["photo_audio", "photo_audio_images", "video_audio"].includes(input.shape),
  );
  const id = handoffIdentity(input.identity);
  stage = "setup";
  const real = await createDisposableHandoffBridge(signal);
  const original = await decodeHandoffState(
    await real.readState(id, signal),
    id,
  );
  assertEquals(original.mapping.items.length, input.source_count);
  assertEquals(original.mapping.objects.length, input.object_count);
  assertEquals(
    original.mapping.objects.reduce((n, x) => n + x.bytes.byte_count, 0),
    input.unique_bytes,
  );
  assertEquals(original.progress, null);
  const objects = new Map<string, Uint8Array<ArrayBuffer>>();
  const types = new Map<string, string>();
  const sourceURLs: string[] = [], destinationURLs: string[] = [];
  const url = (ns: string, object: string) =>
    `https://00000000000000000000000000000000.r2.cloudflarestorage.com/synthetic-only/${ns}/${id.scan_id}/${object}`;
  for (const item of original.mapping.items) {
    for (
      const role of [item.source, ...(item.prepared ? [item.prepared] : [])]
    ) {
      const key = url("initial-preparation/v2", role.original_object_id);
      sourceURLs.push(key);
      const spec = input.specs.find((s: { sha256: string }) =>
        s.sha256 === role.bytes.sha256
      );
      assert(spec && spec.byte_count === role.bytes.byte_count);
      assert(Number.isInteger(spec.fill) && spec.fill >= 0 && spec.fill <= 255);
      if (!objects.has(key)) {
        objects.set(key, new Uint8Array(spec.byte_count).fill(spec.fill));
      }
      types.set(key, role.bytes.content_type);
    }
  }
  assertEquals(sourceURLs.length, input.alias_count);
  assertEquals(objects.size, input.object_count);
  for (const object of original.mapping.objects) {
    const key = url("initial-analysis/v1", object.object_id);
    destinationURLs.push(key);
    types.set(key, object.bytes.content_type);
  }
  let activeSQL = 0, activeIO = 0;
  const bridge: HandoffBridge = { ...real };
  for (const name of Object.keys(real) as (keyof HandoffBridge)[]) {
    // Proxy preserves each fixed method's arguments; no SQL or connection input.
    Object.defineProperty(bridge, name, {
      value: async (...args: unknown[]) => {
        assertEquals(activeIO, 0);
        assertEquals(activeSQL, 0);
        activeSQL++;
        const began = performance.now();
        const record = { name, ms: 0, acknowledged: false };
        calls.push(record);
        try {
          const call = real[name] as (...args: unknown[]) => Promise<unknown>;
          const result = await call(...args);
          record.acknowledged = true;
          assert(performance.now() - began < 5000);
          return result;
        } finally {
          record.ms = Math.ceil(performance.now() - began);
          activeSQL--;
          sample();
        }
      },
    });
  }
  const baseline = Deno.memoryUsage();
  const timer = setInterval(sample, 10);
  stage = "coordinator";
  const began = performance.now();
  try {
    const result = await executeOriginalMediaHandoff(
      {
        bridge,
        attest: (rows) => {
          assertEquals(rows.original, original.original);
          return Promise.resolve({
            copy_adapter_digest: original.handoff.copy_adapter_digest,
            verification_adapter_digest:
              original.handoff.verification_adapter_digest,
            protocol_artifact_digest: original.handoff.protocol_artifact_digest,
          });
        },
        storage: {
          sign: (profile, request) => {
            assertEquals(activeSQL, 0);
            assertEquals(profile, "synthetic_only");
            return Promise.resolve(request);
          },
          fetch: async (input) => {
            assertEquals(activeSQL, 0);
            assertEquals(activeIO, 0);
            activeIO++;
            try {
              const r = input as Request;
              assert(types.has(r.url));
              io.push(r.method + " " + r.url);
              if (r.method === "PUT") {
                assert(destinationURLs.includes(r.url));
                assertEquals(r.headers.get("if-none-match"), "*");
                assert(!objects.has(r.url));
                objects.set(r.url, new Uint8Array(await r.arrayBuffer()));
                return new Response(null, { status: 200 });
              }
              assertEquals(r.method, "GET");
              const value = objects.get(r.url);
              assert(value);
              return new Response(value.slice(), {
                headers: {
                  "Content-Type": types.get(r.url)!,
                  "Content-Length": String(value.length),
                  "Cache-Control": "private, no-store",
                },
              });
            } finally {
              activeIO--;
              sample();
            }
          },
        },
      },
      id,
      signal,
    );
    const elapsed = Math.ceil(performance.now() - began);
    // Unknown/deadline outcomes retain observations and stop. They never pass
    // positive full-cohort acceptance, replay a mutation or renew a deadline.
    if (result.outcome !== "transferred") {
      console.log(
        JSON.stringify({
          passed: false,
          outcome: result.outcome,
          recovered: result.recovered !== null,
          coordinator_ms: elapsed,
          sql_calls: calls,
          storage_operations: io.length,
          baseline,
          peak,
        }),
      );
      Deno.exitCode = 1;
      return;
    }
    assertEquals(activeSQL, 0);
    assertEquals(activeIO, 0);
    assert(calls.every((x) => x.acknowledged));
    assertEquals(
      io.filter((x) => x.startsWith("PUT ")).sort(),
      destinationURLs.map((x) => "PUT " + x).sort(),
    );
    assertEquals(
      io.filter((x) => x.startsWith("GET ")).sort(),
      [...sourceURLs, ...destinationURLs, ...destinationURLs].map((x) =>
        "GET " + x
      ).sort(),
    );
    stage = "durable_state";
    const final = await decodeHandoffState(
      await real.readState(id, signal),
      id,
    );
    assertEquals(final.original, original.original);
    assertEquals(final.transfer?.digest, result.transferDigest);
    console.log(
      JSON.stringify({
        passed: true,
        shape: input.shape,
        coordinator_ms: elapsed,
        source_aliases: sourceURLs.length,
        destinations: destinationURLs.length,
        unique_bytes: input.unique_bytes,
        sql_calls: calls,
        storage_operations: io.length,
        baseline,
        peak,
        no_sql_during_io: true,
      }),
    );
  } finally {
    clearInterval(timer);
  }
}
if (import.meta.main) {
  try {
    await initialDeadline(new AbortController().signal, 85000, main);
  } catch {
    console.log(
      JSON.stringify({
        passed: false,
        error: "local_resource_qualification_failed",
        stage,
        sql_calls: calls,
        storage_operations: io.length,
        peak,
      }),
    );
    Deno.exitCode = 1;
  }
}
