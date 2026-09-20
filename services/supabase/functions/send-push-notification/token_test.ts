import { assertEquals, assertRejects } from "@std/assert";
import { exportPKCS8, generateKeyPair, jwtVerify } from "jose";
import { createApnsBearerToken } from "./token.ts";

Deno.test("APNs signs a verifiable one-hour ES256 provider token with escaped PEM", async () => {
  const { privateKey, publicKey } = await generateKeyPair("ES256", {
    extractable: true,
  });
  const pem = await exportPKCS8(privateKey);
  const now = new Date("2026-09-19T12:00:00Z");
  for (const configuredPem of [pem, pem.replaceAll("\n", "\\n")]) {
    const token = await createApnsBearerToken(
      "SYNTHETIC_TEAM",
      "SYNTHETIC_KEY",
      configuredPem,
      now.getTime(),
    );
    const { payload, protectedHeader } = await jwtVerify(token, publicKey, {
      issuer: "SYNTHETIC_TEAM",
      algorithms: ["ES256"],
      currentDate: now,
    });
    assertEquals(protectedHeader, { alg: "ES256", kid: "SYNTHETIC_KEY" });
    assertEquals(payload.iat, now.getTime() / 1000);
    assertEquals(payload.exp, now.getTime() / 1000 + 3600);
    assertEquals(payload.aud, undefined);
    await assertRejects(() =>
      jwtVerify(token, publicKey, {
        currentDate: new Date(now.getTime() + 3600_000),
      })
    );
  }
});

Deno.test("APNs rejects malformed private keys", async () => {
  await assertRejects(() =>
    createApnsBearerToken("SYNTHETIC_TEAM", "SYNTHETIC_KEY", "invalid", 0)
  );
});
