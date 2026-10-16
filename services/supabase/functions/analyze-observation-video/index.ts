import { serveEdge } from "../_shared/edgeHandler.ts";
import { analyzeVideoRoute } from "./route.ts";
serveEdge((req: Request) => analyzeVideoRoute(req));
