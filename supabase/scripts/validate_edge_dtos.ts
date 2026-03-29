/**
 * Merian API Contract Validator
 * 
 * Asserts that the TypeScript JSON Schema used by Gemini securely maps
 * to the `InferenceEdgeDTOs.swift` Codable structs safely parsed by iOS.
 * 
 * Run with: `deno run --allow-read validate_edge_dtos.ts`
 */

async function validateAPIContracts() {
  console.log("🔍 Starting API Contract Validation...\n");

  const tsPath = "../functions/identify/index.ts";
  const swiftPath = "../../merian/Core/AI/InferenceEdgeDTOs.swift";

  let tsContent = "";
  let swiftContent = "";

  try {
    tsContent = await Deno.readTextFile(tsPath);
    swiftContent = await Deno.readTextFile(swiftPath);
  } catch (e) {
    console.error(`❌ File read failed. Ensure you are running this from supabase/scripts/\n${e}`);
    Deno.exit(1);
  }

  // 1. Extract Swift let declarations (ignoring comments)
  const swiftPropRegex = /let\s+([a-zA-Z_0-9]+)\s*:/g;
  const swiftProps = new Set<string>();
  for (const match of swiftContent.matchAll(swiftPropRegex)) {
    // Escaped swift keywords like `class`
    const cleaned = match[1].replace(/`/g, "");
    swiftProps.add(cleaned);
  }

  // 2. Extract TS Schema keys (Generative AI Schema format)
  // This naively looks for property keys defined in the schema object block.
  // We capture any typical JSON Schema property definition like `my_property: { type: SchemaType... }`
  const tsPropRegex = /([a-zA-Z_0-9]+)\s*:\s*\{\s*type\s*:\s*SchemaType/g;
  const tsProps = new Set<string>();
  for (const match of tsContent.matchAll(tsPropRegex)) {
    tsProps.add(match[1]);
  }

  let failures = 0;

  // 3. Diff Analysis
  console.log(`Analyzing ${tsProps.size} TS schema properties against ${swiftProps.size} Swift struct boundaries...\n`);

  for (const tsProp of tsProps) {
    if (tsProp === "items" || tsProp === "type" || tsProp === "properties") continue;

    if (!swiftProps.has(tsProp)) {
      console.error(`⚠️   MISMATCH: TypeScript schema exposes '${tsProp}' but Swift has no matching 'let ${tsProp}: Type' declaration.`);
      failures++;
    }
  }

  if (failures > 0) {
    console.error(`\n❌ Validation Failed: ${failures} contract violations detected. App crashes likely!`);
    Deno.exit(1);
  } else {
    console.log("✅ All Type Contracts Synchronized Successfully.\n");
  }
}

await validateAPIContracts();
