import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

import { beginScanIngestion } from "./latencyDb.ts";

Deno.test("beginScanIngestion returns server-canonicalized session IDs and checksums", async () => {
  let rpcName: string | undefined;
  let rpcArguments: Record<string, unknown> | undefined;
  const client = {
    rpc: (name: string, arguments_: Record<string, unknown>) => {
      rpcName = name;
      rpcArguments = arguments_;
      return Promise.resolve({
        data: {
          upload_session_ids: ["session-a", 42, "session-b"],
          manifest_checksum: "server-manifest",
          payload_checksum: "server-payload",
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
    uploadSessionIds: ["session-a", "session-b"],
    manifestChecksum: "server-manifest",
    payloadChecksum: "server-payload",
  });
});
