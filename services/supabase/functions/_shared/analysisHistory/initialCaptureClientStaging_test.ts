import { assert, assertEquals, assertRejects } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import { evidenceDigest } from "./evidence.ts";
import {
  initialCaptureClientRepository,
  uploadInitialCaptureClientArtifact,
} from "./initialCaptureClientStaging.ts";
import { initialCaptureAudioStageRequest } from "./initialCaptureAudioStaging.ts";
import { parseInitialEvidenceCapturePlan } from "./initialEvidenceCapturePlan.ts";
const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
async function fixture() {
  const bytes = new Uint8Array(100).fill(1);
  const value = {
    schema_version: 1,
    scan_id: id(2),
    generation: id(3),
    items: [{
      kind: "audio",
      source: {
        media_id: id(4),
        content_type: "audio/wav",
        byte_count: bytes.length,
        sha256: await evidenceDigest(bytes),
      },
      prepared_media_id: id(5),
    }],
  };
  const plan = parseInitialEvidenceCapturePlan(id(1), value),
    request = await initialCaptureAudioStageRequest(plan);
  let written = false,
    ready = false,
    stored: Uint8Array | null = null,
    corrupted = false,
    loseWrite = false,
    writes = 0,
    reads = 0,
    failVerify = false;
  const calls: Record<string, unknown>[] = [];
  const row = () => ({
    request_sha256: request.request_sha256,
    object_id: id(6),
    artifact: plan.uploads[0],
    write_issued: written,
    ready,
  });
  const client = {
    rpc(name: string, args: Record<string, unknown>) {
      assertEquals(name, "initial_capture_client_stage_action");
      calls.push(args);
      return {
        abortSignal: (_signal: AbortSignal) => {
          let data: unknown;
          switch (args.p_action) {
            case "reserve":
              data = row();
              break;
            case "write":
              data = !written;
              written = true;
              break;
            case "verify":
              data = written && !failVerify;
              break;
            case "read":
              data = ready;
              break;
            case "complete":
              assert(written);
              ready = true;
              data = row();
              break;
            default:
              throw new Error("unexpected action");
          }
          return Promise.resolve({ data, error: null });
        },
      };
    },
  } as unknown as SupabaseClient;
  const repository = await initialCaptureClientRepository(
    plan,
    client,
    "b".repeat(64),
  );
  const services = {
    repository,
    storage: {
      writeOnce(_object: unknown, input: Uint8Array, _signal: AbortSignal) {
        writes++;
        stored = input.slice();
        return loseWrite
          ? Promise.reject(new Error("lost_write_ack"))
          : Promise.resolve();
      },
      openBoundStream(_object: unknown, _signal: AbortSignal) {
        reads++;
        if (!stored) return Promise.reject(new Error("missing_object"));
        return Promise.resolve(
          new ReadableStream<Uint8Array>({
            start(c) {
              c.enqueue(
                corrupted ? new Uint8Array(100).fill(9) : stored!.slice(),
              );
              c.close();
            },
          }),
        );
      },
    },
  };
  const submit = (
    media = id(4),
    input = bytes,
    candidate: unknown = value,
    signal = new AbortController().signal,
  ) =>
    uploadInitialCaptureClientArtifact(
      id(1),
      candidate,
      media,
      input,
      () => Promise.resolve(services),
      signal,
    );
  return {
    submit,
    calls,
    plan,
    request,
    value,
    bytes,
    services,
    repository,
    counts: () => ({ writes, reads, ready, written }),
    corrupt: () => corrupted = true,
    loseWrite: () => loseWrite = true,
    remove: () => stored = null,
    failVerify: () => failVerify = true,
  };
}
Deno.test("client private upload freezes incoming bytes, validates full readback, and hides storage authority", async () => {
  const f = await fixture();
  const bytes = f.bytes.slice(), candidate = structuredClone(f.value);
  const pending = f.submit(id(4), bytes, candidate);
  bytes[0] = 7;
  candidate.items[0].source.sha256 = "c".repeat(64);
  const result = await pending;
  assertEquals(result, {
    schema_version: 1,
    scan_id: id(2),
    generation: id(3),
    request_sha256: f.request.request_sha256,
    media_id: id(4),
    ready: true,
  });
  assertEquals(f.counts(), { writes: 1, reads: 1, ready: true, written: true });
  assertEquals(await f.submit(), result);
  assertEquals(f.counts(), { writes: 1, reads: 2, ready: true, written: true });
  assertEquals(f.calls.map((x) => x.p_action), [
    "reserve",
    "write",
    "verify",
    "complete",
    "reserve",
    "verify",
  ]);
  assert(
    f.calls.every((x) =>
      !Object.keys(x).some((key) =>
        ["p_object", "p_role", "p_artifacts"].includes(key)
      )
    ),
  );
});
Deno.test("client cannot upload server DSP identity or wrong bytes, even before reserve", async () => {
  const f = await fixture();
  await assertRejects(() => f.submit(id(5)));
  await assertRejects(() => f.submit(id(4), new Uint8Array([3, 2, 1])));
  await assertRejects(() => f.submit(id(4), new Uint8Array([1, 2])));
  assertEquals(f.calls, []);
});
Deno.test("lost client write acknowledgement only recovers readback; missing bytes never reopen PUT", async () => {
  const f = await fixture();
  f.loseWrite();
  await assertRejects(() => f.submit());
  assertEquals(f.counts(), {
    writes: 1,
    reads: 0,
    ready: false,
    written: true,
  });
  await f.submit();
  assertEquals(f.counts(), { writes: 1, reads: 1, ready: true, written: true });
  f.remove();
  await assertRejects(() => f.submit());
  assertEquals(f.counts().writes, 1);
});
Deno.test("private readback mismatch never marks client ready or authorizes preparation", async () => {
  const f = await fixture();
  f.corrupt();
  await assertRejects(() => f.submit());
  assertEquals(f.counts(), {
    writes: 1,
    reads: 1,
    ready: false,
    written: true,
  });
  assert(!f.calls.some((x) => x.p_action === "complete"));
});
Deno.test("retirement denial before readback preserves write obligation and stops completion", async () => {
  const f = await fixture();
  f.failVerify();
  await assertRejects(() => f.submit());
  assertEquals(f.counts(), {
    writes: 1,
    reads: 0,
    ready: false,
    written: true,
  });
});
Deno.test("cancelled client upload has no database or storage authority", async () => {
  const f = await fixture();
  const controller = new AbortController();
  controller.abort();
  await assertRejects(() =>
    f.submit(id(4), f.bytes, f.value, controller.signal)
  );
  assertEquals(f.calls, []);
});
