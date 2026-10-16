/** Inactive initial-wav-structure-v1. The caller owns the private source copy;
 * metadata is not authority to transform another buffer. No live caller yet. */
export interface InitialWavStructure {
  readonly format: 1 | 3;
  readonly bits: 16 | 32;
  readonly channels: number;
  readonly rate: number;
  readonly blockAlign: number;
  readonly byteRate: number;
  readonly dataOffset: number;
  readonly dataLength: number;
  readonly frameCount: number;
}

/** Only this type denotes an expected structural denial, never a decoder crash. */
export class InitialWavStructureError extends Error {
  constructor() {
    super("Invalid initial WAV structure");
    this.name = "InitialWavStructureError";
  }
}

function invalid(): never {
  throw new InitialWavStructureError();
}

/** Inspect exactly this view, synchronously, with no source-derived allocation. */
export function inspectInitialWavStructure(
  source: Uint8Array<ArrayBuffer>,
): InitialWavStructure {
  if (
    !(source instanceof Uint8Array) ||
    !(source.buffer instanceof ArrayBuffer) ||
    source.byteLength < 44 || source.byteLength > 2_700_000
  ) invalid();
  const view = new DataView(
    source.buffer,
    source.byteOffset,
    source.byteLength,
  );
  if (
    view.getUint32(0, true) !== 0x46464952 ||
    view.getUint32(8, true) !== 0x45564157 ||
    view.getUint32(4, true) + 8 !== source.byteLength
  ) invalid();

  let format: 1 | 3 | undefined;
  let bits: 16 | 32 | undefined;
  let channels = 0;
  let rate = 0;
  let blockAlign = 0;
  let byteRate = 0;
  let dataOffset = 0;
  let dataLength = 0;
  let offset = 12;
  while (offset < source.byteLength) {
    if (source.byteLength - offset < 8) invalid();
    const id = view.getUint32(offset, true);
    const length = view.getUint32(offset + 4, true);
    const payload = offset + 8;
    const end = payload + length;
    const next = end + length % 2;
    if (next > source.byteLength) invalid();
    if (id === 0x20746d66) {
      if (format !== undefined || dataOffset !== 0 || length < 16) invalid();
      const encoding = view.getUint16(payload, true);
      const width = view.getUint16(payload + 14, true);
      if (
        !((encoding === 1 && width === 16) ||
          (encoding === 3 && width === 32))
      ) invalid();
      format = encoding as 1 | 3;
      bits = width as 16 | 32;
      channels = view.getUint16(payload + 2, true);
      rate = view.getUint32(payload + 4, true);
      byteRate = view.getUint32(payload + 8, true);
      blockAlign = view.getUint16(payload + 12, true);
      const frameWidth = channels * (bits / 8);
      const expectedByteRate = rate * frameWidth;
      if (
        channels === 0 || rate === 0 ||
        !Number.isSafeInteger(frameWidth) || frameWidth > 0xffff ||
        frameWidth !== blockAlign ||
        !Number.isSafeInteger(expectedByteRate) ||
        expectedByteRate > 0xffffffff || expectedByteRate !== byteRate
      ) invalid();
    } else if (id === 0x61746164) {
      if (
        format === undefined || dataOffset !== 0 || length === 0 ||
        length % blockAlign !== 0
      ) invalid();
      dataOffset = payload;
      dataLength = length;
    }
    offset = next;
  }
  if (format === undefined || bits === undefined || dataOffset === 0) invalid();
  if (format === 3) {
    for (
      let sample = dataOffset;
      sample < dataOffset + dataLength;
      sample += 4
    ) {
      if (!Number.isFinite(view.getFloat32(sample, true))) invalid();
    }
  }
  return Object.freeze({
    format,
    bits,
    channels,
    rate,
    blockAlign,
    byteRate,
    dataOffset,
    dataLength,
    frameCount: dataLength / blockAlign,
  });
}
