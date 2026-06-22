const BASE64_CHUNK_SIZE = 0x8000;

export function encodeBase64(data: ArrayBuffer | Uint8Array): string {
  const bytes = data instanceof Uint8Array ? data : new Uint8Array(data);
  let binary = "";

  for (let index = 0; index < bytes.length; index += BASE64_CHUNK_SIZE) {
    const chunk = bytes.subarray(index, index + BASE64_CHUNK_SIZE);
    binary += String.fromCharCode(...chunk);
  }

  return btoa(binary);
}

export function decodeBase64(value: string): Uint8Array {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);

  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }

  return bytes;
}

export function encodeHex(data: ArrayBuffer | Uint8Array): string {
  const bytes = data instanceof Uint8Array ? data : new Uint8Array(data);
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join(
    "",
  );
}
