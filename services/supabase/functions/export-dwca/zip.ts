import { ExportWorkerError } from "./types.ts";

const LOCAL_FILE_HEADER_SIGNATURE = 0x04034b50;
const DATA_DESCRIPTOR_SIGNATURE = 0x08074b50;
const CENTRAL_DIRECTORY_SIGNATURE = 0x02014b50;
const END_OF_CENTRAL_DIRECTORY_SIGNATURE = 0x06054b50;
const ZIP_VERSION = 20;
const UTF8_WITH_DATA_DESCRIPTOR_FLAGS = 0x0808;
const STORED_COMPRESSION_METHOD = 0;
const DOS_TIME = 0;
const DOS_DATE_1980_01_01 = 33;
const MAX_ZIP32_VALUE = 0xffff_ffff;
const MAX_ZIP_ENTRIES = 0xffff;

const encoder = new TextEncoder();

export interface StreamingZipFile {
  name: string;
  open(): AsyncIterable<Uint8Array>;
}

interface CentralDirectoryEntry {
  name: Uint8Array;
  crc32: number;
  size: number;
  localHeaderOffset: number;
}

function buildCrc32Table(): Uint32Array {
  const table = new Uint32Array(256);
  for (let index = 0; index < table.length; index += 1) {
    let value = index;
    for (let bit = 0; bit < 8; bit += 1) {
      value = (value & 1) !== 0 ? 0xedb88320 ^ (value >>> 1) : value >>> 1;
    }
    table[index] = value >>> 0;
  }
  return table;
}

const CRC32_TABLE = buildCrc32Table();

function updateCrc32(crc: number, bytes: Uint8Array): number {
  let value = crc;
  for (const byte of bytes) {
    value = CRC32_TABLE[(value ^ byte) & 0xff] ^ (value >>> 8);
  }
  return value >>> 0;
}

function fixedRecord(byteLength: number): {
  bytes: Uint8Array;
  view: DataView;
} {
  const bytes = new Uint8Array(byteLength);
  return {
    bytes,
    view: new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength),
  };
}

function localFileHeader(name: Uint8Array): Uint8Array {
  const { bytes, view } = fixedRecord(30 + name.byteLength);
  view.setUint32(0, LOCAL_FILE_HEADER_SIGNATURE, true);
  view.setUint16(4, ZIP_VERSION, true);
  view.setUint16(6, UTF8_WITH_DATA_DESCRIPTOR_FLAGS, true);
  view.setUint16(8, STORED_COMPRESSION_METHOD, true);
  view.setUint16(10, DOS_TIME, true);
  view.setUint16(12, DOS_DATE_1980_01_01, true);
  view.setUint16(26, name.byteLength, true);
  bytes.set(name, 30);
  return bytes;
}

function dataDescriptor(crc32: number, size: number): Uint8Array {
  const { bytes, view } = fixedRecord(16);
  view.setUint32(0, DATA_DESCRIPTOR_SIGNATURE, true);
  view.setUint32(4, crc32, true);
  view.setUint32(8, size, true);
  view.setUint32(12, size, true);
  return bytes;
}

function centralDirectoryRecord(
  entry: CentralDirectoryEntry,
): Uint8Array {
  const { bytes, view } = fixedRecord(46 + entry.name.byteLength);
  view.setUint32(0, CENTRAL_DIRECTORY_SIGNATURE, true);
  view.setUint16(4, ZIP_VERSION, true);
  view.setUint16(6, ZIP_VERSION, true);
  view.setUint16(8, UTF8_WITH_DATA_DESCRIPTOR_FLAGS, true);
  view.setUint16(10, STORED_COMPRESSION_METHOD, true);
  view.setUint16(12, DOS_TIME, true);
  view.setUint16(14, DOS_DATE_1980_01_01, true);
  view.setUint32(16, entry.crc32, true);
  view.setUint32(20, entry.size, true);
  view.setUint32(24, entry.size, true);
  view.setUint16(28, entry.name.byteLength, true);
  view.setUint32(42, entry.localHeaderOffset, true);
  bytes.set(entry.name, 46);
  return bytes;
}

function endOfCentralDirectory(
  entryCount: number,
  directorySize: number,
  directoryOffset: number,
): Uint8Array {
  const { bytes, view } = fixedRecord(22);
  view.setUint32(0, END_OF_CENTRAL_DIRECTORY_SIGNATURE, true);
  view.setUint16(8, entryCount, true);
  view.setUint16(10, entryCount, true);
  view.setUint32(12, directorySize, true);
  view.setUint32(16, directoryOffset, true);
  return bytes;
}

function assertZip32Value(value: number): void {
  if (!Number.isSafeInteger(value) || value < 0 || value > MAX_ZIP32_VALUE) {
    throw new ExportWorkerError(
      "export_too_large",
      "The generated archive exceeds the ZIP32 size boundary.",
    );
  }
}

export async function* storedZipChunks(
  files: StreamingZipFile[],
): AsyncGenerator<Uint8Array> {
  if (files.length < 1 || files.length > MAX_ZIP_ENTRIES) {
    throw new TypeError("A ZIP archive requires between 1 and 65535 files.");
  }

  const entries: CentralDirectoryEntry[] = [];
  let archiveOffset = 0;

  for (const file of files) {
    const name = encoder.encode(file.name);
    if (
      name.byteLength < 1 ||
      name.byteLength > 0xffff ||
      file.name.includes("..") ||
      file.name.startsWith("/")
    ) {
      throw new TypeError("Invalid ZIP entry name.");
    }

    const header = localFileHeader(name);
    const localHeaderOffset = archiveOffset;
    yield header;
    archiveOffset += header.byteLength;

    let crc = 0xffff_ffff;
    let fileSize = 0;
    for await (const chunk of file.open()) {
      if (!(chunk instanceof Uint8Array)) {
        throw new TypeError("ZIP entry chunks must be Uint8Array values.");
      }
      if (chunk.byteLength === 0) continue;
      fileSize += chunk.byteLength;
      assertZip32Value(fileSize);
      crc = updateCrc32(crc, chunk);
      yield chunk;
      archiveOffset += chunk.byteLength;
      assertZip32Value(archiveOffset);
    }

    const finalCrc = (crc ^ 0xffff_ffff) >>> 0;
    const descriptor = dataDescriptor(finalCrc, fileSize);
    yield descriptor;
    archiveOffset += descriptor.byteLength;
    assertZip32Value(archiveOffset);
    entries.push({
      name,
      crc32: finalCrc,
      size: fileSize,
      localHeaderOffset,
    });
  }

  const directoryOffset = archiveOffset;
  for (const entry of entries) {
    const record = centralDirectoryRecord(entry);
    yield record;
    archiveOffset += record.byteLength;
    assertZip32Value(archiveOffset);
  }
  const directorySize = archiveOffset - directoryOffset;
  const end = endOfCentralDirectory(
    entries.length,
    directorySize,
    directoryOffset,
  );
  yield end;
}

export function readableStreamFromAsyncIterable(
  source: AsyncIterable<Uint8Array>,
): ReadableStream<Uint8Array> {
  const iterator = source[Symbol.asyncIterator]();
  return new ReadableStream<Uint8Array>({
    async pull(controller) {
      try {
        const next = await iterator.next();
        if (next.done) {
          controller.close();
        } else {
          controller.enqueue(next.value);
        }
      } catch (error) {
        controller.error(error);
      }
    },
    async cancel(reason) {
      await iterator.return?.(reason);
    },
  });
}

export function createStoredZipStream(
  files: StreamingZipFile[],
): ReadableStream<Uint8Array> {
  return readableStreamFromAsyncIterable(storedZipChunks(files));
}
