import { withEdgeHandler } from "../_shared/edgeHandler.ts";
import { handleResolvePurchasePrincipal } from "./handler.ts";

Deno.serve((req: Request) =>
  withEdgeHandler(
    req,
    (user, supabaseAdmin) =>
      handleResolvePurchasePrincipal(req, user, supabaseAdmin),
  )
);
