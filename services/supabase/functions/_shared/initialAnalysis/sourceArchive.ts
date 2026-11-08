import catalog from "./configuration-assets-v1.json" with { type: "json" };
import { decodeBase64, encodeBase64 } from "../encoding.ts";
import { hex, initialCanonicalText, initialDigest } from "./canonical.ts";
import {
  cancelInitialStream,
  checkInitialDeadline,
  INITIAL_ASSET_BYTES,
  INITIAL_ASSET_TOTAL_BYTES,
  initialAbortable,
  type InitialAssetReader,
  initialDeadline,
  readInitialStream,
} from "./transport.ts";

/** Source/config bytes only. This format never authorizes code execution. */
export const INITIAL_SOURCE_ARCHIVE_BYTES = 2_097_152;
const encoder = new TextEncoder();
const unavailable = () =>
  new Error("initial_analysis_source_archive_unavailable");
type Entry = {
  path: string;
  sha256: string;
  byte_count: number;
  base64: string;
};

function serialize(files: readonly Entry[]): string {
  // Explicit field order and one LF; no timestamps, filesystem metadata or paths
  // outside the exact catalog. Comparing this spelling also rejects JSON aliases.
  return JSON.stringify({ format_version: 1, catalog, files }) + "\n";
}

async function validateCatalog(signal: AbortSignal): Promise<void> {
  checkInitialDeadline(signal);
  const manifest = catalog.manifest;
  if (
    manifest.resolver_id !== "git_blob_sha256_v1" ||
    manifest.retention_owner !== "initial_engine_release_archive" ||
    !/^[0-9a-f]{40}$/.test(manifest.repository_revision) ||
    manifest.files.length === 0 || manifest.files.length > 64 ||
    new Set(manifest.files.map((file) => file.path)).size !==
      manifest.files.length ||
    !manifest.files.some((file) =>
      file.path === "services/supabase/functions/dependencies.lock"
    ) ||
    manifest.files.some((file) =>
      !/^services\/supabase\/functions\/[A-Za-z0-9_./-]+$/.test(file.path) ||
      file.path.split("/").some((part) =>
        !part || part === "." || part === ".."
      ) ||
      !/^[0-9a-f]{64}$/.test(file.sha256)
    ) ||
    await initialDigest("assets", initialCanonicalText(manifest)) !==
      catalog.digest
  ) throw unavailable();
  checkInitialDeadline(signal);
}

export async function initialSourceArchiveHash(
  bytes: Uint8Array,
): Promise<string> {
  return hex(
    new Uint8Array(
      await crypto.subtle.digest("SHA-256", new Uint8Array(bytes)),
    ),
  );
}

/** Builder dependency must read exact Git blobs, never current checkout files. */
export async function buildInitialSourceArchive(
  readBlob: InitialAssetReader,
  caller: AbortSignal,
): Promise<Uint8Array<ArrayBuffer>> {
  return await initialDeadline(caller, 60_000, async (signal) => {
    await validateCatalog(signal);
    const files: Entry[] = [];
    let total = 0;
    for (const file of catalog.manifest.files) {
      const stream = await initialAbortable(
        signal,
        () => readBlob(file.path, catalog.manifest.repository_revision, signal),
        cancelInitialStream,
      );
      const bytes = await readInitialStream(
        stream,
        INITIAL_ASSET_BYTES,
        signal,
      );
      total += bytes.length;
      if (
        total > INITIAL_ASSET_TOTAL_BYTES ||
        await initialSourceArchiveHash(bytes) !== file.sha256
      ) throw unavailable();
      checkInitialDeadline(signal);
      files.push({
        path: file.path,
        sha256: file.sha256,
        byte_count: bytes.length,
        base64: encodeBase64(bytes),
      });
    }
    const bytes = encoder.encode(serialize(files));
    if (bytes.length > INITIAL_SOURCE_ARCHIVE_BYTES) throw unavailable();
    checkInitialDeadline(signal);
    return bytes;
  });
}

export interface InitialSourceArchive {
  readonly archiveSha256: string;
  readonly assetManifestDigest: string;
  readonly readAsset: InitialAssetReader;
}

/** Verify the entire bounded archive before any member becomes visible. Only
 * this statically retained catalog is supported. No network or code loading. */
export async function resolveInitialSourceArchive(
  stream: ReadableStream<Uint8Array>,
  expectedAssetManifestDigest: string,
  caller: AbortSignal,
): Promise<InitialSourceArchive> {
  try {
    return await initialDeadline(caller, 5_000, async (signal) => {
      await validateCatalog(signal);
      if (expectedAssetManifestDigest !== catalog.digest) throw unavailable();
      const bytes = await readInitialStream(
        stream,
        INITIAL_SOURCE_ARCHIVE_BYTES,
        signal,
      );
      const text = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true })
        .decode(bytes);
      const value = JSON.parse(text);
      if (
        !value || value.format_version !== 1 || !Array.isArray(value.files) ||
        value.files.length !== catalog.manifest.files.length
      ) throw unavailable();
      const files: Entry[] = [];
      const retained = new Map<string, Uint8Array>();
      let total = 0;
      for (const [index, asset] of catalog.manifest.files.entries()) {
        checkInitialDeadline(signal);
        const item = value.files[index];
        if (
          !item || item.path !== asset.path || item.sha256 !== asset.sha256 ||
          !Number.isSafeInteger(item.byte_count) || item.byte_count < 0 ||
          item.byte_count > INITIAL_ASSET_BYTES ||
          typeof item.base64 !== "string" ||
          item.base64.length > 4 * Math.ceil(INITIAL_ASSET_BYTES / 3)
        ) throw unavailable();
        const decoded = decodeBase64(item.base64);
        total += decoded.length;
        if (
          total > INITIAL_ASSET_TOTAL_BYTES ||
          decoded.length !== item.byte_count ||
          encodeBase64(decoded) !== item.base64 ||
          await initialSourceArchiveHash(decoded) !== asset.sha256
        ) throw unavailable();
        files.push({
          path: asset.path,
          sha256: asset.sha256,
          byte_count: decoded.length,
          base64: item.base64,
        });
        retained.set(asset.path, decoded);
      }
      if (serialize(files) !== text) throw unavailable();
      const archiveSha256 = await initialSourceArchiveHash(bytes);
      checkInitialDeadline(signal);
      return Object.freeze({
        archiveSha256,
        assetManifestDigest: catalog.digest,
        readAsset: (
          path: string,
          revision: string,
          readSignal: AbortSignal,
        ) => {
          checkInitialDeadline(readSignal);
          const asset = retained.get(path);
          if (revision !== catalog.manifest.repository_revision || !asset) {
            throw unavailable();
          }
          // A consumer cannot corrupt retained bytes or another consumer's view.
          return Promise.resolve(
            new ReadableStream<Uint8Array>({
              start(controller) {
                controller.enqueue(new Uint8Array(asset));
                controller.close();
              },
            }),
          );
        },
      });
    });
  } catch {
    cancelInitialStream(stream);
    throw unavailable();
  }
}
