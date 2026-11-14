"use client";
import type { ReactNode } from "react";
import { useExploreVisibility } from "./useExploreVisibility";
export function ExploreVisibilityGuard(
  { postId, children }: { postId: string; children: ReactNode },
) {
  const visible = useExploreVisibility([postId]);
  return visible.has(postId.toLowerCase()) ? children : (
    <section
      className="home-section"
      style={{ textAlign: "center", padding: "30vh 24px" }}
      role="status"
    >
      <h1>This discovery is currently unavailable</h1>
      <p>We’re checking whether it can still be displayed.</p>
      <a href="/">Explore other discoveries</a>
    </section>
  );
}
