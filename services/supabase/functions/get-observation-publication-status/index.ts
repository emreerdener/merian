import { serveEdge } from "../_shared/edgeHandler.ts";
import { publicationStatusRoute } from "./route.ts";
serveEdge((req: Request) => publicationStatusRoute(req));
