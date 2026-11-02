import { joined } from "./publicPhotoFixtures.ts";
export const heifText = (s: string) => new TextEncoder().encode(s);
export function heifUint(n: number, width: number) {
  const bytes = new Uint8Array(width);
  for (let i = width - 1; i >= 0; i--) {
    bytes[i] = n % 256;
    n = Math.floor(n / 256);
  }
  return bytes;
}
export const heifBox = (type: string, ...parts: Uint8Array[]) => {
  const body = joined(...parts);
  return joined(heifUint(body.length + 8, 4), heifText(type), body);
};
export const heifFull = (
  type: string,
  version: number,
  ...parts: Uint8Array[]
) => heifBox(type, new Uint8Array([version, 0, 0, 0]), ...parts);
/** Synthetic item/NAL framing only, not HEVC pixel-decodable fixtures. */
export function heifFixture(
  options: {
    idat?: boolean;
    wide?: boolean;
    metadata?: boolean;
    largeOffsets?: boolean;
  } = {},
) {
  const { idat = false, wide = false, metadata = false, largeOffsets = false } =
    options;
  const idWidth = wide ? 4 : 2;
  const id = (n: number) => heifUint(n, idWidth);
  const nal = (type: number) => new Uint8Array([type * 2, 1, 0x80]);
  const config = new Uint8Array(23);
  config[0] = 1;
  config[1] = 1;
  config[12] = 30;
  config.set([0xf0, 0, 0xfc, 0xfd, 0xf8, 0xf8], 13);
  config[21] = 3;
  config[22] = 3;
  const hvc = heifBox(
    "hvcC",
    config,
    ...[32, 33, 34].map((type) =>
      joined(new Uint8Array([0x80 | type, 0, 1, 0, 3]), nal(type))
    ),
  );
  const ispe = heifFull("ispe", 0, heifUint(8, 4), heifUint(6, 4));
  const image = joined(heifUint(3, 4), nal(19));
  const opaque = new Uint8Array([0, 0, 0, 0, 1]);
  const media = joined(image, ...(metadata ? [opaque] : []));
  const ftyp = heifBox(
    "ftyp",
    heifText("heic"),
    heifUint(0, 4),
    heifText("mif1heic"),
  );
  const makeMeta = (absoluteOffset: number) => {
    const infos = [
      heifFull(
        "infe",
        wide ? 3 : 2,
        id(1),
        heifUint(0, 2),
        heifText("hvc1"),
        new Uint8Array([0]),
      ),
    ];
    if (metadata) {
      infos.push(
        heifFull(
          "infe",
          wide ? 3 : 2,
          id(2),
          heifUint(0, 2),
          heifText("Exif"),
          new Uint8Array([0]),
        ),
      );
    }
    const location = (item: number, offset: number, length: number) =>
      joined(
        id(item),
        heifUint(idat ? 1 : 0, 2),
        heifUint(0, 2),
        heifUint(1, 2),
        heifUint(offset, largeOffsets ? 8 : 4),
        heifUint(length, largeOffsets ? 8 : 4),
      );
    return heifFull(
      "meta",
      0,
      heifFull("hdlr", 0, heifUint(0, 4), heifText("pict"), new Uint8Array(13)),
      heifFull("pitm", wide ? 1 : 0, id(1)),
      heifFull(
        "iinf",
        wide ? 1 : 0,
        heifUint(infos.length, wide ? 4 : 2),
        ...infos,
      ),
      heifFull(
        "iloc",
        wide ? 2 : 1,
        new Uint8Array([largeOffsets ? 0x88 : 0x44, 0]),
        heifUint(infos.length, wide ? 4 : 2),
        location(1, absoluteOffset, image.length),
        ...(metadata
          ? [location(2, absoluteOffset + image.length, opaque.length)]
          : []),
      ),
      heifBox(
        "iprp",
        heifBox("ipco", ispe, hvc),
        heifFull(
          "ipma",
          wide ? 1 : 0,
          heifUint(1, 4),
          id(1),
          new Uint8Array([2, 0x81, 0x82]),
        ),
      ),
      ...(metadata
        ? [
          heifFull(
            "iref",
            wide ? 1 : 0,
            heifBox("cdsc", id(2), heifUint(1, 2), id(1)),
          ),
        ]
        : []),
      ...(idat ? [heifBox("idat", media)] : []),
    );
  };
  const preliminary = makeMeta(0);
  return joined(
    ftyp,
    makeMeta(idat ? 0 : ftyp.length + preliminary.length + 8),
    ...(idat ? [] : [heifBox("mdat", media)]),
  );
}
