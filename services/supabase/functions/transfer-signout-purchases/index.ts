import { withEdgeHandler } from "../_shared/edgeHandler.ts";
import { handleSignoutPurchaseHandoff } from "./handler.ts";

Deno.serve((req: Request) =>
  withEdgeHandler(
    req,
    (user, supabaseAdmin) =>
      handleSignoutPurchaseHandoff(req, user, supabaseAdmin),
  )
);
