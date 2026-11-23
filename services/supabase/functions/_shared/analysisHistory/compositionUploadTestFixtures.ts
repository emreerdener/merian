import { compositionByteFixture } from "./compositionByteTestFixtures.ts";
import { compositionFingerprint } from "./compositionFingerprint.ts";
/** Synthetic private media; never uses a user library or hosted storage. */
export async function compositionUploadFixture(withVideo: boolean) {
  const f = await compositionByteFixture(withVideo);
  const input = {
    schema_version: 3,
    input: f.input,
    fingerprint_version: 1,
    fingerprint: await compositionFingerprint(f.input),
  };
  const receipt = {
    ...f.receipt,
    expires_at: "2026-01-01T00:00:00.000Z",
    items: f.receipt.items.map((item) => ({
      ...item,
      ready_at: "2025-12-31T23:59:00.000Z" as string | null,
    })),
  };
  return {
    input,
    receipt,
    bytes: receipt.items.map((item) => f.bytes.get(item.media_id)!),
  };
}
