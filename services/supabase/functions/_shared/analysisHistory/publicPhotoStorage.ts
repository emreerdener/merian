import { getS3Client, type R2Config, r2RequestWithDeadline } from "../aws.ts";
import { historyUUID } from "./contract.ts";
import { evidenceDigest } from "./evidence.ts";
import { type PublicationPhotoSource } from "./photoClassifier.ts";
import { validatePublicPhotoContainer } from "./publicPhotoContainer.ts";

const CACHE_CONTROL = "no-store, max-age=0";
export function publicationPhotoObjectKey(objectId: string): string {
  return `publication_media/v1/${historyUUID(objectId)}`;
}
export function getPublicationPhotoConfig(
  access: "read" | "write",
  env: (key: string) => string | undefined = (key) => Deno.env.get(key),
): R2Config {
  const account = env("R2_ACCOUNT_ID") ?? "";
  const bucket = env("R2_BUCKET_NAME") ?? "";
  const privateBucket = env("R2_HISTORY_BUCKET_NAME");
  const prefix = access === "read"
    ? "R2_PUBLICATION_READ"
    : "R2_PUBLICATION_WRITE";
  const key = env(`${prefix}_ACCESS_KEY_ID`),
    secret = env(`${prefix}_SECRET_ACCESS_KEY`);
  const otherPrefixes = [
    "R2",
    "R2_HISTORY_READ",
    "R2_HISTORY_WRITE",
    access === "read" ? "R2_PUBLICATION_WRITE" : "R2_PUBLICATION_READ",
  ];
  const aliasesAnotherIdentity = otherPrefixes.some((other) =>
    key === env(`${other}_ACCESS_KEY_ID`) ||
    secret === env(`${other}_SECRET_ACCESS_KEY`)
  );
  if (
    aliasesAnotherIdentity ||
    !/^[0-9a-f]{32}$/.test(account) ||
    !/^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$/.test(bucket) ||
    !privateBucket || bucket === privateBucket || !key || !secret
  ) throw new Error("publication_photo_storage_unavailable");
  return {
    s3Client: getS3Client(key, secret),
    bucketName: bucket,
    endpoint: `https://${account}.r2.cloudflarestorage.com`,
  };
}
export interface PublicationPhotoCopyTarget {
  object_id: string;
  source: PublicationPhotoSource;
}
type Transport = (request: Request, config: R2Config) => Promise<Response>;
/** Prepared storage only. SQL reservation/approval/deletion ownership is required
 * before use. No route, worker or generic scan-media helper calls this class. */
export class PublicHistoryPhotoStorage {
  constructor(
    private readonly writeConfig: () => R2Config = () =>
      getPublicationPhotoConfig("write"),
    private readonly readConfig: () => R2Config = () =>
      getPublicationPhotoConfig("read"),
    private readonly transport?: Transport,
  ) {}
  private async request(
    config: R2Config,
    id: string,
    method: string,
    headers: HeadersInit = {},
    body?: Uint8Array,
  ) {
    const url = `${config.endpoint}/${config.bucketName}/${
      publicationPhotoObjectKey(id)
    }`;
    const init: RequestInit = { method, headers, body: body?.slice() };
    try {
      return await (this.transport
        ? this.transport(r2RequestWithDeadline(url, init), config)
        : config.s3Client.fetch(r2RequestWithDeadline(url, init)));
    } catch {
      throw new Error("publication_photo_storage_unavailable");
    }
  }
  private configs(): { write: R2Config; read: R2Config } {
    const write = { ...this.writeConfig() }, read = { ...this.readConfig() };
    if (
      write.endpoint !== read.endpoint || write.bucketName !== read.bucketName
    ) {
      throw new Error("publication_photo_storage_unavailable");
    }
    return { write, read };
  }
  async writeOnce(
    target: PublicationPhotoCopyTarget,
    input: Uint8Array,
  ): Promise<void> {
    const objectId = historyUUID(target.object_id);
    const source = { ...target.source };
    historyUUID(source.media_id);
    historyUUID(source.object_id);
    if (
      objectId === source.object_id || objectId === source.media_id ||
      source.media_id === source.object_id ||
      typeof source.sha256 !== "string" ||
      !/^[0-9a-f]{64}$/.test(source.sha256) ||
      !Number.isSafeInteger(source.byte_count) ||
      source.byte_count !== input.byteLength
    ) throw new Error("invalid_publication_photo_copy");
    const bytes = input.slice();
    // Reject private metadata and unsupported containers before acquiring public
    // write credentials or issuing any destination request. Never transcode here.
    validatePublicPhotoContainer(bytes, source.content_type);
    if (await evidenceDigest(bytes) !== source.sha256) {
      throw new Error("invalid_publication_photo_copy");
    }
    const { write, read } = this.configs();
    const response = await this.request(write, objectId, "PUT", {
      "If-None-Match": "*",
      "Content-Type": source.content_type,
      "Content-Length": String(source.byte_count),
      "Cache-Control": CACHE_CONTROL,
      "x-amz-meta-sha256": source.sha256,
    }, bytes);
    await response.body?.cancel();
    if (!response.ok && response.status !== 412) {
      throw new Error("publication_photo_storage_unavailable");
    }
    const head = await this.request(read, objectId, "HEAD");
    await head.body?.cancel();
    if (
      !head.ok || head.headers.get("Content-Type") !== source.content_type ||
      head.headers.get("Content-Length") !== String(source.byte_count) ||
      head.headers.get("x-amz-meta-sha256") !== source.sha256 ||
      head.headers.get("Cache-Control") !== CACHE_CONTROL ||
      head.headers.has("x-amz-meta-erased")
    ) throw new Error("publication_photo_verification_failed");
  }
  async erase(objectId: string): Promise<void> {
    historyUUID(objectId);
    // Marker permanence is essential: DELETE would allow a delayed PUT to win.
    const { write, read } = this.configs();
    const response = await this.request(write, objectId, "PUT", {
      "Content-Type": "application/octet-stream",
      "Content-Length": "0",
      "Cache-Control": CACHE_CONTROL,
      "x-amz-meta-erased": "true",
    }, new Uint8Array());
    await response.body?.cancel();
    if (!response.ok) throw new Error("publication_photo_erasure_failed");
    const head = await this.request(read, objectId, "HEAD");
    await head.body?.cancel();
    if (
      !head.ok || head.headers.get("Content-Length") !== "0" ||
      head.headers.get("Content-Type") !== "application/octet-stream" ||
      head.headers.get("Cache-Control") !== CACHE_CONTROL ||
      head.headers.get("x-amz-meta-erased") !== "true" ||
      head.headers.has("x-amz-meta-sha256")
    ) throw new Error("publication_photo_erasure_failed");
  }
}
