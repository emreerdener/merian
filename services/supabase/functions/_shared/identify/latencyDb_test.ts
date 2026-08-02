import { assertEquals, assertRejects } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";

import { beginScanIngestion } from "../scanIngestionJobs.ts";

Deno.test("beginScanIngestion returns server-canonicalized session IDs and checksums", async () => {
  let rpcName: string | undefined;
  let rpcArguments: Record<string, unknown> | undefined;
  const client = {
    rpc: (name: string, arguments_: Record<string, unknown>) => {
      rpcName = name;
      rpcArguments = arguments_;
      return Promise.resolve({
        data: {
          upload_session_ids: [
            "00000000-0000-4000-8000-000000000044",
            "00000000-0000-4000-8000-000000000045",
          ],
          manifest_checksum: "a".repeat(64),
          payload_checksum: "b".repeat(64),
          stage: "ai_inference_started",
          already_complete: false,
        },
        error: null,
      });
    },
  } as unknown as SupabaseClient;

  const result = await beginScanIngestion({
    scanId: "00000000-0000-4000-8000-000000000042",
    userId: "00000000-0000-4000-8000-000000000043",
    endpoint: "identify-multimodal",
    requestPayload: { scanId: "00000000-0000-4000-8000-000000000042" },
    mediaCounts: {
      image_count: 1,
      audio_count: 0,
      video_count: 0,
      required_video_count: 0,
      video_frame_count: 0,
    },
    mediaObjectKeys: { image: ["staging/frame.webp"], audio: [], video: [] },
    storageKeys: ["staging/frame.webp"],
    manifestChecksum: "client-manifest-before-session-lookup",
    payloadChecksum: "client-payload-before-session-lookup",
    resumable: true,
    inlineMediaRedacted: false,
    redactedMediaCounts: {},
  }, client);

  assertEquals(rpcName, "begin_scan_ingestion");
  assertEquals(rpcArguments?.p_storage_keys, ["staging/frame.webp"]);
  assertEquals(result, {
    uploadSessionIds: [
      "00000000-0000-4000-8000-000000000044",
      "00000000-0000-4000-8000-000000000045",
    ],
    manifestChecksum: "a".repeat(64),
    payloadChecksum: "b".repeat(64),
    stage: "ai_inference_started",
    alreadyComplete: false,
  });
});

Deno.test("beginScanIngestion fails closed on a malformed atomic response", async () => {
  const client = {
    rpc: () =>
      Promise.resolve({
        data: {
          upload_session_ids: [],
          manifest_checksum: "a".repeat(64),
          payload_checksum: "b".repeat(64),
          stage: "ai_inference_started",
        },
        error: null,
      }),
  } as unknown as SupabaseClient;

  await assertRejects(
    () =>
      beginScanIngestion({
        scanId: "00000000-0000-4000-8000-000000000042",
        userId: "00000000-0000-4000-8000-000000000043",
        endpoint: "identify-multimodal",
        requestPayload: {},
        mediaCounts: {
          image_count: 0,
          audio_count: 0,
          video_count: 0,
          required_video_count: 0,
          video_frame_count: 0,
        },
        mediaObjectKeys: { image: [], audio: [], video: [] },
        storageKeys: [],
        manifestChecksum: null,
        payloadChecksum: null,
        resumable: true,
        inlineMediaRedacted: false,
        redactedMediaCounts: {},
      }, client),
    Error,
    "malformed RPC response",
  );
});
