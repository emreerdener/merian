import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import type { SupabaseClient } from "@supabase/supabase-js";

import { PublicHttpError } from "./http.ts";
import {
  buildCompatibilityScanIngestionIntent,
  createCompatibilityScanIngestionLedger,
} from "./scanIngestionCompatibility.ts";

Deno.test("buildCompatibilityScanIngestionIntent maps staged legacy images to multimodal replay payload", async () => {
  const intent = await buildCompatibilityScanIngestionIntent({
    scanId: "scan-1",
    endpoint: "identify",
    imageKeys: [" staging/user-1/image.webp ", "staging/user-1/image.webp"],
    description: "White bands on leaf underside.",
    mimeType: "image/webp",
    telemetry: {
      timestamp: "2026-07-05T03:00:00.000Z",
      gpsLatitude: 30.1,
      gpsLongitude: -97.7,
      currentMonth: 7,
    },
    uploadSessionIds: ["session-b", " session-a ", "session-a"],
    preferredGoal: {
      user_field_trip_id: "00000000-0000-4000-8000-000000000001",
      item_id: "00000000-0000-4000-8000-000000000002",
    },
  });

  assertEquals(intent.resumable, true);
  assertEquals(intent.inlineMediaRedacted, false);
  assertEquals(intent.mediaCounts, {
    image_count: 1,
    audio_count: 0,
    video_count: 0,
    required_video_count: 0,
    video_frame_count: 0,
    video_inference_frame_count: 0,
    has_description: true,
  });
  assertEquals(intent.mediaObjectKeys, {
    image: ["staging/user-1/image.webp"],
    audio: [],
    video: [],
  });
  assertEquals(intent.uploadSessionIds, ["session-a", "session-b"]);
  assertEquals(intent.payloadChecksum.length, 64);
  assertEquals(intent.requestPayload.endpoint, "identify-multimodal");
  assertEquals(intent.requestPayload.compatibilityEndpoint, "identify");
  assertEquals(intent.requestPayload.media, {
    r2ObjectKeys: ["staging/user-1/image.webp"],
    audioR2ObjectKeys: [],
    videoR2ObjectKeys: [],
    videoFrameCount: 0,
    visualMediaItems: [],
    audioMediaItems: [],
    mimeType: "image/webp",
  });
  assertEquals(intent.requestPayload.observationContexts, [
    { freeText: "White bands on leaf underside." },
  ]);
  assertEquals(intent.requestPayload.preferredGoal, {
    userFieldTripId: "00000000-0000-4000-8000-000000000001",
    itemId: "00000000-0000-4000-8000-000000000002",
  });
});

Deno.test("buildCompatibilityScanIngestionIntent redacts inline media and blocks server replay", async () => {
  const intent = await buildCompatibilityScanIngestionIntent({
    scanId: "scan-1",
    endpoint: "identify",
    inlineImageCount: 2,
    inlineAudioCount: 1,
    description: "Nearby creek.",
  });

  assertEquals(intent.resumable, false);
  assertEquals(intent.inlineMediaRedacted, true);
  assertEquals(intent.redactedMediaCounts, {
    image_base64_count: 2,
    audio_base64_count: 1,
  });
  assertEquals(
    JSON.stringify(intent.requestPayload).includes("raw-image"),
    false,
  );
  assertEquals(
    JSON.stringify(intent.requestPayload).includes("raw-audio"),
    false,
  );
});

Deno.test("buildCompatibilityScanIngestionIntent keeps describe-only rows replayable", async () => {
  const intent = await buildCompatibilityScanIngestionIntent({
    scanId: "scan-1",
    endpoint: "identify-describe",
    description: "Small brown mushroom growing from a lawn after rain.",
    telemetry: { semanticLocation: "Austin, TX", currentMonth: 7 },
  });

  assertEquals(intent.resumable, true);
  assertEquals(intent.mediaCounts.has_description, true);
  assertEquals(intent.mediaCounts.image_count, 0);
  assertEquals(intent.mediaCounts.audio_count, 0);
  assertEquals(intent.requestPayload.observationContexts, [
    { freeText: "Small brown mushroom growing from a lawn after rain." },
  ]);
});

Deno.test("buildCompatibilityScanIngestionIntent keeps staged legacy audio replayable", async () => {
  const intent = await buildCompatibilityScanIngestionIntent({
    scanId: "scan-1",
    endpoint: "audio-spec",
    audioKeys: ["staging/user-1/audio.wav"],
    audioMediaItems: [{ kind: "audio", sourceIndex: 0, clipIndex: 0 }],
  });

  assertEquals(intent.resumable, true);
  assertEquals(intent.mediaCounts.audio_count, 1);
  assertEquals(intent.requestPayload.media, {
    r2ObjectKeys: [],
    audioR2ObjectKeys: ["staging/user-1/audio.wav"],
    videoR2ObjectKeys: [],
    videoFrameCount: 0,
    visualMediaItems: [],
    audioMediaItems: [{ kind: "audio", sourceIndex: 0, clipIndex: 0 }],
  });
});

function compatibilityClient(options: {
  alreadyComplete?: boolean;
  beginError?: { message: string } | null;
  finalizationError?: { message: string } | null;
  rpcCalls?: Array<{ name: string; arguments_: Record<string, unknown> }>;
  updates?: Array<Record<string, unknown>>;
} = {}): SupabaseClient {
  const rpcCalls = options.rpcCalls ?? [];
  const updates = options.updates ?? [];
  const query = {
    update(value: Record<string, unknown>) {
      updates.push(value);
      return query;
    },
    eq() {
      return query;
    },
    neq() {
      return query;
    },
    then(
      onFulfilled?: (
        value: { error: null },
      ) => unknown,
      onRejected?: (reason: unknown) => unknown,
    ) {
      return Promise.resolve({ error: null }).then(onFulfilled, onRejected);
    },
  };
  return {
    rpc(name: string, arguments_: Record<string, unknown>) {
      rpcCalls.push({ name, arguments_ });
      if (
        name === "complete_scan_ingestion_finalization" ||
        name === "complete_scan_ingestion_finalization_with_response"
      ) {
        return Promise.resolve({
          data: options.finalizationError ? null : "completed",
          error: options.finalizationError ?? null,
        });
      }
      return Promise.resolve({
        data: options.beginError ? null : {
          upload_session_ids: [
            "00000000-0000-4000-8000-000000000301",
          ],
          manifest_checksum: "a".repeat(64),
          payload_checksum: "b".repeat(64),
          stage: options.alreadyComplete
            ? "client_recovery_complete"
            : "ai_inference_started",
          already_complete: options.alreadyComplete ?? false,
        },
        error: options.beginError ?? null,
      });
    },
    from(name: string) {
      assertEquals(name, "scan_ingestion_jobs");
      return query;
    },
  } as unknown as SupabaseClient;
}

Deno.test("compatibility ledger atomically establishes ownership before provider work", async () => {
  const rpcCalls: Array<{
    name: string;
    arguments_: Record<string, unknown>;
  }> = [];
  const updates: Array<Record<string, unknown>> = [];
  const ledger = await createCompatibilityScanIngestionLedger(
    {
      scanId: "00000000-0000-4000-8000-000000000201",
      userId: "00000000-0000-4000-8000-000000000202",
      endpoint: "identify",
      imageKeys: [
        "staging/00000000-0000-4000-8000-000000000202/frame.webp",
      ],
    },
    compatibilityClient({ rpcCalls, updates }),
  );

  assertEquals(rpcCalls.length, 1);
  assertEquals(rpcCalls[0].name, "begin_scan_ingestion");
  assertEquals(rpcCalls[0].arguments_.p_storage_keys, [
    "staging/00000000-0000-4000-8000-000000000202/frame.webp",
  ]);
  assertEquals(ledger.intent.uploadSessionIds, [
    "00000000-0000-4000-8000-000000000301",
  ]);
  assertEquals(ledger.intent.manifestChecksum, "a".repeat(64));
  assertEquals(ledger.intent.payloadChecksum, "b".repeat(64));
  assertEquals(updates.length, 0);
  await ledger.mark("finalizing", "background_ingestion_queued", {
    leaseSeconds: 300,
  });
  assertEquals(updates[0].status, "finalizing");
  assertEquals(updates[0].stage, "background_ingestion_queued");
});

Deno.test("compatibility completion forwards the canonical replay envelope", async () => {
  const rpcCalls: Array<{
    name: string;
    arguments_: Record<string, unknown>;
  }> = [];
  const scanId = "00000000-0000-4000-8000-000000000221";
  const responseEnvelope = {
    success: true,
    data: { scan_id: scanId },
  };
  const ledger = await createCompatibilityScanIngestionLedger(
    {
      scanId,
      userId: "00000000-0000-4000-8000-000000000222",
      endpoint: "identify-describe",
      description: "A tall gray wading bird.",
    },
    compatibilityClient({ rpcCalls }),
  );

  await ledger.markComplete({ responseEnvelope });

  assertEquals(
    rpcCalls[1].name,
    "complete_scan_ingestion_finalization_with_response",
  );
  assertEquals(rpcCalls[1].arguments_.p_response_envelope, responseEnvelope);
});

Deno.test("compatibility finalization failures become durable retryable work", async () => {
  const updates: Array<Record<string, unknown>> = [];
  const ledger = await createCompatibilityScanIngestionLedger(
    {
      scanId: "00000000-0000-4000-8000-000000000211",
      userId: "00000000-0000-4000-8000-000000000212",
      endpoint: "identify-describe",
      description: "A small brown mushroom after rain.",
    },
    compatibilityClient({
      updates,
      finalizationError: { message: "temporary finalization failure" },
    }),
  );

  await assertRejects(
    () => ledger.markComplete(),
    Error,
    "temporary finalization failure",
  );
  assertEquals(updates.length, 1);
  assertEquals(updates[0].status, "failed_retryable");
  assertEquals(updates[0].stage, "media_finalization_failed");
  assertEquals(typeof updates[0].retry_after, "string");
});

Deno.test("compatibility ledger fails closed on completed or unavailable generation setup", async () => {
  const alreadyComplete = await assertRejects(
    () =>
      createCompatibilityScanIngestionLedger(
        {
          scanId: "00000000-0000-4000-8000-000000000201",
          userId: "00000000-0000-4000-8000-000000000202",
          endpoint: "identify-describe",
          description: "Brown cap.",
        },
        compatibilityClient({ alreadyComplete: true }),
      ),
    PublicHttpError,
  );
  assertEquals(alreadyComplete.status, 409);
  assertEquals(alreadyComplete.code, "scan_already_complete");

  const unavailable = await assertRejects(
    () =>
      createCompatibilityScanIngestionLedger(
        {
          scanId: "00000000-0000-4000-8000-000000000201",
          userId: "00000000-0000-4000-8000-000000000202",
          endpoint: "audio-spec",
          audioKeys: [
            "staging/00000000-0000-4000-8000-000000000202/audio.wav",
          ],
        },
        compatibilityClient({ beginError: { message: "offline" } }),
      ),
    PublicHttpError,
  );
  assertEquals(unavailable.status, 503);
  assertEquals(unavailable.code, "scan_ingestion_unavailable");
});
