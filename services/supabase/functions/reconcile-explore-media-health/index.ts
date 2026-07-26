import { serveEdge } from "../_shared/edgeHandler.ts";
import { createReconcileExploreMediaHealthHandler } from "./handler.ts";

serveEdge(createReconcileExploreMediaHealthHandler({
  supabaseUrl: Deno.env.get("SUPABASE_URL") ?? "",
  envServiceRoleKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  envSecretKeys: Deno.env.get("SUPABASE_SECRET_KEYS") ?? "",
}));
