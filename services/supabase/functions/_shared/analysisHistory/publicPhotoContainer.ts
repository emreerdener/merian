import { inspectPngContainer, PngContainerRejected } from "./pngContainer.ts";
import {
  inspectJpegContainer,
  JpegContainerRejected,
} from "./jpegContainer.ts";
// This is a bounded metadata/container policy, not an image decoder. It never
// rewrites bytes: the public object must be the exact artifact that was approved.
const MAX_BYTES = 12 * 1024 * 1024;
const MAX_PIXELS = 40_000_000;
export const PUBLIC_PHOTO_CONTAINER_POLICY = "public_photo_container_v1";
/** Deliberate policy rejection only; unexpected validator failures are not proof. */
export class PublicPhotoContainerRejected extends Error {
  constructor() {
    super("publication_photo_not_sanitized");
    this.name = "PublicPhotoContainerRejected";
  }
}
function reject(): never {
  throw new PublicPhotoContainerRejected();
}
export function validatePublicPhotoContainer(
  bytes: Uint8Array,
  contentType: string,
): void {
  if (bytes.byteLength < 4 || bytes.byteLength > MAX_BYTES) reject();
  if (contentType === "image/jpeg") {
    try {
      inspectJpegContainer(bytes, (marker, payload, offset) => {
        const jfif = [74, 70, 73, 70, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0];
        if (
          marker !== 0xe0 || offset !== 2 || payload.length !== jfif.length ||
          !jfif.every((byte, index) => payload[index] === byte)
        ) reject();
      });
    } catch (error) {
      if (error instanceof JpegContainerRejected) reject();
      throw error;
    }
    return;
  }
  if (contentType === "image/png") {
    try {
      inspectPngContainer(bytes, {
        maximumBytes: MAX_BYTES,
        maximumWidth: 8192,
        maximumHeight: 8192,
        maximumPixels: MAX_PIXELS,
      });
    } catch (error) {
      if (error instanceof PngContainerRejected) reject();
      throw error;
    }
    return;
  }
  reject(); // HEIC and transformed derivatives require a separately reviewed path.
}
