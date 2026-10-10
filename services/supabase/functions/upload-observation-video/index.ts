import { serveEdge } from "../_shared/edgeHandler.ts";
import { videoUploadRoute } from "./route.ts";
serveEdge((req: Request) => videoUploadRoute(req));
