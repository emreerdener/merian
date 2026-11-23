/** Prepared authenticated source collection. No route installs this until SQL
 * can atomically seal the complete source identity and reject downgraded replay. */
import { getR2ReadConfig } from "./aws.ts";
import { fetchWithDeadline } from "./outbound.ts";
import {
  type CaptureSourceRead,
  type CaptureSourceSnapshots,
  captureSourceSnapshots,
} from "./captureSourceEvidence.ts";
import {
  MEDIA_BUDGETS,
  STAGING_ALLOWED_CONTENT_TYPES,
  type StagingMediaKind,
} from "./mediaBudgets.ts";
import {
  cancelInitialStream,
  checkInitialDeadline,
  initialAbortable,
  initialDeadline,
  readInitialStream,
} from "./initialAnalysis/transport.ts";

export interface CaptureSourceKeys {
  readonly image: readonly string[];
  readonly audio: readonly string[];
  readonly video: readonly string[];
}
export interface CaptureSourceCollectorDependencies {
  readonly backend: { readonly endpoint: string; readonly bucketName: string };
  sign(request: Request, signal: AbortSignal): Promise<Request>;
  fetch: typeof fetch;
}

const unavailable = () => new Error("capture_source_collection_unavailable");
const kinds = ["image", "audio", "video"] as const;
const uuid =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

/** Validate the entire inventory before signing or fetching even the first key.
 * No trim, deduplication, inferred kind or caller-provided digest/MIME. */
function inventory(owner: string, value: CaptureSourceKeys) {
  if (
    typeof owner !== "string" || !uuid.test(owner) || !value ||
    typeof value !== "object" || Object.keys(value).length !== 3 ||
    kinds.some((kind) => !Object.hasOwn(value, kind))
  ) throw unavailable();
  const limits = {
    image: MEDIA_BUDGETS.maxImageCount,
    audio: MEDIA_BUDGETS.maxAudioClips,
    video: MEDIA_BUDGETS.maxStagedVideoFiles,
  };
  const seen = new Set<string>();
  const result: { sourceKey: string; kind: StagingMediaKind }[] = [];
  for (const kind of kinds) {
    const keys = value[kind];
    if (!Array.isArray(keys) || keys.length > limits[kind]) throw unavailable();
    for (const sourceKey of keys) {
      if (
        typeof sourceKey !== "string" ||
        !new RegExp(`^staging/${owner}/[A-Za-z0-9_.-]{1,255}$`).test(
          sourceKey,
        ) ||
        sourceKey.includes("..") || seen.has(sourceKey)
      ) throw unavailable();
      seen.add(sourceKey);
      result.push({ sourceKey, kind });
    }
  }
  if (result.length === 0 || result.length > MEDIA_BUDGETS.maxStagingFiles) {
    throw unavailable();
  }
  return result;
}

/** Dependencies are trusted server/test code, never request fields. The default
 * factory below obtains signing credentials only from server configuration. */
export async function collectCaptureSourceSnapshots(
  ownerId: string,
  keys: CaptureSourceKeys,
  inputDeps: CaptureSourceCollectorDependencies,
  caller: AbortSignal,
): Promise<CaptureSourceSnapshots> {
  try {
    const members = inventory(ownerId, keys);
    const deps = Object.freeze({
      backend: Object.freeze({ ...inputDeps.backend }),
      sign: inputDeps.sign.bind(inputDeps),
      fetch: inputDeps.fetch.bind(inputDeps),
    });
    const { endpoint, bucketName } = deps.backend;
    if (typeof endpoint !== "string" || typeof bucketName !== "string") {
      throw unavailable();
    }
    const origin = new URL(endpoint);
    if (
      origin.protocol !== "https:" || origin.username || origin.password ||
      endpoint !== origin.origin ||
      !/^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$/.test(bucketName)
    ) throw unavailable();
    return await initialDeadline(caller, 60_000, async (whole) => {
      const reads: CaptureSourceRead[] = [];
      let remainingImageBytes: number = MEDIA_BUDGETS.maxImageRawBytes;
      // Sequential reads cap in-flight bodies at one. No partial handle escapes.
      for (const member of members) {
        const limit = member.kind === "image"
          ? remainingImageBytes
          : member.kind === "audio"
          ? MEDIA_BUDGETS.maxAudioRawBytes
          : MEDIA_BUDGETS.maxVideoRawBytes;
        if (limit < 1) throw unavailable();
        const read = await initialDeadline(whole, 10_000, async (signal) => {
          const url = `${endpoint}/${bucketName}/${member.sourceKey}`;
          const headers = new Headers({
            "Cache-Control": "no-cache, no-store",
            Pragma: "no-cache",
          });
          const unsigned = new Request(url, {
            method: "GET",
            headers,
            signal,
            redirect: "error",
          });
          const signed = await initialAbortable(
            signal,
            () => deps.sign(unsigned, signal),
            (late) => cancelInitialStream(late.body),
          );
          let response: Response;
          try {
            if (
              signed.url !== url || signed.method !== "GET" || signed.body ||
              !signed.headers.get("authorization") ||
              [...headers].some(([key, value]) =>
                signed.headers.get(key) !== value
              ) ||
              [...signed.headers.keys()].some((key) =>
                !headers.has(key) && ![
                  "authorization",
                  "host",
                  "x-amz-date",
                  "x-amz-content-sha256",
                  "x-amz-security-token",
                ].includes(key)
              ) ||
              (signed.headers.has("host") &&
                signed.headers.get("host") !== origin.host)
            ) throw unavailable();
            // Reconstruct the request: signer cannot widen method, URL, headers,
            // redirect policy, credentials, body or lifetime. No SDK retries.
            const outgoing = new Request(url, {
              method: "GET",
              headers: signed.headers,
              signal,
              redirect: "error",
              cache: "no-store",
              credentials: "omit",
            });
            response = await initialAbortable(
              signal,
              () =>
                fetchWithDeadline(outgoing, {
                  signal,
                  redirect: "error",
                  cache: "no-store",
                  credentials: "omit",
                }, { fetcher: deps.fetch, timeoutMs: 10_000 }),
              (late) => cancelInitialStream(late.body),
            );
          } finally {
            cancelInitialStream(signed.body);
          }
          const contentType = response.headers.get("content-type") ?? "";
          const rawLength = response.headers.get("content-length");
          const length = rawLength === null ? null : Number(rawLength);
          if (
            response.status !== 200 || response.redirected ||
            (response.url !== "" && response.url !== url) ||
            response.headers.has("content-encoding") ||
            response.headers.has("content-range") ||
            !STAGING_ALLOWED_CONTENT_TYPES[member.kind].includes(contentType) ||
            (rawLength !== null && (
              !/^[1-9][0-9]*$/.test(rawLength) ||
              !Number.isSafeInteger(length) || Number(length) > limit
            ))
          ) {
            cancelInitialStream(response.body);
            throw unavailable();
          }
          const bytes = await readInitialStream(response.body, limit, signal);
          if (
            bytes.byteLength < 1 ||
            (length !== null && bytes.byteLength !== length)
          ) {
            throw unavailable();
          }
          checkInitialDeadline(signal);
          return { ...member, contentType, bytes };
        });
        if (member.kind === "image") {
          remainingImageBytes -= read.bytes.byteLength;
        }
        reads.push(read);
      }
      const snapshot = await initialAbortable(
        whole,
        () => captureSourceSnapshots(ownerId, deps.backend, reads),
      );
      checkInitialDeadline(whole);
      return snapshot;
    });
  } catch {
    // Do not expose storage URLs, keys, credentials or dependency diagnostics.
    throw unavailable();
  }
}

/** Prepared environment-owned composition; callers still supply only their
 * authenticated owner, exact staged key inventory and cancellation signal. */
export function createCaptureSourceCollector() {
  const config = getR2ReadConfig();
  const sign = config.s3Client.sign.bind(config.s3Client);
  const deps: CaptureSourceCollectorDependencies = {
    backend: { endpoint: config.endpoint, bucketName: config.bucketName },
    sign: (request) => sign(request),
    fetch,
  };
  return (ownerId: string, keys: CaptureSourceKeys, signal: AbortSignal) =>
    collectCaptureSourceSnapshots(ownerId, keys, deps, signal);
}
