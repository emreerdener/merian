import { fetchRevealedProjectApiKeys } from "./services/supabase/scripts/resolve_project_api_keys.ts";

async function main() {
  const projectRef = Deno.env.get("PROJECT_ID");
  const accessToken = Deno.env.get("SUPABASE_ACCESS_TOKEN");
  if (!projectRef || !accessToken) {
    console.error("Missing env vars");
    Deno.exit(1);
  }
  
  const keys = await fetchRevealedProjectApiKeys(projectRef, accessToken, false);
  console.log("Server API Key from API:", keys.server_api_key.substring(0, 15) + "...");
  
  // Hash it with SHA256 to compare with supabase secrets list
  const encoder = new TextEncoder();
  const data = encoder.encode(keys.server_api_key);
  const hashBuffer = await crypto.subtle.digest("SHA-256", data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  const hashHex = hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
  
  console.log("SHA256 of Server API Key from API:", hashHex);
  
  // also hash a json dictionary with it
  const jsonDict = JSON.stringify({ default: keys.server_api_key });
  const jsonBuffer = await crypto.subtle.digest("SHA-256", encoder.encode(jsonDict));
  const jsonHash = Array.from(new Uint8Array(jsonBuffer)).map(b => b.toString(16).padStart(2, '0')).join('');
  console.log("SHA256 of JSON dict:", jsonHash);
}

main();
