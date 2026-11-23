import { historyUUID, invalidHistory } from "./contract.ts";
import { initialEvidenceArtifacts } from "./initialEvidenceManifest.ts";
import { initialRetentionRequest } from "./initialEvidenceRetention.ts";
import { MEDIA_BUDGETS, type StagingMediaKind } from "../mediaBudgets.ts";

/** Deterministic inventory of a finalized evidence manifest. This projection
 * is not the client upload-plan contract: prepared audio is known only after
 * server DSP. It grants no storage, funding or dispatch authority. Live staging
 * must separately associate client-known sources and server-prepared outputs.
 */
export async function initialEvidenceStagingPlan(
  owner: string,
  value: unknown,
) {
  historyUUID(owner);
  const request = await initialRetentionRequest(value);
  const artifacts = initialEvidenceArtifacts(request.evidence_manifest);
  if (
    owner === request.scan_id || owner === request.generation ||
    artifacts.some((artifact) => artifact.media_id === owner)
  ) return invalidHistory();
  const extensions: Readonly<Record<string, string>> = {
    "image/jpeg": "jpg",
    "image/png": "png",
    "image/webp": "webp",
    "image/heic": "heic",
    "image/heif": "heif",
    "audio/wav": "wav",
    "audio/mp4": "m4a",
    "video/mp4": "mp4",
  };
  const files = Object.freeze(artifacts.map((artifact) => {
    const extension = extensions[artifact.content_type];
    if (!extension) return invalidHistory();
    const fileName =
      `initial_${request.scan_id}_${request.generation}_${artifact.media_id}.${extension}`;
    const mediaKind: StagingMediaKind =
      artifact.content_type.startsWith("image/")
        ? "image"
        : artifact.content_type.startsWith("audio/")
        ? "audio"
        : "video";
    return Object.freeze({
      ...artifact,
      fileName,
      sourceKey: `staging/${owner}/${fileName}`,
      mediaKind,
    });
  }));
  // Provider inputs are explicit roles. Originals and playback copies never
  // become images/audio merely because their MIME type matches a provider.
  const image = files.filter((file) =>
    file.role === "prepared_image" || file.role === "inference_frame"
  );
  const audio = files.filter((file) =>
    file.role === "prepared_audio" || file.role === "prepared_companion_audio"
  );
  const video = files.filter((file) => file.role === "playback_video");
  if (
    image.length > MEDIA_BUDGETS.maxImageCount ||
    audio.length > MEDIA_BUDGETS.maxAudioClips ||
    video.length > MEDIA_BUDGETS.maxStagedVideoFiles
  ) return invalidHistory();
  return Object.freeze({
    ownerID: owner,
    request,
    files,
    provider: Object.freeze({
      image: Object.freeze(image.map((file) => file.sourceKey)),
      audio: Object.freeze(audio.map((file) => file.sourceKey)),
      video: Object.freeze(video.map((file) => file.sourceKey)),
    }),
  });
}

export type InitialEvidenceStagingPlan = Awaited<
  ReturnType<typeof initialEvidenceStagingPlan>
>;
