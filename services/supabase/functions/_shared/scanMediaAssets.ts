import { SupabaseClient } from "@supabase/supabase-js";
import { MEDIA_BUDGETS } from "./mediaBudgets.ts";

export type ScanMediaAssetKind = "image" | "video" | "audio";
export type ScanMediaAssetRole =
  | "display"
  | "playback"
  | "thumbnail"
  | "inference_frame"
  | "audio";
export type ScanMediaAssetStatus =
  | "staged"
  | "promoted"
  | "processing"
  | "ready"
  | "failed"
  | "deleted";
export type ReadyScanMediaAssetKind = "image" | "video" | "audio";
export type StagedScanMediaUploadPurpose = "scan_share_restore";

export interface ScanMediaAssetRow {
  kind: ScanMediaAssetKind;
  role?: ScanMediaAssetRole | null;
  status?: ScanMediaAssetStatus | null;
  source?: string | null;
  url?: string | null;
  storage_key?: string | null;
  thumbnail_url?: string | null;
  order_index: number;
  duration_seconds?: number | null;
  has_audio?: boolean | null;
  content_type?: string | null;
  byte_size?: number | null;
  checksum_sha256?: string | null;
  width?: number | null;
  height?: number | null;
  failure_reason?: string | null;
  ready_at?: string | null;
  deleted_at?: string | null;
  metadata?: Record<string, unknown> | null;
}

export interface StagedScanMediaAssetInput {
  userId: string;
  clientScanId: string;
  uploadSessionId: string;
  kind: ScanMediaAssetKind;
  role: ScanMediaAssetRole;
  storageKey: string;
  orderIndex: number;
  contentType: string;
  byteSize?: number | null;
  uploadPurpose?: StagedScanMediaUploadPurpose;
  metadata?: Record<string, unknown> | null;
}

export interface StagedScanMediaAssetRow {
  id: string;
  storage_key: string;
  upload_session_id: string;
  order_index: number;
}

type ReusableStagedScanMediaAssetRow = StagedScanMediaAssetRow & {
  user_id: string;
  client_scan_id: string;
  kind: ScanMediaAssetKind;
  role: ScanMediaAssetRole;
  content_type: string | null;
  byte_size: number | null;
  status: ScanMediaAssetStatus;
  failure_reason: string | null;
};

type NormalizedScanMediaAssetRow = ScanMediaAssetRow & {
  role: ScanMediaAssetRole;
  status: ScanMediaAssetStatus;
  url: string;
  order_index: number;
};

function isScanShareRestoreInput(
  input: StagedScanMediaAssetInput,
): boolean {
  return input.uploadPurpose === "scan_share_restore";
}

function isValidScanShareRestoreInput(
  input: StagedScanMediaAssetInput,
): boolean {
  if (!isScanShareRestoreInput(input)) return false;
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
      .test(input.clientScanId)
  ) {
    return false;
  }
  const fileName = input.storageKey.slice(
    input.storageKey.lastIndexOf("/") + 1,
  );
  if (
    input.storageKey !==
      `staging/${input.userId.toLowerCase()}/${fileName}` ||
    !/^[A-Za-z0-9._-]+$/.test(fileName)
  ) {
    return false;
  }
  const escapedScanId = input.clientScanId.replace(
    /[.*+?^${}()|[\]\\]/g,
    "\\$&",
  );
  const suffix = "[.][A-Za-z0-9]+$";
  switch (input.kind) {
    case "image":
      return input.role === "display" &&
        new RegExp(
          `^${escapedScanId}_explore_restore_(?:live|[0-9]+)${suffix}`,
          "i",
        ).test(fileName);
    case "video":
      return input.role === "playback" &&
        new RegExp(
          `^${escapedScanId}_explore_restore_video_[0-9]+${suffix}`,
          "i",
        ).test(fileName);
    case "audio":
      return input.role === "audio" &&
        new RegExp(
          `^${escapedScanId}_explore_restore_audio_[0-9]+${suffix}`,
          "i",
        ).test(fileName);
  }
}

export type ReadyScanMediaAssetRow =
  & Omit<
    NormalizedScanMediaAssetRow,
    "role" | "status"
  >
  & {
    kind: ReadyScanMediaAssetKind;
    role: "display" | "playback" | "audio";
    status: "ready";
  };

export function cleanScanMediaAssetRows(
  rows: ScanMediaAssetRow[] | null | undefined,
): ReadyScanMediaAssetRow[] {
  return (rows ?? [])
    .map((row): NormalizedScanMediaAssetRow => ({
      ...row,
      role: normalizeAssetRole(row),
      status: normalizeAssetStatus(row),
      url: typeof row.url === "string" ? row.url.trim() : "",
      thumbnail_url: typeof row.thumbnail_url === "string"
        ? row.thumbnail_url.trim()
        : row.thumbnail_url ?? null,
      order_index: Number.isInteger(row.order_index) && row.order_index >= 0
        ? row.order_index
        : Number.MAX_SAFE_INTEGER,
    }))
    .filter(isReadyVisibleAssetRow)
    .sort((lhs, rhs) => lhs.order_index - rhs.order_index);
}

function isReadyVisibleAssetRow(
  row: NormalizedScanMediaAssetRow,
): row is ReadyScanMediaAssetRow {
  const isPublicMediaKind = row.kind === "image" || row.kind === "video" ||
    row.kind === "audio";
  const isVisibleRole = row.role === "display" || row.role === "playback" ||
    row.role === "audio";
  return isPublicMediaKind &&
    row.status === "ready" &&
    isVisibleRole &&
    row.url.length > 0;
}

function normalizeAssetRole(row: ScanMediaAssetRow): ScanMediaAssetRole {
  const role = typeof row.role === "string" ? row.role.trim() : "";
  switch (role) {
    case "display":
    case "playback":
    case "thumbnail":
    case "inference_frame":
    case "audio":
      return role;
    default:
      return row.kind === "video" ? "playback" : "display";
  }
}

function normalizeAssetStatus(row: ScanMediaAssetRow): ScanMediaAssetStatus {
  const status = typeof row.status === "string" ? row.status.trim() : "";
  switch (status) {
    case "staged":
    case "promoted":
    case "processing":
    case "ready":
    case "failed":
    case "deleted":
      return status;
    default:
      return "ready";
  }
}

export function countVideoScanMediaAssets(
  rows: ScanMediaAssetRow[] | null | undefined,
): number {
  return cleanScanMediaAssetRows(rows).filter((row) => row.kind === "video")
    .length;
}

export async function fetchScanMediaAssets(
  scanId: string,
  supabaseAdmin: SupabaseClient,
): Promise<ReadyScanMediaAssetRow[]> {
  const { data, error } = await supabaseAdmin
    .from("scan_media_assets")
    .select(
      "kind,role,status,source,url,storage_key,thumbnail_url,order_index,duration_seconds,has_audio,content_type,byte_size,checksum_sha256,width,height,failure_reason,ready_at,deleted_at,metadata",
    )
    .eq("scan_id", scanId)
    .order("order_index", { ascending: true });

  if (error) {
    throw new Error(`fetchScanMediaAssets: ${error.message}`);
  }

  return cleanScanMediaAssetRows(data as ScanMediaAssetRow[] | null);
}

export async function createStagedScanMediaAssets(
  inputs: StagedScanMediaAssetInput[],
  supabaseAdmin: SupabaseClient,
): Promise<StagedScanMediaAssetRow[]> {
  if (inputs.length === 0) return [];

  const userIds = new Set(inputs.map((input) => input.userId));
  if (userIds.size !== 1) {
    throw new Error(
      "createStagedScanMediaAssets: one registration may have only one owner",
    );
  }
  const userId = inputs[0].userId;
  const identity = (input: {
    clientScanId: string;
    storageKey: string;
  }): string => `${input.clientScanId}\u0000${input.storageKey}`;
  const inputByIdentity = new Map(
    inputs.map((input) => [identity(input), input]),
  );
  if (inputByIdentity.size !== inputs.length) {
    throw new Error(
      "createStagedScanMediaAssets: duplicate active staging key",
    );
  }
  if (new Set(inputs.map((input) => input.storageKey)).size !== inputs.length) {
    throw new Error(
      "createStagedScanMediaAssets: one storage key cannot represent multiple scans",
    );
  }
  if (
    inputs.some((input) =>
      isScanShareRestoreInput(input) &&
      !isValidScanShareRestoreInput(input)
    )
  ) {
    throw new Error(
      "createStagedScanMediaAssets: invalid scan-share restore registration",
    );
  }
  const restoreScanIds = new Set(
    inputs.filter(isScanShareRestoreInput).map((input) => input.clientScanId),
  );
  if (
    inputs.some((input) =>
      restoreScanIds.has(input.clientScanId) &&
      !isValidScanShareRestoreInput(input)
    )
  ) {
    throw new Error(
      "createStagedScanMediaAssets: scan-share restore cannot mix with ordinary registration",
    );
  }

  const rowsByIdentity = new Map<string, StagedScanMediaAssetRow>();
  const activeStorageKeysByClientScanId = new Map<string, Set<string>>();
  const fetchReusableRows = async (): Promise<void> => {
    const { data, error } = await supabaseAdmin
      .from("scan_media_assets")
      .select(
        "id,user_id,client_scan_id,kind,role,content_type,byte_size,status,failure_reason,storage_key,upload_session_id,order_index",
      )
      .eq("user_id", userId)
      .eq("source", "capture_upload")
      .in(
        "client_scan_id",
        [...new Set(inputs.map((input) => input.clientScanId))],
      );

    if (error) {
      throw new Error(
        `createStagedScanMediaAssets: ${error.message}`,
      );
    }

    rowsByIdentity.clear();
    activeStorageKeysByClientScanId.clear();
    for (
      const row of (data ?? []) as unknown as ReusableStagedScanMediaAssetRow[]
    ) {
      if (
        row.status === "failed" &&
        (
          row.failure_reason === "superseded_staging_registration" ||
          row.failure_reason === "superseded_identity_merge_staging"
        )
      ) {
        continue;
      }
      if (row.status === "staged" || row.status === "processing") {
        const activeStorageKeys = activeStorageKeysByClientScanId.get(
          row.client_scan_id,
        ) ?? new Set<string>();
        activeStorageKeys.add(row.storage_key);
        activeStorageKeysByClientScanId.set(
          row.client_scan_id,
          activeStorageKeys,
        );
      }
      const rowIdentity = identity({
        clientScanId: row.client_scan_id,
        storageKey: row.storage_key,
      });
      const input = inputByIdentity.get(rowIdentity);
      // Signing calls are intentionally composable. Live video upload may sign
      // only the clip while the durable queue signs the same scan's recovery
      // frames/audio, and an inline foreground request has no staged sources at
      // all until its offline copy is uploaded. Unrequested rows therefore do
      // not define an immutable full manifest; exact requested identities do.
      if (!input) continue;
      if (
        rowsByIdentity.has(rowIdentity) ||
        row.user_id !== input.userId ||
        row.kind !== input.kind ||
        row.role !== input.role ||
        row.content_type !== input.contentType ||
        row.byte_size !== (input.byteSize ?? null)
      ) {
        throw new Error(
          "createStagedScanMediaAssets: conflicting active staging registration",
        );
      }
      rowsByIdentity.set(rowIdentity, row);
    }
  };

  const insertRows = (missingInputs: StagedScanMediaAssetInput[]) =>
    missingInputs.map((input) => ({
      scan_id: null,
      client_scan_id: input.clientScanId,
      upload_session_id: input.uploadSessionId,
      user_id: input.userId,
      kind: input.kind,
      role: input.role,
      status: "staged",
      source: "capture_upload",
      url: null,
      storage_key: input.storageKey,
      thumbnail_url: null,
      order_index: input.orderIndex,
      duration_seconds: null,
      has_audio: false,
      content_type: input.contentType,
      byte_size: input.byteSize ?? null,
      failure_reason: null,
      ready_at: null,
      deleted_at: null,
      metadata: input.metadata ?? {},
    }));

  // A signing response can be lost after its staged ledger rows commit. Reuse
  // those rows on retry; a partial unique index serializes concurrent retries.
  // If another request wins between SELECT and INSERT, retry the lookup rather
  // than creating a second active row that the exact-count finalizer rejects.
  for (let attempt = 0; attempt < 3; attempt += 1) {
    await fetchReusableRows();
    for (
      const clientScanId of new Set(
        inputs.map((input) => input.clientScanId),
      )
    ) {
      const activeStorageKeys = new Set(
        activeStorageKeysByClientScanId.get(clientScanId) ?? [],
      );
      for (
        const requestedInput of inputs.filter((input) =>
          input.clientScanId === clientScanId
        )
      ) {
        activeStorageKeys.add(requestedInput.storageKey);
      }
      if (activeStorageKeys.size > MEDIA_BUDGETS.maxStagingFiles) {
        throw new Error(
          "createStagedScanMediaAssets: staged media budget exceeded for client scan",
        );
      }
    }
    const requestedClientScanIds = [
      ...new Set(inputs.map((input) => input.clientScanId)),
    ];
    const { data: jobData, error: jobError } = await supabaseAdmin
      .from("scan_ingestion_jobs")
      .select("scan_id,status,stage")
      .eq("user_id", userId)
      .in("scan_id", requestedClientScanIds);
    if (jobError) {
      throw new Error(
        `createStagedScanMediaAssets: ${jobError.message}`,
      );
    }
    const jobStatusByScanId = new Map(
      ((jobData ?? []) as Array<{
        scan_id: string;
        status: string;
        stage: string;
      }>).map(
        (row) => [row.scan_id, { status: row.status, stage: row.stage }],
      ),
    );
    const completedRestoreScanIds: string[] = [];
    const hasDisallowedTerminalJob = requestedClientScanIds.some((scanId) => {
      const status = jobStatusByScanId.get(scanId)?.status;
      if (status === "failed_terminal") return true;
      if (status !== "complete") return false;
      if (!restoreScanIds.has(scanId)) return true;
      completedRestoreScanIds.push(scanId);
      return false;
    });
    if (hasDisallowedTerminalJob) {
      throw new Error(
        "createStagedScanMediaAssets: terminal staging registration cannot be retried",
      );
    }
    if (completedRestoreScanIds.length > 0) {
      const { data: scanData, error: scanError } = await supabaseAdmin
        .from("scans")
        .select("id,user_id,is_tombstoned")
        .in("id", completedRestoreScanIds);
      if (scanError) {
        throw new Error(
          `createStagedScanMediaAssets: ${scanError.message}`,
        );
      }
      const scanById = new Map(
        ((scanData ?? []) as Array<{
          id: string;
          user_id: string;
          is_tombstoned: boolean;
        }>).map((row) => [row.id.toLowerCase(), row]),
      );
      if (
        completedRestoreScanIds.some((scanId) => {
          const scan = scanById.get(scanId.toLowerCase());
          // An absent row is allowed to stage only; the later guarded
          // recovery route remains responsible for reconstructing and
          // authorizing the owner row before any publication.
          if (!scan) return false;
          return scan.user_id.toLowerCase() !== userId.toLowerCase() ||
            scan.is_tombstoned !== false;
        })
      ) {
        throw new Error(
          "createStagedScanMediaAssets: terminal staging registration cannot be retried",
        );
      }
    }

    const failedRows = [...rowsByIdentity.entries()].filter(([, row]) =>
      (row as ReusableStagedScanMediaAssetRow).status === "failed"
    ) as Array<[string, ReusableStagedScanMediaAssetRow]>;
    const invalidRows = [...rowsByIdentity.values()].filter((row) => {
      const status = (row as ReusableStagedScanMediaAssetRow).status;
      return status !== "staged" && status !== "failed";
    });
    if (invalidRows.length > 0) {
      throw new Error(
        "createStagedScanMediaAssets: conflicting active staging registration",
      );
    }
    if (
      failedRows.some(([rowIdentity, row]) => {
        const jobStatus = jobStatusByScanId.get(row.client_scan_id)?.status;
        const requestedInput = inputByIdentity.get(rowIdentity);
        const isCompletedRestore = jobStatus === "complete" &&
          requestedInput != null &&
          isValidScanShareRestoreInput(requestedInput);
        return row.failure_reason === "moderation_rejected" ||
          (
            jobStatus != null &&
            jobStatus !== "failed_retryable" &&
            jobStatus !== "retrying" &&
            !isCompletedRestore
          );
      })
    ) {
      throw new Error(
        "createStagedScanMediaAssets: terminal staging registration cannot be retried",
      );
    }

    const missingInputs = inputs.filter((input) =>
      !rowsByIdentity.has(identity(input))
    );

    if (failedRows.length > 0) {
      let reactivationLostRace = false;
      for (const [rowIdentity, row] of failedRows) {
        const { data, error } = await supabaseAdmin
          .from("scan_media_assets")
          .update({
            status: "staged",
            failure_reason: null,
            deleted_at: null,
            updated_at: new Date().toISOString(),
          })
          .eq("id", row.id)
          .eq("user_id", userId)
          .eq("source", "capture_upload")
          .eq("status", "failed")
          .select("id,storage_key,upload_session_id,order_index")
          .maybeSingle();
        if (error) {
          if (error.code === "23505") {
            reactivationLostRace = true;
            break;
          }
          throw new Error(
            `createStagedScanMediaAssets: ${error.message}`,
          );
        }
        if (!data) {
          reactivationLostRace = true;
          break;
        }
        rowsByIdentity.set(
          rowIdentity,
          data as StagedScanMediaAssetRow,
        );
      }
      if (reactivationLostRace) continue;
    }

    if (missingInputs.length === 0) {
      return inputs.map((input) => rowsByIdentity.get(identity(input))!);
    }

    const { data, error } = await supabaseAdmin
      .from("scan_media_assets")
      .insert(insertRows(missingInputs))
      .select("id,storage_key,upload_session_id,order_index")
      .order("order_index", { ascending: true });

    if (!error) {
      const missingInputByStorageKey = new Map(
        missingInputs.map((input) => [input.storageKey, input]),
      );
      const insertedIdentities = new Set<string>();
      for (const row of (data ?? []) as StagedScanMediaAssetRow[]) {
        const input = missingInputByStorageKey.get(row.storage_key);
        const rowIdentity = input ? identity(input) : "";
        if (!input || insertedIdentities.has(rowIdentity)) {
          throw new Error(
            "createStagedScanMediaAssets: incomplete staging registration",
          );
        }
        insertedIdentities.add(rowIdentity);
        rowsByIdentity.set(rowIdentity, row);
      }
      if (
        insertedIdentities.size !== missingInputs.length ||
        rowsByIdentity.size !== inputs.length
      ) {
        throw new Error(
          "createStagedScanMediaAssets: incomplete staging registration",
        );
      }
      return inputs.map((input) => rowsByIdentity.get(identity(input))!);
    }
    if (error.code !== "23505") {
      throw new Error(`createStagedScanMediaAssets: ${error.message}`);
    }
  }

  throw new Error(
    "createStagedScanMediaAssets: concurrent staging registration did not converge",
  );
}

export async function fetchCaptureUploadSessionIdsForKeys(
  input: {
    userId: string;
    clientScanId: string;
    storageKeys: string[];
  },
  supabaseAdmin: SupabaseClient,
): Promise<string[]> {
  const uniqueKeys = [...new Set(input.storageKeys.map((key) => key.trim()))]
    .filter((key) => key.length > 0);
  if (uniqueKeys.length === 0) return [];

  const { data, error } = await supabaseAdmin
    .from("scan_media_assets")
    .select("upload_session_id")
    .eq("user_id", input.userId)
    .eq("client_scan_id", input.clientScanId)
    .eq("source", "capture_upload")
    .in("storage_key", uniqueKeys);

  if (error) {
    throw new Error(`fetchCaptureUploadSessionIdsForKeys: ${error.message}`);
  }

  return [
    ...new Set(
      ((data ?? []) as Array<{ upload_session_id?: string | null }>)
        .map((row) => row.upload_session_id?.trim() ?? "")
        .filter((id) => id.length > 0),
    ),
  ].sort();
}

export async function markStagedScanMediaAssetsPromoted(
  input: {
    userId: string;
    scanId: string;
    promotedUrlsByStorageKey: Map<string, string>;
  },
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  await updateStagedScanMediaAssets(
    input.userId,
    input.promotedUrlsByStorageKey,
    async (storageKey, publicUrl) => {
      const { error } = await supabaseAdmin
        .from("scan_media_assets")
        .update({
          scan_id: input.scanId,
          status: "promoted",
          url: publicUrl,
          failure_reason: null,
          deleted_at: null,
        })
        .eq("user_id", input.userId)
        .eq("source", "capture_upload")
        .eq("status", "staged")
        .eq("storage_key", storageKey);
      return error?.message ?? null;
    },
  );
}

export async function markStagedScanMediaAssetsFailed(
  input: {
    userId: string;
    storageKeys: string[];
    failureReason: string;
  },
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const uniqueKeys = [...new Set(input.storageKeys.map((key) => key.trim()))]
    .filter((key) => key.length > 0);
  if (uniqueKeys.length === 0) return;

  const { error } = await supabaseAdmin
    .from("scan_media_assets")
    .update({
      status: "failed",
      failure_reason: input.failureReason.slice(0, 500),
    })
    .eq("user_id", input.userId)
    .eq("source", "capture_upload")
    .eq("status", "staged")
    .in("storage_key", uniqueKeys);

  if (error) {
    throw new Error(`markStagedScanMediaAssetsFailed: ${error.message}`);
  }
}

export async function markStagedScanMediaAssetsDeleted(
  input: {
    userId: string;
    scanId?: string | null;
    storageKeys: string[];
  },
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const uniqueKeys = [...new Set(input.storageKeys.map((key) => key.trim()))]
    .filter((key) => key.length > 0);
  if (uniqueKeys.length === 0) return;

  const { error } = await supabaseAdmin
    .from("scan_media_assets")
    .update({
      scan_id: input.scanId ?? null,
      status: "deleted",
      deleted_at: new Date().toISOString(),
      failure_reason: null,
    })
    .eq("user_id", input.userId)
    .eq("source", "capture_upload")
    .eq("status", "staged")
    .in("storage_key", uniqueKeys);

  if (error) {
    throw new Error(`markStagedScanMediaAssetsDeleted: ${error.message}`);
  }
}

async function updateStagedScanMediaAssets(
  userId: string,
  urlsByStorageKey: Map<string, string>,
  update: (storageKey: string, publicUrl: string) => Promise<string | null>,
): Promise<void> {
  const failures: string[] = [];
  for (const [storageKey, publicUrl] of urlsByStorageKey) {
    const cleanStorageKey = storageKey.trim();
    const cleanPublicUrl = publicUrl.trim();
    if (cleanStorageKey.length === 0 || cleanPublicUrl.length === 0) continue;
    const errorMessage = await update(cleanStorageKey, cleanPublicUrl);
    if (errorMessage) {
      failures.push(`${cleanStorageKey}: ${errorMessage}`);
    }
  }

  if (failures.length > 0) {
    throw new Error(
      `updateStagedScanMediaAssets(${userId}) failed: ${failures.join("; ")}`,
    );
  }
}

export async function fetchScanMediaAssetsBestEffort(
  scanId: string,
  supabaseAdmin: SupabaseClient,
): Promise<ReadyScanMediaAssetRow[]> {
  try {
    return await fetchScanMediaAssets(scanId, supabaseAdmin);
  } catch (error) {
    console.error(JSON.stringify({
      event: "scan_media_assets_fetch_failed",
      scan_id: scanId,
      error: error instanceof Error ? error.message : String(error),
      ts: new Date().toISOString(),
    }));
    return [];
  }
}

export async function refreshScanMediaAssets(
  scanId: string,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { error } = await supabaseAdmin.rpc("refresh_scan_media_assets", {
    target_scan_id: scanId,
  });

  if (error) {
    throw new Error(`refreshScanMediaAssets: ${error.message}`);
  }
}

export async function refreshScanMediaAssetsBestEffort(
  scanId: string,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  try {
    await refreshScanMediaAssets(scanId, supabaseAdmin);
  } catch (error) {
    console.error(JSON.stringify({
      event: "scan_media_assets_refresh_failed",
      scan_id: scanId,
      error: error instanceof Error ? error.message : String(error),
      ts: new Date().toISOString(),
    }));
  }
}
