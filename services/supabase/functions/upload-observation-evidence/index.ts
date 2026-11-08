import { serveEdge } from "../_shared/edgeHandler.ts";
import { evidenceUploadRoute } from "./route.ts";
serveEdge((req: Request) => evidenceUploadRoute(req));
