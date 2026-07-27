import { serveEdge } from "../_shared/edgeHandler.ts";
import { serverApiKeyOptionsFromEnvironment } from "../_shared/serviceRoleAuth.ts";
import { createReconcileExploreMediaHealthHandler } from "./handler.ts";

serveEdge(createReconcileExploreMediaHealthHandler({
  supabaseUrl: Deno.env.get("SUPABASE_URL") ?? "",
  ...serverApiKeyOptionsFromEnvironment(),
}));
