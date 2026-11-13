import { assertEquals, assertRejects } from "@std/assert";
import {
  INITIAL_CONFIGURATION_ARTIFACT_BYTES,
  inspectInitialConfigurationArtifact,
  inspectInitialConfigurationArtifactStream,
} from "./initial_configuration_artifact.ts";

const utf8 = (value: string) => new TextEncoder().encode(value);
const u32 = (value: number) => {
  const result = new Uint8Array(4);
  new DataView(result.buffer).setUint32(0, value);
  return result;
};
const concat = (...values: Uint8Array[]) => {
  const result = new Uint8Array(
    values.reduce((n, value) => n + value.length, 0),
  );
  let offset = 0;
  for (const value of values) {
    result.set(value, offset);
    offset += value.length;
  }
  return result;
};
const text = (value: string) => concat(u32(utf8(value).length), utf8(value));
const section = (value: Uint8Array) => concat(u32(value.length), value);
const module = (
  name: string,
  offset: number,
  size: number,
  mapOffset = 0,
  mapSize = 0,
  kind = 0,
) =>
  concat(
    text(name),
    new Uint8Array([0]),
    u32(offset),
    u32(size),
    u32(mapOffset),
    u32(mapSize),
    new Uint8Array([kind]),
  );
const redirect = (name: string, target: string) =>
  concat(text(name), new Uint8Array([1]), text(target));
const npmRoot = (name: string, index: number) =>
  concat(text(name), new Uint8Array([2]), u32(index));
const bundle = (
  header: Uint8Array,
  source = utf8("abc"),
  maps = new Uint8Array(),
  npm = new Uint8Array(),
) =>
  concat(
    utf8("ESZIP2.3"),
    section(new Uint8Array([0, 0, 1, 0])),
    section(header),
    section(npm),
    section(source),
    section(maps),
  );
const reject = (bytes: Uint8Array) =>
  assertRejects(
    () => inspectInitialConfigurationArtifact(bytes),
    Error,
    "initial_configuration_artifact_unavailable",
  );

Deno.test("initial artifact inventory hashes exact bytes, maps, opaque modules and npm references without loading them", async () => {
  const bytes = bundle(
    concat(
      module("entry.ts", 0, 3, 0, 2),
      module("vfs://0", 3, 2, 0, 0, 3),
      redirect("alias.ts", "entry.ts"),
      npmRoot("pkg@1", 0),
    ),
    utf8("abcXY"),
    utf8("{}"),
    concat(
      text("pkg@1.0.0"),
      u32(1),
      text("dep"),
      u32(1),
      text("dep@2.0.0"),
      u32(0),
    ),
  );
  const result = await inspectInitialConfigurationArtifact(bytes);
  assertEquals(result.modules[0].source, {
    bytes: 3,
    sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  });
  assertEquals(result.modules[0].source_map.bytes, 2);
  assertEquals(result.modules[1].kind, 3);
  assertEquals(result.npm_roots, [{
    specifier: "pkg@1",
    package: "pkg@1.0.0",
  }]);
  assertEquals(result.npm_packages[0].dependencies, [{
    name: "dep",
    package: "dep@2.0.0",
  }]);
  assertEquals(result.qualification, "artifact_byte_inventory_only");
  const changed = new Uint8Array(bytes);
  changed[changed.length - 1] ^= 1;
  const different = await inspectInitialConfigurationArtifact(changed);
  assertEquals(different.sha256 === result.sha256, false);
  assertEquals(
    different.modules[0].source_map.sha256 ===
      result.modules[0].source_map.sha256,
    false,
  );
});

Deno.test("initial artifact stream inventories bodies beyond the array allocation ceiling without retaining them", async () => {
  const size = 33 * 1024 * 1024;
  const prefix = concat(
    utf8("ESZIP2.3"),
    section(new Uint8Array([0, 0, 1, 0])),
    section(module("vfs://0", 0, size, 0, 0, 3)),
    section(new Uint8Array()),
    u32(size),
  );
  let phase = 0, remaining = size;
  const chunk = new Uint8Array(65536);
  const result = await inspectInitialConfigurationArtifactStream(
    new ReadableStream<Uint8Array>({
      pull(controller) {
        if (phase++ === 0) controller.enqueue(prefix);
        else if (remaining) {
          controller.enqueue(chunk);
          remaining -= chunk.length;
        } else {
          controller.enqueue(u32(0));
          controller.close();
        }
      },
    }),
  );
  assertEquals(result.modules[0].source.bytes, size);
  assertEquals(result.byte_count, prefix.length + size + 4);
});

Deno.test("initial artifact stream closes on cancellation and rejects oversized chunks", async () => {
  const abort = new AbortController();
  let cancelled = false;
  const stream = new ReadableStream<Uint8Array>({
    cancel() {
      cancelled = true;
      return new Promise(() => {});
    },
  });
  const pending = inspectInitialConfigurationArtifactStream(
    stream,
    abort.signal,
  );
  abort.abort();
  await assertRejects(
    () => pending,
    Error,
    "initial_configuration_artifact_unavailable",
  );
  assertEquals(cancelled, true);
  assertEquals(stream.locked, false);
  let closed = false;
  const oversized = new ReadableStream<Uint8Array>({
    start(c) {
      c.enqueue(new Uint8Array(1024 * 1024 + 1));
    },
    cancel() {
      closed = true;
    },
  });
  await assertRejects(() =>
    inspectInitialConfigurationArtifactStream(oversized)
  );
  assertEquals(closed, true);
  assertEquals(oversized.locked, false);
});

Deno.test("initial artifact inventory rejects every truncation, trailing bytes and unsupported format/options", async () => {
  const bytes = bundle(module("entry.ts", 0, 3));
  for (let end = 0; end < bytes.length; end++) {
    await reject(bytes.subarray(0, end));
  }
  await reject(concat(bytes, new Uint8Array([0])));
  for (const [offset, value] of [[7, 50], [11, 6], [12, 2], [13, 2], [15, 8]]) {
    const changed = new Uint8Array(bytes);
    changed[offset] = value;
    await reject(changed);
  }
  await reject(new Uint8Array(INITIAL_CONFIGURATION_ARTIFACT_BYTES + 1));
  await reject(new Uint8Array(new SharedArrayBuffer(16)));
});

Deno.test("initial artifact inventory rejects hidden, overlapping or out-of-range source and map sections", async () => {
  for (
    const header of [
      module("a", 1, 2),
      module("a", 0, 4),
      module("a", 1, 0),
      concat(module("a", 0, 3), module("b", 0, 3)),
      concat(module("a", 0, 1), module("b", 2, 1)),
      module("a", 0xffffffff, 3),
      module("a", 0, 2),
      module("a", 0, 3, 1, 0),
    ]
  ) await reject(bundle(header));
  await reject(bundle(module("a", 0, 3, 0, 1), utf8("abc"), utf8("{}")));
  await reject(
    bundle(
      concat(module("a", 0, 1, 0, 2), module("b", 1, 2, 0, 2)),
      utf8("abc"),
      utf8("{}"),
    ),
  );
});

Deno.test("initial artifact inventory rejects ambiguous names, redirects and invalid npm indices", async () => {
  for (
    const header of [
      concat(module("a", 0, 3), module("a", 0, 0)),
      module("a", 0, 3, 0, 0, 5),
      module("a\0b", 0, 3),
      concat(module("a", 0, 3), redirect("a", "a")),
      concat(module("a", 0, 3), redirect("b", "c"), redirect("c", "b")),
      concat(module("a", 0, 3), redirect("b", "missing")),
      concat(module("a", 0, 3), npmRoot("pkg@1", 0)),
      concat(module("a", 0, 3), text("bad"), new Uint8Array([255])),
    ]
  ) await reject(bundle(header));
  for (
    const npm of [
      concat(text("pkg@1"), u32(1), text("dep"), u32(1)),
      concat(text("pkg@1"), u32(0), text("pkg@1"), u32(0)),
      concat(text("pkg@1"), u32(2), text("dep"), u32(0), text("dep"), u32(0)),
    ]
  ) await reject(bundle(module("a", 0, 3), utf8("abc"), new Uint8Array(), npm));
});

Deno.test("initial artifact inventory verifies SHA256 options, headers and each nonempty body", async () => {
  const hash = async (bytes: Uint8Array<ArrayBuffer>) =>
    new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
  const checked = async (bytes: Uint8Array<ArrayBuffer>) =>
    concat(section(bytes), await hash(bytes));
  const options = new Uint8Array([0, 1, 1, 32]);
  const source = utf8("abc"), maps = utf8("{}");
  const bytes = concat(
    utf8("ESZIP2.3"),
    await checked(options),
    await checked(module("entry.ts", 0, 3, 0, 2)),
    await checked(new Uint8Array()),
    section(concat(source, await hash(source))),
    section(concat(maps, await hash(maps))),
  );
  const result = await inspectInitialConfigurationArtifact(bytes);
  assertEquals(result.checksum, "sha256");
  for (const offset of [16, 52, bytes.length - 1, bytes.length - 40]) {
    const changed = new Uint8Array(bytes);
    changed[offset] ^= 1;
    await reject(changed);
  }
});

Deno.test("initial artifact inventory snapshots input before its first asynchronous hash", async () => {
  const bytes = bundle(module("entry.ts", 0, 3));
  const expected = await inspectInitialConfigurationArtifact(bytes);
  const pending = inspectInitialConfigurationArtifact(bytes);
  bytes.fill(0);
  assertEquals(await pending, expected);
});

Deno.test("initial artifact inventory preserves Supabase npm VFS redirects only for exact declared roots", async () => {
  const header = concat(module("entry.ts", 0, 3), npmRoot("pkg@1.0.0", 0));
  const npm = concat(text("pkg@1.0.0"), u32(0));
  const result = await inspectInitialConfigurationArtifact(bundle(
    concat(header, redirect("npm:pkg@1.0.0", "npm:/pkg@1.0.0")),
    utf8("abc"),
    new Uint8Array(),
    npm,
  ));
  assertEquals(result.redirects, [{
    specifier: "npm:pkg@1.0.0",
    target: "npm:/pkg@1.0.0",
  }]);
  for (
    const target of [
      "npm:/pkg@1.0.1",
      "npm:/pkg@1.0.0/other.js",
      "https://example.invalid/pkg",
    ]
  ) {
    await reject(
      bundle(
        concat(header, redirect("alias", target)),
        utf8("abc"),
        new Uint8Array(),
        npm,
      ),
    );
  }
});
