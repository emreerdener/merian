"use client";
import { useEffect, useState } from "react";
import { subscribeExploreVisibility } from "@/lib/subscribeExploreVisibility";
import { watchExploreVisibility } from "@/lib/watchExploreVisibility";

const empty: ReadonlySet<string> = new Set();
export function useExploreVisibility(ids: string[]): ReadonlySet<string> {
  const key = [...new Set(ids.map((id) => id.toLowerCase()))].sort().join(",");
  const [state, setState] = useState<
    { key: string; visible: ReadonlySet<string> }
  >({ key: "", visible: empty });
  useEffect(() => {
    if (!key) return;
    let stop: (() => void) | undefined;
    const start = () => {
      stop?.();
      setState({ key, visible: empty });
      if (document.hidden) return;
      stop = watchExploreVisibility(
        key.split(","),
        (visible) => setState({ key, visible }),
        {
          check: async (batch, signal) => {
            const response = await fetch(
              `/api/explore/visibility?ids=${batch.join(",")}`,
              { cache: "no-store", signal },
            );
            if (!response.ok) throw new Error("Visibility unavailable");
            return response.json();
          },
          changes: (snapshot, failed) => {
            // Larger sessions use bounded sequential polling instead of opening
            // unbounded EventSource connections as more pages are loaded.
            if (
              typeof EventSource === "undefined" || key.split(",").length > 128
            ) return null;
            return subscribeExploreVisibility(
              (handlers) => {
                const connection = new EventSource(
                  `/api/explore/changes?ids=${key}`,
                );
                connection.onmessage = (event) => handlers.message(event.data);
                connection.onerror = handlers.error;
                connection.addEventListener("unavailable", handlers.error);
                connection.addEventListener("reconnect", handlers.reconnect);
                return () => connection.close();
              },
              snapshot,
              failed,
            );
          },
        },
      );
    };
    start();
    document.addEventListener("visibilitychange", start);
    window.addEventListener("pageshow", start);
    const hide = () => {
      stop?.();
      stop = undefined;
      setState({ key, visible: empty });
    };
    window.addEventListener("pagehide", hide);
    return () => {
      stop?.();
      document.removeEventListener("visibilitychange", start);
      window.removeEventListener("pageshow", start);
      window.removeEventListener("pagehide", hide);
    };
  }, [key]);
  return state.key === key ? state.visible : empty;
}
