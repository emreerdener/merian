export interface ParsedDelimitedText {
  delimiter: "," | ";" | "\t";
  headers: string[];
  rows: Array<Record<string, string>>;
}

export function parseDelimitedText(
  source: string,
  requestedDelimiter?: "," | ";" | "\t",
): ParsedDelimitedText {
  const normalizedSource = source.startsWith("\uFEFF")
    ? source.slice(1)
    : source;
  const delimiter = requestedDelimiter ?? detectDelimiter(normalizedSource);
  const records = parseRecords(normalizedSource, delimiter)
    .filter((record) => record.some((value) => value.length > 0));

  if (records.length === 0) {
    throw new Error("Delimited input is empty.");
  }

  const headers = records[0].map((header) => header.trim());
  if (headers.some((header) => header.length === 0)) {
    throw new Error("Delimited input contains an empty header.");
  }
  if (new Set(headers).size !== headers.length) {
    throw new Error("Delimited input contains duplicate headers.");
  }

  const rows = records.slice(1).map((record, rowIndex) => {
    if (record.length > headers.length) {
      throw new Error(
        `Delimited row ${rowIndex + 2} has more fields than its header.`,
      );
    }
    return Object.fromEntries(
      headers.map((header, index) => [header, record[index] ?? ""]),
    );
  });

  return { delimiter, headers, rows };
}

export async function readPossiblyGzippedText(path: string): Promise<string> {
  return (await readPossiblyGzippedTextArtifact(path)).text;
}

export async function readPossiblyGzippedTextArtifact(
  path: string,
): Promise<{ text: string; sourceBytes: Uint8Array }> {
  const bytes = await Deno.readFile(path);
  const isGzip = bytes.length >= 2 && bytes[0] === 0x1f && bytes[1] === 0x8b;
  const decodedBytes = isGzip
    ? new Uint8Array(
      await new Response(
        new Blob([bytes]).stream().pipeThrough(
          new DecompressionStream("gzip"),
        ),
      ).arrayBuffer(),
    )
    : bytes;

  try {
    return {
      text: new TextDecoder("utf-8", { fatal: true }).decode(decodedBytes),
      sourceBytes: bytes,
    };
  } catch {
    throw new Error(`Delimited input is not valid UTF-8: ${path}`);
  }
}

export function serializeDelimitedRows(
  headers: string[],
  rows: object[],
): string {
  const lines = [headers.map(csvCell).join(",")];
  for (const row of rows) {
    const values = row as Record<string, unknown>;
    lines.push(
      headers.map((header) => csvCell(values[header] ?? "")).join(","),
    );
  }
  return `${lines.join("\n")}\n`;
}

function detectDelimiter(source: string): "," | ";" | "\t" {
  const counts = new Map<"," | ";" | "\t", number>([
    [",", 0],
    [";", 0],
    ["\t", 0],
  ]);
  let inQuotes = false;

  for (let index = 0; index < source.length; index += 1) {
    const character = source[index];
    if (character === '"') {
      if (inQuotes && source[index + 1] === '"') {
        index += 1;
      } else {
        inQuotes = !inQuotes;
      }
      continue;
    }
    if (!inQuotes && (character === "\n" || character === "\r")) break;
    if (!inQuotes && counts.has(character as "," | ";" | "\t")) {
      const delimiter = character as "," | ";" | "\t";
      counts.set(delimiter, (counts.get(delimiter) ?? 0) + 1);
    }
  }

  const ranked = [...counts.entries()].sort((lhs, rhs) => rhs[1] - lhs[1]);
  if (ranked[0][1] === 0) {
    throw new Error("Could not detect a delimited input separator.");
  }
  return ranked[0][0];
}

function parseRecords(source: string, delimiter: string): string[][] {
  const records: string[][] = [];
  let record: string[] = [];
  let field = "";
  let inQuotes = false;

  const finishRecord = () => {
    record.push(field);
    records.push(record);
    record = [];
    field = "";
  };

  for (let index = 0; index < source.length; index += 1) {
    const character = source[index];
    if (inQuotes) {
      if (character === '"') {
        if (source[index + 1] === '"') {
          field += '"';
          index += 1;
        } else {
          inQuotes = false;
        }
      } else {
        field += character;
      }
      continue;
    }

    if (character === '"') {
      if (field.length > 0) {
        throw new Error(
          "Delimited input contains a quote inside an unquoted field.",
        );
      }
      inQuotes = true;
    } else if (character === delimiter) {
      record.push(field);
      field = "";
    } else if (character === "\n") {
      finishRecord();
    } else if (character === "\r") {
      if (source[index + 1] === "\n") index += 1;
      finishRecord();
    } else {
      field += character;
    }
  }

  if (inQuotes) {
    throw new Error("Delimited input contains an unterminated quoted field.");
  }
  if (field.length > 0 || record.length > 0) {
    finishRecord();
  }
  return records;
}

function csvCell(value: unknown): string {
  const text = String(value);
  return /[",\r\n]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
}
