import { serveEdge } from "../_shared/edgeHandler.ts";
import { publicationTargetRoute } from "./route.ts";
serveEdge((req: Request) => publicationTargetRoute(req));
