import catalog from "./configuration-assets-v1.json" with { type: "json" };
import { hex, initialCanonicalText, initialDigest } from "./canonical.ts";

import {
  cancelInitialStream,
  checkInitialDeadline,
  INITIAL_ASSET_BYTES,
  INITIAL_ASSET_TOTAL_BYTES,
  initialAbortable,
  type InitialAssetReader,
  readInitialStream,
} from "./transport.ts";

export const INITIAL_CONFIGURATION_ASSET_DIGEST = catalog.digest;
/** Initial engine owns immutable release-archive retention and resolution.
 * No current-code fallback is permitted when the saved archive is unavailable.
 * readAsset must resolve the exact repository revision, not a moving branch.
 */
export async function verifyInitialConfigurationAssets(
  readAsset: InitialAssetReader,
  signal: AbortSignal,
  expectedDigest = INITIAL_CONFIGURATION_ASSET_DIGEST,
): Promise<void> {
  checkInitialDeadline(signal);
  if (
    expectedDigest !== catalog.digest ||
    await initialDigest("assets", initialCanonicalText(catalog.manifest)) !==
      expectedDigest
  ) throw new Error("initial_analysis_configuration_unavailable");
  try {
    let total = 0;
    if (catalog.manifest.files.length > 64) throw new Error("asset_count");
    for (const asset of catalog.manifest.files) {
      const stream = await initialAbortable(
        signal,
        () =>
          readAsset(asset.path, catalog.manifest.repository_revision, signal),
        cancelInitialStream,
      );
      const bytes = await readInitialStream(
        stream,
        INITIAL_ASSET_BYTES,
        signal,
      );
      total += bytes.byteLength;
      if (total > INITIAL_ASSET_TOTAL_BYTES) throw new Error("asset_total");
      if (
        hex(new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))) !==
          asset.sha256
      ) throw new Error("mismatch");
    }
    checkInitialDeadline(signal);
  } catch {
    throw new Error("initial_analysis_configuration_unavailable");
  }
}
