const CRC32_POLYNOMIAL = 0xedb8_8320;
const MAXIMUM_CRC32 = 0xffff_ffff;
const GF2_MATRIX_WIDTH = 32;
const MAXIMUM_SAFE_BYTE_COUNT_BITS = 53;

export interface Crc32Part {
  crc32: number;
  byteCount: number;
}

export interface Crc32Digest {
  crc32: number;
  byteCount: number;
}

function buildCrc32Table(): Uint32Array {
  const table = new Uint32Array(256);
  for (let index = 0; index < table.length; index += 1) {
    let value = index;
    for (let bit = 0; bit < 8; bit += 1) {
      value = (value & 1) !== 0
        ? CRC32_POLYNOMIAL ^ (value >>> 1)
        : value >>> 1;
    }
    table[index] = value >>> 0;
  }
  return table;
}

const CRC32_TABLE = buildCrc32Table();

function assertCrc32(value: number): void {
  if (
    !Number.isSafeInteger(value) ||
    value < 0 ||
    value > MAXIMUM_CRC32
  ) {
    throw new TypeError("crc32 must be an unsigned 32-bit integer.");
  }
}

function assertByteCount(value: number): void {
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new TypeError("byteCount must be a non-negative safe integer.");
  }
}

/**
 * Calculates one CRC over a caller-bounded byte array. Export preparation calls
 * this once for each <= 512 KiB CSV chunk; final archive assembly never scans
 * the complete archive to calculate CRCs.
 */
export function calculateCrc32(bytes: Uint8Array): number {
  if (!(bytes instanceof Uint8Array)) {
    throw new TypeError("CRC input must be a Uint8Array.");
  }
  let value = MAXIMUM_CRC32;
  for (const byte of bytes) {
    value = CRC32_TABLE[(value ^ byte) & 0xff] ^ (value >>> 8);
  }
  return (value ^ MAXIMUM_CRC32) >>> 0;
}

function gf2MatrixTimes(matrix: Uint32Array, vector: number): number {
  let sum = 0;
  let index = 0;
  let remaining = vector >>> 0;
  while (remaining !== 0) {
    if ((remaining & 1) !== 0) sum ^= matrix[index];
    remaining >>>= 1;
    index += 1;
  }
  return sum >>> 0;
}

function gf2MatrixSquare(
  square: Uint32Array,
  matrix: Uint32Array,
): void {
  for (let index = 0; index < GF2_MATRIX_WIDTH; index += 1) {
    square[index] = gf2MatrixTimes(matrix, matrix[index]);
  }
}

function buildCrc32ByteOperators(): readonly Uint32Array[] {
  const oneBitOperator = new Uint32Array(GF2_MATRIX_WIDTH);
  oneBitOperator[0] = CRC32_POLYNOMIAL;
  let row = 1;
  for (let index = 1; index < GF2_MATRIX_WIDTH; index += 1) {
    oneBitOperator[index] = row;
    row = (row << 1) >>> 0;
  }

  const twoBitOperator = new Uint32Array(GF2_MATRIX_WIDTH);
  const fourBitOperator = new Uint32Array(GF2_MATRIX_WIDTH);
  gf2MatrixSquare(twoBitOperator, oneBitOperator);
  gf2MatrixSquare(fourBitOperator, twoBitOperator);

  const byteOperators: Uint32Array[] = [];
  let priorOperator = fourBitOperator;
  for (
    let bit = 0;
    bit < MAXIMUM_SAFE_BYTE_COUNT_BITS;
    bit += 1
  ) {
    const operator = new Uint32Array(GF2_MATRIX_WIDTH);
    gf2MatrixSquare(operator, priorOperator);
    byteOperators.push(operator);
    priorOperator = operator;
  }
  return byteOperators;
}

// Operator n applies 2^n zero bytes to a CRC. Building these once per isolate
// keeps final composition proportional to manifest cardinality and set length
// bits, without matrix allocation or squaring for every durable chunk.
const CRC32_BYTE_OPERATORS = buildCrc32ByteOperators();

/**
 * Returns CRC(A || B) from CRC(A), CRC(B), and B's byte length without reading
 * either payload. This is the same GF(2) composition used by ZIP/zlib tooling.
 */
export function combineCrc32(
  firstCrc32: number,
  secondCrc32: number,
  secondByteCount: number,
): number {
  assertCrc32(firstCrc32);
  assertCrc32(secondCrc32);
  assertByteCount(secondByteCount);
  if (secondByteCount === 0) {
    if (secondCrc32 !== 0) {
      throw new TypeError("An empty CRC32 part must have checksum zero.");
    }
    return firstCrc32;
  }

  let combined = firstCrc32 >>> 0;
  let remainingBytes = secondByteCount;
  let bit = 0;
  while (remainingBytes !== 0) {
    if (remainingBytes % 2 === 1) {
      combined = gf2MatrixTimes(CRC32_BYTE_OPERATORS[bit], combined);
    }
    remainingBytes = Math.floor(remainingBytes / 2);
    bit += 1;
  }

  return (combined ^ secondCrc32) >>> 0;
}

export function combineCrc32Parts(parts: Iterable<Crc32Part>): Crc32Digest {
  let combinedCrc32 = 0;
  let byteCount = 0;
  for (const part of parts) {
    assertCrc32(part.crc32);
    assertByteCount(part.byteCount);
    if (byteCount > Number.MAX_SAFE_INTEGER - part.byteCount) {
      throw new TypeError("Combined byteCount exceeds the safe integer range.");
    }
    combinedCrc32 = combineCrc32(
      combinedCrc32,
      part.crc32,
      part.byteCount,
    );
    byteCount += part.byteCount;
  }
  return { crc32: combinedCrc32, byteCount };
}
