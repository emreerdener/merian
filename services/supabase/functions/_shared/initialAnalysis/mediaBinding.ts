import { hex, initialCanonicalText, initialDigest } from "./canonical.ts";
import { validateInitialInput } from "./schema.ts";
import type { InitialInput } from "./semantics.ts";
import { matchesInitialMediaContainer } from "./mediaContainer.ts";

export const INITIAL_MEDIA_BYTES = 28_625_792;
export const INITIAL_MEDIA_SUPPLIED_BYTES = 33_868_672;
export const initialMediaUnavailable = () =>
  new Error("initial_media_unavailable");
export function mediaRecord(
  value: unknown,
  keys: string[],
): Record<string, unknown> {
  if (
    !value || typeof value !== "object" || Array.isArray(value) ||
    Object.keys(value).sort().join() !== [...keys].sort().join()
  ) throw initialMediaUnavailable();
  return value as Record<string, unknown>;
}
export function mediaUUID(value: unknown): string {
  if (
    typeof value !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(
      value,
    )
  ) throw initialMediaUnavailable();
  return value;
}
export function mediaDigest(value: unknown): string {
  if (typeof value !== "string" || !/^[0-9a-f]{64}$/.test(value)) {
    throw initialMediaUnavailable();
  }
  return value;
}
export function mediaTime(value: unknown): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value <= 0) {
    throw initialMediaUnavailable();
  }
  return value;
}
export interface InitialMediaScope {
  owner_id: string;
  scan_id: string;
  submission_digest: string;
}
export interface InitialMediaRole {
  object_id: string;
  content_type: string;
  byte_count: number;
  sha256: string;
}
export interface InitialMediaBinding extends InitialMediaScope {
  version: 1;
  backend_generation: string;
  expires_at: number;
  manifest_digest: string;
  items: {
    index: number;
    input: InitialInput["media"][number];
    source: InitialMediaRole;
    prepared: InitialMediaRole | null;
  }[];
}
export interface InitialMediaBuffers {
  source: Uint8Array;
  prepared: Uint8Array | null;
}
export interface InitialMediaSnapshot {
  binding: InitialMediaBinding;
  canonicalInput: string;
  objects: { role: InitialMediaRole; bytes: Uint8Array<ArrayBuffer> }[];
}
function sameTuple(a: InitialMediaRole, b: InitialMediaRole): boolean {
  return a.content_type === b.content_type && a.byte_count === b.byte_count &&
    a.sha256 === b.sha256;
}
export async function initialMediaHash(
  bytes: Uint8Array<ArrayBuffer>,
): Promise<string> {
  return hex(new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)));
}
/** All structure/length/work bounds precede private byte copies and any await.
 * This validates byte identities, not trusted executable derivation. */
export function snapshotInitialMedia(
  bindingValue: unknown,
  input: unknown,
  scope: InitialMediaScope,
  buffers: readonly InitialMediaBuffers[],
): InitialMediaSnapshot {
  const canonicalInput = validateInitialInput(input);
  const admitted = JSON.parse(canonicalInput) as InitialInput;
  const text = initialCanonicalText(bindingValue);
  if (new TextEncoder().encode(text).length > 65_536) {
    throw initialMediaUnavailable();
  }
  const b = mediaRecord(JSON.parse(text), [
    "version",
    "owner_id",
    "scan_id",
    "submission_digest",
    "backend_generation",
    "expires_at",
    "manifest_digest",
    "items",
  ]);
  if (
    b.version !== 1 || mediaUUID(b.owner_id) !== scope.owner_id ||
    mediaUUID(b.scan_id) !== scope.scan_id ||
    mediaDigest(b.submission_digest) !== scope.submission_digest
  ) throw initialMediaUnavailable();
  mediaUUID(b.backend_generation);
  mediaTime(b.expires_at);
  mediaDigest(b.manifest_digest);
  if (
    !Array.isArray(b.items) || b.items.length > 8 ||
    b.items.length !== admitted.media.length ||
    buffers.length !== b.items.length
  ) throw initialMediaUnavailable();
  const objects: { role: InitialMediaRole; bytes: Uint8Array }[] = [];
  const seen = new Set<string>();
  let supplied = 0, distinct = 0;
  for (let i = 0; i < b.items.length; i++) {
    const item = mediaRecord(b.items[i], [
        "index",
        "input",
        "source",
        "prepared",
      ]),
      expected = admitted.media[i];
    if (
      item.index !== i ||
      initialCanonicalText(item.input) !== initialCanonicalText(expected)
    ) throw initialMediaUnavailable();
    const parseRole = (value: unknown, source: boolean): InitialMediaRole => {
      const role = mediaRecord(value, [
        "object_id",
        "content_type",
        "byte_count",
        "sha256",
      ]);
      mediaUUID(role.object_id);
      mediaDigest(role.sha256);
      if (
        role.content_type !==
          (source ? expected.source_content_type : expected.content_type) ||
        role.byte_count !==
          (source ? expected.source_byte_count : expected.byte_count) ||
        role.sha256 !== (source ? expected.source_sha256 : expected.sha256)
      ) throw initialMediaUnavailable();
      return role as unknown as InitialMediaRole;
    };
    const source = parseRole(item.source, true),
      prepared = expected.kind === "video"
        ? null
        : parseRole(item.prepared, false);
    const suppliedItem = buffers[i];
    if (
      !suppliedItem ||
      (expected.kind === "video" &&
        (item.prepared !== null || suppliedItem.prepared !== null))
    ) throw initialMediaUnavailable();
    const check = (bytes: unknown, role: InitialMediaRole): Uint8Array => {
      if (
        !(bytes instanceof Uint8Array) || bytes.byteLength !== role.byte_count
      ) throw initialMediaUnavailable();
      supplied += bytes.byteLength;
      if (supplied > INITIAL_MEDIA_SUPPLIED_BYTES) {
        throw initialMediaUnavailable();
      }
      if (!matchesInitialMediaContainer(bytes, role.content_type)) {
        throw initialMediaUnavailable();
      }
      return bytes;
    };
    const sourceBytes = check(suppliedItem.source, source);
    if (seen.has(source.object_id)) throw initialMediaUnavailable();
    seen.add(source.object_id);
    objects.push({ role: source, bytes: sourceBytes });
    distinct += source.byte_count;
    if (prepared) {
      const preparedBytes = check(suppliedItem.prepared, prepared);
      const shared = sameTuple(source, prepared);
      if (shared) {
        if (source.object_id !== prepared.object_id) {
          throw initialMediaUnavailable();
        }
        for (let j = 0; j < source.byte_count; j++) {
          if (sourceBytes[j] !== preparedBytes[j]) {
            throw initialMediaUnavailable();
          }
        }
      } else {
        if (seen.has(prepared.object_id)) throw initialMediaUnavailable();
        seen.add(prepared.object_id);
        objects.push({ role: prepared, bytes: preparedBytes });
        distinct += prepared.byte_count;
      }
    }
  }
  if (objects.length > 10 || distinct > INITIAL_MEDIA_BYTES) {
    throw initialMediaUnavailable();
  }
  return {
    binding: b as unknown as InitialMediaBinding,
    canonicalInput,
    objects: objects.map(({ role, bytes }) => ({
      role,
      bytes: new Uint8Array(
        new Uint8Array(bytes.buffer, bytes.byteOffset, role.byte_count),
      ),
    })),
  };
}
export async function verifyInitialMediaSnapshot(
  snapshot: InitialMediaSnapshot,
): Promise<void> {
  const { manifest_digest, ...manifest } = snapshot.binding;
  if (
    await initialMediaHash(
        new TextEncoder().encode(
          `merian.initial-analysis.media-allocation.v1\n${
            initialCanonicalText(manifest)
          }`,
        ),
      ) !== manifest_digest ||
    await initialDigest("input", snapshot.canonicalInput) !==
      snapshot.binding.submission_digest
  ) throw initialMediaUnavailable();
  for (const object of snapshot.objects) {
    if (
      !matchesInitialMediaContainer(object.bytes, object.role.content_type) ||
      await initialMediaHash(object.bytes) !== object.role.sha256
    ) {
      throw initialMediaUnavailable();
    }
  }
}
export interface InitialMediaBackend {
  generation: string;
  provider: "r2";
  direct_endpoint: string;
  private_bucket: string;
  namespace: "initial-analysis/v1";
  credential_profile: string;
}
export function decodeInitialMediaBackend(
  value: unknown,
  generation: string,
): InitialMediaBackend {
  const copied = JSON.parse(initialCanonicalText(value));
  const envelope = mediaRecord(copied, ["version", "outcome", "backend"]);
  if (envelope.version !== 1 || envelope.outcome !== "resolved") {
    throw initialMediaUnavailable();
  }
  const b = mediaRecord(envelope.backend, [
    "generation",
    "provider",
    "direct_endpoint",
    "private_bucket",
    "namespace",
    "credential_profile",
  ]);
  if (
    mediaUUID(b.generation) !== generation || b.provider !== "r2" ||
    typeof b.direct_endpoint !== "string" ||
    !/^https:\/\/[0-9a-f]{32}\.r2\.cloudflarestorage\.com$/.test(
      b.direct_endpoint,
    ) || typeof b.private_bucket !== "string" ||
    !/^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$/.test(b.private_bucket) ||
    b.namespace !== "initial-analysis/v1" ||
    typeof b.credential_profile !== "string" ||
    !/^[a-z][a-z0-9_]{0,63}$/.test(b.credential_profile)
  ) throw initialMediaUnavailable();
  return b as unknown as InitialMediaBackend;
}
