import type { SupabaseClient } from "@supabase/supabase-js";

export type DwcaDownloadAuthorization =
  | { status: "authorized"; objectKey: string }
  | { status: "gone" }
  | { status: "not_found" }
  | { status: "not_ready"; retryAfterSeconds: number }
  | { status: "rate_limited"; retryAfterSeconds: number };

const ARCHIVE_OBJECT_KEY_PATTERN =
  /^exports\/[0-9a-f-]{36}\/[0-9a-f-]{36}\/[0-9a-f-]{36}\.zip$/i;

export async function authorizeDwcaArchiveDownload(
  tokenSha256: string,
  ipHash: string,
  supabaseAdmin: SupabaseClient,
): Promise<DwcaDownloadAuthorization> {
  const { data, error } = await supabaseAdmin.rpc(
    "authorize_dwca_archive_download",
    {
      p_token_sha256: tokenSha256,
      p_ip_hash: ipHash,
    },
  );
  if (error || !data || typeof data !== "object" || Array.isArray(data)) {
    throw new Error("DwCA download authorization is unavailable.");
  }

  const row = data as Record<string, unknown>;
  switch (row.status) {
    case "authorized":
      if (
        typeof row.object_key !== "string" ||
        !ARCHIVE_OBJECT_KEY_PATTERN.test(row.object_key)
      ) {
        throw new Error("DwCA download authorization returned an invalid key.");
      }
      return { status: "authorized", objectKey: row.object_key };
    case "not_ready":
    case "rate_limited":
      if (
        !Number.isSafeInteger(row.retry_after_seconds) ||
        Number(row.retry_after_seconds) < 1 ||
        Number(row.retry_after_seconds) > 300
      ) {
        throw new Error(
          "DwCA download authorization returned an invalid retry window.",
        );
      }
      return {
        status: row.status,
        retryAfterSeconds: Number(row.retry_after_seconds),
      };
    case "gone":
    case "not_found":
      return { status: row.status };
    default:
      throw new Error("DwCA download authorization returned an unknown state.");
  }
}
