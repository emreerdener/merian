import {
  assertEquals,
  assertGreater,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import JSZip from "jszip";
import { calculateCrc32, combineCrc32Parts } from "./crc32.ts";
import { ExportWorkerError } from "./types.ts";
import { createStoredZipStream, StreamingZipFile } from "./zip.ts";

const encoder = new TextEncoder();

async function collect(
  stream: ReadableStream<Uint8Array>,
): Promise<Uint8Array> {
  const chunks: Uint8Array[] = [];
  let total = 0;
  for await (const chunk of stream) {
    chunks.push(chunk);
    total += chunk.byteLength;
  }
  const result = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    result.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return result;
}

function streamedFile(name: string, chunks: string[]): StreamingZipFile {
  const encodedChunks = chunks.map((chunk) => encoder.encode(chunk));
  return {
    name,
    expected: combineCrc32Parts(
      encodedChunks.map((chunk) => ({
        crc32: calculateCrc32(chunk),
        byteCount: chunk.byteLength,
      })),
    ),
    async *open() {
      yield* encodedChunks;
    },
  };
}

Deno.test("stored ZIP stream produces standards-compliant lazy entries", async () => {
  let openedEntries = 0;
  const files: StreamingZipFile[] = [
    {
      name: "occurrence.csv",
      expected: {
        crc32: calculateCrc32(encoder.encode("header\nrow\n")),
        byteCount: 11,
      },
      async *open() {
        openedEntries += 1;
        yield encoder.encode("header\n");
        yield encoder.encode("row\n");
      },
    },
    {
      name: "multimedia.csv",
      expected: {
        crc32: calculateCrc32(encoder.encode("media\n")),
        byteCount: 6,
      },
      async *open() {
        openedEntries += 1;
        yield encoder.encode("media\n");
      },
    },
    streamedFile("meta.xml", ["<archive/>"]),
  ];

  const stream = createStoredZipStream(files);
  assertEquals(openedEntries, 0);
  const bytes = await collect(stream);
  assertEquals(openedEntries, 2);
  assertGreater(bytes.byteLength, 100);

  const archive = await JSZip.loadAsync(bytes);
  assertEquals(
    await archive.file("occurrence.csv")?.async("string"),
    "header\nrow\n",
  );
  assertEquals(
    await archive.file("multimedia.csv")?.async("string"),
    "media\n",
  );
  assertEquals(await archive.file("meta.xml")?.async("string"), "<archive/>");
});

Deno.test("stored ZIP output is deterministic for identical streams", async () => {
  const files = () => [
    streamedFile("a.csv", ["one", "two"]),
    streamedFile("b.xml", ["three"]),
  ];
  assertEquals(
    await collect(createStoredZipStream(files())),
    await collect(createStoredZipStream(files())),
  );
});

Deno.test("stored ZIP stream fails closed when object bytes miss the manifest", async () => {
  const error = await assertRejects(
    () =>
      collect(createStoredZipStream([{
        name: "occurrence.csv",
        expected: {
          crc32: calculateCrc32(encoder.encode("expected")),
          byteCount: 8,
        },
        async *open() {
          yield encoder.encode("short");
        },
      }])),
    ExportWorkerError,
  );
  assertEquals(error.code, "archive_generation_failed");
});

Deno.test("stored ZIP stream rejects an impossible empty-entry CRC", async () => {
  await assertRejects(
    () =>
      collect(createStoredZipStream([{
        name: "empty.csv",
        expected: { crc32: 1, byteCount: 0 },
        async *open() {},
      }])),
    TypeError,
    "checksum zero",
  );
});
