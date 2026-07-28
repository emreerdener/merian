import { publicHttpError } from "../_shared/http.ts";
import { validateStagingObjectKey } from "../_shared/mediaBudgets.ts";

export function normalizeRestoredObjectKeys(
  value: unknown,
  userId: string,
  fieldName = "restored_object_keys",
  maxItems = 5,
): string[] {
  if (value == null) return [];
  if (!Array.isArray(value)) {
    throw publicHttpError(400, `${fieldName} must be an array.`);
  }

  const normalized = value.map((entry) => {
    if (typeof entry !== "string") {
      throw publicHttpError(
        400,
        `${fieldName} must only contain strings.`,
      );
    }
    return entry.trim();
  }).filter((entry) => entry.length > 0);

  if (normalized.length > maxItems) {
    throw publicHttpError(
      400,
      `${fieldName} cannot contain more than ${maxItems} item${
        maxItems === 1 ? "" : "s"
      }.`,
    );
  }

  const canonicalUserId = userId.toLowerCase();
  const expectedPrefix = `staging/${canonicalUserId}/`;
  if (
    !normalized.every((entry) =>
      entry.length <= 512 &&
      validateStagingObjectKey(entry, canonicalUserId) === null &&
      /^[A-Za-z0-9._-]+$/.test(entry.slice(expectedPrefix.length))
    )
  ) {
    throw publicHttpError(
      400,
      `${fieldName} must contain safe staging keys owned by the current user.`,
    );
  }

  return [...new Set(normalized)];
}

export function restoredObjectKeysMissingDurableUrls(
  restoredObjectKeys: string[],
  durableUrls: string[] | null | undefined,
  userId: string,
): string[] {
  const canonicalUserId = userId.toLowerCase();
  const durableFileNames = new Set(
    (durableUrls ?? []).flatMap((value) => {
      if (typeof value !== "string") return [];
      const match = value.trim().match(
        /^https:\/\/media[.]merian[.]app\/public_uploads\/(?:free|pro)\/([0-9a-f-]+)\/([A-Za-z0-9._-]+)$/,
      );
      return match?.[1]?.toLowerCase() === canonicalUserId && match[2]
        ? [match[2]]
        : [];
    }),
  );

  return restoredObjectKeys.filter((key) => {
    const fileName = key.slice(key.lastIndexOf("/") + 1);
    return !durableFileNames.has(fileName);
  });
}
