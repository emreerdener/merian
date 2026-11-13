import { IconDeviceMobile } from "@tabler/icons-react";

/** Deliberately illustrative: replace with the approved app destination QR. */
export function QrPlaceholder() {
  const cells = Array.from(
    { length: 25 * 25 },
    (_, i) => ({ x: i % 25, y: Math.floor(i / 25) }),
  )
    .filter(({ x, y }) =>
      !((x < 8 && y < 8) || (x > 16 && y < 8) || (x < 8 && y > 16))
    )
    .filter(({ x, y }) => (x * 13 + y * 7 + x * y * 3) % 11 < 5);
  return (
    <div className="app-qr-card">
      <p>
        <IconDeviceMobile size={17} aria-hidden="true" /> Naturebook for iPhone
      </p>
      <div className="app-qr-art" aria-hidden="true">
        <svg viewBox="-2 -2 29 29">
          {cells.map(({ x, y }) => (
            <rect
              key={`${x}-${y}`}
              x={x}
              y={y}
              width=".8"
              height=".8"
              rx=".25"
            />
          ))}
          {[[0, 0], [18, 0], [0, 18]].map(([x, y]) => (
            <g key={`${x}-${y}`}>
              <rect x={x} y={y} width="7" height="7" rx="2" />
              <rect
                x={x + 1}
                y={y + 1}
                width="5"
                height="5"
                rx="1.3"
                fill="white"
              />
              <rect x={x + 2} y={y + 2} width="3" height="3" rx=".8" />
            </g>
          ))}
        </svg>
        <span>QR preview</span>
      </div>
      <small>App link coming soon</small>
    </div>
  );
}
