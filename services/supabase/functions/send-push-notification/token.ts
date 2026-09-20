import { importPKCS8, SignJWT } from "jose";

export async function createApnsBearerToken(
  teamId: string,
  keyId: string,
  privateKey: string,
  nowMs: number,
): Promise<string> {
  const importedKey = await importPKCS8(
    privateKey.replace(/\\n/g, "\n").trim(),
    "ES256",
  );
  const issuedAtSeconds = Math.floor(nowMs / 1000);
  return await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: keyId })
    .setIssuer(teamId)
    .setIssuedAt(issuedAtSeconds)
    .setExpirationTime(issuedAtSeconds + 60 * 60)
    .sign(importedKey);
}
