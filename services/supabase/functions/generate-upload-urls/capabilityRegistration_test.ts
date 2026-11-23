import { assertEquals, assertRejects, assertThrows } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { R2Config } from "../_shared/aws.ts";
import {
  registerCaptureUploadCapabilities,
  signedCaptureUploadExpiry,
} from "./capabilityRegistration.ts";
import type { StagingUploadFile } from "./storage.ts";

const config = {
  endpoint: "https://storage.invalid",
  bucketName: "synthetic",
} as R2Config;
const owner = "00000000-0000-4000-8000-000000000001";
const key = `staging/${owner}/fixture.webp`;
const signed =
  `${config.endpoint}/${config.bucketName}/${key}?X-Amz-Date=20261120T040000Z&X-Amz-Expires=86400`;
Deno.test("capture capability records actual signed expiry", () => {
  assertEquals(
    signedCaptureUploadExpiry(signed, key, config),
    "2026-11-21T04:00:00.000Z",
  );
});
Deno.test("capture capability rejects foreign targets and ambiguous signing parameters", () => {
  for (
    const candidate of [
      signed.replace("storage.invalid", "foreign.invalid"),
      signed.replace("fixture.webp", "other.webp"),
      signed + "&X-Amz-Date=20261120T040000Z",
      signed.replace("86400", "86401"),
      signed.replace("20261120", "20260230"),
      signed + "#fragment",
    ]
  ) {
    assertThrows(() => signedCaptureUploadExpiry(candidate, key, config));
  }
});
Deno.test("capture capabilities bind canonical asset/session and require durable acknowledgement", async () => {
  const calls: Record<string, unknown>[] = [];
  const file: StagingUploadFile = {
    fileName: "fixture.webp",
    mediaKind: "image",
    contentType: "image/webp",
    sizeBytes: 100,
    clientScanId: "00000000-0000-4000-8000-000000000002",
  };
  const url = {
    fileName: file.fileName,
    signedUrl: signed,
    objectKey: key,
    requiredHeaders: {
      "Content-Type": file.contentType,
      "Content-Length": "100",
    },
  };
  const asset = {
    id: "00000000-0000-4000-8000-000000000003",
    storage_key: key,
    upload_session_id: "00000000-0000-4000-8000-000000000004",
    order_index: 0,
  };
  let accepted = true;
  const client = {
    rpc: (name: string, args: Record<string, unknown>) => {
      assertEquals(name, "register_capture_upload_capabilities");
      calls.push(args);
      return Promise.resolve({ data: accepted, error: null });
    },
  } as unknown as SupabaseClient;
  await registerCaptureUploadCapabilities(
    owner,
    [file],
    [url],
    [asset],
    config,
    client,
  );
  assertEquals(calls[0].p_objects, [{
    object_key: key,
    expires_at: "2026-11-21T04:00:00.000Z",
    scan_id: file.clientScanId,
    asset_id: asset.id,
    session_id: asset.upload_session_id,
  }]);
  accepted = false;
  await assertRejects(() =>
    registerCaptureUploadCapabilities(
      owner,
      [file],
      [url],
      [asset],
      config,
      client,
    )
  );
  await assertRejects(() =>
    registerCaptureUploadCapabilities(owner, [file], [url], [], config, client)
  );
  assertEquals(calls.length, 2);
});
