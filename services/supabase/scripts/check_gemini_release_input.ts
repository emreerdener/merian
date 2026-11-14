import {
  parseGeminiReleaseManifest,
  verifyGeminiReleaseSource,
} from "./gemini_release_contract.ts";
/** Runs before backend mutations. No DB or provider network access. */
if (import.meta.main) {
  const raw = Deno.env.get("GEMINI_ACTIVATION_RELEASE");
  if (!raw) Deno.exit(0);
  const m = parseGeminiReleaseManifest(raw);
  if (
    Deno.env.get("GITHUB_EVENT_NAME") !== "workflow_dispatch" ||
    Deno.env.get("GITHUB_REF") !== "refs/heads/main" ||
    Deno.env.get("GITHUB_SHA") !== m.backend_sha ||
    Deno.env.get("PROJECT_ID") !== m.target ||
    Date.now() >= Date.parse(m.window_end) ||
    Date.now() < Date.parse(m.window_start) ||
    Date.parse(m.app.availability_checked_at) > Date.now() ||
    Date.parse(m.app.availability_checked_at) <
      Date.parse(m.window_start) - 7 * 86400000
  ) throw new Error("gemini_release_prerequisite_invalid");
  await verifyGeminiReleaseSource(m);
  if (Deno.args.includes("--functions")) {
    const c = JSON.parse(m.configuration_text);
    console.log(Object.keys(c.required_functions).sort().join("\n"));
  }
}
