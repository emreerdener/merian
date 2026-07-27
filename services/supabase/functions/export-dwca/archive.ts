import {
  DWCA_META_XML,
  generateOccurrenceRow,
  iterateMultimediaRows,
  MULTIMEDIA_HEADERS,
  OCCURRENCE_HEADERS,
} from "./dwca.ts";
import { calculateCrc32, combineCrc32Parts, Crc32Digest } from "./crc32.ts";
import { MAXIMUM_WORK_CHUNK_BYTES } from "./limits.ts";
import { UserPseudonymizer } from "./pseudonym.ts";
import { fetchExportWorkChunk } from "./storage.ts";
import {
  ClaimedExportJob,
  DBScanRow,
  ExportChunkManifestEntry,
  ExportWorkerError,
} from "./types.ts";
import { createStoredZipStream, StreamingZipFile } from "./zip.ts";

const encoder = new TextEncoder();
const LINE_FEED = 0x0a;

export type ExportProgressCallback = () => void | Promise<void>;

export interface EncodedExportBatch {
  bytes: Uint8Array;
  crc32: number;
  rowCount: number;
}

class BoundedCsvEncoder {
  readonly #buffer: Uint8Array;
  #byteLength = 0;

  constructor(maximumBytes: number) {
    if (
      !Number.isSafeInteger(maximumBytes) ||
      maximumBytes < 1 ||
      maximumBytes > MAXIMUM_WORK_CHUNK_BYTES
    ) {
      throw new TypeError(
        `maximumBytes must be an integer between 1 and ${MAXIMUM_WORK_CHUNK_BYTES}.`,
      );
    }
    this.#buffer = new Uint8Array(maximumBytes);
  }

  appendLine(line: string): void {
    const writable = this.#buffer.subarray(
      this.#byteLength,
      this.#buffer.byteLength - 1,
    );
    const { read, written } = encoder.encodeInto(line, writable);
    if (
      read !== line.length ||
      this.#byteLength + written >= this.#buffer.byteLength
    ) {
      throw new ExportWorkerError(
        "export_too_large",
        "A prepared CSV batch exceeded its hard byte limit.",
      );
    }
    this.#byteLength += written;
    this.#buffer[this.#byteLength] = LINE_FEED;
    this.#byteLength += 1;
  }

  finish(): Uint8Array {
    return this.#buffer.subarray(0, this.#byteLength);
  }
}

export async function encodeExportBatch(
  job: ClaimedExportJob,
  phase: "occurrence" | "multimedia",
  scans: DBScanRow[],
  pseudonymizer: UserPseudonymizer | null,
  maximumBytes = MAXIMUM_WORK_CHUNK_BYTES,
): Promise<EncodedExportBatch> {
  const csv = new BoundedCsvEncoder(maximumBytes);
  let rowCount = 0;
  const firstBatch = phase === "occurrence"
    ? job.occurrenceAfterId === null
    : job.multimediaAfterId === null;
  if (firstBatch) {
    csv.appendLine(
      phase === "occurrence" ? OCCURRENCE_HEADERS : MULTIMEDIA_HEADERS,
    );
  }

  if (phase === "occurrence") {
    for (const scan of scans) {
      csv.appendLine(
        await generateOccurrenceRow(
          scan,
          job.exportScope,
          job.includePreciseCoordinates,
          job.userId,
          pseudonymizer,
        ),
      );
      rowCount += 1;
    }
  } else {
    for (const scan of scans) {
      for (const line of iterateMultimediaRows(scan)) {
        csv.appendLine(line);
        rowCount += 1;
      }
    }
  }

  const bytes = csv.finish();
  return {
    bytes,
    crc32: calculateCrc32(bytes),
    rowCount,
  };
}

async function* preparedFileChunks(
  chunks: ExportChunkManifestEntry[],
  onProgress: ExportProgressCallback,
): AsyncGenerator<Uint8Array> {
  for (const chunk of chunks) {
    const bytes = await fetchExportWorkChunk(
      chunk.objectKey,
      chunk.byteCount,
    );
    if (bytes.byteLength > 0) yield bytes;
    await onProgress();
  }
}

function preparedEntryDigest(
  chunks: ExportChunkManifestEntry[],
): Crc32Digest {
  return combineCrc32Parts(
    chunks.map((chunk) => ({
      crc32: chunk.crc32,
      byteCount: chunk.byteCount,
    })),
  );
}

async function* fixedFileChunks(
  bytes: Uint8Array,
): AsyncGenerator<Uint8Array> {
  yield bytes;
}

export function createPreparedDwcaArchiveStream(
  manifest: ExportChunkManifestEntry[],
  onProgress: ExportProgressCallback = () => {},
): ReadableStream<Uint8Array> {
  const occurrence = manifest.filter((chunk) => chunk.phase === "occurrence");
  const multimedia = manifest.filter((chunk) => chunk.phase === "multimedia");
  const occurrenceDigest = preparedEntryDigest(occurrence);
  const multimediaDigest = preparedEntryDigest(multimedia);
  const metaXmlBytes = encoder.encode(`${DWCA_META_XML}\n`);
  const files: StreamingZipFile[] = [
    {
      name: "occurrence.csv",
      expected: occurrenceDigest,
      open: () => preparedFileChunks(occurrence, onProgress),
    },
    {
      name: "multimedia.csv",
      expected: multimediaDigest,
      open: () => preparedFileChunks(multimedia, onProgress),
    },
    {
      name: "meta.xml",
      expected: {
        crc32: calculateCrc32(metaXmlBytes),
        byteCount: metaXmlBytes.byteLength,
      },
      open: () => fixedFileChunks(metaXmlBytes),
    },
  ];
  return createStoredZipStream(files);
}
