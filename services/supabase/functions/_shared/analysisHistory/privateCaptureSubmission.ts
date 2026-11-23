import type { SupabaseClient } from "@supabase/supabase-js";
import {
  isScanGeoprivacy,
  resolveScanGeoprivacy,
  type ScanGeoprivacy,
} from "../identify/db.ts";
import type { MultimodalPayload } from "../identify/types.ts";
import {
  beginScanIngestion,
  type BeginScanIngestionInput,
  type BeginScanIngestionResult,
} from "../scanIngestionJobs.ts";
import {
  initialAbortable,
  initialDeadline,
} from "../initialAnalysis/transport.ts";
import { HistoryError, invalidHistory } from "./contract.ts";
import { PrivateHistoryEvidenceStorage } from "./evidenceStorage.ts";
import {
  type InitialEvidenceCapturePlan,
  parseInitialEvidenceCapturePlan,
} from "./initialEvidenceCapturePlan.ts";
import { initialEvidenceRepository } from "./initialEvidenceRepository.ts";
import {
  type InitialRetentionRepository,
  initialRetentionRequest,
  type InitialRetentionSource,
  type InitialRetentionStorage,
  retainInitialEvidenceFromSource,
} from "./initialEvidenceRetention.ts";
import { buildPrivateCaptureIntent } from "./privateCaptureIntent.ts";
import {
  createPrivateCapturePreparationServices,
  preparePrivateCaptureStage,
} from "./privateCaptureStagePreparation.ts";

export interface PrivateCaptureSubmissionDependencies {
  resolveGeoprivacy(
    owner: string,
    explicit: string | undefined,
    signal: AbortSignal,
  ): Promise<ScanGeoprivacy>;
  readIntent(owner: string, scan: string, signal: AbortSignal): Promise<
    {
      readonly payload_schema_version: number;
      readonly request_payload: Record<string, unknown>;
    } | null
  >;
  prepare(plan: InitialEvidenceCapturePlan, signal: AbortSignal): Promise<{
    readonly request: unknown;
    readonly source: InitialRetentionSource;
  }>;
  begin(
    input: BeginScanIngestionInput,
    signal: AbortSignal,
  ): Promise<BeginScanIngestionResult>;
  repository: InitialRetentionRepository;
  storage: InitialRetentionStorage;
}

export function validatePrivateCaptureSubmissionPayload(
  plan: InitialEvidenceCapturePlan,
  payload: MultimodalPayload,
): void {
  if (
    payload.user_id !== plan.ownerID ||
    payload.client_scan_id !== plan.scanID ||
    payload.audio_comparison !== undefined ||
    payload.audio_prompt_comparison !== undefined
  ) return invalidHistory();
  const wire = payload as unknown as Record<string, unknown>;
  if (
    [
      "initialEvidence",
      "initial_evidence",
      "privateCaptureStage",
      "capture_plan",
      "captureSourceObservations",
      "captureSourceProofs",
      "captureSources",
      "audioBase64",
    ]
      .some((key) => Object.hasOwn(wire, key)) ||
    [
      "imageBase64s",
      "audioBase64s",
      "r2ObjectKeys",
      "audioR2ObjectKeys",
      "videoR2ObjectKeys",
      "visualMediaItems",
      "visual_media_items",
      "audioMediaItems",
      "audio_media_items",
      "ownerMediaTimeline",
      "owner_media_timeline",
      "observation_contexts",
    ].some((key) =>
      Object.hasOwn(wire, key) &&
      (!Array.isArray(wire[key]) || wire[key].length !== 0)
    )
  ) {
    return invalidHistory();
  }
}

/** Pre-provider portion of the existing ordinary executor. Stage, admission and
 * retention each keep their existing owner. A saved intent recovers without
 * staging unless an unready retained artifact still requires a source read.
 * No quota reservation, provider dispatch or finalization occurs in this helper.
 */
export async function preparePrivateCaptureSubmission(
  input: {
    owner: string;
    plan: unknown;
    payload: MultimodalPayload;
    normalizedTelemetry?: Record<string, unknown>;
  },
  dependencies: PrivateCaptureSubmissionDependencies,
  signal: AbortSignal,
) {
  signal.throwIfAborted();
  const plan = parseInitialEvidenceCapturePlan(input.owner, input.plan);
  let payload = structuredClone(input.payload);
  const telemetry = structuredClone(input.normalizedTelemetry);
  validatePrivateCaptureSubmissionPayload(plan, payload);
  const saved = await dependencies.readIntent(
    plan.ownerID,
    plan.scanID,
    signal,
  );
  signal.throwIfAborted();
  // Account defaults are frozen in the immutable admission, before any result
  // binding. Recovery never consults the current account preference again.
  const savedTelemetry = saved?.request_payload.telemetry;
  const savedPrivacy = savedTelemetry && typeof savedTelemetry === "object"
    ? (savedTelemetry as Record<string, unknown>).geoprivacy
    : undefined;
  const geoprivacy = saved !== null
    ? savedPrivacy
    : await dependencies.resolveGeoprivacy(
      plan.ownerID,
      payload.geoprivacy,
      signal,
    );
  signal.throwIfAborted();
  if (!isScanGeoprivacy(geoprivacy)) return invalidHistory();
  if (saved !== null) {
    // New telemetry belongs to a new observation, never to recovery of this
    // admitted operation. Re-sanitize the persisted projection and let begin
    // compare the complete immutable intent before any retained read.
    payload = {
      ...(savedTelemetry as Record<string, unknown>),
      user_id: plan.ownerID,
      client_scan_id: plan.scanID,
      preferred_goal: saved.request_payload
        .preferredGoal as MultimodalPayload["preferred_goal"],
    };
  }

  let prepared:
    | Awaited<ReturnType<PrivateCaptureSubmissionDependencies["prepare"]>>
    | undefined;
  let candidate: unknown;
  if (saved !== null) {
    if (
      saved.payload_schema_version !== 4 ||
      saved.request_payload.schemaVersion !== 4 ||
      !Object.hasOwn(saved.request_payload, "privateCaptureStage")
    ) {
      throw new HistoryError("analysis_history_operation_conflict");
    }
    candidate = saved.request_payload.initialEvidence;
  } else {
    prepared = await dependencies.prepare(plan, signal);
    candidate = prepared.request;
  }
  const request = await initialRetentionRequest(candidate);
  signal.throwIfAborted();
  // This checks the complete ordered client graph against the server result;
  // begin then enforces the saved immutable payload/proof under its SQL fences.
  const intent = await buildPrivateCaptureIntent({
    plan,
    initialEvidence: request,
    payload,
    normalizedTelemetry: {
      ...(saved !== null
        ? savedTelemetry as Record<string, unknown>
        : telemetry),
      geoprivacy,
    },
  });
  const ingestion = await dependencies.begin({
    scanId: plan.scanID,
    userId: plan.ownerID,
    endpoint: "identify-multimodal",
    requestPayload: intent.payload,
    mediaCounts: intent.mediaCounts,
    mediaObjectKeys: intent.mediaObjectKeys,
    storageKeys: intent.storageKeys,
    manifestChecksum: null,
    payloadChecksum: null,
    resumable: true,
    inlineMediaRedacted: false,
    redactedMediaCounts: intent.redactedMediaCounts,
    payloadSchemaVersion: intent.payloadSchemaVersion,
    leaseSeconds: 300,
  }, signal);
  signal.throwIfAborted();
  if (ingestion.alreadyComplete) {
    return { plan, request, intent, ingestion, retained: null };
  }
  const source: InitialRetentionSource = {
    async open(artifact, current) {
      current.throwIfAborted();
      if (!prepared) {
        prepared = await dependencies.prepare(plan, current);
        const recovered = await initialRetentionRequest(prepared.request);
        if (recovered.evidence_digest !== request.evidence_digest) {
          return invalidHistory();
        }
      }
      current.throwIfAborted();
      return await prepared.source.open(artifact, current);
    },
  };
  const retained = await retainInitialEvidenceFromSource(
    plan.ownerID,
    request,
    source,
    dependencies.repository,
    dependencies.storage,
    signal,
  );
  signal.throwIfAborted();
  return { plan, request, intent, ingestion, retained };
}

export function privateCaptureSubmissionDependencies(
  client: SupabaseClient,
  storage: InitialRetentionStorage = new PrivateHistoryEvidenceStorage(),
): PrivateCaptureSubmissionDependencies {
  return {
    resolveGeoprivacy: (owner, explicit, signal) =>
      initialDeadline(
        signal,
        5_000,
        (current) =>
          initialAbortable(
            current,
            () => resolveScanGeoprivacy(owner, client, explicit),
          ),
      ),
    async readIntent(owner, scan, signal) {
      return await initialDeadline(signal, 5_000, async (current) => {
        const { data, error } = await initialAbortable(current, () =>
          client
            .from("scan_ingestion_intents")
            .select("payload_schema_version,request_payload")
            .eq("user_id", owner).eq("scan_id", scan).abortSignal(current)
            .maybeSingle());
        if (error) throw new HistoryError("analysis_history_unavailable");
        if (data === null) return null;
        if (
          !data || typeof data.payload_schema_version !== "number" ||
          !data.request_payload || typeof data.request_payload !== "object" ||
          Array.isArray(data.request_payload)
        ) return invalidHistory();
        return {
          payload_schema_version: data.payload_schema_version,
          request_payload: data.request_payload,
        };
      });
    },
    async prepare(plan, signal) {
      const services = await createPrivateCapturePreparationServices(
        plan,
        client,
      );
      return await preparePrivateCaptureStage(
        plan,
        crypto.randomUUID(),
        services,
        signal,
      );
    },
    begin: (input, signal) =>
      initialDeadline(
        signal,
        5_000,
        (current) =>
          initialAbortable(current, () => beginScanIngestion(input, client)),
      ),
    repository: initialEvidenceRepository(client),
    storage,
  };
}
