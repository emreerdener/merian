import { serveEdge } from "../_shared/edgeHandler.ts";
import { handleReconcileAccountDeletions } from "./handler.ts";

serveEdge(handleReconcileAccountDeletions);
