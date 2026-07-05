import { AwsClient } from "aws4fetch";
import { mapWithConcurrencyLimit } from "./concurrency.ts";

export interface R2Config {
  s3Client: AwsClient;
  bucketName: string;
  endpoint: string;
}

export const R2_MEDIA_PREFIXES = {
  temporary: ["staging/", "quarantine/", "exports/"],
  scanMedia: ["public_uploads/free/", "public_uploads/pro/"],
  avatars: "avatars/",
} as const;

export function getS3Client(): AwsClient {
  return new AwsClient({
    accessKeyId: Deno.env.get("R2_ACCESS_KEY_ID") ?? "",
    secretAccessKey: Deno.env.get("R2_SECRET_ACCESS_KEY") ?? "",
    region: "auto",
  });
}

export function getR2Config(): R2Config {
  const accountId = Deno.env.get("R2_ACCOUNT_ID") ?? "";
  const bucketName = Deno.env.get("R2_BUCKET_NAME") ?? "";
  const endpoint = `https://${accountId}.r2.cloudflarestorage.com`;

  return {
    s3Client: getS3Client(),
    bucketName,
    endpoint,
  };
}

export function getInternalS3Url(publicUrl: string, config: R2Config): string {
  return publicUrl.replace(
    "https://media.merian.app/",
    `${config.endpoint}/${config.bucketName}/`,
  );
}

export function r2ObjectKeyFromPublicUrl(publicUrl: string): string | null {
  try {
    const parsedUrl = new URL(publicUrl);
    if (parsedUrl.hostname !== "media.merian.app") return null;
    return parsedUrl.pathname.replace(/^\/+/, "");
  } catch {
    return null;
  }
}

export function publicR2UrlForKey(key: string): string {
  return `https://media.merian.app/${key}`;
}

export function isScanMediaR2Url(publicUrl: string): boolean {
  const key = r2ObjectKeyFromPublicUrl(publicUrl);
  return key !== null &&
    R2_MEDIA_PREFIXES.scanMedia.some((prefix) => key.startsWith(prefix));
}

export function isAvatarR2Key(key: string, userId?: string): boolean {
  const prefix = userId
    ? `${R2_MEDIA_PREFIXES.avatars}${userId}/`
    : R2_MEDIA_PREFIXES.avatars;
  return !key.includes("..") && key.startsWith(prefix);
}

export function avatarR2KeyFromPublicUrl(
  publicUrl: string,
  userId?: string,
): string | null {
  const key = r2ObjectKeyFromPublicUrl(publicUrl);
  if (!key || !isAvatarR2Key(key, userId)) return null;
  return key;
}

const R2_DELETE_CONCURRENCY = 16;

export const deleteR2Objects = async (urls: string[], r2Config: R2Config) => {
  const { s3Client } = r2Config;
  await mapWithConcurrencyLimit(
    urls,
    R2_DELETE_CONCURRENCY,
    async (url: string) => {
      try {
        console.log(`Deleting R2 object: ${url}`);
        const s3Url = getInternalS3Url(url, r2Config);
        await s3Client.fetch(new Request(s3Url, { method: "DELETE" }));
      } catch (e) {
        console.error(`Failed to wipe media at ${url} from Cloudflare R2:`, e);
      }
    },
  );
};

export async function deleteScanMediaR2Objects(
  urls: string[],
  r2Config: R2Config,
) {
  const scanMediaUrls = urls.filter(isScanMediaR2Url);
  const skippedCount = urls.length - scanMediaUrls.length;
  if (skippedCount > 0) {
    console.warn(
      `Skipped ${skippedCount} non-scan R2 object(s) during scan media deletion.`,
    );
  }
  await deleteR2Objects(scanMediaUrls, r2Config);
}

export async function deleteAvatarR2Object(
  avatarUrl: string,
  userId: string,
  r2Config: R2Config,
): Promise<Response | null> {
  const avatarKey = avatarR2KeyFromPublicUrl(avatarUrl, userId);
  if (!avatarKey) return null;
  return await deleteR2Object(avatarKey, r2Config);
}

export async function copyR2Object(
  sourceKey: string,
  targetKey: string,
  config: R2Config,
): Promise<Response> {
  const { s3Client, bucketName, endpoint } = config;
  const copyUrl = `${endpoint}/${bucketName}/${targetKey}`;

  return await s3Client.fetch(
    new Request(copyUrl, {
      method: "PUT",
      headers: {
        "x-amz-copy-source": encodeURI(`/${bucketName}/${sourceKey}`),
      },
    }),
  );
}

export async function deleteR2Object(
  key: string,
  config: R2Config,
): Promise<Response> {
  const { s3Client, bucketName, endpoint } = config;
  const deleteUrl = `${endpoint}/${bucketName}/${key}`;
  return await s3Client.fetch(new Request(deleteUrl, { method: "DELETE" }));
}

export async function headR2Object(
  key: string,
  config: R2Config,
): Promise<Response> {
  const { s3Client, bucketName, endpoint } = config;
  const headUrl = `${endpoint}/${bucketName}/${key}`;
  return await s3Client.fetch(new Request(headUrl, { method: "HEAD" }));
}

/**
 * Generates a presigned PUT URL for an R2 object.
 *
 * @param config  R2 config from `getR2Config()`.
 * @param key     Object key (e.g. `staging/{userId}/{fileName}`).
 * @param expirySeconds  URL lifetime in seconds (default 86400 = 24 h).
 * @returns The signed URL string ready for the client to PUT to.
 */
export async function generatePresignedPutUrl(
  config: R2Config,
  key: string,
  expirySeconds = 86400,
  contentType = "image/webp",
): Promise<string> {
  const { s3Client, bucketName, endpoint } = config;
  const url = new URL(`${endpoint}/${bucketName}/${key}`);
  url.searchParams.set("X-Amz-Expires", String(expirySeconds));
  const request = new Request(url.toString(), {
    method: "PUT",
    headers: { "Content-Type": contentType },
  });
  const signed = await s3Client.sign(request, {
    aws: { signQuery: true },
  });
  return signed.url;
}
