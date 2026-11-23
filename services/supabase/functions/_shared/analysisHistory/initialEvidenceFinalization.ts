import type { IdentificationProvenance } from "../ai/provenance.ts";
import {
  initialAbortable,
  initialDeadline,
} from "../initialAnalysis/transport.ts";
import type { SupabaseClient } from "@supabase/supabase-js";
import { parseIdentifySuccessEnvelope } from "../identify/contract.ts";
import {
  insertPreparedScan,
  isScanGeoprivacy,
  normalizeScanEcologyType,
  type PreparedScanInsertRow,
} from "../identify/db.ts";
import { initialEvidenceCompletionVerifier } from "../identify/initialEvidenceEnvelopeV1.ts";
import {
  completeScanIngestionFinalization,
  type CompleteScanIngestionFinalizationInput,
  type CompleteScanIngestionFinalizationResult,
} from "../scanIngestionJobs.ts";
import { historyUUID, invalidHistory } from "./contract.ts";
import { initialEvidenceRepository } from "./initialEvidenceRepository.ts";
import { initialRetentionRequest } from "./initialEvidenceRetention.ts";

export interface InitialEvidenceFinalizationDependencies {
  bind: ReturnType<typeof initialEvidenceRepository>["bindResult"];
  insert(row: PreparedScanInsertRow, signal: AbortSignal): Promise<void>;
  complete(
    input: CompleteScanIngestionFinalizationInput,
    signal: AbortSignal,
  ): Promise<CompleteScanIngestionFinalizationResult>;
}

/** One finalization join used by first acceptance and accepted-result recovery.
 * The caller has already enforced provider safety/result policy. The original
 * result is bound BEFORE insertion; ambiguity resumes that same binding. Public
 * media stays empty and the existing finalizer must return the exact server seal.
 */
export async function finalizeInitialEvidence(
  input: {
    owner: string;
    request: unknown;
    result: unknown;
    speciesID: string | null;
    telemetry: Record<string, unknown>;
  },
  dependencies: InitialEvidenceFinalizationDependencies,
  signal: AbortSignal,
) {
  signal.throwIfAborted();
  const owner = historyUUID(input.owner),
    result = structuredClone(input.result),
    telemetry = structuredClone(input.telemetry),
    species = input.speciesID === null ? null : historyUUID(input.speciesID);
  const { data } = parseIdentifySuccessEnvelope({
    success: true,
    data: result,
  });
  const request = await initialRetentionRequest(input.request);
  signal.throwIfAborted();
  if (
    request.evidence_manifest.schema_version !== 9 ||
    data.scan_id !== request.scan_id
  ) return invalidHistory();
  const text = (key: string) =>
    typeof telemetry[key] === "string" ? telemetry[key] as string : undefined;
  const number = (key: string) =>
    typeof telemetry[key] === "number" && Number.isFinite(telemetry[key])
      ? telemetry[key] as number
      : undefined;
  const notes = request.evidence_manifest.items.filter((item) =>
    item.kind === "description"
  );
  if (!isScanGeoprivacy(telemetry.geoprivacy)) return invalidHistory();
  const row: PreparedScanInsertRow = {
    id: request.scan_id,
    user_id: owner,
    species_id: species,
    primary_identification: data.primary_identification,
    // The closed Identify parser above validates each version/provider arm;
    // its generic integer type widens literal versions to number in TypeScript.
    identification_provenance: data.identification_provenance as
      | IdentificationProvenance
      | undefined,
    ai_confidence_score: data.confidence_score,
    is_biological_subject: data.is_biological_subject,
    ai_reasoning: data.ai_reasoning,
    inference_tier: data.inference_tier,
    candidates: data.candidates ?? null,
    pet_identification: data.pet_identification ?? null,
    blur_score: data.blur_score,
    is_live_capture: data.is_live_capture,
    ecology_type: normalizeScanEcologyType(data.ecology_type),
    is_invasive: data.is_invasive ?? undefined,
    invasive_status_region: data.invasive_status_region,
    invasive_rationale: data.invasive_rationale,
    invasive_confidence: data.invasive_confidence,
    life_stage: data.life_stage,
    reproductive_condition: data.reproductive_condition,
    sex: data.sex,
    sex_confidence: data.sex_confidence,
    sex_evidence: data.sex_evidence,
    individual_count: data.individual_count,
    ecological_interactions: data.ecological_interactions ?? [],
    extracted_visual_traits: data.extracted_visual_traits ?? [],
    colors: data.colors ?? [],
    estimated_size_cm: data.estimated_size_cm,
    image_quality_score: data.image_quality?.overall_score ?? null,
    timestamp: text("timestamp"),
    geoprivacy: telemetry.geoprivacy,
    gps_lat_exact: number("gpsLatitude"),
    gps_long_exact: number("gpsLongitude"),
    gps_elevation: number("gpsElevation"),
    semantic_location: text("semanticLocation"),
    public_location_label: telemetry.geoprivacy === "private"
      ? null
      : text("publicLocationLabel"),
    weather_condition: text("weatherCondition"),
    weather_temperature_f: number("weatherTemperatureF"),
    device_locale: text("deviceLocale"),
    device_time_zone: text("deviceTimeZone"),
    current_month: number("currentMonth"),
    time_of_day: text("timeOfDay"),
    depth_scale_text: text("depthScaleText"),
    zoom_factor: number("zoomFactor"),
    image_storage_urls: [],
    video_storage_urls: [],
    audio_storage_urls: [],
    captured_media: [],
    user_observation_context: notes.length
      ? { freeText: notes.map((note) => note.text).join("\n") }
      : null,
  };
  await dependencies.bind(owner, request, result, species, signal);
  signal.throwIfAborted();
  await dependencies.insert(row, signal);
  signal.throwIfAborted();
  const verify = initialEvidenceCompletionVerifier({
    ownerID: owner,
    scanID: request.scan_id,
    generation: request.generation,
    evidenceDigest: request.evidence_digest,
  });
  const completed = await dependencies.complete({
    scanId: request.scan_id,
    userId: owner,
    promotedUrlsByStorageKey: new Map(),
    deletedStorageKeys: [],
    responseEnvelope: { success: true, data: result },
    initialEvidence: {
      generation: request.generation,
      evidence_digest: request.evidence_digest,
      verifyResponse: verify,
    },
  }, signal);
  signal.throwIfAborted();
  verify(completed.responseEnvelope);
  return completed;
}

export function initialEvidenceFinalizationDependencies(
  client: SupabaseClient,
  onResultBindingDispatch?: () => void,
): InitialEvidenceFinalizationDependencies {
  return {
    bind: initialEvidenceRepository(client, onResultBindingDispatch).bindResult,
    insert: (row, signal) =>
      initialDeadline(
        signal,
        5_000,
        (current) =>
          initialAbortable(current, () => insertPreparedScan(row, client)),
      ),
    complete: (input, signal) =>
      initialDeadline(
        signal,
        5_000,
        (current) =>
          initialAbortable(
            current,
            () => completeScanIngestionFinalization(input, client),
          ),
      ),
  };
}
