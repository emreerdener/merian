import { compositionCohortItems } from "./compositionCohort.ts";
import { compositionEvidenceIdentity } from "./compositionEvidence.ts";
import { evidenceDigest } from "./evidence.ts";
import { videoByteFixture } from "./videoByteTestFixtures.ts";
const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
export async function compositionByteFixture(withVideo = true) {
  const video = await videoByteFixture(true);
  const graph = video.input.input.evidence_manifest.provenance;
  const bytes = new Map<string, Uint8Array>();
  video.receipt.items.forEach((item, index) =>
    bytes.set(item.media_id, video.bytes[index])
  );
  const sound = video.bytes.at(-1)!.slice();
  const standalone = {
    media_id: id(7001),
    content_type: "audio/wav",
    byte_count: sound.length,
    sha256: await evidenceDigest(sound),
  };
  bytes.set(standalone.media_id, sound);
  const image = {
    media_id: id(7002),
    content_type: "image/jpeg",
    byte_count: 3,
    sha256: await evidenceDigest(new Uint8Array([1, 2, 3])),
  };
  bytes.set(image.media_id, new Uint8Array([1, 2, 3]));
  const input = {
    schema_version: 5,
    observation_id: id(6000),
    analysis_id: id(6001),
    source_analysis_id: id(6002),
    request_digest: "a".repeat(64),
    entitlement_protocol: 3,
    identification_protocol: 7,
    history_protocol: 10,
    expected_processor_permission: "google_gemini",
    evidence_manifest: {
      schema_version: 5,
      items: [
        { kind: "description", text: "  before 🦋  " },
        { kind: "audio", artifact: standalone },
        { kind: "description", text: "between" },
        ...(withVideo
          ? [{ kind: "video", provenance: graph }]
          : [{ kind: "image", artifact: image }]),
        { kind: "description", text: "after" },
      ],
    },
  };
  const identity = await compositionEvidenceIdentity(input);
  const receipt = {
    ...identity,
    owner_id: id(9000),
    state: "ready",
    expires_at: "2027-01-01T00:00:00.000Z",
    items: compositionCohortItems(input).map((item, index) => ({
      ...item,
      object_id: id(8000 + index),
      ready_at: "2026-01-01T00:00:00.000Z" as string | null,
    })),
  };
  return { input, receipt, bytes };
}
