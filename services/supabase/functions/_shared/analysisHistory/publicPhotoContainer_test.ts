import { assertEquals, assertThrows } from "@std/assert";
import { validatePublicPhotoContainer } from "./publicPhotoContainer.ts";
import {
  joined,
  jpegSegment,
  pngChunk,
  pngParts,
  safeJpeg,
  safePng,
} from "./testing/publicPhotoFixtures.ts";
const text = (value: string) => [...new TextEncoder().encode(value)];
Deno.test("public photo container accepts bounded allowed JPEG and PNG containers unchanged", () => {
  for (
    const [bytes, type] of [[safeJpeg(), "image/jpeg"], [
      safePng(),
      "image/png",
    ]] as const
  ) {
    const before = bytes.slice();
    validatePublicPhotoContainer(bytes, type);
    assertEquals(bytes, before);
  }
  assertEquals([...pngChunk("IEND").slice(-4)], [174, 66, 96, 130]);
});
Deno.test("public JPEG accepts only the exact minimal JFIF header", () => {
  const bytes = safeJpeg(),
    header = [74, 70, 73, 70, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0];
  validatePublicPhotoContainer(
    joined(bytes.slice(0, 2), jpegSegment(0xe0, header), bytes.slice(2)),
    "image/jpeg",
  );
  for (
    const payload of [
      [...header, 0],
      [...header.slice(0, 12), 1, 1, 0, 0, 0],
      text("JFXX\0thumbnail"),
    ]
  ) {
    assertThrows(
      () =>
        validatePublicPhotoContainer(
          joined(bytes.slice(0, 2), jpegSegment(0xe0, payload), bytes.slice(2)),
          "image/jpeg",
        ),
      Error,
      "publication_photo_not_sanitized",
    );
  }
});
Deno.test("public JPEG rejects metadata segments before and after scan data", async (t) => {
  const bytes = safeJpeg();
  for (
    const [marker, payload] of [
      [0xe1, text("Exif\0\0synthetic GPS")],
      [0xe1, text("http://ns.adobe.com/xap/1.0/\0synthetic")],
      [0xe2, text("ICC_PROFILE\0synthetic")],
      [0xed, text("Photoshop 3.0\0synthetic IPTC")],
      [0xfe, text("synthetic private comment")],
    ] as const
  ) {
    await t.step(String(marker) + "/" + payload.length, () => {
      const segment = jpegSegment(marker, [...payload]);
      for (const position of [2, bytes.length - 2]) {
        assertThrows(
          () =>
            validatePublicPhotoContainer(
              joined(bytes.slice(0, position), segment, bytes.slice(position)),
              "image/jpeg",
            ),
          Error,
          "publication_photo_not_sanitized",
        );
      }
    });
  }
});
Deno.test("public JPEG rejects malformed lengths, trailing data, unsupported coding and missing end", () => {
  const original = safeJpeg();
  const malformed = original.slice();
  malformed[4] = 255;
  malformed[5] = 255;
  for (
    const bytes of [
      malformed,
      original.slice(0, -1),
      joined(original, new Uint8Array([1])),
      joined(
        new Uint8Array([255, 216]),
        jpegSegment(0xc3, [1, 2]),
        new Uint8Array([255, 217]),
      ),
      new Uint8Array([255, 216, 255, 217]),
      new Uint8Array([255, 216, 255]),
    ]
  ) {
    assertThrows(
      () => validatePublicPhotoContainer(bytes, "image/jpeg"),
      Error,
      "publication_photo_not_sanitized",
    );
  }
});
Deno.test("public PNG rejects private and unknown chunks regardless of CRC or placement", async (t) => {
  const [signature, header, data, end] = pngParts();
  for (
    const type of [
      "eXIf",
      "tEXt",
      "zTXt",
      "iTXt",
      "iCCP",
      "tIME",
      "pHYs",
      "vpAg",
      "acTL",
    ]
  ) {
    await t.step(type, () => {
      const extra = pngChunk(type, text("synthetic private metadata"));
      for (
        const bytes of [
          joined(signature, header, extra, data, end),
          joined(signature, header, data, extra, end),
        ]
      ) {
        assertThrows(
          () => validatePublicPhotoContainer(bytes, "image/png"),
          Error,
          "publication_photo_not_sanitized",
        );
      }
    });
  }
});
Deno.test("public PNG rejects CRC corruption, duplicate headers, chunk order, oversized lengths and trailing bytes", () => {
  const [signature, header, data, end] = pngParts();
  const badCRC = data.slice();
  badCRC[badCRC.length - 1] ^= 1;
  const badLength = data.slice();
  badLength[0] = 255;
  for (
    const bytes of [
      joined(signature, header, badCRC, end),
      joined(signature, header, header, data, end),
      joined(signature, data, header, end),
      joined(signature, header, badLength, end),
      joined(signature, header, data, end, new Uint8Array([0])),
      joined(signature, header, end),
      joined(signature, header, data),
      joined(signature, header, data, pngChunk("sRGB", [0]), data, end),
    ]
  ) {
    assertThrows(
      () => validatePublicPhotoContainer(bytes, "image/png"),
      Error,
      "publication_photo_not_sanitized",
    );
  }
});
Deno.test("public PNG permits only bounded color hints before image data", () => {
  const [signature, header, data, end] = pngParts();
  validatePublicPhotoContainer(
    joined(
      signature,
      header,
      pngChunk("sRGB", [0]),
      pngChunk("gAMA", [0, 0, 177, 143]),
      data,
      end,
    ),
    "image/png",
  );
  for (
    const chunk of [
      pngChunk("sRGB", [4]),
      pngChunk("gAMA", [0, 0, 0, 0]),
      pngChunk("cHRM", [0]),
    ]
  ) {
    assertThrows(
      () =>
        validatePublicPhotoContainer(
          joined(signature, header, chunk, data, end),
          "image/png",
        ),
      Error,
      "publication_photo_not_sanitized",
    );
  }
});
Deno.test("public container holds HEIC, wrong MIME and excessive input", () => {
  for (
    const [bytes, type] of [[safePng(), "image/heic"], [
      safeJpeg(),
      "image/png",
    ], [new Uint8Array(12 * 1024 * 1024 + 1), "image/jpeg"]] as const
  ) {
    assertThrows(
      () => validatePublicPhotoContainer(bytes, type),
      Error,
      "publication_photo_not_sanitized",
    );
  }
});
