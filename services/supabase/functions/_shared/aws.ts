import { AwsClient } from "aws4fetch";
import { mapWithConcurrencyLimit } from "./concurrency.ts";
import { readByteStreamWithinLimit } from "./http.ts";

export interface R2Config {
  s3Client: AwsClient;
  bucketName: string;
  endpoint: string;
}

export interface R2ObjectPage {
  keys: string[];
  isTruncated: boolean;
}

export const R2_MEDIA_PREFIXES = {
  temporary: ["staging/", "quarantine/", "exports/"],
  scanMedia: ["public_uploads/free/", "public_uploads/pro/"],
  avatars: "avatars/",
} as const;

export function getS3Client(
  accessKeyId = Deno.env.get("R2_ACCESS_KEY_ID") ?? "",
  secretAccessKey = Deno.env.get("R2_SECRET_ACCESS_KEY") ?? "",
): AwsClient {
  return new AwsClient({
    accessKeyId,
    secretAccessKey,
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

export function getR2ReadConfig(): R2Config {
  const accountId = Deno.env.get("R2_ACCOUNT_ID") ?? "";
  const bucketName = Deno.env.get("R2_BUCKET_NAME") ?? "";
  const endpoint = `https://${accountId}.r2.cloudflarestorage.com`;
  const accessKeyId = Deno.env.get("R2_READ_ACCESS_KEY_ID") ?? "";
  const secretAccessKey = Deno.env.get("R2_READ_SECRET_ACCESS_KEY") ?? "";

  if (
    !accountId ||
    !bucketName ||
    !accessKeyId ||
    !secretAccessKey
  ) {
    throw new Error("Required R2 read configuration is missing.");
  }

  return {
    s3Client: getS3Client(accessKeyId, secretAccessKey),
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
  const failures: Array<{ url: string; reason: string }> = [];
  await mapWithConcurrencyLimit(
    urls,
    R2_DELETE_CONCURRENCY,
    async (url: string) => {
      try {
        console.log(`Deleting R2 object: ${url}`);
        const s3Url = getInternalS3Url(url, r2Config);
        const response = await s3Client.fetch(
          new Request(s3Url, { method: "DELETE" }),
        );
        if (!response.ok) {
          throw new Error(`R2 delete returned HTTP ${response.status}`);
        }
      } catch (e) {
        console.error(`Failed to wipe media at ${url} from Cloudflare R2:`, e);
        failures.push({
          url,
          reason: e instanceof Error ? e.message : String(e),
        });
      }
    },
  );
  if (failures.length > 0) {
    throw new AggregateError(
      failures.map((failure) => new Error(`${failure.url}: ${failure.reason}`)),
      `Failed to delete ${failures.length}/${urls.length} R2 object(s).`,
    );
  }
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
  return await s3Client.fetch(
    new Request(deleteUrl, {
      method: "DELETE",
      signal: AbortSignal.timeout(R2_OBJECT_REQUEST_TIMEOUT_MS),
    }),
  );
}

const R2_LIST_RESPONSE_LIMIT_BYTES = 256 * 1024;
const R2_LIST_TIMEOUT_MS = 10_000;
const R2_OBJECT_REQUEST_TIMEOUT_MS = 10_000;

function decodeXmlText(value: string): string {
  return value
    .replaceAll("&apos;", "'")
    .replaceAll("&quot;", '"')
    .replaceAll("&gt;", ">")
    .replaceAll("&lt;", "<")
    .replaceAll("&amp;", "&");
}

export async function listR2ObjectKeys(
  prefix: string,
  startAfter: string | null,
  config: R2Config,
  maximumKeys = 50,
): Promise<R2ObjectPage> {
  if (
    !prefix ||
    prefix.startsWith("/") ||
    prefix.includes("..") ||
    !Number.isSafeInteger(maximumKeys) ||
    maximumKeys < 1 ||
    maximumKeys > 1000
  ) {
    throw new TypeError("Invalid bounded R2 list request.");
  }

  const { s3Client, bucketName, endpoint } = config;
  const listUrl = new URL(`${endpoint}/${bucketName}`);
  listUrl.searchParams.set("list-type", "2");
  listUrl.searchParams.set("encoding-type", "url");
  listUrl.searchParams.set("prefix", prefix);
  listUrl.searchParams.set("max-keys", String(maximumKeys));
  if (startAfter) listUrl.searchParams.set("start-after", startAfter);

  const response = await s3Client.fetch(
    new Request(listUrl, {
      method: "GET",
      signal: AbortSignal.timeout(R2_LIST_TIMEOUT_MS),
    }),
  );
  if (!response.ok) {
    await response.body?.cancel();
    throw new Error(`R2 list returned HTTP ${response.status}.`);
  }

  const body = await readByteStreamWithinLimit(
    response.body,
    R2_LIST_RESPONSE_LIMIT_BYTES,
    "R2 list response exceeded limit",
  );
  if (body.exceeded || !body.bytes) {
    throw new Error("R2 list returned an oversized response.");
  }
  const xml = new TextDecoder("utf-8", { fatal: true }).decode(body.bytes);
  const isTruncatedText = xml.match(
    /<IsTruncated>(true|false)<\/IsTruncated>/i,
  )?.[1]?.toLowerCase();
  if (!isTruncatedText) {
    throw new Error("R2 list response omitted IsTruncated.");
  }

  const keys = [...xml.matchAll(/<Key>([^<]*)<\/Key>/g)].map((match) => {
    const encodedKey = decodeXmlText(match[1]);
    try {
      return decodeURIComponent(encodedKey);
    } catch {
      throw new Error("R2 list returned an invalid encoded key.");
    }
  });
  if (keys.length > maximumKeys) {
    throw new Error("R2 list exceeded its requested page size.");
  }

  let previousKey = startAfter;
  for (const key of keys) {
    if (
      !key.startsWith(prefix) ||
      (previousKey !== null && key <= previousKey)
    ) {
      throw new Error("R2 list returned invalid cursor ordering.");
    }
    previousKey = key;
  }

  return {
    keys,
    isTruncated: isTruncatedText === "true",
  };
}

export async function headR2Object(
  key: string,
  config: R2Config,
): Promise<Response> {
  const { s3Client, bucketName, endpoint } = config;
  const headUrl = `${endpoint}/${bucketName}/${key}`;
  return await s3Client.fetch(
    new Request(headUrl, {
      method: "HEAD",
      signal: AbortSignal.timeout(R2_OBJECT_REQUEST_TIMEOUT_MS),
    }),
  );
}

export async function putR2Object(
  key: string,
  body: Uint8Array,
  contentType: string,
  config: R2Config,
): Promise<Response> {
  const { s3Client, bucketName, endpoint } = config;
  const putUrl = `${endpoint}/${bucketName}/${key}`;
  return await s3Client.fetch(
    new Request(putUrl, {
      method: "PUT",
      headers: { "Content-Type": contentType },
      body: body as unknown as BodyInit,
    }),
  );
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
