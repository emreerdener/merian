import { serveEdge } from "../_shared/edgeHandler.ts";
import { publicationConsentRoute } from "./route.ts";
serveEdge((req: Request) => publicationConsentRoute(req));
