/** Deployment-only credential transport; does not call or enable OpenAI. */
import { listedSecretDigest, sha256Hex } from "./verify_edge_secret_digest.ts";

const SECRET_NAME = "NATUREBOOK_OPENAI_API_KEY";
const PROJECT_REF = "qlarqavoqhkuwzmevrmf";

class SecretSyncError extends Error {}

async function run(): Promise<void> {
  const [flag, project, mode] = Deno.args;
  if (
    flag !== "--project-ref" || project !== PROJECT_REF ||
    Deno.args.length < 2 || Deno.args.length > 3 ||
    (mode !== undefined && mode !== "--validate-only")
  ) {
    throw new SecretSyncError("invalid_target_or_arguments");
  }
  const key = Deno.env.get(SECRET_NAME) ?? "";
  if (!key) {
    // Absence never deletes a previously synchronized runtime credential.
    console.log(
      "OpenAI runtime secret skipped: no GitHub credential configured.",
    );
    return;
  }
  // Validate transport only, without assuming a provider-specific key prefix.
  if (!/^[\x21-\x7e]{1,4096}$/.test(key)) {
    throw new SecretSyncError("invalid_credential_format");
  }
  if (mode === "--validate-only") {
    console.log("OpenAI deployment credential format validated.");
    return;
  }
  const token = Deno.env.get("SUPABASE_ACCESS_TOKEN") ?? "";
  if (!token) throw new SecretSyncError("missing_supabase_access_token");
  const path = Deno.env.get("PATH") ?? "";

  const cli = async (operation: "set" | "list"): Promise<Uint8Array> => {
    const signal = AbortSignal.timeout(60_000);
    let child: Deno.ChildProcess;
    try {
      child = new Deno.Command("supabase", {
        args: [
          "secrets",
          operation,
          ...(operation === "list" ? ["--output", "json"] : []),
          "--output-format",
          "json",
          "--project-ref",
          project,
        ],
        // The isolated public template loads exactly one env-backed secret.
        // Never put key material in argv, stdin, temporary files or CLI logs.
        cwd: new URL("./openai-secret-sync/", import.meta.url),
        clearEnv: true,
        env: {
          PATH: path,
          SUPABASE_ACCESS_TOKEN: token,
          SUPABASE_TELEMETRY_DISABLED: "1",
          ...(operation === "set" ? { [SECRET_NAME]: key } : {}),
        },
        stdin: "null",
        stdout: operation === "set" ? "null" : "piped",
        stderr: "null",
        signal,
      }).spawn();
    } catch {
      throw new SecretSyncError(`${operation}_spawn_failed`);
    }
    try {
      const result = await child.output();
      if (signal.aborted) throw new SecretSyncError(`${operation}_timeout`);
      if (!result.success) throw new SecretSyncError(`${operation}_failed`);
      if (operation === "set") return new Uint8Array();
      // Buffered CLI output is inspected, never logged or saved as evidence.
      if (result.stdout.length > 1_048_576) {
        throw new SecretSyncError(`${operation}_output_limit`);
      }
      return result.stdout;
    } catch (error) {
      if (error instanceof SecretSyncError) throw error;
      throw new SecretSyncError(
        signal.aborted ? `${operation}_timeout` : `${operation}_io_failed`,
      );
    } finally {
      try {
        child.kill("SIGKILL");
      } catch { /* Already stopped. */ }
      await child.status;
    }
  };

  await cli("set");
  const output = await cli("list");
  try {
    const actual = listedSecretDigest(
      JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(output)),
      SECRET_NAME,
    );
    if (actual !== await sha256Hex(key)) throw new Error();
  } catch {
    // No rollback/unset: a failed read must not delete a working credential.
    throw new SecretSyncError("digest_verification_failed");
  }
  console.log("OpenAI runtime secret digest verified.");
}

if (import.meta.main) {
  try {
    await run();
  } catch (error) {
    const reason = error instanceof SecretSyncError
      ? error.message
      : "unexpected_failure";
    console.error(`OpenAI runtime secret synchronization failed: ${reason}.`);
    Deno.exit(1);
  }
}
