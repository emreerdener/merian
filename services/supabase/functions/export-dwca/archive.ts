import {
  DWCA_META_XML,
  generateMultimediaRows,
  generateOccurrenceRow,
  MULTIMEDIA_HEADERS,
  OCCURRENCE_HEADERS,
} from "./dwca.ts";
import { UserPseudonymizer } from "./pseudonym.ts";
import { fetchExportWorkChunk } from "./storage.ts";
import {
  ClaimedExportJob,
  DBScanRow,
  ExportChunkManifestEntry,
} from "./types.ts";
import { createStoredZipStream, StreamingZipFile } from "./zip.ts";

const encoder = new TextEncoder();

export type ExportProgressCallback = () => void | Promise<void>;

export interface EncodedExportBatch {
  bytes: Uint8Array;
  rowCount: number;
}

export async function encodeExportBatch(
  job: ClaimedExportJob,
  phase: "occurrence" | "multimedia",
  scans: DBScanRow[],
  pseudonymizer: UserPseudonymizer | null,
): Promise<EncodedExportBatch> {
  const lines: string[] = [];
  const firstBatch = phase === "occurrence"
    ? job.occurrenceAfterId === null
    : job.multimediaAfterId === null;
  if (firstBatch) {
    lines.push(
      phase === "occurrence" ? OCCURRENCE_HEADERS : MULTIMEDIA_HEADERS,
    );
  }

  if (phase === "occurrence") {
    lines.push(
      ...await Promise.all(
        scans.map((scan) =>
          generateOccurrenceRow(
            scan,
            job.exportScope,
            job.includePreciseCoordinates,
            job.userId,
            pseudonymizer,
          )
        ),
      ),
    );
  } else {
    for (const scan of scans) {
      lines.push(...generateMultimediaRows(scan));
    }
  }

  return {
    bytes: lines.length > 0
      ? encoder.encode(`${lines.join("\n")}\n`)
      : new Uint8Array(),
    rowCount: phase === "occurrence" ? scans.length : lines.length -
      (firstBatch ? 1 : 0),
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

async function* metaXmlChunks(): AsyncGenerator<Uint8Array> {
  yield encoder.encode(`${DWCA_META_XML}\n`);
}

export function createPreparedDwcaArchiveStream(
  manifest: ExportChunkManifestEntry[],
  onProgress: ExportProgressCallback = () => {},
): ReadableStream<Uint8Array> {
  const occurrence = manifest.filter((chunk) => chunk.phase === "occurrence");
  const multimedia = manifest.filter((chunk) => chunk.phase === "multimedia");
  const files: StreamingZipFile[] = [
    {
      name: "occurrence.csv",
      open: () => preparedFileChunks(occurrence, onProgress),
    },
    {
      name: "multimedia.csv",
      open: () => preparedFileChunks(multimedia, onProgress),
    },
    {
      name: "meta.xml",
      open: metaXmlChunks,
    },
  ];
  return createStoredZipStream(files);
}
