import { evidenceDigest } from "../_shared/analysisHistory/evidence.ts";
import {
  initialEvidenceArtifacts,
  initialEvidenceDigest,
} from "../_shared/analysisHistory/initialEvidenceManifest.ts";
import { initialRetentionRequest } from "../_shared/analysisHistory/initialEvidenceRetention.ts";
import type { InitialEvidenceUploadDependencies } from "../_shared/analysisHistory/initialEvidenceUpload.ts";

export const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
export function frame(metadata: unknown, bytes: Uint8Array) {
  const json = new TextEncoder().encode(JSON.stringify(metadata)),
    result = new Uint8Array(4 + json.length + bytes.length);
  new DataView(result.buffer).setUint32(0, json.length);
  result.set(json, 4);
  result.set(bytes, 4 + json.length);
  return result;
}
export async function fixture(size = 3, version = 8) {
  const source = new Uint8Array(size).fill(1),
    prepared = new Uint8Array([1, 2, 3]);
  const artifact = async (n: number, bytes: Uint8Array) => ({
    media_id: id(n),
    content_type: "image/jpeg",
    byte_count: bytes.length,
    sha256: await evidenceDigest(bytes),
  });
  const manifest = {
    schema_version: version,
    items: [{
      kind: "image",
      source: await artifact(3, source),
      prepared: await artifact(4, prepared),
      coordinate_basis: "prepared_image_top_left_v1",
      focus_region: null,
    }],
  };
  const request = await initialRetentionRequest({
    schema_version: 1,
    scan_id: id(1),
    generation: id(2),
    evidence_manifest: manifest,
    evidence_digest: await initialEvidenceDigest(manifest, id(1), id(2)),
  });
  const owner = id(9), events: string[] = [];
  const receipt = {
    schema_version: 1,
    owner_id: owner,
    scan_id: id(1),
    generation: id(2),
    evidence_digest: request.evidence_digest,
    items: initialEvidenceArtifacts(request.evidence_manifest).map((
      item,
      i,
    ) => ({ ...item, object_id: id(100 + i), ready: false })),
  };
  const buffers = new Map([[id(3), source], [id(4), prepared]]);
  const dependencies: InitialEvidenceUploadDependencies = {
    repository: {
      reserve: () => {
        events.push("reserve");
        return Promise.resolve(structuredClone(receipt));
      },
      complete: (_owner, _request, object) => {
        events.push("complete");
        receipt.items.find((x) => x.object_id === object)!.ready = true;
        return Promise.resolve(structuredClone(receipt));
      },
    },
    storage: {
      writeOnce: () => {
        events.push("write");
        return Promise.resolve();
      },
      verifyStored: async (item) => {
        events.push("read");
        const bytes = buffers.get(item.media_id)!;
        if (
          bytes.length !== item.byte_count ||
          await evidenceDigest(bytes) !== item.sha256
        ) {
          throw new Error("history_evidence_verification_failed");
        }
      },
    },
  };
  return {
    owner,
    request,
    receipt,
    buffers,
    source,
    prepared,
    dependencies,
    events,
    metadata: { schema_version: 1, request, media_id: id(3) },
  };
}
