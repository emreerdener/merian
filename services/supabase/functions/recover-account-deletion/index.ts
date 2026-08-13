import { serveEdge } from "../_shared/edgeHandler.ts";
import { createServiceRoleClientFromEnvironment } from "../_shared/serviceRoleClient.ts";
import { handleAccountDeletionRecovery } from "./handler.ts";

serveEdge((req: Request) =>
  handleAccountDeletionRecovery(
    req,
    createServiceRoleClientFromEnvironment(),
  )
);
