import { getS3Client, type R2Config, r2RequestWithDeadline } from "../aws.ts";
import { readResponseArrayBufferWithinBudget } from "../mediaBudgets.ts";
import { createHash } from "node:crypto";
import { publicationAbortable } from "./publicationDeadline.ts";
import {
  evidenceDigest,
  evidenceObjectKey,
  type EvidenceReceipt,
  type EvidenceStorage,
} from "./evidence.ts";

// No legacy aliases: even an empty old setting makes installation ambiguous.
export function hasLegacyHistoryStorageConfiguration(
  env: (name: string) => string | undefined,
): boolean {
  return [
    "R2_HISTORY_BUCKET_NAME",
    "R2_HISTORY_READ_ACCESS_KEY_ID",
    "R2_HISTORY_READ_SECRET_ACCESS_KEY",
    "R2_HISTORY_WRITE_ACCESS_KEY_ID",
    "R2_HISTORY_WRITE_SECRET_ACCESS_KEY",
  ].some((name) => env(name) !== undefined);
}

// A namespace in the public scan bucket is not private storage. The new bucket
// must additionally pass the deployment audit for public endpoints and policies.
export function getHistoryEvidenceConfig(
  access: "read" | "write",
  env: (name: string) => string | undefined = (name) => Deno.env.get(name),
): R2Config {
  const account = env("R2_ACCOUNT_ID") ?? "";
  const bucket = env("R2_SCANS_PRIVATE_BUCKET_NAME") ?? "";
  const publicBucket = env("R2_BUCKET_NAME") ?? "";
  const prefix = access === "read"
    ? "R2_SCANS_PRIVATE_READ"
    : "R2_SCANS_PRIVATE_WRITE";
  const key = env(`${prefix}_ACCESS_KEY_ID`);
  const secret = env(`${prefix}_SECRET_ACCESS_KEY`);
  if (
    hasLegacyHistoryStorageConfiguration(env) ||
    !/^[0-9a-f]{32}$/.test(account) ||
    !/^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$/.test(bucket) || !publicBucket ||
    bucket === publicBucket || !key || !secret
  ) {
    throw new Error("history_evidence_storage_unavailable");
  }
  const s3Client = getS3Client(key, secret);
  // Durable owners reconcile/retry the original operation. SDK backoff is not
  // abortable and must not outlive this private storage request's deadline.
  s3Client.retries = 0;
  return {
    s3Client,
    bucketName: bucket,
    endpoint: `https://${account}.r2.cloudflarestorage.com`,
  };
}

type Transport = (request: Request, config: R2Config) => Promise<Response>;
// Closed namespaces prevent a stage erasure marker from touching retained
// History evidence, even if two durable owners happen to allocate the same UUID.
// Storage primitives are not authorization; each owner must check its exact
// reservation and current lifecycle before calling them.
class PrivateEvidenceObjectStorage implements EvidenceStorage {
  constructor(
    private readonly writeConfig: () => R2Config = () =>
      getHistoryEvidenceConfig("write"),
    private readonly readConfig: () => R2Config = () =>
      getHistoryEvidenceConfig("read"),
    private readonly transport: Transport | undefined,
    private readonly purpose: "history" | "capture_stage",
  ) {}
  private objectKey(objectId: string): string {
    const historyKey = evidenceObjectKey(objectId);
    return this.purpose === "history"
      ? historyKey
      : `capture-stage/v1/${objectId}`;
  }
  private async request(
    config: R2Config,
    objectId: string,
    method: string,
    headers: HeadersInit = {},
    body?: Uint8Array,
    signal?: AbortSignal,
  ): Promise<Response> {
    const url = `${config.endpoint}/${config.bucketName}/${
      this.objectKey(objectId)
    }`;
    signal?.throwIfAborted();
    const init: RequestInit = { method, headers, body: body?.slice(), signal };
    const request = r2RequestWithDeadline(url, init);
    if (this.transport) {
      return await this.transport(request, config);
    }
    // aws4fetch does not copy Request.signal while signing. Supply it in init
    // so both the request deadline and caller cancellation reach native fetch.
    return await config.s3Client.fetch(request, { signal: request.signal });
  }

  async writeOnce(
    receipt: Pick<
      EvidenceReceipt,
      "object_id" | "content_type" | "byte_count" | "sha256"
    >,
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
  async verifyStored(
    value: Pick<
      EvidenceReceipt,
      "object_id" | "content_type" | "byte_count" | "sha256"
    >,
    signal: AbortSignal,
  ): Promise<void> {
    const receipt = { ...value };
    signal.throwIfAborted();
    if (
      !Number.isSafeInteger(receipt.byte_count) || receipt.byte_count < 1 ||
      receipt.byte_count > 33_554_432
    ) throw new Error("invalid_history_evidence");
    const response = await this.request(
      this.readConfig(),
      receipt.object_id,
      "GET",
      { "Cache-Control": "no-cache, no-store", Pragma: "no-cache" },
      undefined,
      signal,
    );
    if (
      response.status !== 200 ||
      response.headers.get("Content-Type") !== receipt.content_type ||
      response.headers.get("Content-Length") !== String(receipt.byte_count) ||
      response.headers.get("x-amz-meta-sha256") !== receipt.sha256 ||
      response.headers.has("x-amz-meta-erased") ||
      response.headers.has("Content-Encoding") ||
      response.headers.has("Content-Range") ||
      !response.body
    ) {
      void response.body?.cancel().catch(() => {});
      throw new Error("history_evidence_verification_failed");
    }
    // Verification consumes each chunk synchronously; no complete readback
    // buffer is retained alongside the upload. Transport/runtime memory still
    // needs qualification separately from this application buffer bound.
    const reader = response.body.getReader(), hash = createHash("sha256");
    let count = 0, chunks = 0, empty = 0, complete = false;
    try {
      for (;;) {
        const next = await publicationAbortable(signal, () => reader.read());
        if (next.done) break;
        if (
          !(next.value instanceof Uint8Array) ||
          !(next.value.buffer instanceof ArrayBuffer) || ++chunks > 4096 ||
          next.value.byteLength > receipt.byte_count - count
        ) {
          throw new Error("history_evidence_verification_failed");
        }
        if (next.value.byteLength === 0) {
          if (++empty > 32) {
            throw new Error("history_evidence_verification_failed");
          }
          continue;
        }
        empty = 0;
        hash.update(next.value);
        count += next.value.byteLength;
        signal.throwIfAborted();
      }
      signal.throwIfAborted();
      if (
        count !== receipt.byte_count || hash.digest("hex") !== receipt.sha256
      ) {
        throw new Error("history_evidence_verification_failed");
      }
      complete = true;
    } finally {
      hash.destroy();
      if (!complete) void reader.cancel().catch(() => {});
      reader.releaseLock();
    }
  }

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
  /** Opens only an exact bound object. The owning consumer MUST bound and hash
   * the actual stream; matching headers alone never establish readiness. */
  async openBoundStream(
    value: Pick<
      EvidenceReceipt,
      "object_id" | "content_type" | "byte_count" | "sha256"
    >,
    signal: AbortSignal,
  ): Promise<ReadableStream<Uint8Array>> {
    const receipt = { ...value };
    signal.throwIfAborted();
    if (
      !Number.isSafeInteger(receipt.byte_count) || receipt.byte_count < 1 ||
      receipt.byte_count > 33_554_432 || !/^[0-9a-f]{64}$/.test(receipt.sha256)
    ) {
      throw new Error("invalid_history_evidence");
    }
    const response = await this.request(
      this.readConfig(),
      receipt.object_id,
      "GET",
      { "Cache-Control": "no-cache, no-store", Pragma: "no-cache" },
      undefined,
      signal,
    );
    if (
      signal.aborted || response.status !== 200 ||
      response.headers.get("Content-Type") !== receipt.content_type ||
      response.headers.get("Content-Length") !== String(receipt.byte_count) ||
      response.headers.get("x-amz-meta-sha256") !== receipt.sha256 ||
      response.headers.has("x-amz-meta-erased") ||
      response.headers.has("Content-Encoding") ||
      response.headers.has("Content-Range") || !response.body
    ) {
      void response.body?.cancel().catch(() => {});
      throw new Error("history_evidence_verification_failed");
    }
    return response.body;
  }

  async signedRead(
    receipt: Pick<EvidenceReceipt, "object_id" | "content_type">,
  ): Promise<string> {
    if (this.purpose !== "history") {
      throw new Error("capture_stage_signed_read_forbidden");
    }
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
  async erase(objectId: string, signal?: AbortSignal): Promise<void> {
    signal?.throwIfAborted();
    const config = this.writeConfig();
    // Never DELETE this key. An unconditional empty PUT atomically replaces any
    // content and blocks every delayed conditional upload, in either ordering.
    const response = await this.request(
      config,
      objectId,
      "PUT",
      {
        "Content-Type": "application/octet-stream",
        "Content-Length": "0",
        "Cache-Control": "private, no-store",
        "x-amz-meta-erased": "true",
      },
      new Uint8Array(),
      signal,
    );
    await response.body?.cancel();
    if (!response.ok) throw new Error("history_evidence_erasure_failed");
    signal?.throwIfAborted();
    const head = await this.request(
      config,
      objectId,
      "HEAD",
      {},
      undefined,
      signal,
    );
    await head.body?.cancel();
    signal?.throwIfAborted();
    if (
      !head.ok || head.headers.get("Content-Length") !== "0" ||
      head.headers.get("x-amz-meta-erased") !== "true" ||
      head.headers.has("x-amz-meta-sha256")
    ) {
      throw new Error("history_evidence_erasure_failed");
    }
  }
}

/** Existing retained History namespace; constructor compatibility is preserved. */
export class PrivateHistoryEvidenceStorage
  extends PrivateEvidenceObjectStorage {
  constructor(
    writeConfig: () => R2Config = () => getHistoryEvidenceConfig("write"),
    readConfig: () => R2Config = () => getHistoryEvidenceConfig("read"),
    transport?: Transport,
  ) {
    super(writeConfig, readConfig, transport, "history");
  }
}

/** Server-only staging namespace in the same audited private bucket. No signed
 * read or public/client upload is provided. A separate durable stage owner must
 * reserve, authorize, adopt/retire and reconcile these objects. */
export class PrivateCaptureStageObjectStorage
  extends PrivateEvidenceObjectStorage {
  constructor(
    writeConfig: () => R2Config = () => getHistoryEvidenceConfig("write"),
    readConfig: () => R2Config = () => getHistoryEvidenceConfig("read"),
    transport?: Transport,
  ) {
    super(writeConfig, readConfig, transport, "capture_stage");
  }
}
