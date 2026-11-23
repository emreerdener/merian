import { serveEdge } from "../_shared/edgeHandler.ts";
import { initialEvidenceUploadRoute } from "./route.ts";
serveEdge((req: Request) => initialEvidenceUploadRoute(req));
