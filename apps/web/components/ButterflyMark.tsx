export function ButterflyMark({ size }: { size: number }) {
  return (
    <picture aria-hidden="true" style={{ display: "block", flexShrink: 0 }}>
      <source
        media="(prefers-reduced-motion: no-preference)"
        srcSet="/assets/butterfly-animated-40.webp 40w, /assets/butterfly-animated.webp 84w, /assets/butterfly-animated-120.webp 120w"
        sizes={`(max-width: 48em) 28px, ${size}px`}
        type="image/webp"
      />
      <img
        src="/assets/butterfly-static.png"
        alt=""
        width={size}
        height={size}
        style={{ display: "block" }}
      />
    </picture>
  );
}
