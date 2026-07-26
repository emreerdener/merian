export type ExportScope = "personal" | "global";
export type ExportWorkPhase =
  | "occurrence"
  | "multimedia"
  | "assembling"
  | "delivering"
  | "completed";

export interface ClaimedExportJob {
  id: string;
  userId: string;
  exportScope: ExportScope;
  includePreciseCoordinates: boolean;
  pseudonymKeyVersion: number;
  maxExportRows: number;
  maxArchiveBytes: number;
  archiveObjectKey: string | null;
  fileUrl: string | null;
  archiveReadyAt: string | null;
  attemptCount: number;
  leaseExpiresAt: string;
  workPhase: ExportWorkPhase;
  occurrenceAfterId: string | null;
  multimediaAfterId: string | null;
  occurrenceRows: number;
  multimediaRows: number;
  csvBytes: number;
  chunkSequence: number;
}

export interface ExportChunkManifestEntry {
  phase: "occurrence" | "multimedia";
  sequence: number;
  objectKey: string;
  byteCount: number;
}

export interface DBScanRow {
  id: string;
  user_id: string | null;
  timestamp?: string;
  gps_lat_exact?: number | null;
  gps_long_exact?: number | null;
  gps_lat_public?: number | null;
  gps_long_public?: number | null;
  coordinate_uncertainty_in_meters?: number | string | null;
  image_storage_urls?: string[];
  life_stage?: string;
  reproductive_condition?: string;
  sex?: string | null;
  individual_count?: number | null;
  ecological_interactions?: string[];
  ai_confidence_score?: number | null;
  species_dictionary?: {
    scientific_name?: string;
    kingdom?: string;
    phylum?: string;
    class?: string;
    order?: string;
    family?: string;
    genus?: string;
    iucn_red_list_status?: string;
  } | null;
}

export interface ExportScanBatch {
  scans: DBScanRow[];
  sourceByteCount: number;
  pageComplete: boolean;
}

export interface ExportQueueHealth {
  generatedAt: string;
  backlogCount: number;
  dueCount: number;
  activeClaimCount: number;
  expiredClaimCount: number;
  oldestDueAt: string | null;
  oldestDueAgeSeconds: number | null;
}

export class ExportWorkerError extends Error {
  readonly code:
    | "archive_generation_failed"
    | "archive_stage_failed"
    | "database_unavailable"
    | "delivery_failed"
    | "export_too_large"
    | "pseudonym_key_unavailable"
    | "source_snapshot_changed"
    | "storage_unavailable";
  readonly safeToFailJob: boolean;

  constructor(
    code: ExportWorkerError["code"],
    message: string,
    safeToFailJob = true,
    options?: ErrorOptions,
  ) {
    super(message, options);
    this.name = "ExportWorkerError";
    this.code = code;
    this.safeToFailJob = safeToFailJob;
  }
}
