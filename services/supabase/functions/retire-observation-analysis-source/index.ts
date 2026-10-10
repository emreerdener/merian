import { serveEdge } from "../_shared/edgeHandler.ts";
import { sourceRetirementRoute } from "./route.ts";
serveEdge((req: Request) => sourceRetirementRoute(req));
