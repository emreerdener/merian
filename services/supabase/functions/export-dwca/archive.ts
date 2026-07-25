import { SupabaseClient } from "@supabase/supabase-js";
import { fetchExportScanPages } from "./db.ts";
import {
  DWCA_META_XML,
  generateMultimediaRows,
  generateOccurrenceRow,
  MULTIMEDIA_HEADERS,
  OCCURRENCE_HEADERS,
} from "./dwca.ts";
import { UserPseudonymizer } from "./pseudonym.ts";
import { ClaimedExportJob } from "./types.ts";
import { createStoredZipStream, StreamingZipFile } from "./zip.ts";

const encoder = new TextEncoder();
const MAXIMUM_CSV_CHUNK_CHARACTERS = 64 * 1024;

export type ExportProgressCallback = () => void | Promise<void>;

async function* occurrenceCsvChunks(
  job: ClaimedExportJob,
  supabaseAdmin: SupabaseClient,
  pseudonymizer: UserPseudonymizer | null,
  onProgress: ExportProgressCallback,
): AsyncGenerator<Uint8Array> {
  yield encoder.encode(`${OCCURRENCE_HEADERS}\n`);

  for await (
    const page of fetchExportScanPages(job, "occurrence", supabaseAdmin)
  ) {
    const rows = await Promise.all(
      page.map((scan) =>
        generateOccurrenceRow(
          scan,
          job.exportScope,
          job.includePreciseCoordinates,
          job.userId,
          pseudonymizer,
        )
      ),
    );
    if (rows.length > 0) {
      yield encoder.encode(`${rows.join("\n")}\n`);
    }
    await onProgress();
  }
}

async function* multimediaCsvChunks(
  job: ClaimedExportJob,
  supabaseAdmin: SupabaseClient,
  onProgress: ExportProgressCallback,
): AsyncGenerator<Uint8Array> {
  yield encoder.encode(`${MULTIMEDIA_HEADERS}\n`);

  let bufferedLines: string[] = [];
  let bufferedCharacters = 0;
  for await (
    const page of fetchExportScanPages(job, "multimedia", supabaseAdmin)
  ) {
    for (const scan of page) {
      for (const row of generateMultimediaRows(scan)) {
        if (
          bufferedLines.length > 0 &&
          bufferedCharacters + row.length + 1 >
            MAXIMUM_CSV_CHUNK_CHARACTERS
        ) {
          yield encoder.encode(`${bufferedLines.join("\n")}\n`);
          bufferedLines = [];
          bufferedCharacters = 0;
        }
        bufferedLines.push(row);
        bufferedCharacters += row.length + 1;
      }
    }

    if (bufferedLines.length > 0) {
      yield encoder.encode(`${bufferedLines.join("\n")}\n`);
      bufferedLines = [];
      bufferedCharacters = 0;
    }
    await onProgress();
  }
}

async function* metaXmlChunks(): AsyncGenerator<Uint8Array> {
  yield encoder.encode(`${DWCA_META_XML}\n`);
}

export function createDwcaArchiveStream(
  job: ClaimedExportJob,
  supabaseAdmin: SupabaseClient,
  pseudonymizer: UserPseudonymizer | null,
  onProgress: ExportProgressCallback = () => {},
): ReadableStream<Uint8Array> {
  const files: StreamingZipFile[] = [
    {
      name: "occurrence.csv",
      open: () =>
        occurrenceCsvChunks(
          job,
          supabaseAdmin,
          pseudonymizer,
          onProgress,
        ),
    },
    {
      name: "multimedia.csv",
      open: () => multimediaCsvChunks(job, supabaseAdmin, onProgress),
    },
    {
      name: "meta.xml",
      open: metaXmlChunks,
    },
  ];
  return createStoredZipStream(files);
}
