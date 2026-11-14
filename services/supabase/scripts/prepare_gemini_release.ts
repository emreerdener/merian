import postgres from "npm:postgres@3.4.7";
import {
  buildGeminiReleaseConfiguration,
  parseGeminiReleaseManifest,
} from "./gemini_release_contract.ts";
import { geminiSmokeDigest } from "../functions/_shared/ai/geminiSmokeCatalog.ts";
/** Read-only preparation. An operator supplies build/prerequisite and authorization
 * details; this prints a concrete manifest to review before dispatching release. */
if (import.meta.main) {
  const input = Deno.args[0], url = Deno.env.get("MERIAN_DATABASE_URL");
  if (!input || !url) {
    throw new Error("gemini_release_input_and_database_required");
  }
  const draft = JSON.parse(await Deno.readTextFile(input));
  const sql = postgres(url, { max: 1, connect_timeout: 10, idle_timeout: 2 });
  try {
    const [state] =
      await sql`SELECT internal.gemini_assignment_manifest() AS assignments,revision FROM internal.gemini_routing_head WHERE singleton`;
    const c = await buildGeminiReleaseConfiguration(state.assignments);
    const m = {
      ...draft,
      version: 1,
      configuration_text: JSON.stringify(c),
      configuration_digest: await geminiSmokeDigest(c),
      expected_previous_revision: Number(state.revision),
    };
    const validated = parseGeminiReleaseManifest(JSON.stringify(m));
    if (
      validated.authorization.spending_cap_microusd <
        c.smoke_cases.reduce((sum, c) => sum + c.reservation_microusd, 0)
    ) throw new Error("gemini_release_budget_insufficient");
    console.log(JSON.stringify(validated));
  } finally {
    await sql.end();
  }
}
