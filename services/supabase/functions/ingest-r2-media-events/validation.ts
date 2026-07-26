const OWNER_UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const OBJECT_NAME_PATTERN = /^[a-z0-9_.-]+$/i;

export function parseDurableObjectKeys(value: unknown): string[] | null {
  if (!Array.isArray(value) || value.length < 1 || value.length > 100) {
    return null;
  }

  const keys = value.map((item) => typeof item === "string" ? item.trim() : "");
  if (
    keys.some((key) => {
      const parts = key.split("/");
      return key.length < 1 ||
        key.length > 512 ||
        parts.length !== 4 ||
        parts[0] !== "public_uploads" ||
        (parts[1] !== "free" && parts[1] !== "pro") ||
        !OWNER_UUID_PATTERN.test(parts[2] ?? "") ||
        !OBJECT_NAME_PATTERN.test(parts[3] ?? "") ||
        (parts[3] ?? "").includes("..");
    })
  ) {
    return null;
  }

  return [...new Set(keys)];
}
