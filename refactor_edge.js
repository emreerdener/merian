const fs = require('fs');
const path = require('path');

const sharedDir = path.join(__dirname, 'supabase', 'functions', '_shared');
if (!fs.existsSync(sharedDir)) fs.mkdirSync(sharedDir, { recursive: true });

// cors.ts
fs.writeFileSync(path.join(sharedDir, 'cors.ts'), `export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS, PUT, DELETE",
};`);

// auth.ts
fs.writeFileSync(path.join(sharedDir, 'auth.ts'), `import { SupabaseClient, User } from "@supabase/supabase-js";
import { corsHeaders } from "./cors.ts";

export async function requireAuth(req: Request, supabaseAdmin: SupabaseClient): Promise<{ user: User | null; response: Response | null }> {
  const authHeader = req.headers.get("Authorization")?.replace("Bearer ", "");
  if (!authHeader) {
    return {
      user: null,
      response: new Response(
        JSON.stringify({ error: "Unauthorized" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 401 }
      )
    };
  }

  const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(authHeader);

  if (authError || !user) {
    return {
      user: null,
      response: new Response(
        JSON.stringify({ error: "Unauthorized" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 401 }
      )
    };
  }

  return { user, response: null };
}`);

// Map over all index.ts files and replace manually tracking the new imports internally:
const functionsDir = path.join(__dirname, 'supabase', 'functions');
fs.readdirSync(functionsDir).forEach(dir => {
  if (dir === '_shared' || dir.includes('.')) return; // Skip _shared and files like deno.json
  const indexPath = path.join(functionsDir, dir, 'index.ts');
  if (fs.existsSync(indexPath)) {
    let content = fs.readFileSync(indexPath, 'utf8');
    
    // Replace cors abstraction
    content = content.replace(/^const corsHeaders = \{[\s\S]*?\};\n/m, 'import { corsHeaders } from "../_shared/cors.ts";\n');
    
    // Replace auth abstractions across nodes manually:
    // Extract block mapping:
    let newContent = content;
    if (newContent.includes('await supabaseAdmin.auth.getUser(') || newContent.includes('await supabase.auth.getUser(')) {
        // We inject the requireAuth map statically since parsing TS AST in a raw node script is too risky for this project.
        // I will let me AI manually fix the Swift and keep the Node script for the basic cors map to be DRY.
    }
    fs.writeFileSync(indexPath, newContent);
  }
});
