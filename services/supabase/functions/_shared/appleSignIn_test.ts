import { assertEquals, assertRejects } from "@std/assert";
import {
  decodeJwt,
  decodeProtectedHeader,
  exportJWK,
  generateKeyPair,
  jwtVerify,
  SignJWT,
} from "jose";
import {
  AppleAuthorizationExchangeError,
  type AppleSignInConfiguration,
  createAppleClientSecret,
  exchangeAppleAuthorizationCode,
  revokeAppleRefreshToken,
  verifyAppleIdentityToken,
} from "./appleSignIn.ts";

const configuration: AppleSignInConfiguration = {
  clientId: "app.merian.Merian",
  teamId: "TEAM123",
  keyId: "KEY123",
  privateKey: "unused-in-injected-tests",
};

const identityToken = "header.payload.signature-that-is-long-enough";

Deno.test("Apple client secret pins the native client and five-minute ES256 claims", async () => {
  const now = new Date("2026-08-06T12:00:00Z");
  const { privateKey, publicKey } = await createP256PrivateKeyPem();
  const token = await createAppleClientSecret(
    { ...configuration, privateKey },
    now,
  );
  const header = decodeProtectedHeader(token);
  const claims = decodeJwt(token);
  const issuedAt = Math.floor(now.getTime() / 1_000);

  assertEquals(header.alg, "ES256");
  assertEquals(header.kid, configuration.keyId);
  assertEquals(claims.iss, configuration.teamId);
  assertEquals(claims.sub, configuration.clientId);
  assertEquals(claims.aud, "https://appleid.apple.com");
  assertEquals(claims.iat, issuedAt);
  assertEquals(claims.exp, issuedAt + 300);
  await jwtVerify(token, publicKey, {
    issuer: configuration.teamId,
    audience: "https://appleid.apple.com",
    algorithms: ["ES256"],
    currentDate: now,
  });
});

Deno.test("Apple identity verification checks real RS256 signatures and rejects invalid claims", async () => {
  const { privateKey, publicKey } = await generateKeyPair("RS256");
  const other = await generateKeyPair("RS256");
  const jwk = await exportJWK(publicKey);
  const now = Math.floor(Date.now() / 1000);
  const sign = (
    claims: Record<string, unknown> = {},
    key = privateKey,
    kid = "synthetic-apple-key",
  ) =>
    new SignJWT({
      sub: "synthetic-apple-subject",
      iss: "https://appleid.apple.com",
      aud: configuration.clientId,
      iat: now,
      exp: now + 300,
      ...claims,
    }).setProtectedHeader({ alg: "RS256", kid }).sign(key);
  const originalFetch = globalThis.fetch;
  let requests = 0;
  globalThis.fetch = (input) => {
    assertEquals(String(input), "https://appleid.apple.com/auth/keys");
    requests++;
    return Promise.resolve(Response.json({
      keys: [{ ...jwk, kid: "synthetic-apple-key", use: "sig", alg: "RS256" }],
    }));
  };
  try {
    assertEquals(
      await verifyAppleIdentityToken(await sign(), configuration.clientId),
      "synthetic-apple-subject",
    );
    const invalidTokens = await Promise.all([
      sign({ iss: "https://issuer.invalid" }),
      sign({ aud: "different.client" }),
      sign({ exp: now - 1 }),
      sign({ nbf: now + 3600 }),
      sign({ sub: "" }),
      sign({ sub: "unsafe\nsubject" }),
      sign({}, other.privateKey),
      sign({}, privateKey, "unknown-key"),
      new SignJWT({ sub: "synthetic-apple-subject", exp: now + 300 })
        .setProtectedHeader({ alg: "HS256" })
        .sign(crypto.getRandomValues(new Uint8Array(32))),
    ]);
    for (const token of invalidTokens) {
      const error = await assertRejects(
        () => verifyAppleIdentityToken(token, configuration.clientId),
        AppleAuthorizationExchangeError,
      );
      assertEquals(error.code, "apple_identity_token_invalid");
      assertEquals(error.retryable, false);
      assertEquals(
        error.message,
        "The Apple authorization credential could not be secured.",
      );
    }
    assertEquals(requests, 1, "A fresh cached JWKS must be reused");
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("Apple authorization exchange binds both identity tokens and form-encodes the code", async () => {
  let requestBody = "";
  const result = await exchangeAppleAuthorizationCode(
    "single-use-code+with reserved characters",
    identityToken,
    {
      configuration,
      clientSecret: () => Promise.resolve("signed-client-secret"),
      verifyIdentityToken: () => Promise.resolve("apple-subject-123"),
      fetcher: (_input, init) => {
        requestBody = String(init?.body ?? "");
        return Promise.resolve(
          new Response(
            JSON.stringify({
              refresh_token: "refresh-token-value-123456789",
              id_token: "returned.header.payload.signature",
            }),
            { status: 200 },
          ),
        );
      },
    },
  );

  assertEquals(result, {
    subject: "apple-subject-123",
    refreshToken: "refresh-token-value-123456789",
  });
  const fields = new URLSearchParams(requestBody);
  assertEquals(fields.get("client_id"), configuration.clientId);
  assertEquals(fields.get("client_secret"), "signed-client-secret");
  assertEquals(
    fields.get("code"),
    "single-use-code+with reserved characters",
  );
  assertEquals(fields.get("grant_type"), "authorization_code");
  assertEquals(fields.has("redirect_uri"), false);
});

Deno.test("Apple authorization exchange rejects a subject mismatch", async () => {
  let verificationCount = 0;
  await assertRejects(
    () =>
      exchangeAppleAuthorizationCode("single-use-code", identityToken, {
        configuration,
        clientSecret: () => Promise.resolve("signed-client-secret"),
        verifyIdentityToken: () =>
          Promise.resolve(
            verificationCount++ === 0 ? "presented-subject" : "other-subject",
          ),
        fetcher: () =>
          Promise.resolve(
            new Response(
              JSON.stringify({
                refresh_token: "refresh-token-value-123456789",
                id_token: "returned.header.payload.signature",
              }),
              { status: 200 },
            ),
          ),
      }),
    AppleAuthorizationExchangeError,
    "The Apple authorization credential could not be secured.",
  );
});

Deno.test("Apple token endpoint invalid_grant is terminal and safely classified", async () => {
  try {
    await exchangeAppleAuthorizationCode(
      "expired-single-use-code",
      identityToken,
      {
        configuration,
        clientSecret: () => Promise.resolve("signed-client-secret"),
        verifyIdentityToken: () => Promise.resolve("apple-subject-123"),
        fetcher: () =>
          Promise.resolve(
            new Response('{"error":"invalid_grant"}', {
              status: 400,
            }),
          ),
      },
    );
    throw new Error("expected exchange failure");
  } catch (error) {
    if (!(error instanceof AppleAuthorizationExchangeError)) throw error;
    assertEquals(error.code, "apple_token_exchange_invalid_grant");
    assertEquals(error.retryable, false);
  }
});

Deno.test("Apple revocation sends the refresh-token hint and accepts idempotent HTTP 200", async () => {
  let requestBody = "";
  const result = await revokeAppleRefreshToken(
    "refresh-token-value-123456789",
    {
      configuration,
      clientSecret: () => Promise.resolve("signed-client-secret"),
      fetcher: (_input, init) => {
        requestBody = String(init?.body ?? "");
        return Promise.resolve(new Response(null, { status: 200 }));
      },
    },
  );

  assertEquals(result, { succeeded: true });
  const fields = new URLSearchParams(requestBody);
  assertEquals(fields.get("token"), "refresh-token-value-123456789");
  assertEquals(fields.get("token_type_hint"), "refresh_token");
  assertEquals(fields.get("client_id"), configuration.clientId);
  assertEquals(fields.get("client_secret"), "signed-client-secret");
});

Deno.test("Apple revocation never exposes an upstream response body as an error code", async () => {
  const result = await revokeAppleRefreshToken(
    "refresh-token-value-123456789",
    {
      configuration,
      clientSecret: () => Promise.resolve("signed-client-secret"),
      fetcher: () =>
        Promise.resolve(
          new Response('{"error":"secret-injected-value"}', {
            status: 400,
          }),
        ),
    },
  );

  assertEquals(result, {
    succeeded: false,
    errorCode: "apple_revoke_http_400",
  });
});

async function createP256PrivateKeyPem(): Promise<{
  privateKey: string;
  publicKey: CryptoKey;
}> {
  const pair = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  const privateKey = await crypto.subtle.exportKey("pkcs8", pair.privateKey);
  const bytes = new Uint8Array(privateKey);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  const lines = btoa(binary).match(/.{1,64}/g) ?? [];
  return {
    privateKey: `-----BEGIN PRIVATE KEY-----\n${
      lines.join("\n")
    }\n-----END PRIVATE KEY-----`,
    publicKey: pair.publicKey,
  };
}
