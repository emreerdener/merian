import { r2ObjectKeyFromPublicUrl } from "../_shared/aws.ts";
import { PublicHttpError, publicHttpError } from "../_shared/http.ts";

const IMAGE_FILE_NAME_PATTERN =
  /^[A-Za-z0-9][A-Za-z0-9_.-]*[.](?:heic|heif|jpeg|jpg|png|webp)$/i;

function invalid(message: string): PublicHttpError {
  return publicHttpError(400, message);
}

export function normalizeSourceUrl(value: unknown): string {
  if (typeof value !== "string") {
    throw invalid("source_url must be a string.");
  }

  const trimmed = value.trim();
  let parsed: URL;
  try {
    parsed = new URL(trimmed);
  } catch {
    throw invalid("source_url must be a valid durable media URL.");
  }

  const objectKey = r2ObjectKeyFromPublicUrl(trimmed);
  if (
    parsed.protocol !== "https:" ||
    parsed.search.length > 0 ||
    parsed.hash.length > 0 ||
    objectKey == null ||
    !/^public_uploads\/(?:free|pro)\/[^/]+\/[^/]+$/.test(objectKey)
  ) {
    throw invalid("source_url must be a valid durable scan image URL.");
  }

  return trimmed;
}

export function normalizeRestoredObjectKey(
  value: unknown,
  userId: string,
): string | null {
  if (value == null) return null;
  if (typeof value !== "string") {
    throw invalid("restored_object_key must be a string.");
  }

  const trimmed = value.trim();
  const expectedPrefix = `staging/${userId.toLowerCase()}/`;
  const fileName = trimmed.slice(expectedPrefix.length);
  if (
    !trimmed.startsWith(expectedPrefix) ||
    fileName.length === 0 ||
    fileName.includes("/") ||
    fileName.includes("..") ||
    !IMAGE_FILE_NAME_PATTERN.test(fileName)
  ) {
    throw invalid(
      "restored_object_key must be a staged image owned by the current user.",
    );
  }

  return trimmed;
}
