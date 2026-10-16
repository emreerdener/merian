import { serveEdge } from "../_shared/edgeHandler.ts";
import { analysisRetirementRoute } from "./route.ts";
serveEdge((req: Request) => analysisRetirementRoute(req));
