/** Private transient capability contract. Never persist or log this result.
 * Validation binds metadata; it cannot grant freshness or qualify a provider. */
import schema from "./cpm-photo-upload-ticket-schema-v1.json" with {
  type: "json",
};
import { matchesInitialSchema } from "./schema.ts";
import { initialMediaUnavailable } from "./mediaBinding.ts";
import type { prepareCpmPhotoUploadSpecification } from "./cpmPhotoUploadSpecification.ts";

import {
  type CpmPhotoContentType,
  snapshotCpmWriteObservationTarget,
} from "./cpmPhotoWriteObservation.ts";

type Specification = Awaited<
  ReturnType<typeof prepareCpmPhotoUploadSpecification>
>;
export const CPM_PHOTO_UPLOAD_TICKET_MAX_BYTES = 8192;
export interface CpmPhotoUploadTicket {
  readonly version: 1;
  readonly outcome: "issued";
  readonly attempt_id: string;
  readonly scan_id: string;
  readonly assignment_digest: string;
  readonly object_id: string;
  readonly backend_generation: string;
  readonly backend_configuration_digest: string;
  readonly role: "source" | "ai" | "display";
  readonly byte_count: number;
  readonly content_type: CpmPhotoContentType;
  readonly sha256: string;
  readonly created_at_ms: number;
  readonly capability_expires_at_ms: number;
  readonly signed_expires_at_ms: number;
  readonly url: string;
  readonly method: "PUT";
  readonly headers: Readonly<{
    "If-None-Match": "*";
    "Content-Type": CpmPhotoContentType;
    "Content-Length": string;
    "Cache-Control": "private, no-store";
    "x-amz-content-sha256": string;
  }>;
  readonly provider_enforcement: "unqualified";
}

/** The issuer supplies its frozen saved specification. No request-selected
 * backend/profile or recovered attempt may use this validator to sign again. */
export function decodeCpmPhotoUploadTicket(
  value: unknown,
  spec: Specification,
): CpmPhotoUploadTicket {
  if (!matchesInitialSchema(value, schema)) throw initialMediaUnavailable();
  const v = value as CpmPhotoUploadTicket;
  if (
    new TextEncoder().encode(JSON.stringify(v)).length >
      CPM_PHOTO_UPLOAD_TICKET_MAX_BYTES
  ) {
    throw initialMediaUnavailable();
  }
  for (
    const key of [
      "attempt_id",
      "scan_id",
      "assignment_digest",
      "object_id",
      "backend_generation",
      "backend_configuration_digest",
    ] as const
  ) {
    if (v[key] !== spec.binding[key]) throw initialMediaUnavailable();
  }
  const target = snapshotCpmWriteObservationTarget(spec.target);
  if (
    target.outcome !== "live_object" || v.role !== target.role ||
    v.byte_count !== target.byte_count ||
    v.content_type !== target.content_type ||
    v.sha256 !== target.sha256 || v.created_at_ms !== spec.created_at_ms ||
    v.capability_expires_at_ms !== spec.capability_expires_at_ms ||
    v.signed_expires_at_ms !==
      Math.floor(v.capability_expires_at_ms / 1000) * 1000
  ) throw initialMediaUnavailable();
  const headers = { ...spec.headers, "x-amz-content-sha256": target.sha256 };
  for (const key of Object.keys(headers) as (keyof typeof headers)[]) {
    if (v.headers[key] !== headers[key]) throw initialMediaUnavailable();
  }
  // Check the exact direct destination and closed SigV4 vocabulary. This is
  // metadata agreement, not cryptographic/provider acceptance of the signature.
  let url: URL;
  try {
    url = new URL(v.url);
  } catch {
    throw initialMediaUnavailable();
  }
  const destination =
    `${spec.destination.direct_endpoint}/${spec.destination.private_bucket}/${spec.destination.key}`;
  const query = url.searchParams;
  const keys = [
    "X-Amz-Algorithm",
    "X-Amz-Credential",
    "X-Amz-Date",
    "X-Amz-Expires",
    "X-Amz-Signature",
    "X-Amz-SignedHeaders",
  ];
  if (
    url.href !== v.url || url.protocol !== "https:" || url.username ||
    url.password || url.hash ||
    `${url.origin}${url.pathname}` !== destination ||
    [...query.keys()].length !== keys.length ||
    keys.some((key) => query.getAll(key).length !== 1) ||
    query.get("X-Amz-Algorithm") !== "AWS4-HMAC-SHA256" ||
    query.get("X-Amz-SignedHeaders") !==
      "cache-control;content-length;content-type;host;if-none-match;x-amz-content-sha256" ||
    !/^[a-f0-9]{64}$/.test(query.get("X-Amz-Signature") ?? "")
  ) throw initialMediaUnavailable();
  const date = query.get("X-Amz-Date")!;
  const ttl = query.get("X-Amz-Expires")!;
  if (!/^\d{8}T\d{6}Z$/.test(date) || !/^[1-9][0-9]{0,2}$/.test(ttl)) {
    throw initialMediaUnavailable();
  }
  const signedAt = Date.parse(
    `${date.slice(0, 4)}-${date.slice(4, 6)}-${date.slice(6, 8)}T${
      date.slice(9, 11)
    }:${date.slice(11, 13)}:${date.slice(13, 15)}Z`,
  );
  const credential = query.get("X-Amz-Credential")!;
  if (
    !Number.isSafeInteger(signedAt) || Number(ttl) > 600 ||
    new Date(signedAt).toISOString().replace(/[:-]|\.\d{3}/g, "") !== date ||
    signedAt < Math.floor(v.created_at_ms / 1000) * 1000 ||
    signedAt + Number(ttl) * 1000 !== v.signed_expires_at_ms ||
    v.signed_expires_at_ms <= Date.now() || signedAt > Date.now() ||
    !new RegExp(
      `^[A-Za-z0-9/+_=.-]{16,256}/${date.slice(0, 8)}/auto/s3/aws4_request$`,
    ).test(credential)
  ) throw initialMediaUnavailable();
  return Object.freeze({ ...v, headers: Object.freeze({ ...v.headers }) });
}
