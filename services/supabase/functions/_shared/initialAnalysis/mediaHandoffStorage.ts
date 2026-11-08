/** Inactive private handoff storage primitives. No SQL transport, signer
 * installation, provider, environment composition or fresh authority. */
import { fetchWithDeadline } from "../outbound.ts";
import { initialCanonicalText } from "./canonical.ts";
import {
  decodeInitialMediaBackend,
  type InitialMediaBackend,
  initialMediaHash,
  type InitialMediaRole,
  initialMediaUnavailable,
  mediaDigest,
  mediaRecord,
  mediaUUID,
} from "./mediaBinding.ts";
import {
  cancelInitialStream,
  checkInitialDeadline,
  initialAbortable,
  readInitialStream,
} from "./transport.ts";

export interface HandoffSourceBackend
  extends Omit<InitialMediaBackend, "namespace"> {
  namespace: "initial-preparation/v2";
  configuration_digest: string;
  storage_protocol: "conditional_create_permanent_same_key_marker_v1";
}
type Backend = InitialMediaBackend | HandoffSourceBackend;
const sources = new WeakSet<HandoffSourceBackend>();
const destinations = new WeakSet<InitialMediaBackend>();

/** Decode the saved source row separately; never broaden the legacy M1 codec. */
export async function decodeHandoffSourceBackend(
  value: unknown,
  generation: string,
  digest: string,
): Promise<HandoffSourceBackend> {
  const raw = mediaRecord(value, [
    "generation",
    "configuration_digest",
    "provider",
    "direct_endpoint",
    "private_bucket",
    "namespace",
    "credential_profile",
    "storage_protocol",
  ]);
  const b = { ...raw };
  if (
    mediaUUID(b.generation) !== generation ||
    mediaDigest(b.configuration_digest) !== digest ||
    b.provider !== "r2" || typeof b.direct_endpoint !== "string" ||
    !/^https:\/\/[0-9a-f]{32}\.r2\.cloudflarestorage\.com$/.test(
      b.direct_endpoint,
    ) ||
    typeof b.private_bucket !== "string" ||
    !/^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$/.test(b.private_bucket) ||
    typeof b.credential_profile !== "string" ||
    !/^[a-z][a-z0-9_]{0,63}$/.test(b.credential_profile) ||
    b.namespace !== "initial-preparation/v2" ||
    b.storage_protocol !== "conditional_create_permanent_same_key_marker_v1"
  ) throw initialMediaUnavailable();
  const { configuration_digest: _, ...configuration } = b;
  const computed = await initialMediaHash(new TextEncoder().encode(
    `merian.initial-analysis.media.backend.v1\n${
      initialCanonicalText(configuration)
    }`,
  ));
  if (computed !== digest) throw initialMediaUnavailable();
  const backend = Object.freeze(b) as unknown as HandoffSourceBackend;
  sources.add(backend);
  return backend;
}

export function decodeHandoffDestinationBackend(
  value: unknown,
  generation: string,
): InitialMediaBackend {
  const backend = Object.freeze(
    decodeInitialMediaBackend({
      version: 1,
      outcome: "resolved",
      backend: value,
    }, generation),
  );
  destinations.add(backend);
  return backend;
}

export interface HandoffStorageDependencies {
  /** The adapter reloads and validates original fresh facts before EACH GET/PUT.
   * This observation is not a lease against erasure. No SQL lock spans I/O. */
  beforeIO(signal: AbortSignal): Promise<void>;
  sign(
    profile: string,
    request: Request,
    signal: AbortSignal,
  ): Promise<Request>;
  fetch: typeof fetch;
}

declare const verifiedBrand: unique symbol;
export interface HandoffVerifiedObject {
  readonly [verifiedBrand]: true;
}
const verified = new WeakMap<
  HandoffVerifiedObject,
  { scan: string; role: InitialMediaRole; bytes: Uint8Array<ArrayBuffer> }
>();

function snapshotRole(value: InitialMediaRole): InitialMediaRole {
  const r = {
    ...mediaRecord(value, [
      "object_id",
      "content_type",
      "byte_count",
      "sha256",
    ]),
  };
  mediaUUID(r.object_id);
  mediaDigest(r.sha256);
  if (
    typeof r.byte_count !== "number" || !Number.isSafeInteger(r.byte_count) ||
    r.byte_count < 1 || r.byte_count > 12_582_912 ||
    ![
      "image/jpeg",
      "image/png",
      "image/webp",
      "image/heic",
      "image/heif",
      "audio/wav",
      "video/mp4",
    ].includes(r.content_type as string)
  ) throw initialMediaUnavailable();
  return Object.freeze(r) as unknown as InitialMediaRole;
}
function urlFor(backend: Backend, scan: string, object: string): string {
  if (
    !sources.has(backend as HandoffSourceBackend) &&
    !destinations.has(backend as InitialMediaBackend)
  ) throw initialMediaUnavailable();
  mediaUUID(scan);
  mediaUUID(object);
  return `${backend.direct_endpoint}/${backend.private_bucket}/${backend.namespace}/${scan}/${object}`;
}
class HandoffPutUnknown extends Error {}

async function request(
  deps: HandoffStorageDependencies,
  backend: Backend,
  url: string,
  method: "GET" | "PUT",
  headers: Headers,
  body: Uint8Array<ArrayBuffer> | null,
  signal: AbortSignal,
): Promise<Response> {
  await initialAbortable(signal, () => deps.beforeIO(signal));
  checkInitialDeadline(signal);
  const unsigned = new Request(url, {
    method,
    headers,
    body,
    signal,
    redirect: "error",
    cache: "no-store",
  });
  let signed: Request;
  try {
    signed = await initialAbortable(
      signal,
      () => deps.sign(backend.credential_profile, unsigned, signal),
      (late) => cancelInitialStream(late.body),
    );
  } finally {
    cancelInitialStream(unsigned.body);
  }
  if (
    signed.url !== url || signed.method !== method ||
    [...headers].some(([k, v]) => signed.headers.get(k) !== v) ||
    signed.headers.has("content-encoding") ||
    [...signed.headers.keys()].some((k) => k.startsWith("x-amz-meta-"))
  ) {
    cancelInitialStream(signed.body);
    throw initialMediaUnavailable();
  }
  // The signer may decorate headers, never substitute the verified body. A new
  // Request copies our private bytes; neither request streams nor dependencies
  // receive the retained buffer itself. Discard any replacement signer stream.
  const outgoing = new Request(url, {
    method,
    headers: signed.headers,
    body,
    signal,
    redirect: "error",
    cache: "no-store",
  });
  cancelInitialStream(signed.body);
  try {
    // Signing can suspend. Revalidate fresh original facts after that await;
    // the private outgoing snapshot cannot be changed by the signer meanwhile.
    await initialAbortable(signal, () => deps.beforeIO(signal));
    checkInitialDeadline(signal);
  } catch (error) {
    cancelInitialStream(outgoing.body);
    throw error;
  }
  let started = false;
  try {
    return await initialAbortable(
      signal,
      () =>
        fetchWithDeadline(outgoing, {
          signal,
          redirect: "error",
          cache: "no-store",
        }, {
          timeoutMs: 20_000,
          fetcher: (input, init) => {
            started = true;
            return deps.fetch(input, init);
          },
        }),
      (late) => cancelInitialStream(late.body),
    );
  } catch (error) {
    if (method === "PUT" && started) throw new HandoffPutUnknown();
    throw error;
  }
}
async function readVerified(
  deps: HandoffStorageDependencies,
  backend: Backend,
  scan: string,
  role: InitialMediaRole,
  signal: AbortSignal,
): Promise<Uint8Array<ArrayBuffer>> {
  const response = await request(
    deps,
    backend,
    urlFor(backend, scan, role.object_id),
    "GET",
    new Headers({ "Cache-Control": "no-cache, no-store", Pragma: "no-cache" }),
    null,
    signal,
  );
  if (
    response.status !== 200 ||
    response.headers.get("content-type") !== role.content_type ||
    response.headers.get("content-length") !== String(role.byte_count) ||
    response.headers.get("cache-control") !== "private, no-store" ||
    response.headers.has("content-encoding") ||
    [...response.headers.keys()].some((k) => k.startsWith("x-amz-meta-"))
  ) {
    cancelInitialStream(response.body);
    throw initialMediaUnavailable();
  }
  const bytes = await readInitialStream(response.body, role.byte_count, signal);
  if (
    bytes.length !== role.byte_count ||
    await initialAbortable(signal, () => initialMediaHash(bytes)) !==
      role.sha256
  ) throw initialMediaUnavailable();
  checkInitialDeadline(signal);
  return bytes;
}
export async function readHandoffSource(
  deps: HandoffStorageDependencies,
  backend: HandoffSourceBackend,
  scan: string,
  value: InitialMediaRole,
  signal: AbortSignal,
): Promise<HandoffVerifiedObject> {
  if (!sources.has(backend)) throw initialMediaUnavailable();
  const role = snapshotRole(value);
  const bytes = await readVerified(deps, backend, scan, role, signal);
  const token = Object.freeze({}) as HandoffVerifiedObject;
  verified.set(token, { scan, role, bytes });
  return token;
}
export function discardHandoffSource(token: HandoffVerifiedObject): void {
  verified.delete(token);
}
export async function verifyHandoffDestination(
  deps: HandoffStorageDependencies,
  backend: InitialMediaBackend,
  scan: string,
  value: InitialMediaRole,
  signal: AbortSignal,
): Promise<void> {
  if (!destinations.has(backend)) throw initialMediaUnavailable();
  await readVerified(deps, backend, scan, snapshotRole(value), signal);
}
export async function retainHandoffDestination(
  deps: HandoffStorageDependencies,
  backend: InitialMediaBackend,
  scan: string,
  value: InitialMediaRole,
  token: HandoffVerifiedObject,
  signal: AbortSignal,
): Promise<void> {
  if (!destinations.has(backend)) throw initialMediaUnavailable();
  const role = snapshotRole(value), saved = verified.get(token);
  if (
    !saved || saved.scan !== scan ||
    saved.role.byte_count !== role.byte_count ||
    saved.role.content_type !== role.content_type ||
    saved.role.sha256 !== role.sha256
  ) throw initialMediaUnavailable();
  // At most one conditional PUT consumes this exact verified private snapshot.
  verified.delete(token);
  try {
    const response = await request(
      deps,
      backend,
      urlFor(backend, scan, role.object_id),
      "PUT",
      new Headers({
        "Content-Type": role.content_type,
        "Content-Length": String(role.byte_count),
        "Cache-Control": "private, no-store",
        "If-None-Match": "*",
      }),
      saved.bytes,
      signal,
    );
    cancelInitialStream(response.body);
  } catch (error) {
    if (!(error instanceof HandoffPutUnknown)) throw error;
    checkInitialDeadline(signal);
  }
  // A PUT reply is never verification. Unknown PUT permits this exact GET only.
  await readVerified(deps, backend, scan, role, signal);
}
