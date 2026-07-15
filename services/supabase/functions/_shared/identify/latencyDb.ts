import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import type { CachedSpeciesRow } from "./types.ts";
import type {
  ScanIngestionMediaCounts,
  ScanIngestionMediaObjectKeys,
} from "../scanIngestionJobs.ts";

export interface BeginScanIngestionInput {
  scanId: string;
  userId: string;
  endpoint: string;
  requestPayload: Record<string, unknown>;
  mediaCounts: ScanIngestionMediaCounts;
  mediaObjectKeys: ScanIngestionMediaObjectKeys;
  storageKeys: string[];
  manifestChecksum: string | null;
  payloadChecksum: string | null;
  resumable: boolean;
  inlineMediaRedacted: boolean;
  redactedMediaCounts: Record<string, number>;
  payloadSchemaVersion?: number;
  leaseSeconds?: number;
}

export interface BeginScanIngestionResult {
  uploadSessionIds: string[];
  manifestChecksum: string | null;
  payloadChecksum: string | null;
}

export async function beginScanIngestion(
  input: BeginScanIngestionInput,
  supabaseAdmin: SupabaseClient,
): Promise<BeginScanIngestionResult> {
  const { data, error } = await supabaseAdmin.rpc("begin_scan_ingestion", {
    p_scan_id: input.scanId,
    p_user_id: input.userId,
    p_endpoint: input.endpoint,
    p_request_payload: input.requestPayload,
    p_media_counts: input.mediaCounts,
    p_media_object_keys: input.mediaObjectKeys,
    p_storage_keys: input.storageKeys,
    p_manifest_checksum: input.manifestChecksum,
    p_payload_checksum: input.payloadChecksum,
    p_resumable: input.resumable,
    p_inline_media_redacted: input.inlineMediaRedacted,
    p_redacted_media_counts: input.redactedMediaCounts,
    p_payload_schema_version: input.payloadSchemaVersion ?? 1,
    p_lease_seconds: input.leaseSeconds ?? 300,
  });

  if (error) {
    throw new Error(`beginScanIngestion: ${error.message}`);
  }

  const result = data as {
    upload_session_ids?: unknown;
    manifest_checksum?: unknown;
    payload_checksum?: unknown;
  } | null;
  const rawIds = result?.upload_session_ids;
  return {
    uploadSessionIds: Array.isArray(rawIds)
      ? rawIds.filter((value): value is string => typeof value === "string")
      : [],
    manifestChecksum: typeof result?.manifest_checksum === "string"
      ? result.manifest_checksum
      : null,
    payloadChecksum: typeof result?.payload_checksum === "string"
      ? result.payload_checksum
      : null,
  };
}

export interface IdentificationDictionaryHydration {
  cachedSpecies: CachedSpeciesRow | null;
  candidateCommonNames: Map<string, string>;
}

export async function fetchIdentificationDictionaryHydration(
  primaryScientificName: string | null,
  candidateScientificNames: string[],
  supabaseAdmin: SupabaseClient,
): Promise<IdentificationDictionaryHydration> {
  const { data, error } = await supabaseAdmin.rpc(
    "hydrate_identification_dictionary",
    {
      p_primary_scientific_name: primaryScientificName,
      p_candidate_scientific_names: candidateScientificNames,
    },
  );
  if (error) {
    throw new Error(`fetchIdentificationDictionaryHydration: ${error.message}`);
  }

  const hydration = data as {
    primary?: CachedSpeciesRow | null;
    candidate_common_names?: Record<string, unknown> | null;
  } | null;
  const candidateCommonNames = new Map<string, string>();
  for (
    const [scientificName, commonName] of Object.entries(
      hydration?.candidate_common_names ?? {},
    )
  ) {
    if (typeof commonName === "string" && commonName.trim().length > 0) {
      candidateCommonNames.set(scientificName, commonName.trim());
    }
  }

  return {
    cachedSpecies: hydration?.primary ?? null,
    candidateCommonNames,
  };
}
