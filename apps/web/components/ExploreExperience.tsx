"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { type ExplorePage, mergeCards } from "@/lib/exploreCanvas";
import type { createExploreRenderer } from "@/lib/exploreRenderer";
import { useExploreVisibility } from "./useExploreVisibility";
import { ExploreSkeleton } from "./ExploreSkeleton";
import {
  displayExploreCards,
  EXPLORE_FALLBACK_DELAY_MS,
  type ExploreDisplayCard,
  explorePostHref,
  explorePreviewCards,
} from "@/lib/exploreDisplay";

function PhotoCard({ item }: { item: ExploreDisplayCard }) {
  const [primaryReady, setPrimaryReady] = useState(false);
  const [fallbackAllowed, setFallbackAllowed] = useState(!item.poster);
  const [fallbackReady, setFallbackReady] = useState(false);
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    if (primaryReady) return;
    const timer = setTimeout(
      () => setFallbackAllowed(true),
      EXPLORE_FALLBACK_DELAY_MS,
    );
    return () => clearTimeout(timer);
  }, [primaryReady]);
  const live = !item.decorative && primaryReady;
  const ready = primaryReady || fallbackReady;
  return (
    <a
      className="explore-photo-card"
      href={explorePostHref(item, primaryReady)}
      aria-label={live ? item.label : "Nature preview"}
      data-image-state={ready ? "ready" : failed ? "unavailable" : "loading"}
    >
      <span aria-hidden="true" className="explore-photo-placeholder">
        {failed && !ready && <span>Image unavailable</span>}
      </span>
      {fallbackAllowed && !primaryReady && (
        <img
          src={item.fallbackPoster}
          alt=""
          decoding="async"
          data-loaded={fallbackReady}
          onLoad={() => setFallbackReady(true)}
          onError={() => setFailed(true)}
        />
      )}
      {item.poster && (
        <img
          src={item.poster}
          alt=""
          loading="lazy"
          decoding="async"
          data-loaded={primaryReady}
          onLoad={() => setPrimaryReady(true)}
          onError={() => setFallbackAllowed(true)}
        />
      )}
    </a>
  );
}

type Controller = ReturnType<typeof createExploreRenderer>;
function Canvas(
  { items, more, unavailable }: {
    items: ExploreDisplayCard[];
    more: () => void;
    unavailable: () => void;
  },
) {
  const host = useRef<HTMLDivElement>(null);
  const [ready, setReady] = useState(false);
  const controller = useRef<Controller | null>(null);
  const latest = useRef({ items, more, unavailable });
  latest.current = { items, more, unavailable };
  const router = useRouter();
  useEffect(() => {
    let cancelled = false;
    import("@/lib/exploreRenderer").then(({ createExploreRenderer }) => {
      if (cancelled || !host.current) return;
      try {
        controller.current = createExploreRenderer(host.current, {
          open: (id) => router.push(`/explore/post/${id}`),
          more: () => latest.current.more(),
          unavailable: () => latest.current.unavailable(),
        });
        controller.current.update(latest.current.items);
        setReady(true);
      } catch {
        latest.current.unavailable();
      }
    }).catch(() => {
      if (!cancelled) latest.current.unavailable();
    });
    return () => {
      cancelled = true;
      controller.current?.destroy();
      controller.current = null;
    };
  }, [router]);
  useEffect(() => {
    controller.current?.update(items);
  }, [items]);
  return (
    <>
      {!ready && <ExploreSkeleton />}
      <div ref={host} className="explore-canvas-surface" />
    </>
  );
}

export function ExploreExperience(
  { initialPage }: { initialPage: ExplorePage | null },
) {
  const [page, setPage] = useState(initialPage);
  const [mode, setMode] = useState<"canvas" | "grid">("grid");
  const [error, setError] = useState(false);
  const [allowPreview, setAllowPreview] = useState(false);
  const [busy, setBusy] = useState(initialPage === null);
  const [fallback, setFallback] = useState(false);
  const [generation, setGeneration] = useState(0);
  const state = useRef({ page, error });
  state.current = { page, error };
  const active = useRef<AbortController | null>(null);
  useEffect(() => {
    const known = ["#about", "#waitlist", "#features"];
    if (known.includes(window.location.hash)) {
      window.location.replace(`/about${window.location.hash}`);
      return;
    }
    const preference = window.matchMedia("(prefers-reduced-motion: reduce)");
    if (!preference.matches) setMode("canvas");
    const changed = () => {
      if (preference.matches) setMode("grid");
    };
    preference.addEventListener("change", changed);
    return () => {
      preference.removeEventListener("change", changed);
      active.current?.abort();
    };
  }, []);
  const load = useCallback(async (refresh = false, retry = false) => {
    if (active.current && !refresh) return;
    const current = state.current;
    if (
      !refresh &&
      ((!current.page?.hasMore && current.page) || (current.error && !retry))
    ) return;
    active.current?.abort();
    const request = new AbortController();
    active.current = request;
    setBusy(true);
    setError(false);
    try {
      const cursor = refresh ? null : current.page?.nextCursor;
      const response = await fetch(
        `/api/explore${cursor ? `?cursor=${encodeURIComponent(cursor)}` : ""}`,
        {
          cache: "no-store",
          signal: AbortSignal.any([request.signal, AbortSignal.timeout(20000)]),
        },
      );
      if (!response.ok) throw new Error("Unavailable");
      const next: ExplorePage = await response.json();
      if (request.signal.aborted) return;
      if (next.hasMore && (!next.nextCursor || next.nextCursor === cursor)) {
        throw new Error("Pagination did not advance");
      }
      const value = {
        ...next,
        items: refresh
          ? next.items
          : mergeCards(current.page?.items ?? [], next.items),
      };
      state.current = { page: value, error: false };
      setPage(value);
      if (refresh) setGeneration((value) => value + 1);
    } catch {
      if (!request.signal.aborted) {
        state.current.error = true;
        setError(true);
      }
    } finally {
      if (active.current === request) {
        active.current = null;
        setBusy(false);
      }
    }
  }, []);
  useEffect(() => {
    const timer = setTimeout(
      () => setAllowPreview(true),
      EXPLORE_FALLBACK_DELAY_MS,
    );
    if (!initialPage) void load(true);
    return () => {
      clearTimeout(timer);
      active.current?.abort();
    };
  }, [initialPage, load]);
  const more = useCallback(() => {
    if (state.current.page?.items.length) void load();
  }, [load]);
  const unavailable = useCallback(() => {
    setFallback(true);
    setMode("grid");
  }, []);
  const visiblePosts = useExploreVisibility(
    page?.items.map((item) => item.id) ?? [],
  );
  const preview = !page?.items.length && allowPreview;
  const items = useMemo(
    () =>
      page?.items.length
        ? displayExploreCards(page.items).map((item, index) =>
          visiblePosts.has(item.id.toLowerCase()) ? item : {
            ...explorePreviewCards[index % explorePreviewCards.length],
            id: `withheld-${item.id}`,
          }
        )
        : preview
        ? explorePreviewCards
        : [],
    [page, preview, visiblePosts],
  );
  return (
    <section
      className={`explore-experience explore-experience--${mode}`}
      aria-labelledby="explore-title"
    >
      <h1 id="explore-title" className="explore-sr-only">
        Explore community discoveries
      </h1>
      {mode === "canvas"
        ? (
          <Canvas
            key={`${generation}:${preview ? "preview" : "posts"}`}
            items={items}
            more={more}
            unavailable={unavailable}
          />
        )
        : (
          <div
            className="explore-accessible-grid"
            key={`${generation}:${preview ? "preview" : "posts"}`}
          >
            {items.map((item) => (
              <PhotoCard item={item} key={`${item.id}:${item.poster}`} />
            ))}
            <div className="explore-grid-more">
              {page?.hasMore && (
                <button
                  type="button"
                  onClick={() => void load(false, true)}
                  disabled={busy}
                >
                  {busy
                    ? "Loading…"
                    : error
                    ? "Try again"
                    : "Load more discoveries"}
                </button>
              )}
              {!!items.length && !preview && !page?.hasMore && (
                <p>You’ve reached the end of this selection.</p>
              )}
            </div>
          </div>
        )}
      {!items.length && mode === "grid" && <ExploreSkeleton />}
      <div className="explore-sr-only" role="status" aria-live="polite">
        {preview
          ? "Nature preview: preset photographs are shown while community discoveries are unavailable."
          : busy || !items.length
          ? "Loading discoveries…"
          : fallback
          ? "Showing an accessible grid of discoveries."
          : "Community discoveries loaded."}
      </div>
    </section>
  );
}
