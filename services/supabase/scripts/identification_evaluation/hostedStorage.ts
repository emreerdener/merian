/** Only the approved public benchmark prefix; no bucket settings, lists or deletes. */
import { AwsClient } from "aws4fetch";
import { readByteStreamWithinLimit } from "../../functions/_shared/http.ts";
import { fingerprintJson } from "./evidence.ts";
import {
  BUNDLE_LIMIT,
  bundleUrl,
  claimKey,
  HOSTED_PREFIX,
  type HostedClaim,
} from "./hosted.ts";
import { requireCondition as check } from "./validation.ts";

export type Transport = (request: Request) => Promise<Response>;
export async function downloadHostedBundle(
  digest: string,
  transport: Transport = fetch,
): Promise<Uint8Array> {
  const response = await transport(
    new Request(bundleUrl(digest), {
      redirect: "error",
      signal: AbortSignal.timeout(30000),
      cache: "no-store",
    }),
  );
  if (response.status !== 200) {
    await response.body?.cancel();
    throw new Error("hosted_bundle_download_failed");
  }
  const data = await readByteStreamWithinLimit(response.body, BUNDLE_LIMIT);
  check(data.bytes && data.bytes.length > 0);
  return data.bytes;
}

export function r2Endpoint(accountId: string): string {
  check(/^[a-f0-9]{32}$/.test(accountId));
  return `https://${accountId}.r2.cloudflarestorage.com/merian/`;
}
export class HostedR2 {
  readonly endpoint: string;
  private readonly client: AwsClient;
  constructor(
    accountId: string,
    accessKeyId: string,
    secretAccessKey: string,
    private readonly transport: Transport = fetch,
  ) {
    this.endpoint = r2Endpoint(accountId);
    check(accessKeyId.length > 0 && secretAccessKey.length > 0);
    this.client = new AwsClient({
      accessKeyId,
      secretAccessKey,
      region: "auto",
      service: "s3",
      retries: 0,
    });
  }
  /** Exactly one signed request; no SDK retries, redirect following or body logging. */
  private async request(key: string, init: RequestInit) {
    return await this.transport(
      await this.client.sign(this.endpoint + key, {
        ...init,
        redirect: "error",
        signal: AbortSignal.timeout(15000),
      }),
    );
  }
  private async putOnce(key: string, value: unknown) {
    const body = JSON.stringify(value) + "\n";
    check(new TextEncoder().encode(body).length <= 2 * 1024 * 1024);
    const response = await this.request(key, {
      method: "PUT",
      headers: {
        "content-type": "application/json",
        "cache-control": "no-store",
        "if-none-match": "*",
      },
      body,
    });
    await response.body?.cancel();
    // 412 means an earlier run owns this experiment. Any other failure is also terminal.
    check(response.status === 200);
    const readback = await this.request(key, {
      method: "GET",
      cache: "no-store",
    });
    if (readback.status !== 200) {
      await readback.body?.cancel();
      throw new Error("hosted_storage_readback_failed");
    }
    const read = await readByteStreamWithinLimit(
      readback.body,
      2 * 1024 * 1024,
    );
    check(
      read.bytes &&
        new TextDecoder("utf-8", { fatal: true }).decode(read.bytes) === body,
    );
  }
  async claim(claim: HostedClaim) {
    await this.putOnce(claimKey(claim.experimentId), claim);
  }
  async publish(claim: HostedClaim, summary: unknown) {
    const response = await this.request(claimKey(claim.experimentId), {
      method: "GET",
      cache: "no-store",
    });
    if (response.status !== 200) {
      await response.body?.cancel();
      throw new Error("hosted_claim_unavailable");
    }
    const read = await readByteStreamWithinLimit(response.body, 16384);
    check(
      read.bytes &&
        await fingerprintJson(
            JSON.parse(new TextDecoder().decode(read.bytes)),
          ) === await fingerprintJson(claim),
    );
    const key =
      `${HOSTED_PREFIX}/results/${claim.experimentId}/${claim.githubRunId}-${claim.githubRunAttempt}.json`;
    await this.putOnce(key, summary);
    return key;
  }
}
