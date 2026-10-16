import { serveEdge } from "../_shared/edgeHandler.ts";
import { sourceReservationRoute } from "./route.ts";
serveEdge((req: Request) => sourceReservationRoute(req));
