import { serveEdge } from "../_shared/edgeHandler.ts";
import { audioUploadRoute } from "./route.ts";
serveEdge((req: Request) => audioUploadRoute(req));
