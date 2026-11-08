/** Signature plausibility only, not structural validation or decoding. A
 * provider path must separately validate the exact retained execution bytes. */
export function matchesInitialMediaContainer(
  bytes: Uint8Array,
  type: string,
): boolean {
  const prefix = (...values: number[]) =>
    values.every((v, i) => bytes[i] === v);
  const ascii = (start: number, length: number) =>
    new TextDecoder().decode(bytes.subarray(start, start + length));
  switch (type) {
    case "image/jpeg":
      return bytes.length >= 4 && prefix(255, 216, 255);
    case "image/png":
      return prefix(137, 80, 78, 71, 13, 10, 26, 10);
    case "image/webp":
      return bytes.length >= 12 && ascii(0, 4) === "RIFF" &&
        ascii(8, 4) === "WEBP";
    case "image/heic":
    case "image/heif":
      return bytes.length >= 16 && ascii(4, 4) === "ftyp" &&
        ["heic", "heix", "hevc", "hevx", "mif1", "msf1"].includes(ascii(8, 4));
    case "video/mp4":
      return bytes.length >= 16 && ascii(4, 4) === "ftyp" &&
        ["isom", "iso2", "mp41", "mp42", "avc1", "M4V "].includes(ascii(8, 4));
    case "audio/wav":
      return bytes.length >= 44 && ascii(0, 4) === "RIFF" &&
        ascii(8, 4) === "WAVE";
    default:
      return false;
  }
}
