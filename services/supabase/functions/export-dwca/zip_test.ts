import {
  assertEquals,
  assertGreater,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import JSZip from "jszip";
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
  return {
    name,
    async *open() {
      for (const chunk of chunks) yield encoder.encode(chunk);
    },
  };
}

Deno.test("stored ZIP stream produces standards-compliant lazy entries", async () => {
  let openedEntries = 0;
  const files: StreamingZipFile[] = [
    {
      name: "occurrence.csv",
      async *open() {
        openedEntries += 1;
        yield encoder.encode("header\n");
        yield encoder.encode("row\n");
      },
    },
    {
      name: "multimedia.csv",
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
