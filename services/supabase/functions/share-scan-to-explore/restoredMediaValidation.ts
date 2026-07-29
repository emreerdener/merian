import type { SupabaseClient } from "@supabase/supabase-js";
import { publicHttpError } from "../_shared/http.ts";
import {
  MEDIA_BUDGETS,
  type StagingMediaKind,
  validateStagingObjectKey,
} from "../_shared/mediaBudgets.ts";

export interface RestoredMediaObjectKeys {
  restoredObjectKeys: string[];
  restoredVideoObjectKeys: string[];
  restoredAudioObjectKeys: string[];
}

export interface RestoredMediaLedgerRow {
  client_scan_id?: string | null;
  kind?: string | null;
  role?: string | null;
  storage_key?: string | null;
}

interface ExpectedRestoredMediaKey {
  key: string;
  kind: StagingMediaKind;
  role: "display" | "playback" | "audio";
}

function restoredMediaConflict(): never {
  throw publicHttpError(
    409,
    "Restored media is not registered for this scan. Upload it again and retry.",
    "restored_media_not_registered",
  );
}

function legacyKindForFileName(fileName: string): StagingMediaKind {
  const lower = fileName.toLowerCase();
  if (lower.endsWith(".mp4")) return "video";
  if (lower.endsWith(".wav") || lower.endsWith(".m4a")) return "audio";
  return "image";
}

function isExactLegacyRestoreKey(
  key: string,
  scanId: string,
  kind: StagingMediaKind,
): boolean {
  const fileName = key.slice(key.lastIndexOf("/") + 1);
  if (legacyKindForFileName(fileName) !== kind) return false;

  const escapedScanId = scanId.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  switch (kind) {
    case "image":
      return new RegExp(
        `^${escapedScanId}_explore_restore_(?:live|[0-9]+)[.][A-Za-z0-9]+$`,
        "i",
      ).test(fileName);
    case "video":
      return new RegExp(
        `^${escapedScanId}_explore_restore_video_[0-9]+[.]mp4$`,
        "i",
      ).test(fileName);
    case "audio":
      return new RegExp(
        `^${escapedScanId}_explore_restore_audio_[0-9]+[.](?:wav|m4a)$`,
        "i",
      ).test(fileName);
  }
}

function expectedRestoredMediaKeys(
  keys: RestoredMediaObjectKeys,
): ExpectedRestoredMediaKey[] {
  return [
    ...keys.restoredObjectKeys.map((key) => ({
      key,
      kind: "image" as const,
      role: "display" as const,
    })),
    ...keys.restoredVideoObjectKeys.map((key) => ({
      key,
      kind: "video" as const,
      role: "playback" as const,
    })),
    ...keys.restoredAudioObjectKeys.map((key) => ({
      key,
      kind: "audio" as const,
      role: "audio" as const,
    })),
  ];
}

/**
 * Bind every restored object to its authoritative upload-signing identity.
 *
 * Current clients register capture-upload ledger rows before receiving upload
 * URLs. Older released clients did not provide a client scan ID to the signer,
 * so a missing row is accepted only for their exact deterministic
 * scan/category filename contract. A ledger row for a key always wins: it must
 * match the requested scan, kind, and role and can never fall back to filename
 * inference.
 */
export function assertRestoredMediaLedgerBinding(
  scanId: string,
  keys: RestoredMediaObjectKeys,
  rows: RestoredMediaLedgerRow[],
): void {
  const canonicalScanId = scanId.toLowerCase();
  const rowsByKey = new Map<string, RestoredMediaLedgerRow[]>();
  for (const row of rows) {
    const storageKey = row.storage_key?.trim();
    if (!storageKey) continue;
    const matchingRows = rowsByKey.get(storageKey) ?? [];
    matchingRows.push(row);
    rowsByKey.set(storageKey, matchingRows);
  }

  for (const expected of expectedRestoredMediaKeys(keys)) {
    const ledgerRows = rowsByKey.get(expected.key) ?? [];
    if (ledgerRows.length === 0) {
      if (
        !isExactLegacyRestoreKey(expected.key, canonicalScanId, expected.kind)
      ) {
        restoredMediaConflict();
      }
      continue;
    }

    const hasOnlyExactBindings = ledgerRows.every((row) =>
      row.client_scan_id?.toLowerCase() === canonicalScanId &&
      row.kind === expected.kind &&
      row.role === expected.role
    );
    if (!hasOnlyExactBindings) restoredMediaConflict();
  }
}

export async function requireRestoredMediaLedgerBinding(
  scanId: string,
  userId: string,
  keys: RestoredMediaObjectKeys,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const expectedKeys = expectedRestoredMediaKeys(keys);
  if (expectedKeys.length === 0) return;

  const { data, error } = await supabaseAdmin
    .from("scan_media_assets")
    .select("client_scan_id,kind,role,storage_key")
    .eq("user_id", userId)
    .eq("source", "capture_upload")
    .in("storage_key", expectedKeys.map(({ key }) => key));

  if (error) {
    throw publicHttpError(
      503,
      "Restored media could not be verified. Please try again.",
      "restored_media_verification_unavailable",
    );
  }

  assertRestoredMediaLedgerBinding(
    scanId,
    keys,
    (data ?? []) as RestoredMediaLedgerRow[],
  );
}

export function normalizeRestoredObjectKeys(
  value: unknown,
  userId: string,
  fieldName = "restored_object_keys",
  maxItems = 5,
): string[] {
  if (value == null) return [];
  if (!Array.isArray(value)) {
    throw publicHttpError(400, `${fieldName} must be an array.`);
  }

  const normalized = value.map((entry) => {
    if (typeof entry !== "string") {
      throw publicHttpError(
        400,
        `${fieldName} must only contain strings.`,
      );
    }
    return entry.trim();
  }).filter((entry) => entry.length > 0);

  if (normalized.length > maxItems) {
    throw publicHttpError(
      400,
      `${fieldName} cannot contain more than ${maxItems} item${
        maxItems === 1 ? "" : "s"
      }.`,
    );
  }

  const canonicalUserId = userId.toLowerCase();
  const expectedPrefix = `staging/${canonicalUserId}/`;
  if (
    !normalized.every((entry) =>
      entry.length <= 512 &&
      validateStagingObjectKey(entry, canonicalUserId) === null &&
      /^[A-Za-z0-9._-]+$/.test(entry.slice(expectedPrefix.length))
    )
  ) {
    throw publicHttpError(
      400,
      `${fieldName} must contain safe staging keys owned by the current user.`,
    );
  }

  return [...new Set(normalized)];
}

export function normalizeRestoredMediaObjectKeys(
  body: Record<string, unknown>,
  userId: string,
): RestoredMediaObjectKeys {
  const restoredObjectKeys = normalizeRestoredObjectKeys(
    body.restored_object_keys,
    userId,
    "restored_object_keys",
    MEDIA_BUDGETS.maxImageCount,
  );
  const restoredVideoObjectKeys = normalizeRestoredObjectKeys(
    body.restored_video_object_keys,
    userId,
    "restored_video_object_keys",
    MEDIA_BUDGETS.maxStagedVideoFiles,
  );
  const restoredAudioObjectKeys = normalizeRestoredObjectKeys(
    body.restored_audio_object_keys,
    userId,
    "restored_audio_object_keys",
    MEDIA_BUDGETS.maxStagedAudioFiles,
  );
  const combinedKeys = [
    ...restoredObjectKeys,
    ...restoredVideoObjectKeys,
    ...restoredAudioObjectKeys,
  ];

  if (combinedKeys.length > MEDIA_BUDGETS.maxStagingFiles) {
    throw publicHttpError(
      400,
      `restored media keys cannot contain more than ${MEDIA_BUDGETS.maxStagingFiles} items in total.`,
    );
  }
  if (new Set(combinedKeys).size !== combinedKeys.length) {
    throw publicHttpError(
      400,
      "A restored staging key cannot be claimed as more than one media kind.",
    );
  }

  return {
    restoredObjectKeys,
    restoredVideoObjectKeys,
    restoredAudioObjectKeys,
  };
}

export function restoredObjectKeysMissingDurableUrls(
  restoredObjectKeys: string[],
  durableUrls: string[] | null | undefined,
  userId: string,
): string[] {
  const canonicalUserId = userId.toLowerCase();
  const durableFileNames = new Set(
    (durableUrls ?? []).flatMap((value) => {
      if (typeof value !== "string") return [];
      const match = value.trim().match(
        /^https:\/\/media[.]merian[.]app\/public_uploads\/(?:free|pro)\/([0-9a-f-]+)\/([A-Za-z0-9._-]+)$/,
      );
      return match?.[1]?.toLowerCase() === canonicalUserId && match[2]
        ? [match[2]]
        : [];
    }),
  );

  return restoredObjectKeys.filter((key) => {
    const fileName = key.slice(key.lastIndexOf("/") + 1);
    return !durableFileNames.has(fileName);
  });
}
