export const MAX_PUBLIC_DISPLAY_NAME_LENGTH = 40;

export function normalizePublicDisplayName(value: unknown): string {
  if (typeof value !== "string") return "";

  return value
    .replace(/\s+/g, " ")
    .trim();
}

export function publicDisplayNameValidationError(
  displayName: string,
): string | null {
  if (displayName.length > MAX_PUBLIC_DISPLAY_NAME_LENGTH) {
    return "Display name must be 40 characters or fewer.";
  }
  if (/[\p{Cc}\p{Cf}]/u.test(displayName)) {
    return "Display name cannot include control characters.";
  }

  return null;
}

export function makePublicDisplayNameResponse(displayName: string) {
  return { display_name: displayName };
}
