import catalog from "./configuration-assets-v1.json" with { type: "json" };
import { hex, initialCanonicalText, initialDigest } from "./canonical.ts";

export const INITIAL_CONFIGURATION_ASSET_DIGEST = catalog.digest;
/** Initial engine owns immutable release-archive retention and resolution.
 * No current-code fallback is permitted when the saved archive is unavailable.
 * readAsset must resolve the exact repository revision, not a moving branch.
 */
export async function verifyInitialConfigurationAssets(
  readAsset: (path: string, revision: string) => Promise<Uint8Array>,
  expectedDigest = INITIAL_CONFIGURATION_ASSET_DIGEST,
): Promise<void> {
  if (
    expectedDigest !== catalog.digest ||
    await initialDigest("assets", initialCanonicalText(catalog.manifest)) !==
      expectedDigest
  ) throw new Error("initial_analysis_configuration_unavailable");
  try {
    for (const asset of catalog.manifest.files) {
      const bytes = new Uint8Array(
        await readAsset(asset.path, catalog.manifest.repository_revision),
      );
      if (
        hex(new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))) !==
          asset.sha256
      ) throw new Error("mismatch");
    }
  } catch {
    throw new Error("initial_analysis_configuration_unavailable");
  }
}
