import { getS3Client, type R2Config, r2RequestWithDeadline } from "../aws.ts";
import { readResponseArrayBufferWithinBudget } from "../mediaBudgets.ts";
import {
  evidenceDigest,
  evidenceObjectKey,
  type EvidenceReceipt,
  type EvidenceStorage,
} from "./evidence.ts";

// A namespace in the public scan bucket is not private storage. The new bucket
// must additionally pass the deployment audit for public endpoints and policies.
export function getHistoryEvidenceConfig(
  access: "read" | "write",
  env: (name: string) => string | undefined = (name) => Deno.env.get(name),
): R2Config {
  const account = env("R2_ACCOUNT_ID") ?? "";
  const bucket = env("R2_HISTORY_BUCKET_NAME") ?? "";
  const publicBucket = env("R2_BUCKET_NAME") ?? "";
  const prefix = access === "read" ? "R2_HISTORY_READ" : "R2_HISTORY_WRITE";
  const key = env(`${prefix}_ACCESS_KEY_ID`);
  const secret = env(`${prefix}_SECRET_ACCESS_KEY`);
  if (
    !/^[0-9a-f]{32}$/.test(account) ||
    !/^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$/.test(bucket) || !publicBucket ||
    bucket === publicBucket || !key || !secret
  ) {
    throw new Error("history_evidence_storage_unavailable");
  }
  return {
    s3Client: getS3Client(key, secret),
    bucketName: bucket,
    endpoint: `https://${account}.r2.cloudflarestorage.com`,
  };
}

type Transport = (request: Request, config: R2Config) => Promise<Response>;
export class PrivateHistoryEvidenceStorage implements EvidenceStorage {
  constructor(
    private readonly writeConfig: () => R2Config = () =>
      getHistoryEvidenceConfig("write"),
    private readonly readConfig: () => R2Config = () =>
      getHistoryEvidenceConfig("read"),
    private readonly transport?: Transport,
  ) {}
  private async request(
    config: R2Config,
    objectId: string,
    method: string,
    headers: HeadersInit = {},
    body?: Uint8Array,
    signal?: AbortSignal,
  ): Promise<Response> {
    const url = `${config.endpoint}/${config.bucketName}/${
      evidenceObjectKey(objectId)
    }`;
    signal?.throwIfAborted();
    const init: RequestInit = { method, headers, body: body?.slice(), signal };
    if (this.transport) {
      return await this.transport(r2RequestWithDeadline(url, init), config);
    }
    return await config.s3Client.fetch(r2RequestWithDeadline(url, init));
  }

  async writeOnce(
    receipt: EvidenceReceipt,
    bytes: Uint8Array,
    signal?: AbortSignal,
  ): Promise<void> {
    signal?.throwIfAborted();
    // Defence in depth: only bytes matching the admitted immutable tuple enter R2.
    const body = bytes.slice();
    if (
      body.byteLength !== receipt.byte_count ||
      await evidenceDigest(body) !== receipt.sha256
    ) throw new Error("invalid_history_evidence");
    const config = this.writeConfig();
    const response = await this.request(
      config,
      receipt.object_id,
      "PUT",
      {
        "If-None-Match": "*",
        "Content-Type": receipt.content_type,
        "Content-Length": String(receipt.byte_count),
        "Cache-Control": "private, no-store",
        "x-amz-meta-sha256": receipt.sha256,
      },
      body,
      signal,
    );
    await response.body?.cancel();
    if (!response.ok && response.status !== 412) {
      throw new Error("history_evidence_storage_unavailable");
    }
    // A lost PUT response can be retried; an existing marker or different object
    // cannot pass this tuple. Only this trusted writer can set hash metadata.
    const head = await this.request(
      config,
      receipt.object_id,
      "HEAD",
      {},
      undefined,
      signal,
    );
    await head.body?.cancel();
    if (
      !head.ok ||
      head.headers.get("Content-Length") !== String(receipt.byte_count) ||
      head.headers.get("Content-Type") !== receipt.content_type ||
      head.headers.get("x-amz-meta-sha256") !== receipt.sha256 ||
      head.headers.has("x-amz-meta-erased")
    ) {
      throw new Error("history_evidence_verification_failed");
    }
  }
  /** Trusted worker read. No storage URL is passed to an inference provider. */
  async readVerified(
    receipt: Pick<
      EvidenceReceipt,
      "object_id" | "content_type" | "byte_count" | "sha256"
    >,
    signal?: AbortSignal,
  ): Promise<Uint8Array> {
    const response = await this.request(
      this.readConfig(),
      receipt.object_id,
      "GET",
      {},
      undefined,
      signal,
    );
    if (
      !response.ok ||
      response.headers.get("Content-Type") !== receipt.content_type ||
      response.headers.get("Content-Length") !== String(receipt.byte_count) ||
      response.headers.has("x-amz-meta-erased") ||
      response.headers.get("x-amz-meta-sha256") !== receipt.sha256
    ) {
      await response.body?.cancel();
      throw new Error("history_evidence_verification_failed");
    }
    const read = await readResponseArrayBufferWithinBudget(
      response,
      receipt.byte_count,
      "history_evidence_verification_failed",
    );
    if (!read.buffer || read.error) {
      throw new Error("history_evidence_verification_failed");
    }
    const bytes = new Uint8Array(read.buffer);
    signal?.throwIfAborted();
    if (
      bytes.byteLength !== receipt.byte_count ||
      await evidenceDigest(bytes) !== receipt.sha256
    ) {
      throw new Error("history_evidence_verification_failed");
    }
    signal?.throwIfAborted();
    return bytes;
  }
  async signedRead(receipt: EvidenceReceipt): Promise<string> {
    const config = this.readConfig();
    const url = new URL(
      `${config.endpoint}/${config.bucketName}/${
        evidenceObjectKey(receipt.object_id)
      }`,
    );
    url.searchParams.set("X-Amz-Expires", "30");
    url.searchParams.set("response-cache-control", "private, no-store");
    url.searchParams.set("response-content-type", receipt.content_type);
    const signed = await config.s3Client.sign(
      new Request(url, { method: "GET" }),
      { aws: { signQuery: true } },
    );
    return signed.url;
  }
  async erase(objectId: string): Promise<void> {
    // Never DELETE this key. An unconditional empty PUT atomically replaces any
    // content and blocks every delayed conditional upload, in either ordering.
    const response = await this.request(this.writeConfig(), objectId, "PUT", {
      "Content-Type": "application/octet-stream",
      "Content-Length": "0",
      "Cache-Control": "private, no-store",
      "x-amz-meta-erased": "true",
    }, new Uint8Array());
    await response.body?.cancel();
    if (!response.ok) throw new Error("history_evidence_erasure_failed");
    const head = await this.request(this.writeConfig(), objectId, "HEAD");
    await head.body?.cancel();
    if (
      !head.ok || head.headers.get("Content-Length") !== "0" ||
      head.headers.get("x-amz-meta-erased") !== "true" ||
      head.headers.has("x-amz-meta-sha256")
    ) {
      throw new Error("history_evidence_erasure_failed");
    }
  }
}
