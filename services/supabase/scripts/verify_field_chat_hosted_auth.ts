/** No-write authentication probe; never supplies a subject or a send action. */
import {
  computeFieldChatBundleDigests,
  FIELD_CHAT_FUNCTION_NAMES,
  type FieldChatFunctionName,
} from "./generate_field_chat_deployment_identity.ts";
import { repoRoot } from "./function_dependency_tools.ts";

const PRODUCTION_PROJECT = "qlarqavoqhkuwzmevrmf";
const MAX_BODY_BYTES = 32_768;
type Digests = Readonly<Record<FieldChatFunctionName, string>>;
type Transport = (url: string, init: RequestInit) => Promise<Response>;

export interface HostedAuthConfig {
  projectRef: string;
  candidateSha: string;
  publicKey: string;
  userToken: string;
  digests: Digests;
}

function fail(stage: string): never {
  // Never interpolate upstream error messages, identities, bodies, or credentials.
  throw new Error(`Field Chat hosted auth check failed: ${stage}`);
}

function claims(token: string): Record<string, unknown> {
  try {
    const parts = token.split(".");
    if (parts.length !== 3 || token.length > 16_384) fail("token format");
    const part = parts[1].replaceAll("-", "+").replaceAll("_", "/");
    const value = JSON.parse(
      atob(part.padEnd(Math.ceil(part.length / 4) * 4, "=")),
    );
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      fail("token format");
    }
    return value;
  } catch {
    fail("token format");
  }
}

export function validateHostedAuthConfig(config: HostedAuthConfig): void {
  if (!/^[a-z]{20}$/.test(config.projectRef)) fail("project reference");
  if (config.projectRef === PRODUCTION_PROJECT) {
    fail("production is prohibited");
  }
  if (!/^[0-9a-f]{40}$/.test(config.candidateSha)) fail("candidate SHA");
  if (
    !FIELD_CHAT_FUNCTION_NAMES.every((route) =>
      /^[0-9a-f]{64}$/.test(config.digests[route])
    )
  ) fail("bundle digests");
  if (!/^sb_publishable_[A-Za-z0-9_-]+$/.test(config.publicKey)) {
    const keyClaims = claims(config.publicKey);
    if (keyClaims.role !== "anon" || keyClaims.ref !== config.projectRef) {
      fail("public key must belong to the staging project");
    }
  }
  const userClaims = claims(config.userToken);
  if (
    userClaims.role !== "authenticated" ||
    userClaims.iss !== `https://${config.projectRef}.supabase.co/auth/v1` ||
    typeof userClaims.sub !== "string" || !userClaims.sub ||
    typeof userClaims.exp !== "number" ||
    userClaims.exp <= Date.now() / 1000
  ) fail("a current staging user token is required");
}

async function boundedJson(
  response: Response,
): Promise<Record<string, unknown>> {
  const reader = response.body?.getReader();
  if (!reader) fail("missing JSON response");
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > MAX_BODY_BYTES) fail("response size");
      chunks.push(value);
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.byteLength;
    }
    const parsed = JSON.parse(new TextDecoder().decode(bytes));
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      fail("response JSON");
    }
    return parsed;
  } catch {
    fail("bounded response JSON");
  } finally {
    await reader.cancel().catch(() => {});
    reader.releaseLock();
  }
}

export async function verifyHostedAuth(
  config: HostedAuthConfig,
  transport: Transport = fetch,
) {
  validateHostedAuthConfig(config);
  const origin = `https://${config.projectRef}.supabase.co`;
  const request = async (path: string, init: RequestInit) => {
    try {
      return await transport(`${origin}${path}`, {
        ...init,
        redirect: "error",
        signal: AbortSignal.timeout(15_000),
      });
    } catch {
      fail("transport");
    }
  };
  const verified = await request("/auth/v1/user", {
    headers: {
      apikey: config.publicKey,
      Authorization: `Bearer ${config.userToken}`,
    },
  });
  if (verified.status !== 200) {
    await verified.body?.cancel();
    fail("GoTrue user verification");
  }
  const verifiedUser = await boundedJson(verified);
  if (verifiedUser.id !== claims(config.userToken).sub) {
    fail("GoTrue identity binding");
  }
  // Keep the issued claims; change the signature so this is never a valid token.
  const parts = config.userToken.split(".");
  parts[2] = (parts[2][0] === "A" ? "B" : "A") + parts[2].slice(1);
  const invalidToken = parts.join(".");
  const checks = [];
  for (const route of FIELD_CHAT_FUNCTION_NAMES) {
    for (const mode of ["missing", "invalid", "verified"] as const) {
      const headers: Record<string, string> = {
        apikey: config.publicKey,
        "Content-Type": "application/json",
      };
      if (mode !== "missing") {
        headers.Authorization = `Bearer ${
          mode === "verified" ? config.userToken : invalidToken
        }`;
      }
      const response = await request(`/functions/v1/${route}`, {
        method: "POST",
        headers,
        // requireUuid runs immediately after auth and before any subject DB read.
        body: JSON.stringify({ action: "load" }),
      });
      const expected = mode === "verified" ? 400 : 401;
      if (
        response.status !== expected ||
        response.headers.get("X-Merian-Handler") !== "1" ||
        response.headers.get("X-Merian-Field-Chat-Contract") !==
          "atomic-admission-v1" ||
        response.headers.get("X-Merian-Field-Chat-Bundle-SHA256") !==
          config.digests[route]
      ) {
        await response.body?.cancel();
        fail(`${route} ${mode} status or deployment identity`);
      }
      if (mode === "verified") {
        const body = await boundedJson(response);
        if (body.code !== "invalid_request") {
          fail(`${route} authenticated validation boundary`);
        }
      } else {
        await response.body?.cancel();
      }
      checks.push({ route, mode, status: expected, outcome: "passed" });
    }
  }
  return {
    schema_version: 1,
    candidate_sha: config.candidateSha,
    environment: "staging",
    project_ref: config.projectRef,
    observed_at: new Date().toISOString(),
    scope: "real_token_http_auth_boundary_only",
    bundle_sha256: config.digests,
    checks,
  };
}

async function exactCleanCheckout(candidate: string) {
  for (const args of [["rev-parse", "HEAD"], ["status", "--porcelain"]]) {
    const result = await new Deno.Command("git", {
      cwd: repoRoot,
      args,
      stdout: "piped",
      stderr: "piped",
    }).output();
    const output = new TextDecoder().decode(result.stdout).trim();
    if (
      !result.success || output !== (args[0] === "rev-parse" ? candidate : "")
    ) {
      fail("exact clean checkout required");
    }
  }
}

if (import.meta.main) {
  try {
    const candidateSha = Deno.env.get("FIELD_CHAT_AUTH_CANDIDATE_SHA") ?? "";
    await exactCleanCheckout(candidateSha);
    const evidence = await verifyHostedAuth({
      candidateSha,
      projectRef: Deno.env.get("FIELD_CHAT_AUTH_STAGING_REF") ?? "",
      publicKey: Deno.env.get("FIELD_CHAT_AUTH_PUBLIC_KEY") ?? "",
      userToken: Deno.env.get("FIELD_CHAT_AUTH_USER_TOKEN") ?? "",
      digests: await computeFieldChatBundleDigests(),
    });
    console.log(JSON.stringify(evidence));
  } catch {
    // Fixed output even for filesystem, runtime, or transport exceptions.
    console.error(
      "Field Chat hosted authentication verification failed; no passing evidence emitted.",
    );
    Deno.exit(1);
  }
}
