import { serveEdge } from "../_shared/edgeHandler.ts";
import { compositionUploadRoute } from "./route.ts";
serveEdge((req: Request) => compositionUploadRoute(req));
