import { fetchWithDeadline } from "../outbound.ts";
import {
  type InitialMediaBackend,
  initialMediaHash,
  type InitialMediaRole,
  initialMediaUnavailable,
  mediaUUID,
} from "./mediaBinding.ts";
import {
  cancelInitialStream,
  checkInitialDeadline,
  initialAbortable,
  readInitialStream,
} from "./transport.ts";

export interface InitialMediaStorageDependencies {
  /** Trusted server configuration maps the immutable nonsecret profile to a
   * writer/eraser signer. It must not supply a URL or invoke its own fetch. */
  sign(
    profile: string,
    purpose: "writer" | "eraser",
    request: Request,
    signal: AbortSignal,
  ): Promise<Request>;
  fetch: typeof fetch;
}
function metadataIs(headers: Headers, marker: boolean): boolean {
  const metadata = [...headers.keys()].filter((key) =>
    key.startsWith("x-amz-meta-")
  );
  return marker
    ? metadata.length === 1 && metadata[0] === "x-amz-meta-merian-state" &&
      headers.get(metadata[0]) === "erased-v1"
    : metadata.length === 0;
}
/** The key is always reconstructed from original immutable identities. */
export function initialMediaURL(
  backend: InitialMediaBackend,
  scan: string,
  object: string,
): string {
  mediaUUID(scan);
  mediaUUID(object);
  return `${backend.direct_endpoint}/${backend.private_bucket}/${backend.namespace}/${scan}/${object}`;
}
async function request(
  deps: InitialMediaStorageDependencies,
  backend: InitialMediaBackend,
  purpose: "writer" | "eraser",
  url: string,
  method: "GET" | "PUT",
  headers: Headers,
  body: Uint8Array<ArrayBuffer> | null,
  signal: AbortSignal,
): Promise<Response> {
  checkInitialDeadline(signal);
  const unsigned = new Request(url, {
    method,
    headers,
    body,
    signal,
    redirect: "error",
    cache: "no-store",
  });
  const signed = await initialAbortable(
    signal,
    () => deps.sign(backend.credential_profile, purpose, unsigned, signal),
  );
  if (
    signed.url !== url || signed.method !== method ||
    [...headers].some(([key, value]) => signed.headers.get(key) !== value)
  ) throw initialMediaUnavailable();
  return await initialAbortable(
    signal,
    () =>
      fetchWithDeadline(
        signed,
        { signal, redirect: "error", cache: "no-store" },
        { timeoutMs: 20_000, fetcher: deps.fetch },
      ),
    (response) => cancelInitialStream(response.body),
  );
}
async function readObject(
  deps: InitialMediaStorageDependencies,
  backend: InitialMediaBackend,
  purpose: "writer" | "eraser",
  url: string,
  type: string,
  size: number,
  marker: boolean,
  signal: AbortSignal,
): Promise<Uint8Array<ArrayBuffer>> {
  const response = await request(
    deps,
    backend,
    purpose,
    url,
    "GET",
    new Headers({ "Cache-Control": "no-cache, no-store", Pragma: "no-cache" }),
    null,
    signal,
  );
  if (
    response.status !== 200 || response.headers.get("content-type") !== type ||
    response.headers.get("content-length") !== String(size) ||
    response.headers.get("cache-control") !== "private, no-store" ||
    response.headers.has("content-encoding") ||
    !metadataIs(response.headers, marker)
  ) {
    cancelInitialStream(response.body);
    throw initialMediaUnavailable();
  }
  const bytes = response.body === null && size === 0
    ? new Uint8Array()
    : await readInitialStream(response.body, size, signal);
  if (bytes.length !== size) throw initialMediaUnavailable();
  return bytes;
}
/** PUT acknowledgement and GET metadata alone are never byte verification. Every
 * path, including an unknown PUT outcome, reads only this exact original key. */
export async function retainInitialMediaObject(
  deps: InitialMediaStorageDependencies,
  backend: InitialMediaBackend,
  scan: string,
  role: InitialMediaRole,
  bytes: Uint8Array<ArrayBuffer>,
  signal: AbortSignal,
): Promise<void> {
  const url = initialMediaURL(backend, scan, role.object_id);
  try {
    const response = await request(
      deps,
      backend,
      "writer",
      url,
      "PUT",
      new Headers({
        "Content-Type": role.content_type,
        "Cache-Control": "private, no-store",
        "If-None-Match": "*",
      }),
      bytes,
      signal,
    );
    cancelInitialStream(response.body);
  } catch {
    // A transport exception says nothing about storage. Recovery is one GET,
    // subject to the same aggregate deadline; never a second PUT.
    checkInitialDeadline(signal);
  }
  const saved = await readObject(
    deps,
    backend,
    "writer",
    url,
    role.content_type,
    role.byte_count,
    false,
    signal,
  );
  if (
    await initialAbortable(signal, () => initialMediaHash(saved)) !==
      role.sha256
  ) throw initialMediaUnavailable();
}
/** Retirement is permanent; even a late marker remains safe. The caller must
 * separately acknowledge only its still-current SQL erasure claim. */
export async function markInitialMediaErased(
  deps: InitialMediaStorageDependencies,
  backend: InitialMediaBackend,
  scan: string,
  object: string,
  signal: AbortSignal,
): Promise<void> {
  const url = initialMediaURL(backend, scan, object);
  try {
    const response = await request(
      deps,
      backend,
      "eraser",
      url,
      "PUT",
      new Headers({
        "Content-Type": "application/octet-stream",
        "Cache-Control": "private, no-store",
        "x-amz-meta-merian-state": "erased-v1",
      }),
      new Uint8Array(),
      signal,
    );
    cancelInitialStream(response.body);
  } catch {
    checkInitialDeadline(signal);
  }
  await readObject(
    deps,
    backend,
    "eraser",
    url,
    "application/octet-stream",
    0,
    true,
    signal,
  );
}
