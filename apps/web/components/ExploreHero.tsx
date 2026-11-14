"use client";

import {
  type PointerEvent,
  useCallback,
  useEffect,
  useRef,
  useState,
} from "react";
import { heroFallbackImages, watchHeroImages } from "@/lib/heroImages";
import {
  type HeroMask,
  isHeroPointVisible,
  loadHeroMask,
} from "@/lib/heroMask";
import {
  HERO_POINTER_LIMIT,
  HERO_TILES,
  heroGridLayout,
  heroIdleEmphasis,
  heroIdleOffset,
  stepHeroSpring,
} from "@/lib/heroFocus";
import { useExploreVisibility } from "./useExploreVisibility";
import styles from "./ExploreHero.module.css";
import {
  HERO_RADIAL_TILE_COUNT,
  heroResponsiveLayout,
  heroScrollProgress,
} from "@/lib/heroRadial";

function HeroTile({ src, fallback, allowFallback, onReady, index, active }: {
  active: boolean;
  index: number;
  src: string | undefined;
  fallback: string;
  allowFallback: boolean;
  onReady: () => void;
}) {
  const [readySrc, setReadySrc] = useState<string>();
  const [failedSrc, setFailedSrc] = useState<string>();
  const [fallbackRequested, setFallbackRequested] = useState(false);
  const [fallbackReady, setFallbackReady] = useState(false);
  const ready = Boolean(src && readySrc === src);

  useEffect(() => {
    if (!ready && (allowFallback || Boolean(src && failedSrc === src))) {
      setFallbackRequested(true);
    }
  }, [allowFallback, failedSrc, ready, src]);

  return (
    <div
      className={styles.tile}
      data-ready={ready || fallbackReady}
      data-hero-index={index}
      data-radial-accent={index >= HERO_TILES.length}
      data-active={active}
    >
      {fallbackRequested && (
        <img
          src={fallback}
          className={styles.fallbackImage}
          data-loaded={fallbackReady}
          alt=""
          width={400}
          height={400}
          decoding="async"
          draggable={false}
          onLoad={async (event) => {
            try {
              await event.currentTarget.decode();
              setFallbackReady(true);
              onReady();
            } catch {
              /* Retain the neutral tile if even a bundled image fails. */
            }
          }}
        />
      )}
      {src && (
        <img
          key={src}
          src={src}
          className={styles.exploreImage}
          data-loaded={ready}
          alt=""
          width={400}
          height={400}
          decoding="async"
          draggable={false}
          onLoad={async (event) => {
            try {
              await event.currentTarget.decode();
              setReadySrc(src);
              onReady();
            } catch {
              setFailedSrc(src);
            }
          }}
          onError={() => setFailedSrc(src)}
        />
      )}
    </div>
  );
}

/** Only poster URLs cross the server boundary; fallback photos are decorative. */
export function ExploreHero(
  { images, variant = "radial" }: {
    images: string[] | Promise<string[]>;
    variant?: "mesh" | "radial";
  },
) {
  const root = useRef<HTMLDivElement>(null);
  const viewport = useRef<HTMLDivElement>(null);
  const field = useRef<HTMLDivElement>(null);
  const pointerPosition = useRef<{ x: number; y: number } | null>(null);
  const motion = useRef({ x: 0, y: 0, seconds: 0 });
  const focus = useRef<number | null>(null);
  const emphasis = useRef(HERO_TILES.map(() => 0));
  const emphasisVelocity = useRef(HERO_TILES.map(() => 0));
  const [hoveredIndex, setHoveredIndex] = useState<number | null>(null);
  const masks = useRef<
    { centered?: HeroMask; stacked?: HeroMask; radial?: HeroMask }
  >({});
  const [visible, setVisible] = useState(false);
  const [pageVisible, setPageVisible] = useState(true);
  const [posters, setPosters] = useState<string[]>([]);
  const visiblePosts = useExploreVisibility(posters.flatMap((src) => {
    const match = src.match(/^\/api\/explore\/poster\/([0-9a-f-]{36})$/i);
    return match ? [match[1]] : [];
  }));
  const safePosters = posters.map((src) => {
    const match = src.match(/^\/api\/explore\/poster\/([0-9a-f-]{36})$/i);
    return match && !visiblePosts.has(match[1].toLowerCase()) ? undefined : src;
  });
  const [allowFallback, setAllowFallback] = useState(false);
  const [hasReadyImage, setHasReadyImage] = useState(false);
  const onReady = useCallback(() => setHasReadyImage(true), []);

  useEffect(
    () => watchHeroImages(images, setPosters, () => setAllowFallback(true)),
    [images],
  );

  useEffect(() => {
    let active = true;
    for (const layout of ["centered", "stacked", "radial"] as const) {
      void loadHeroMask(layout).then((mask) => {
        if (active) masks.current[layout] = mask;
      });
    }
    // A resize can move the fade underneath a stationary pointer.
    window.addEventListener("resize", resetHover);
    return () => {
      active = false;
      window.removeEventListener("resize", resetHover);
    };
  }, []);

  useEffect(() => {
    const element = root.current;
    if (!element) return;
    const observer = new IntersectionObserver(([entry]) =>
      setVisible(entry.isIntersecting)
    );
    observer.observe(element);
    const updateVisibility = () => setPageVisible(!document.hidden);
    updateVisibility();
    document.addEventListener("visibilitychange", updateVisibility);
    return () => {
      observer.disconnect();
      document.removeEventListener("visibilitychange", updateVisibility);
    };
  }, []);

  useEffect(() => {
    if (variant !== "mesh" || !viewport.current || !field.current) return;
    const movingField = field.current;
    const element = viewport.current;
    const tiles = Array.from(
      element.querySelectorAll<HTMLElement>("[data-hero-index]"),
    );
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)");
    let width = element.clientWidth;
    let height = element.clientHeight;
    const calculateLayout = heroGridLayout;
    let restingLayout = calculateLayout(width, height);
    let frame = 0;
    let lastTime = 0;
    const running = visible && pageVisible && hasReadyImage;

    function placeTiles() {
      const layout = calculateLayout(width, height, emphasis.current);

      layout.tiles.forEach((tile, index) => {
        tiles[index].style.width = `${restingLayout.tiles[index].width}px`;
        tiles[index].style.height = `${restingLayout.tiles[index].height}px`;
        tiles[index].style.transform =
          `translate3d(${tile.x}px, ${tile.y}px, 0) scale(${
            tile.width / restingLayout.tiles[index].width
          })`;
      });
    }

    function animate(now: number) {
      const elapsed = lastTime ? Math.min((now - lastTime) / 1000, 0.05) : 0;
      lastTime = now;
      const state = motion.current;
      if (!pointerPosition.current) state.seconds += elapsed;
      const idleEmphasis = heroIdleEmphasis(state.seconds);
      let changed = false;
      emphasis.current.forEach((value, index) => {
        const target = focus.current === null
          ? idleEmphasis[index]
          : focus.current === index
          ? 1 + idleEmphasis[index]
          : 0;
        const next = stepHeroSpring(
          value,
          emphasisVelocity.current[index],
          target,
          elapsed,
        );
        if (next.value !== value) changed = true;
        emphasis.current[index] = next.value;
        emphasisVelocity.current[index] = next.velocity;
      });
      if (changed) placeTiles();
      const idle = heroIdleOffset(state.seconds);
      // Hover adds a small offset at the current drift position, rather than
      // pulling the whole composition toward a new origin on pointer entry.
      const target = {
        x: idle.x + (pointerPosition.current?.x ?? 0),
        y: idle.y + (pointerPosition.current?.y ?? 0),
      };
      const ease = 1 - Math.exp(-elapsed / 0.55);
      state.x += (target.x - state.x) * ease;
      state.y += (target.y - state.y) * ease;
      movingField.style.transform =
        `translate3d(${state.x}px, ${state.y}px, 0)`;
      frame = requestAnimationFrame(animate);
    }

    function restart() {
      cancelAnimationFrame(frame);
      lastTime = 0;
      if (reduced.matches) {
        focus.current = null;
        emphasis.current.fill(0);
        emphasisVelocity.current.fill(0);
        placeTiles();
        pointerPosition.current = null;
        motion.current.x = 0;
        motion.current.y = 0;
        movingField.style.transform = "none";
        setHoveredIndex(null);
      } else if (running) {
        frame = requestAnimationFrame(animate);
      }
    }

    const observer = new ResizeObserver(() => {
      width = element.clientWidth;
      height = element.clientHeight;
      restingLayout = calculateLayout(width, height);
      placeTiles();
    });
    observer.observe(element);
    reduced.addEventListener("change", restart);
    placeTiles();
    restart();
    return () => {
      cancelAnimationFrame(frame);
      observer.disconnect();
      reduced.removeEventListener("change", restart);
    };
  }, [visible, pageVisible, hasReadyImage, variant]);

  useEffect(() => {
    if (variant !== "radial" || !viewport.current || !field.current) return;
    const element = viewport.current;
    const section = element.closest("section");
    if (!section) return;
    const tiles = Array.from(
      element.querySelectorAll<HTMLElement>("[data-hero-index]"),
    );
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)");
    const running = visible && pageVisible && hasReadyImage;
    let width = element.clientWidth;
    let height = element.clientHeight;
    const initialBounds = section.getBoundingClientRect();
    let current = reduced.matches
      ? 0
      : heroScrollProgress(initialBounds.top, initialBounds.height);
    let target = current;
    let frame = 0;
    let lastTime = 0;
    field.current.style.transform = "none";

    function paint() {
      const resting = heroResponsiveLayout(width, height);
      heroResponsiveLayout(width, height, current).tiles.forEach(
        (tile, index) => {
          const side = resting.tiles[index].width;
          tiles[index].style.width = `${side}px`;
          tiles[index].style.height = `${side}px`;
          tiles[index].style.transform = `translate3d(${
            tile.x + (tile.width - side) / 2
          }px, ${tile.y + (tile.height - side) / 2}px, 0) scale(${
            side ? tile.width / side : 1
          }) rotate(${tile.rotation}deg)`;
        },
      );
    }
    function animate(now: number) {
      const elapsed = lastTime
        ? Math.min((now - lastTime) / 1000, 0.05)
        : 1 / 60;
      lastTime = now;
      current += (target - current) * (1 - Math.exp(-elapsed / 0.18));
      if (Math.abs(target - current) < 0.0001) current = target;
      paint();
      frame = current !== target ? requestAnimationFrame(animate) : 0;
      if (!frame) lastTime = 0;
    }
    function update() {
      const bounds = section!.getBoundingClientRect();
      target = reduced.matches
        ? 0
        : heroScrollProgress(bounds.top, bounds.height);
      if (reduced.matches || !running) {
        cancelAnimationFrame(frame);
        frame = 0;
        lastTime = 0;
        current = target;
        paint();
      } else if (!frame && current !== target) {
        frame = requestAnimationFrame(animate);
      }
    }
    const resize = new ResizeObserver(() => {
      width = element.clientWidth;
      height = element.clientHeight;
      update();
      paint();
    });
    resize.observe(element);
    window.addEventListener("scroll", update, { passive: true });
    reduced.addEventListener("change", update);
    update();
    paint();
    return () => {
      cancelAnimationFrame(frame);
      resize.disconnect();
      window.removeEventListener("scroll", update);
      reduced.removeEventListener("change", update);
    };
  }, [visible, pageVisible, hasReadyImage, variant]);

  function resetHover() {
    focus.current = null;
    setHoveredIndex(null);
    pointerPosition.current = null;
    if (root.current) root.current.dataset.hovering = "false";
  }

  function updateHover(event: PointerEvent<HTMLDivElement>) {
    if (
      variant === "radial" ||
      event.pointerType !== "mouse" ||
      !window.matchMedia(
        "(hover: hover) and (prefers-reduced-motion: no-preference)",
      ).matches
    ) {
      resetHover();
      return;
    }
    const bounds = event.currentTarget.getBoundingClientRect();
    const x = (event.clientX - bounds.left) / bounds.width;
    const y = (event.clientY - bounds.top) / bounds.height;
    const layout = window.matchMedia("(max-width: 48em)").matches
      ? "stacked"
      : "centered";
    const tile = event.target instanceof Element
      ? event.target.closest('[data-ready="true"]')
      : null;
    if (!tile || !isHeroPointVisible(masks.current[layout], layout, x, y)) {
      resetHover();
      return;
    }
    const index = Number(tile.getAttribute("data-hero-index"));
    pointerPosition.current = {
      x: (0.5 - x) * HERO_POINTER_LIMIT * 2,
      y: (0.5 - y) * HERO_POINTER_LIMIT * 2,
    };
    focus.current = index;
    setHoveredIndex(index);
    if (root.current) root.current.dataset.hovering = "true";
  }

  return (
    <div
      ref={root}
      className={styles.hero}
      data-arrangement={variant}
      data-running={visible && pageVisible && hasReadyImage}
    >
      <div
        ref={viewport}
        className={styles.viewport}
        onPointerEnter={variant === "mesh" ? updateHover : undefined}
        onPointerMove={variant === "mesh" ? updateHover : undefined}
        onPointerLeave={resetHover}
        onPointerCancel={resetHover}
        aria-hidden="true"
      >
        <div ref={field} className={styles.field}>
          {Array.from({
            length: variant === "radial"
              ? HERO_RADIAL_TILE_COUNT
              : HERO_TILES.length,
          }, (_, index) => (
            <HeroTile
              key={index}
              index={index}
              active={hoveredIndex === index}
              src={safePosters.length
                ? safePosters[index % safePosters.length]
                : undefined}
              fallback={heroFallbackImages[index % heroFallbackImages.length]}
              allowFallback={allowFallback}
              onReady={onReady}
            />
          ))}
        </div>
      </div>
    </div>
  );
}
