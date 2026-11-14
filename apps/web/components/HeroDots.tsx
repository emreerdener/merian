"use client";

import { useEffect, useRef } from "react";
import { HERO_DOT_SPACING, heroDotTarget, stepDotSpring } from "@/lib/heroDots";

type Dot = {
  x: number;
  y: number;
  offsetX: number;
  offsetY: number;
  glow: number;
  vx: number;
  vy: number;
  vg: number;
};

/** Decorative only; pointer events remain with the hero's links and imagery. */
export function HeroDots() {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const layer = ref.current;
    const hero = layer?.closest("section");
    const canvas = layer?.querySelector("canvas");
    const context = canvas?.getContext("2d");
    if (!layer || !hero || !canvas || !context) return;
    const motion = matchMedia("(prefers-reduced-motion: reduce)");
    const pointer = matchMedia("(any-hover: hover) and (any-pointer: fine)");
    let dots: Dot[] = [];
    let width = 0;
    let height = 0;
    let color = "";
    let frame = 0;
    let last = 0;
    let visible = true;
    let active = false;
    let clientX = 0;
    let clientY = 0;
    let scrollingUntil = 0;
    const interactive = () => !motion.matches && pointer.matches;
    const enabled = () => interactive() && visible && !document.hidden;

    function draw(dt: number) {
      const bounds = hero!.getBoundingClientRect();
      const px = clientX - bounds.left;
      const py = clientY - bounds.top;
      context!.clearRect(0, 0, width, height);
      context!.fillStyle = color;
      context!.shadowColor = color;
      let unsettled = false;
      for (const dot of dots) {
        const target = heroDotTarget(dot.x - px, dot.y - py, active);
        // Release more slowly, retaining the current size, glow, and momentum.
        const frequency = active ? 12 : 6;
        const x = stepDotSpring(dot.offsetX, dot.vx, target.x, dt, frequency);
        const y = stepDotSpring(dot.offsetY, dot.vy, target.y, dt, frequency);
        const glow = stepDotSpring(
          dot.glow,
          dot.vg,
          target.glow,
          dt,
          frequency,
        );
        dot.offsetX = x.value;
        dot.offsetY = y.value;
        dot.glow = glow.value;
        dot.vx = x.velocity;
        dot.vy = y.velocity;
        dot.vg = glow.velocity;
        const moving =
          Math.abs(x.value - target.x) + Math.abs(y.value - target.y) +
              Math.abs(glow.value - target.glow) + Math.abs(x.velocity) +
              Math.abs(y.velocity) + Math.abs(glow.velocity) > 0.003;
        unsettled ||= moving;
        const strength = Math.max(0, Math.min(1.04, dot.glow));
        context!.globalAlpha = 0.14 + strength * 0.12;
        context!.shadowBlur = strength * 2.5;
        context!.beginPath();
        context!.arc(
          dot.x + dot.offsetX,
          dot.y + dot.offsetY,
          0.9 + strength * 0.35,
          0,
          Math.PI * 2,
        );
        context!.fill();
      }
      return unsettled;
    }

    function tick(now: number) {
      frame = 0;
      if (!enabled()) return;
      const moving = draw(last ? (now - last) / 1000 : 1 / 60);
      last = now;
      if (moving) frame = requestAnimationFrame(tick);
      else last = 0;
    }
    function wake() {
      if (!frame && enabled()) frame = requestAnimationFrame(tick);
    }
    function leave() {
      active = false;
      wake();
    }
    function scroll() {
      scrollingUntil = performance.now() + 180;
      leave();
    }
    function move(event: PointerEvent) {
      if (event.pointerType === "touch" || !enabled()) return;
      const moved = event.clientX !== clientX || event.clientY !== clientY;
      clientX = event.clientX;
      clientY = event.clientY;
      // Scrolling can dispatch pointer events without intentional hover motion.
      if (!moved || performance.now() < scrollingUntil) return;
      active = true;
      wake();
    }
    function reset() {
      cancelAnimationFrame(frame);
      frame = 0;
      last = 0;
      active = false;
      width = layer!.clientWidth;
      height = layer!.clientHeight;
      const density = Math.min(window.devicePixelRatio || 1, 2);
      canvas!.width = Math.round(width * density);
      canvas!.height = Math.round(height * density);
      context!.setTransform(density, 0, 0, density, 0, 0);
      color = getComputedStyle(layer!).color;
      dots = [];
      for (let y = HERO_DOT_SPACING / 2; y < height; y += HERO_DOT_SPACING) {
        for (let x = HERO_DOT_SPACING / 2; x < width; x += HERO_DOT_SPACING) {
          dots.push({
            x,
            y,
            offsetX: 0,
            offsetY: 0,
            glow: 0,
            vx: 0,
            vy: 0,
            vg: 0,
          });
        }
      }
      // The CSS pattern remains the fallback for touch, reduced motion, and no JS.
      layer!.dataset.animated = String(interactive());
      if (interactive()) draw(0);
    }

    const resize = new ResizeObserver(() => {
      if (layer.clientWidth !== width || layer.clientHeight !== height) reset();
    });
    resize.observe(layer);
    const intersection = new IntersectionObserver(([entry]) => {
      if (visible === entry.isIntersecting) return;
      visible = entry.isIntersecting;
      // Intersection updates during scrolling must not erase the spring state.
      active = false;
      if (visible) wake();
      else {
        cancelAnimationFrame(frame);
        frame = 0;
        last = 0;
      }
    });
    intersection.observe(hero);
    const theme = new MutationObserver(reset);
    theme.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ["data-mantine-color-scheme"],
    });
    hero.addEventListener("pointermove", move);
    hero.addEventListener("pointerleave", leave);
    hero.addEventListener("pointercancel", leave);
    window.addEventListener("blur", leave);
    window.addEventListener("scroll", scroll, { passive: true });
    window.addEventListener("wheel", scroll, { passive: true });
    document.addEventListener("visibilitychange", reset);
    motion.addEventListener("change", reset);
    pointer.addEventListener("change", reset);
    reset();
    return () => {
      cancelAnimationFrame(frame);
      resize.disconnect();
      intersection.disconnect();
      theme.disconnect();
      hero.removeEventListener("pointermove", move);
      hero.removeEventListener("pointerleave", leave);
      hero.removeEventListener("pointercancel", leave);
      window.removeEventListener("blur", leave);
      window.removeEventListener("scroll", scroll);
      window.removeEventListener("wheel", scroll);
      document.removeEventListener("visibilitychange", reset);
      motion.removeEventListener("change", reset);
      pointer.removeEventListener("change", reset);
      delete layer.dataset.animated;
    };
  }, []);

  return (
    <div ref={ref} className="hero-dots" aria-hidden="true">
      <canvas />
    </div>
  );
}
