import type { SupabaseClient } from "@supabase/supabase-js";
import {
  cancelInitialStream,
  initialAbortable,
  initialDeadline,
  readInitialStream,
} from "../initialAnalysis/transport.ts";
import { HistoryError, invalidHistory } from "./contract.ts";
import { evidenceDigest } from "./evidence.ts";
import { type InitialEvidenceCapturePlan } from "./initialEvidenceCapturePlan.ts";
import {
  createInitialCaptureClientServices,
  type InitialCaptureClientServices,
} from "./initialCaptureClientStaging.ts";
import { createInitialCaptureAudioStageServices } from "./initialCaptureAudioStageRepository.ts";
import {
  type InitialCaptureAudioStageRepository,
  type InitialCaptureAudioStageStorage,
  stageInitialCaptureAudio,
} from "./initialCaptureAudioStaging.ts";
import { type InitialRetentionSource } from "./initialEvidenceRetention.ts";
import { initialEvidenceArtifacts } from "./initialEvidenceManifest.ts";

export interface PrivateCapturePreparationServices {
  client: InitialCaptureClientServices;
  audio: {
    repository: InitialCaptureAudioStageRepository;
    storage: InitialCaptureAudioStageStorage;
  };
}

/** Uses the existing one-shot DSP composition, reading only private ready
 * client objects. A recovered server output never reads or processes raw audio.
 * The returned source is for post-begin retention, not a provider or native
 * original-release capability. Each read reauthorizes its exact stage object. */
export async function preparePrivateCaptureStage(
  plan: InitialEvidenceCapturePlan,
  attempt: string,
  services: PrivateCapturePreparationServices,
  signal: AbortSignal,
) {
  async function read(
    artifact: InitialEvidenceCapturePlan["uploads"][number],
    current: AbortSignal,
  ) {
    current.throwIfAborted();
    const object = await services.client.repository.reserve(
      artifact.media_id,
      current,
    );
    current.throwIfAborted();
    if (
      !object.ready ||
      !await services.client.repository.authorize(
        artifact.media_id,
        "read",
        current,
      )
    ) throw new HistoryError("analysis_history_evidence_unavailable");
    current.throwIfAborted();
    return await services.client.storage.openBoundStream({
      object_id: object.object_id,
      ...artifact,
    }, current);
  }
  const prepared = await stageInitialCaptureAudio(
    plan,
    attempt,
    { read },
    services.audio.repository,
    services.audio.storage,
    signal,
  );
  signal.throwIfAborted();
  const expected = initialEvidenceArtifacts(
    prepared.result.request.evidence_manifest,
  );
  const source: InitialRetentionSource = {
    async open(artifact, current) {
      current.throwIfAborted();
      const exact = expected.find((item) =>
        item.media_id === artifact.media_id
      );
      if (
        !exact ||
        Object.keys(exact).some((key) =>
          exact[key as keyof typeof exact] !==
            artifact[key as keyof typeof artifact]
        )
      ) return invalidHistory();
      const bytes = await initialDeadline(current, 30_000, async (bounded) => {
        const stream = await initialAbortable(bounded, () => {
          if (
            exact.role === "prepared_audio" ||
            exact.role === "prepared_companion_audio"
          ) {
            const object = prepared.stage?.items.find((item) =>
              item.media_id === exact.media_id
            );
            if (!object?.ready) {
              throw new HistoryError("analysis_history_evidence_unavailable");
            }
            return services.audio.storage.read(object, bounded);
          }
          return read(exact, bounded);
        }, cancelInitialStream);
        const bytes = await readInitialStream(
          stream,
          exact.byte_count,
          bounded,
        );
        if (
          bytes.length !== exact.byte_count ||
          await evidenceDigest(bytes) !== exact.sha256
        ) throw new HistoryError("analysis_history_evidence_unavailable");
        bounded.throwIfAborted();
        return bytes;
      });
      return {
        bytes,
        close: () => {
          bytes.fill(0);
          return Promise.resolve();
        },
      };
    },
  };
  return Object.freeze({ request: prepared.result.request, source });
}

export async function createPrivateCapturePreparationServices(
  plan: InitialEvidenceCapturePlan,
  client: SupabaseClient,
): Promise<PrivateCapturePreparationServices> {
  return {
    client: await createInitialCaptureClientServices(plan, client),
    audio: await createInitialCaptureAudioStageServices(
      plan,
      client,
      "complete_client_stage",
    ),
  };
}
