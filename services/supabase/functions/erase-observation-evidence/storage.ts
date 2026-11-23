import type { R2Config } from "../_shared/aws.ts";
import { captureObjectBackendDigest } from "../_shared/captureObjectRetirement.ts";
import {
  getHistoryEvidenceConfig,
  PrivateCaptureStageObjectStorage,
  PrivateHistoryEvidenceStorage,
} from "../_shared/analysisHistory/evidenceStorage.ts";
import type { PrivateErasureTarget } from "./handler.ts";

type Marker = { erase(object: string, signal: AbortSignal): Promise<void> };
/** Consumes only a validated, current typed claim. Never treats the currently
 * configured private bucket as a replacement for the stage's recorded backend. */
export class PrivateEvidenceErasureStorage {
  constructor(
    private readonly history: Marker = new PrivateHistoryEvidenceStorage(),
    private readonly stageConfig: () => R2Config = () =>
      getHistoryEvidenceConfig("write"),
    private readonly stage: (config: R2Config) => Marker = (config) =>
      new PrivateCaptureStageObjectStorage(() => config),
  ) {}
  async erase(
    object: string,
    signal: AbortSignal,
    target: PrivateErasureTarget,
  ) {
    signal.throwIfAborted();
    const namespace = target.namespace, backend = target.backend_sha256;
    if (namespace === "history" && backend === null) {
      return await this.history.erase(object, signal);
    }
    if (
      namespace !== "capture_stage" || typeof backend !== "string" ||
      !/^[0-9a-f]{64}$/.test(backend)
    ) {
      throw new Error("private_evidence_backend_unavailable");
    }
    const config = this.stageConfig();
    if (await captureObjectBackendDigest(config) !== backend) {
      throw new Error("private_evidence_backend_unavailable");
    }
    signal.throwIfAborted();
    await this.stage(config).erase(object, signal);
  }
}
