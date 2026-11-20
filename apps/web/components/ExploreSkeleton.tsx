"use client";

import { useEffect, useRef, useState } from "react";
import {
  curvedSkeletonPath,
  exploreViewportLayout,
  visibleCanvasCells,
} from "@/lib/exploreCanvas";

/** SVG uses the same lens geometry before WebGL is available. */
export function ExploreSkeleton({ pending = true }: { pending?: boolean }) {
  const host = useRef<HTMLDivElement>(null);
  const [viewport, setViewport] = useState({ width: 1200, height: 800 });
  useEffect(() => {
    if (!host.current) return;
    const element = host.current;
    const observer = new ResizeObserver(() =>
      setViewport({
        width: Math.max(1, element.clientWidth),
        height: Math.max(1, element.clientHeight),
      })
    );
    observer.observe(element);
    return () => observer.disconnect();
  }, []);
  const { width, height } = viewport;
  const { pitch, bend } = exploreViewportLayout(width, height);
  return (
    <div
      ref={host}
      className={`explore-skeleton${
        pending ? " explore-skeleton--pending" : ""
      }`}
      aria-hidden="true"
    >
      <svg viewBox={`0 0 ${width} ${height}`} preserveAspectRatio="none">
        {visibleCanvasCells(width, height, { x: 0, y: 0 }, pitch, 1, bend).map((
          { x, y },
        ) => (
          <path key={`${x}:${y}`} d={curvedSkeletonPath(x, y, width, height)} />
        ))}
      </svg>
    </div>
  );
}
