import { createHmac } from "node:crypto";
import { isIP } from "node:net";
import { readByteStreamWithinLimit } from "./boundedJson.ts";

export const WAITLIST_BODY_LIMIT_BYTES = 4 * 1024;
export const TURNSTILE_TOKEN_MAX_LENGTH = 2048;
export const TURNSTILE_RESPONSE_MAX_BYTES = 32 * 1024;
export const TURNSTILE_SECRET_MIN_LENGTH = 20;
export const WAITLIST_USER_AGENT_MAX_LENGTH = 512;

export type TurnstileVerification =
  | { ok: true }
  | {
    ok: false;
    kind: "invalid" | "unavailable";
  };

type TurnstileSiteverifyResponse = {
  success?: unknown;
  action?: unknown;
  hostname?: unknown;
};

export function normalizeWaitlistEmail(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const email = value.trim().toLowerCase();
  if (
    email.length < 3 ||
    email.length > 254 ||
    /[\u0000-\u0020\u007f]/.test(email)
  ) {
    return null;
  }

  const atIndex = email.indexOf("@");
  if (
    atIndex < 1 ||
    atIndex !== email.lastIndexOf("@") ||
    atIndex > 64 ||
    email.startsWith(".") ||
    email.slice(0, atIndex).endsWith(".") ||
    email.includes("..")
  ) {
    return null;
  }

  const localPart = email.slice(0, atIndex);
  const domain = email.slice(atIndex + 1);
  if (!/^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+$/.test(localPart)) return null;
  if (domain.length < 3 || domain.length > 253) return null;

  const labels = domain.split(".");
  if (labels.length < 2) return null;
  for (const label of labels) {
    if (
      label.length < 1 ||
      label.length > 63 ||
      !/^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/.test(label)
    ) {
      return null;
    }
  }
  if (!/^[a-z]{2,63}$/.test(labels.at(-1) ?? "")) return null;

  return email;
}

export function normalizedUserAgent(value: string | null): string | null {
  if (!value) return null;
  const normalized = value
    .replace(/[\u0000-\u001f\u007f]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  if (!normalized) return null;
  return normalized.slice(0, WAITLIST_USER_AGENT_MAX_LENGTH);
}

export function resolveTrustedClientIp(
  headers: Headers,
  trustedHeader: string,
): string | null {
  const normalizedHeader = trustedHeader.trim().toLowerCase();
  if (
    ![
      "cf-connecting-ip",
      "x-forwarded-for",
      "x-real-ip",
      "x-vercel-forwarded-for",
    ]
      .includes(normalizedHeader)
  ) {
    return null;
  }

  const candidate = headers.get(normalizedHeader)?.split(",", 1)[0]?.trim() ??
    "";
  return isIP(candidate) > 0 ? candidate : null;
}

export function waitlistIpHash(
  clientIp: string,
  secret: string,
  now = new Date(),
): string | null {
  if (isIP(clientIp) === 0 || secret.length < 32) return null;
  const utcDay = now.toISOString().slice(0, 10);
  return createHmac("sha256", secret)
    .update(`waitlist-ip-v1\n${utcDay}\n${clientIp}`, "utf8")
    .digest("hex");
}

export async function verifyTurnstileToken(
  input: {
    token: string;
    secret: string;
    remoteIp: string;
    requestId: string;
    allowedHostnames: ReadonlySet<string>;
  },
  fetchImpl: typeof fetch = fetch,
): Promise<TurnstileVerification> {
  if (
    input.secret.length < TURNSTILE_SECRET_MIN_LENGTH ||
    input.token.length < 1 ||
    input.token.length > TURNSTILE_TOKEN_MAX_LENGTH ||
    input.allowedHostnames.size < 1
  ) {
    return { ok: false, kind: "unavailable" };
  }

  const body = new URLSearchParams({
    secret: input.secret,
    response: input.token,
    remoteip: input.remoteIp,
    idempotency_key: input.requestId,
  });

  let response: Response;
  try {
    response = await fetchImpl(
      "https://challenges.cloudflare.com/turnstile/v0/siteverify",
      {
        method: "POST",
        body,
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
        },
        signal: AbortSignal.timeout(5_000),
      },
    );
  } catch {
    return { ok: false, kind: "unavailable" };
  }

  if (!response.ok) {
    await response.body?.cancel("unexpected Siteverify status");
    return { ok: false, kind: "unavailable" };
  }

  let result: TurnstileSiteverifyResponse;
  try {
    const text = await readBoundedUtf8Response(
      response,
      TURNSTILE_RESPONSE_MAX_BYTES,
    );
    if (text === null) {
      return { ok: false, kind: "unavailable" };
    }
    result = JSON.parse(text) as TurnstileSiteverifyResponse;
  } catch {
    return { ok: false, kind: "unavailable" };
  }

  const hostname = typeof result.hostname === "string"
    ? result.hostname.toLowerCase()
    : "";
  if (
    result.success !== true ||
    result.action !== "waitlist" ||
    !input.allowedHostnames.has(hostname)
  ) {
    return { ok: false, kind: "invalid" };
  }
  return { ok: true };
}

export function parseAllowedHostnames(value: string | undefined): Set<string> {
  return new Set(
    (value ?? "")
      .split(",")
      .map((entry) => entry.trim().toLowerCase())
      .filter((entry) =>
        entry.length > 0 &&
        entry.length <= 253 &&
        /^[a-z0-9.-]+$/.test(entry)
      ),
  );
}

async function readBoundedUtf8Response(
  response: Response,
  maximumBytes: number,
): Promise<string | null> {
  const declaredLength = response.headers.get("content-length");
  let declaredBytes: number | null = null;
  if (declaredLength !== null) {
    const normalizedLength = declaredLength.trim();
    if (!/^(0|[1-9][0-9]*)$/.test(normalizedLength)) return null;
    declaredBytes = Number(normalizedLength);
    if (
      !Number.isSafeInteger(declaredBytes) ||
      declaredBytes > maximumBytes
    ) {
      await response.body?.cancel("response body exceeded limit");
      return null;
    }
  }

  if (!response.body) return null;
  const streamResult = await readByteStreamWithinLimit(
    response.body,
    maximumBytes,
    "response body exceeded limit",
  );
  if (!streamResult.ok) return null;
  const bytes = streamResult.bytes;
  if (declaredBytes !== null && declaredBytes !== bytes.byteLength) return null;
  try {
    return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    return null;
  }
}
