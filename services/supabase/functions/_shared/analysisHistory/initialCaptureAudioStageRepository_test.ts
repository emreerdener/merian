import { assertEquals, assertRejects } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  initialCaptureAudioStageRepository,
  initialCaptureAudioStageStorage,
} from "./initialCaptureAudioStageRepository.ts";
import { initialCaptureAudioStageRequest } from "./initialCaptureAudioStaging.ts";
import { parseInitialEvidenceCapturePlan } from "./initialEvidenceCapturePlan.ts";
import {
  getHistoryEvidenceConfig,
  PrivateCaptureStageObjectStorage,
} from "./evidenceStorage.ts";
import { evidenceDigest } from "./evidence.ts";

const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
async function fixture(
  reply: (
    args: Record<string, unknown>,
    signal: AbortSignal,
  ) => Promise<{ data: unknown; error: null | { message: string } }> = () =>
    Promise.resolve({ data: true, error: null }),
) {
  const bytes = new Uint8Array(16044), hash = await evidenceDigest(bytes);
  const plan = parseInitialEvidenceCapturePlan(id(1), {
    schema_version: 1,
    scan_id: id(2),
    generation: id(3),
    items: [
      {
        kind: "audio",
        source: {
          media_id: id(4),
          content_type: "audio/wav",
          byte_count: 16044,
          sha256: hash,
        },
        prepared_media_id: id(5),
      },
    ],
  });
  const request = await initialCaptureAudioStageRequest(plan);
  const object = {
    object_id: id(6),
    media_id: id(5),
    ready: false,
    artifact: {
      media_id: id(5),
      content_type: "audio/wav",
      byte_count: 16044,
      sha256: hash,
    },
  };
  const calls: Record<string, unknown>[] = [];
  const client = {
    rpc(name: string, args: Record<string, unknown>) {
      assertEquals(name, "initial_capture_audio_stage_action");
      return {
        abortSignal(signal: AbortSignal) {
          calls.push(args);
          return reply(args, signal);
        },
      };
    },
  } as unknown as SupabaseClient;
  const repository = initialCaptureAudioStageRepository(client, "a".repeat(64));
  return { request, object, repository, calls, bytes };
}

Deno.test("stage RPC owns full canonical request and artifacts before suspension", async () => {
  const f = await fixture();
  const request = structuredClone(f.request),
    artifacts = [structuredClone(f.object.artifact)];
  const pending = f.repository.bind(
    request,
    id(7),
    artifacts,
    new AbortController().signal,
  );
  // Deliberately mutate otherwise-readonly input through its serialized boundary.
  Object.assign(request, { recipe: "changed" });
  artifacts[0].sha256 = "d".repeat(64);
  await pending;
  assertEquals(f.calls.length, 1);
  const call = f.calls[0];
  assertEquals(call.p_action, "bind");
  assertEquals(call.p_artifacts, [f.object.artifact]);
  assertEquals(call.p_attempt, id(7));
  assertEquals(
    call.p_sha256,
    await evidenceDigest(new TextEncoder().encode(call.p_request as string)),
  );
  assertEquals(JSON.parse(call.p_request as string), {
    owner_id: f.request.owner_id,
    plan: f.request.plan,
    recipe: f.request.recipe,
  });
});

Deno.test("stage RPC rejects a forged request hash without database I/O", async () => {
  const f = await fixture();
  await assertRejects(() =>
    f.repository.reserve(
      { ...f.request, request_sha256: "0".repeat(64) },
      id(7),
      new AbortController().signal,
    )
  );
  assertEquals(f.calls, []);
});

Deno.test("cancelled or lost stage authorization never retries or authorizes storage", async () => {
  let entered!: () => void,
    finish!: (reply: { data: unknown; error: null }) => void;
  const started = new Promise<void>((resolve) => entered = resolve);
  const f = await fixture(() => {
    entered();
    return new Promise((resolve) => finish = resolve);
  });
  const controller = new AbortController();
  const pending = f.repository.authorize(
    f.request,
    f.object,
    "write",
    controller.signal,
  );
  await started;
  controller.abort();
  await assertRejects(() => pending);
  finish({ data: true, error: null });
  await Promise.resolve();
  assertEquals(f.calls.length, 1);
});

Deno.test("stage storage checks exact bytes before consuming a write and denies nontrue authorization", async () => {
  const f = await fixture(() => Promise.resolve({ data: false, error: null }));
  let io = 0;
  const objects = new PrivateCaptureStageObjectStorage(() => {
    io++;
    throw new Error("unexpected I/O");
  });
  const storage = initialCaptureAudioStageStorage(
      f.request,
      f.repository,
      objects,
    ),
    signal = new AbortController().signal;
  await assertRejects(() =>
    storage.writeOnce(f.object, new Uint8Array(1), signal)
  );
  assertEquals(f.calls.length, 0);
  await assertRejects(() => storage.writeOnce(f.object, f.bytes, signal));
  await assertRejects(() => storage.read(f.object, signal));
  assertEquals(f.calls.map((c) => c.p_action), ["write", "read"]);
  assertEquals(io, 0);
});

Deno.test("stage storage freshly authorizes each I/O and uses only the private stage namespace", async () => {
  const trace: string[] = [];
  const f = await fixture((args) => {
    trace.push(String(args.p_action));
    return Promise.resolve({ data: true, error: null });
  });
  const config = getHistoryEvidenceConfig("write", (key) => ({
    R2_ACCOUNT_ID: "a".repeat(32),
    R2_BUCKET_NAME: "synthetic-public",
    R2_SCANS_PRIVATE_BUCKET_NAME: "synthetic-private",
    R2_SCANS_PRIVATE_WRITE_ACCESS_KEY_ID: "synthetic-key",
    R2_SCANS_PRIVATE_WRITE_SECRET_ACCESS_KEY: "synthetic-secret",
  }[key]));
  const headers = new Headers({
    "content-type": "audio/wav",
    "content-length": String(f.bytes.length),
    "x-amz-meta-sha256": f.object.artifact.sha256,
  });
  const objects = new PrivateCaptureStageObjectStorage(
    () => config,
    () => config,
    async (request) => {
      trace.push(request.method);
      assertEquals(
        new URL(request.url).pathname,
        `/synthetic-private/capture-stage/v1/${id(6)}`,
      );
      if (request.method === "PUT") {
        assertEquals(request.headers.get("if-none-match"), "*");
        assertEquals(new Uint8Array(await request.arrayBuffer()), f.bytes);
      }
      return new Response(request.method === "GET" ? f.bytes : null, {
        headers,
      });
    },
  );
  const storage = initialCaptureAudioStageStorage(
      f.request,
      f.repository,
      objects,
    ),
    signal = new AbortController().signal;
  await storage.writeOnce(f.object, f.bytes, signal);
  const stream = await storage.read(f.object, signal);
  assertEquals(
    new Uint8Array(await new Response(stream).arrayBuffer()),
    f.bytes,
  );
  assertEquals(trace, ["write", "PUT", "HEAD", "read", "GET"]);
});
