import { serveEdge } from "../_shared/edgeHandler.ts";
import { captureStageUploadRoute } from "./route.ts";
serveEdge((req: Request) => captureStageUploadRoute(req));
