/** Offline byte inventory, not installation or dispatch authority.
 * Format reference: Supabase's pinned eszip 0.80.0 serializer/parser:
 * https://github.com/supabase/eszip/blob/45d5a22e8629170a6cb7d3c25d1e676c084a126f/src/v2.rs
 * Only the v2.3 no-checksum/SHA256 encodings are understood. No evaluation,
 * imports, decompression, filesystem or network access occurs here. Opaque VFS
 * and runtime metadata are hashed, not interpreted or certified as SDK contents.
 */
import { createHash } from "node:crypto";

const unavailable = () =>
  new Error("initial_configuration_artifact_unavailable");
// Existing array-mode allocation ceiling. Stream mode retains no full artifact:
// it accepts the compiler's 64 MiB tmpfs ceiling using at most a 1 MiB chunk
// plus a 2 MiB header. This is tooling, not a media/runtime allowance.
export const INITIAL_CONFIGURATION_ARTIFACT_BYTES = 32 * 1024 * 1024;
export const INITIAL_CONFIGURATION_ARTIFACT_STREAM_BYTES = 64 * 1024 * 1024;
const CHUNK_BYTES = 1024 * 1024;
const decoder = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true });
const hash = async (bytes: Uint8Array<ArrayBuffer>) =>
  new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
const hex = (bytes: Uint8Array) =>
  Array.from(bytes, (n) => n.toString(16).padStart(2, "0")).join("");

class Cursor {
  offset = 0;
  constructor(readonly bytes: Uint8Array<ArrayBuffer>) {}
  take(size: number): Uint8Array<ArrayBuffer> {
    if (
      !Number.isSafeInteger(size) || size < 0 ||
      size > this.bytes.length - this.offset
    ) throw unavailable();
    const value = this.bytes.subarray(this.offset, this.offset + size);
    this.offset += size;
    return value;
  }
  u32() {
    const b = this.take(4);
    return new DataView(b.buffer, b.byteOffset, 4).getUint32(0);
  }
  string() {
    const size = this.u32();
    if (!size || size > 8192) throw unavailable();
    const value = decoder.decode(this.take(size));
    if (value.includes("\0")) throw unavailable();
    return value;
  }
  done() {
    return this.offset === this.bytes.length;
  }
}
type Range = { offset: number; length: number };
type Module = { specifier: string; kind: number; source: Range; map: Range };

class StreamCursor {
  private pending: Uint8Array<ArrayBuffer> = new Uint8Array();
  private offset = 0;
  count = 0;
  readonly digest = createHash("sha256");
  constructor(readonly reader: ReadableStreamDefaultReader<Uint8Array>) {}
  private async fill() {
    if (this.offset < this.pending.length) return true;
    const result = await this.reader.read();
    if (result.done) return false;
    if (
      !(result.value instanceof Uint8Array) ||
      !(result.value.buffer instanceof ArrayBuffer) ||
      !result.value.length || result.value.length > CHUNK_BYTES ||
      this.count + result.value.length >
        INITIAL_CONFIGURATION_ARTIFACT_STREAM_BYTES
    ) throw unavailable();
    this.pending = new Uint8Array(result.value);
    this.offset = 0;
    this.count += this.pending.length;
    this.digest.update(this.pending);
    return true;
  }
  async consume(size: number, sink: (chunk: Uint8Array<ArrayBuffer>) => void) {
    if (
      !Number.isSafeInteger(size) || size < 0 ||
      size > INITIAL_CONFIGURATION_ARTIFACT_STREAM_BYTES
    ) throw unavailable();
    while (size) {
      if (!await this.fill()) throw unavailable();
      const length = Math.min(size, this.pending.length - this.offset);
      sink(this.pending.subarray(this.offset, this.offset + length));
      this.offset += length;
      size -= length;
    }
  }
  async take(size: number) {
    if (size > 2 * 1024 * 1024) throw unavailable();
    const result = new Uint8Array(size);
    let offset = 0;
    await this.consume(size, (chunk) => {
      result.set(chunk, offset);
      offset += chunk.length;
    });
    return result;
  }
  async u32() {
    return new DataView((await this.take(4)).buffer).getUint32(0);
  }
  async done() {
    return !await this.fill();
  }
}

/** Array convenience API snapshots before the first await. Neither API executes
 * archive content. The stream API owns and closes its reader on every exit. */
export function inspectInitialConfigurationArtifact(input: Uint8Array) {
  if (
    !(input instanceof Uint8Array) || !(input.buffer instanceof ArrayBuffer) ||
    input.length > INITIAL_CONFIGURATION_ARTIFACT_BYTES
  ) return Promise.reject(unavailable());
  const bytes = new Uint8Array(input);
  let offset = 0;
  return inspectInitialConfigurationArtifactStream(
    new ReadableStream<Uint8Array>({
      pull(controller) {
        if (offset === bytes.length) {
          controller.close();
          return;
        }
        const end = Math.min(bytes.length, offset + 65536);
        controller.enqueue(bytes.subarray(offset, end));
        offset = end;
      },
    }),
  );
}

/** Bounded offline inventory. A caller retains the encoded upload artifact
 * separately; this parser does not grant installation or dispatch authority.
 * Cancellation is mandatory for streams that may stall; local finite files do
 * not need a synthetic deadline. No decompression takes place in this owner.
 */
export async function inspectInitialConfigurationArtifactStream(
  stream: ReadableStream<Uint8Array>,
  signal?: AbortSignal,
) {
  const reader = stream.getReader();
  const cancelled = () => {
    void reader.cancel().catch(() => {});
  };
  signal?.addEventListener("abort", cancelled, { once: true });
  try {
    if (signal?.aborted) throw unavailable();
    const cursor = new StreamCursor(reader);
    if (
      decoder.decode(await cursor.take(8)) !== "ESZIP2.3" ||
      await cursor.u32() !== 4
    ) throw unavailable();
    const options = await cursor.take(4);
    if (
      options[0] !== 0 || options[2] !== 1 ||
      !((options[1] === 0 && options[3] === 0) ||
        (options[1] === 1 && options[3] === 32))
    ) throw unavailable();
    const checksumSize = options[3];
    const checksum = async (
      value: Uint8Array<ArrayBuffer>,
      expected: Uint8Array,
    ) => {
      if (checksumSize && hex(await hash(value)) !== hex(expected)) {
        throw unavailable();
      }
    };
    await checksum(options, await cursor.take(checksumSize));
    const section = async (maximum: number, checked: boolean) => {
      const size = await cursor.u32();
      if (size > maximum) throw unavailable();
      const value = await cursor.take(size);
      if (checked) await checksum(value, await cursor.take(checksumSize));
      return value;
    };
    const header = new Cursor(await section(2 * 1024 * 1024, true));
    const modules: Module[] = [];
    const redirects = new Map<string, string>();
    const npmRoots = new Map<string, number>();
    const names = new Set<string>();
    while (!header.done()) {
      if (names.size >= 8192) throw unavailable();
      const specifier = header.string();
      if (names.has(specifier)) throw unavailable();
      names.add(specifier);
      const frame = header.take(1)[0];
      if (frame === 0) {
        const source = { offset: header.u32(), length: header.u32() };
        const map = { offset: header.u32(), length: header.u32() };
        const kind = header.take(1)[0];
        if (kind > 4) throw unavailable();
        modules.push({ specifier, kind, source, map });
      } else if (frame === 1) redirects.set(specifier, header.string());
      else if (frame === 2) npmRoots.set(specifier, header.u32());
      else throw unavailable();
    }
    const npm = new Cursor(await section(2 * 1024 * 1024, true));
    const packages: {
      id: string;
      dependencies: { name: string; index: number }[];
    }[] = [];
    const packageNames = new Set<string>();
    while (!npm.done()) {
      if (packages.length >= 512) throw unavailable();
      const id = npm.string();
      if (packageNames.has(id)) throw unavailable();
      packageNames.add(id);
      const count = npm.u32();
      if (count > 512) throw unavailable();
      const dependencies: { name: string; index: number }[] = [];
      const seen = new Set<string>();
      for (let i = 0; i < count; i++) {
        const name = npm.string();
        if (seen.has(name)) throw unavailable();
        seen.add(name);
        dependencies.push({ name, index: npm.u32() });
      }
      packages.push({ id, dependencies });
    }
    for (
      const index of [
        ...npmRoots.values(),
        ...packages.flatMap((p) => p.dependencies.map((d) => d.index)),
      ]
    ) {
      if (index >= packages.length) throw unavailable();
    }
    // Each nonempty body must occupy its exact consecutive serialized range.
    // Hash each body incrementally; neither the 40+ MiB source section nor the
    // whole artifact is materialized in stream mode.
    const inventory = async (field: "source" | "map") => {
      const bodySize = await cursor.u32();
      if (bodySize > INITIAL_CONFIGURATION_ARTIFACT_STREAM_BYTES) {
        throw unavailable();
      }
      let end = 0;
      const result = new Map<string, { bytes: number; sha256: string }>();
      for (
        const module of [...modules].sort((a, b) =>
          a[field].offset - b[field].offset
        )
      ) {
        const range = module[field];
        if (range.length === 0) {
          if (range.offset !== 0) throw unavailable();
        } else {
          if (
            range.offset !== end || range.length + checksumSize > bodySize - end
          ) throw unavailable();
          end += range.length + checksumSize;
        }
        const digest = createHash("sha256");
        await cursor.consume(range.length, (chunk) => {
          digest.update(chunk);
        });
        const sha256 = digest.digest("hex");
        if (
          range.length && checksumSize &&
          sha256 !== hex(await cursor.take(checksumSize))
        ) throw unavailable();
        result.set(module.specifier, { bytes: range.length, sha256 });
      }
      if (end !== bodySize) throw unavailable();
      return result;
    };
    const sourceInventory = await inventory("source");
    const mapInventory = await inventory("map");
    if (!await cursor.done() || signal?.aborted) throw unavailable();
    const moduleNames = new Set(modules.map((m) => m.specifier));
    for (const start of redirects.keys()) {
      const seen = new Set<string>();
      let target = start;
      while (redirects.has(target)) {
        if (seen.has(target) || seen.size >= 64) throw unavailable();
        seen.add(target);
        target = redirects.get(target)!;
      }
      // Supabase resolves npm:/ roots through its separately embedded VFS.
      // Recognize only an exact declared npm root here; its dependency bytes
      // remain opaque and are not certified by successful frame parsing.
      if (
        !moduleNames.has(target) &&
        !(target.startsWith("npm:/") && npmRoots.has(target.slice(5)))
      ) {
        throw unavailable();
      }
    }
    return {
      version: 1,
      format: "ESZIP2.3" as const,
      byte_count: cursor.count,
      sha256: cursor.digest.digest("hex"),
      checksum: checksumSize ? "sha256" : "none",
      modules: modules.map((m) => ({
        specifier: m.specifier,
        kind: m.kind,
        source: sourceInventory.get(m.specifier)!,
        source_map: mapInventory.get(m.specifier)!,
      })),
      redirects: [...redirects].map(([specifier, target]) => ({
        specifier,
        target,
      })),
      npm_roots: [...npmRoots].map(([specifier, index]) => ({
        specifier,
        package: packages[index].id,
      })),
      npm_packages: packages.map((p) => ({
        id: p.id,
        dependencies: p.dependencies.map((d) => ({
          name: d.name,
          package: packages[d.index].id,
        })),
      })),
      qualification: "artifact_byte_inventory_only" as const,
    };
  } catch {
    throw unavailable();
  } finally {
    signal?.removeEventListener("abort", cancelled);
    // A hostile source may never settle its cancellation promise. Closing the
    // reader is immediate; do not let producer cleanup delay terminal denial.
    void reader.cancel().catch(() => {});
    reader.releaseLock();
  }
}
