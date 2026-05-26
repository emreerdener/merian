const RESERVED_USERNAMES = new Set([
  "admin",
  "administrator",
  "api",
  "explore",
  "help",
  "merian",
  "moderator",
  "null",
  "official",
  "root",
  "staff",
  "support",
  "system",
  "undefined",
]);

export function normalizePublicUsername(value: unknown): string {
  if (typeof value !== "string") return "";

  return value
    .trim()
    .replace(/^@+/, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/_{2,}/g, "_")
    .replace(/^_+|_+$/g, "");
}

export function publicUsernameValidationError(username: string): string | null {
  if (username.length < 3) return "Username must be at least 3 characters.";
  if (username.length > 24) return "Username must be 24 characters or fewer.";
  if (!/^[a-z]/.test(username)) return "Username must start with a letter.";
  if (!/[a-z0-9]$/.test(username)) {
    return "Username must end with a letter or number.";
  }
  if (!/^[a-z0-9_]+$/.test(username)) {
    return "Username can only use letters, numbers, and underscores.";
  }
  if (username.includes("__")) {
    return "Username cannot use repeated underscores.";
  }
  if (RESERVED_USERNAMES.has(username)) return "That username is reserved.";

  return null;
}
