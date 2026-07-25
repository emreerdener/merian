export const NONCE_REQUEST_HEADER = "x-nonce";

type SecurityHeadersOptions = {
  nonce: string;
  development: boolean;
};

export function contentSecurityPolicy({
  nonce,
  development,
}: SecurityHeadersOptions): string {
  const directives = [
    "default-src 'self'",
    "base-uri 'self'",
    "object-src 'none'",
    "form-action 'self'",
    "frame-ancestors 'none'",
    `script-src 'self' 'nonce-${nonce}' 'strict-dynamic'${
      development ? " 'unsafe-eval'" : ""
    }`,
    "script-src-attr 'none'",
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' data: blob: https:",
    "font-src 'self' data:",
    "media-src 'self' blob: https://media.merian.app",
    "connect-src 'self' https://*.supabase.co https://challenges.cloudflare.com https://us.i.posthog.com",
    "frame-src https://challenges.cloudflare.com",
    "worker-src 'self' blob:",
    "manifest-src 'self'",
  ];

  if (!development) directives.push("upgrade-insecure-requests");
  return directives.join("; ");
}

export function explicitSecurityHeaders(
  options: SecurityHeadersOptions,
): ReadonlyArray<readonly [string, string]> {
  const headers: Array<readonly [string, string]> = [
    ["Content-Security-Policy", contentSecurityPolicy(options)],
    ["X-Content-Type-Options", "nosniff"],
    ["Referrer-Policy", "strict-origin-when-cross-origin"],
    [
      "Permissions-Policy",
      "camera=(), microphone=(), geolocation=(), payment=(), usb=()",
    ],
    ["X-Frame-Options", "DENY"],
    ["Cross-Origin-Opener-Policy", "same-origin"],
  ];
  if (!options.development) {
    headers.push([
      "Strict-Transport-Security",
      "max-age=63072000; includeSubDomains; preload",
    ]);
  }
  return headers;
}
