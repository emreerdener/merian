import { serveEdge } from "../_shared/edgeHandler.ts";
import { initialPhotoAllocationRoute } from "./route.ts";
serveEdge((req: Request) => initialPhotoAllocationRoute(req));
