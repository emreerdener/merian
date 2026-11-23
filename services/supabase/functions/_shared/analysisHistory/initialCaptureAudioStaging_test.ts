import { assertEquals, assertRejects } from "@std/assert";
import { encodeWav16 } from "../../audio-spec/wav.ts";
import { evidenceDigest } from "./evidence.ts";
import { parseInitialEvidenceCapturePlan } from "./initialEvidenceCapturePlan.ts";
import {
  type InitialCaptureAudioStageReceipt,
  type InitialCaptureAudioStageRepository,
  type InitialCaptureAudioStageStorage,
  stageInitialCaptureAudio,
} from "./initialCaptureAudioStaging.ts";

const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const stream = (bytes: Uint8Array) =>
  new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(bytes.slice());
      controller.close();
    },
  });
async function fixture(count = 1) {
  const samples = new Float32Array(44_100);
  for (let index = 0; index < samples.length; index++) {
    samples[index] = 0.2 * Math.sin(index * 0.15);
  }
  const bytes = encodeWav16(samples, 44_100);
  const hash = await evidenceDigest(bytes);
  const plan = parseInitialEvidenceCapturePlan(id(1), {
    schema_version: 1,
    scan_id: id(2),
    generation: id(3),
    items: Array.from(
      { length: count },
      (_, index) => ({
        kind: "audio",
        source: {
          media_id: id(10 + index * 2),
          content_type: "audio/wav",
          byte_count: bytes.length,
          sha256: hash,
        },
        prepared_media_id: id(11 + index * 2),
      }),
    ),
  });
  const trace: string[] = [];
  let saved: InitialCaptureAudioStageReceipt | null = null;
  let bindLost = false, writeLost = false, completeLost = false;
  const objects = new Map<string, Uint8Array>();
  const repository: InitialCaptureAudioStageRepository = {
    reserve(request, attempt) {
      trace.push("reserve");
      assertEquals(request.owner_id, plan.ownerID);
      assertEquals(request.plan.scan_id, plan.scanID);
      saved ??= {
        request_sha256: request.request_sha256,
        attempt_id: attempt,
        items: plan.audio.map((slot, index) => ({
          object_id: id(50 + index),
          media_id: slot.preparedID,
          artifact: null,
          ready: false,
        })),
      };
      if (!saved.request_sha256) {
        saved = { ...saved, request_sha256: request.request_sha256 };
      }
      return Promise.resolve(structuredClone(saved));
    },
    bind(_request, attempt, artifacts) {
      trace.push("bind");
      if (
        !saved || saved.attempt_id !== attempt ||
        saved.items.some((item) => item.artifact)
      ) throw new Error("conflict");
      saved = {
        ...saved,
        items: saved.items.map((item, index) => ({
          ...item,
          artifact: artifacts[index],
        })),
      };
      if (bindLost) throw new Error("synthetic lost bind acknowledgement");
      return Promise.resolve(structuredClone(saved));
    },
    complete(_request, object) {
      trace.push("complete");
      if (!saved) throw new Error("missing");
      saved = {
        ...saved,
        items: saved.items.map((item) => ({
          ...item,
          ready: item.ready || item.object_id === object.object_id,
        })),
      };
      if (completeLost) {
        throw new Error("synthetic lost completion acknowledgement");
      }
      return Promise.resolve(structuredClone(saved));
    },
  };
  const storage: InitialCaptureAudioStageStorage = {
    writeOnce(object, input) {
      trace.push("write");
      if (objects.has(object.object_id)) throw new Error("overwrite forbidden");
      objects.set(object.object_id, input.slice());
      if (writeLost) throw new Error("synthetic lost PUT acknowledgement");
      return Promise.resolve();
    },
    read(object) {
      trace.push("read");
      const output = objects.get(object.object_id);
      if (!output) throw new Error("missing");
      return Promise.resolve(stream(output));
    },
  };
  const source = {
    read() {
      trace.push("source");
      return Promise.resolve(stream(bytes));
    },
  };
  return {
    plan,
    trace,
    repository,
    storage,
    source,
    objects,
    get saved() {
      return saved;
    },
    set saved(value: InitialCaptureAudioStageReceipt | null) {
      saved = value;
    },
    lose(kind: string) {
      bindLost = kind === "bind";
      writeLost = kind === "write";
      completeLost = kind === "complete";
    },
    run(attempt = id(4), signal = new AbortController().signal) {
      return stageInitialCaptureAudio(
        plan,
        attempt,
        source,
        repository,
        storage,
        signal,
      );
    },
  };
}

Deno.test("audio staging records obligations before DSP, binds before write and verifies all before completion", async () => {
  const f = await fixture(2), result = await f.run();
  assertEquals(f.trace, [
    "reserve",
    "source",
    "source",
    "bind",
    "write",
    "read",
    "write",
    "read",
    "complete",
    "complete",
  ]);
  assertEquals(result.stage?.items.every((item) => item.ready), true);
  f.trace.length = 0;
  const cold = await f.run(id(5));
  assertEquals(f.trace, ["reserve", "read", "read"]);
  assertEquals(cold.result.request, result.result.request);
  assertEquals(cold.result.audioBase64s, result.result.audioBase64s);
});

Deno.test("lost output bind never grants a write or silently recomputes after retry", async () => {
  const f = await fixture();
  f.lose("bind");
  await assertRejects(() => f.run());
  assertEquals(f.trace, ["reserve", "source", "bind"]);
  f.lose("");
  f.trace.length = 0;
  await assertRejects(() => f.run(id(5)));
  assertEquals(f.trace, ["reserve", "read"]);
  assertEquals(f.objects.size, 0);
});

Deno.test("lost PUT and completion acknowledgements recover destination bytes without a second DSP or write", async () => {
  for (const failure of ["write", "complete"]) {
    const f = await fixture();
    f.lose(failure);
    await assertRejects(() => f.run());
    f.lose("");
    f.trace.length = 0;
    const recovered = await f.run(id(5));
    assertEquals(
      f.trace,
      failure === "write"
        ? ["reserve", "read", "complete"]
        : ["reserve", "read"],
    );
    assertEquals(recovered.stage?.items.every((item) => item.ready), true);
  }
});

Deno.test("a different unfinished attempt stays held and cannot prepare replacement audio", async () => {
  const f = await fixture();
  f.saved = {
    request_sha256: "",
    attempt_id: id(5),
    items: [{
      object_id: id(50),
      media_id: id(11),
      artifact: null,
      ready: false,
    }],
  };
  await assertRejects(() => f.run());
  assertEquals(f.trace, ["reserve"]);
});

Deno.test("changed bound bytes prevent completion of every item and never fall back to the raw input", async () => {
  const f = await fixture(2);
  const originalRead = f.storage.read;
  f.storage.read = async (object, signal) => {
    const bytes = new Uint8Array(
      await new Response(await originalRead(object, signal)).arrayBuffer(),
    );
    if (object.media_id === id(13)) bytes[60] ^= 1;
    return stream(bytes);
  };
  await assertRejects(() => f.run());
  assertEquals(f.trace.includes("complete"), false);
  f.trace.length = 0;
  await assertRejects(() => f.run(id(5)));
  assertEquals(f.trace, ["reserve", "read", "read"]);
});

Deno.test("changed receipt identities, ready regression and cancellation cannot authorize more work", async () => {
  const f = await fixture();
  const reserve = f.repository.reserve;
  f.repository.reserve = async (...args) => {
    const saved = await reserve(...args) as InitialCaptureAudioStageReceipt;
    return {
      ...saved,
      items: saved.items.map((item) => ({ ...item, object_id: id(1) })),
    };
  };
  await assertRejects(() => f.run());
  assertEquals(f.trace, ["reserve"]);
  const g = await fixture();
  const bind = g.repository.bind;
  const controller = new AbortController();
  g.repository.bind = async (...args) => {
    const result = await bind(...args);
    controller.abort();
    return result;
  };
  await assertRejects(() => g.run(id(4), controller.signal));
  assertEquals(g.trace, ["reserve", "source", "bind"]);
  const h = await fixture(2), complete = h.repository.complete;
  h.repository.complete = async (...args) => {
    const result = await complete(...args) as InitialCaptureAudioStageReceipt;
    return {
      ...result,
      items: result.items.map((item, index) =>
        index === 0 ? { ...item, ready: false } : item
      ),
    };
  };
  await assertRejects(() => h.run());
  assertEquals(h.trace.filter((item) => item === "complete").length, 1);
});

Deno.test("staging rejects another plan or recipe binding even when media IDs match", async () => {
  const f = await fixture();
  const reserve = f.repository.reserve;
  f.repository.reserve = async (...args) => ({
    ...await reserve(...args) as InitialCaptureAudioStageReceipt,
    request_sha256: "0".repeat(64),
  });
  await assertRejects(() => f.run());
  assertEquals(f.trace, ["reserve"]);
});

Deno.test("staging bounds actual raw and prepared stream bytes and cancels oversized bodies", async () => {
  for (const kind of ["source", "prepared"]) {
    const f = await fixture();
    let cancelled = false;
    const oversized = () =>
      Promise.resolve(
        new ReadableStream<Uint8Array>({
          start(controller) {
            controller.enqueue(new Uint8Array(2_700_001));
          },
          cancel() {
            cancelled = true;
          },
        }),
      );
    if (kind === "source") f.source.read = oversized;
    else f.storage.read = oversized;
    await assertRejects(() => f.run());
    assertEquals(cancelled, true);
    assertEquals(f.trace.includes("complete"), false);
    if (kind === "source") assertEquals(f.trace, ["reserve"]);
  }
});

Deno.test("cancellation during a stalled source read discards and cancels a late stream", async () => {
  const f = await fixture(), controller = new AbortController();
  let opened!: () => void;
  const opening = new Promise<void>((resolve) => {
    opened = resolve;
  });
  let deliver!: (stream: ReadableStream<Uint8Array>) => void;
  f.source.read = () => {
    opened();
    return new Promise((resolve) => {
      deliver = resolve;
    });
  };
  const pending = f.run(id(4), controller.signal);
  await opening;
  controller.abort();
  await assertRejects(() => pending);
  let cancelled!: () => void;
  const cancellation = new Promise<void>((resolve) => {
    cancelled = resolve;
  });
  deliver(
    new ReadableStream<Uint8Array>({
      cancel() {
        cancelled();
      },
    }),
  );
  await cancellation;
  assertEquals(f.trace, ["reserve"]);
});
