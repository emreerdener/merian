import {
  canvasDisplayCard,
  EXPLORE_FALLBACK_DELAY_MS,
  type ExploreDisplayCard,
  explorePostHref,
} from "./exploreDisplay";
import * as THREE from "three";
import {
  cardAtPoint,
  cellAt,
  exploreViewportLayout,
  indexAtCell,
  lensPoint,
  type Point,
  visibleCanvasCells,
} from "./exploreCanvas";

// A single lens acts on the completed scene, including gaps and rounded edges.
const fragmentShader = `
uniform sampler2D sceneTexture;
uniform float bend;
uniform float overscan;
varying vec2 vUv;
void main() {
  vec2 p = vUv * 2.0 - 1.0;
  p *= 1.0 + bend * dot(p, p);
  gl_FragColor = texture2D(sceneTexture, p / overscan * 0.5 + 0.5);
  #include <colorspace_fragment>
}`;

export function createExploreRenderer(host: HTMLElement, callbacks: {
  open: (id: string) => void;
  more: () => void;
  unavailable: () => void;
}) {
  const renderer = new THREE.WebGLRenderer({
    antialias: true,
    alpha: false,
    powerPreference: "low-power",
  });
  renderer.domElement.setAttribute(
    "aria-label",
    "Explore canvas. Drag or use arrow keys to move. Enter opens a loaded community photo at the center. Preset nature photos are decorative.",
  );
  renderer.domElement.tabIndex = 0;
  host.append(renderer.domElement);
  const scene = new THREE.Scene();
  const camera = new THREE.OrthographicCamera();
  camera.position.z = 10;
  const outputScene = new THREE.Scene();
  const outputCamera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
  const target = new THREE.WebGLRenderTarget(1, 1, {
    depthBuffer: false,
    stencilBuffer: false,
  });
  const overscan = 1.5;
  const lens = new THREE.ShaderMaterial({
    uniforms: {
      sceneTexture: { value: target.texture },
      bend: { value: 0.075 },
      overscan: { value: overscan },
    },
    vertexShader:
      "varying vec2 vUv; void main() { vUv = uv; gl_Position = vec4(position.xy, 0., 1.); }",
    fragmentShader,
    depthTest: false,
    depthWrite: false,
  });
  const outputGeometry = new THREE.PlaneGeometry(2, 2);
  outputScene.add(new THREE.Mesh(outputGeometry, lens));
  const geometry = new THREE.PlaneGeometry(1, 1);
  type Tile = {
    mesh: THREE.Mesh<THREE.PlaneGeometry, THREE.MeshBasicMaterial>;
    texture?: THREE.Texture;
    loading: boolean;
    primaryReady: boolean;
    failed: boolean;
    abort?: AbortController;
    used: number;
  };
  const tiles = new Map<string, Tile>();
  let items: ExploreDisplayCard[] = [];
  let disposed = false,
    frame = 0,
    previous = 0,
    width = 1,
    height = 1,
    size = 240,
    cornerRadius = 16,
    pitch = 252;
  let pan: Point = { x: 0, y: 0 }, velocity: Point = { x: 0, y: 0 }, zoom = 1;
  let drag: {
    id: number;
    start: Point;
    last: Point;
    at: number;
    moved: boolean;
  } | null = null;
  const pointers = new Set<number>();
  let pinch = false, activeLoads = 0;
  let dark = false;
  const motionPreference = window.matchMedia("(prefers-reduced-motion: reduce)");
  const background = new THREE.Color();
  const emptyCanvas = document.createElement("canvas");
  emptyCanvas.width = emptyCanvas.height = 512;
  const emptyContext = emptyCanvas.getContext("2d")!;
  const placeholder = new THREE.CanvasTexture(emptyCanvas);
  placeholder.colorSpace = THREE.SRGBColorSpace;

  function theme() {
    dark =
      document.documentElement.getAttribute("data-mantine-color-scheme") ===
        "dark";
    background.set(dark ? "#191919" : "#f6f5f2");
    scene.background = background;
    emptyContext.clearRect(0, 0, 512, 512);
    emptyContext.fillStyle = dark ? "#303030" : "#e2e2e2";
    emptyContext.beginPath();
    emptyContext.roundRect(0, 0, 512, 512, cornerRadius / size * 512);
    emptyContext.fill();
    placeholder.needsUpdate = true;
    wake();
  }

  async function load(item: ExploreDisplayCard, tile: Tile) {
    if (
      item.placeholder || tile.loading || tile.texture || tile.failed ||
      activeLoads >= 4
    ) return;
    tile.loading = true;
    activeLoads++;
    const abort = new AbortController();
    tile.abort = abort;
    async function poster(url: string, primary: boolean) {
      let bitmap: ImageBitmap | undefined;
      try {
        const response = await fetch(url, {
          signal: AbortSignal.any([
            abort.signal,
            AbortSignal.timeout(primary ? 15000 : 8000),
          ]),
          cache: url.startsWith("/assets/") ? "default" : "no-store",
        });
        if (!response.ok) throw new Error("Poster unavailable");
        bitmap = await createImageBitmap(await response.blob());
        if (
          disposed || abort.signal.aborted || tiles.get(item.id) !== tile ||
          (!primary && tile.primaryReady)
        ) return;
        const canvas = document.createElement("canvas");
        canvas.width = canvas.height = 512;
        const ctx = canvas.getContext("2d")!;
        ctx.beginPath();
        ctx.roundRect(0, 0, 512, 512, cornerRadius / size * 512);
        ctx.clip();
        const crop = Math.min(bitmap.width, bitmap.height);
        ctx.drawImage(
          bitmap,
          (bitmap.width - crop) / 2,
          (bitmap.height - crop) / 2,
          crop,
          crop,
          0,
          0,
          512,
          512,
        );
        const texture = new THREE.CanvasTexture(canvas);
        texture.colorSpace = THREE.SRGBColorSpace;
        tile.texture?.dispose();
        tile.texture = texture;
        tile.primaryReady = primary;
        tile.mesh.material.map = texture;
        tile.mesh.material.needsUpdate = true;
        wake();
      } finally {
        bitmap?.close();
      }
    }
    let fallbackLoad: Promise<void> | undefined;
    function fallback() {
      if (abort.signal.aborted || tile.primaryReady) return;
      fallbackLoad ??= poster(item.fallbackPoster, false).catch(() => {});
    }
    const timer = setTimeout(fallback, EXPLORE_FALLBACK_DELAY_MS);
    try {
      if (item.poster) {
        await poster(item.poster, true).catch(fallback);
      } else fallback();
    } finally {
      clearTimeout(timer);
      await fallbackLoad;
      tile.failed = !tile.texture;
      tile.loading = false;
      activeLoads--;
      wake();
    }
  }

  function bounds() {
    if (!items.some((item) => !item.decorative)) {
      return { x: Infinity, y: Infinity };
    }
    const ring = Math.ceil((Math.sqrt(items.length) - 1) / 2);
    return {
      x: Math.max(0, (ring + 0.5) * pitch * zoom - width / 2),
      y: Math.max(0, (ring + 0.5) * pitch * zoom - height / 2),
    };
  }
  function remove(id: string, tile: Tile) {
    tile.abort?.abort();
    tile.texture?.dispose();
    tile.mesh.material.dispose();
    scene.remove(tile.mesh);
    tiles.delete(id);
  }
  function draw(now: number) {
    frame = 0;
    if (disposed || document.hidden) return;
    const dt = Math.min(32, previous ? now - previous : 16);
    previous = now;
    const goalZoom = drag?.moved ? 0.94 : 1;
    zoom += (goalZoom - zoom) * (1 - Math.exp(-dt / (drag ? 110 : 190)));
    if (!drag) {
      pan.x += velocity.x * dt;
      pan.y += velocity.y * dt;
      const decay = Math.exp(-dt / 165);
      velocity.x *= decay;
      velocity.y *= decay;
    }
    const limit = bounds();
    if (!drag) {
      const k = 1 - Math.exp(-dt / 90);
      pan.x += (THREE.MathUtils.clamp(pan.x, -limit.x, limit.x) - pan.x) * k;
      pan.y += (THREE.MathUtils.clamp(pan.y, -limit.y, limit.y) - pan.y) * k;
    }
    camera.left = -width * overscan / 2;
    camera.right = width * overscan / 2;
    camera.top = height * overscan / 2;
    camera.bottom = -height * overscan / 2;
    camera.updateProjectionMatrix();
    const visible: Array<
      { item: ExploreDisplayCard; index: number; distance: number }
    > = [];
    const unit = pitch * zoom;
    for (
      const { x: cx, y: cy, index } of visibleCanvasCells(
        width,
        height,
        pan,
        pitch,
        zoom,
        lens.uniforms.bend.value,
      )
    ) {
      const item = canvasDisplayCard(items, index);
      const x = cx * unit + pan.x, y = cy * unit + pan.y;
      visible.push({ item, index, distance: x * x + y * y });
    }
    visible.sort((a, b) => a.distance - b.distance);
    const retained = new Set(visible.slice(0, 96).map(({ item }) => item.id));
    for (const [id, tile] of tiles) if (!retained.has(id)) remove(id, tile);
    let pending = false;
    for (const { item, index } of visible.slice(0, 96)) {
      let tile = tiles.get(item.id);
      if (!tile) {
        const material = new THREE.MeshBasicMaterial({
          map: placeholder,
          transparent: true,
          depthWrite: false,
        });
        tile = {
          mesh: new THREE.Mesh(geometry, material),
          loading: false,
          primaryReady: false,
          failed: false,
          used: now,
        };
        tiles.set(item.id, tile);
        scene.add(tile.mesh);
      }
      const cell = cellAt(index);
      tile.mesh.position.set(
        cell.x * pitch * zoom + pan.x,
        -(cell.y * pitch * zoom + pan.y),
        0,
      );
      tile.mesh.scale.set(size * zoom, size * zoom, 1);
      const loading = !tile.texture && !tile.failed;
      pending ||= loading;
      tile.mesh.material.opacity = loading && !motionPreference.matches
        ? 0.8 + 0.2 * Math.cos(now * Math.PI / 1000)
        : 1;
      void load(item, tile);
    }
    renderer.setRenderTarget(target);
    renderer.render(scene, camera);
    renderer.setRenderTarget(null);
    renderer.render(outputScene, outputCamera);
    if (
      items.length &&
      (limit.x - Math.abs(pan.x) < pitch || limit.y - Math.abs(pan.y) < pitch)
    ) callbacks.more();
    const moving = Math.abs(zoom - goalZoom) > .0001 ||
      Math.hypot(velocity.x, velocity.y) > .005 ||
      Math.abs(pan.x) > limit.x + .1 || Math.abs(pan.y) > limit.y + .1;
    if (moving && !drag) wake();
    else if (Math.abs(zoom - goalZoom) > .0001) wake();
    if (pending && !motionPreference.matches) wake();
  }
  function wake() {
    if (!frame && !disposed && !document.hidden) {
      frame = requestAnimationFrame(draw);
    }
  }
  function resize() {
    const oldPitch = pitch;
    width = host.clientWidth;
    height = host.clientHeight;
    const layout = exploreViewportLayout(width, height);
    size = layout.size;
    pitch = layout.pitch;
    cornerRadius = layout.radius;
    pan.x *= pitch / oldPitch;
    pan.y *= pitch / oldPitch;
    lens.uniforms.bend.value = layout.bend;
    const dpr = Math.min(devicePixelRatio, 1.5);
    renderer.setPixelRatio(dpr);
    renderer.setSize(width, height);
    target.setSize(
      Math.round(width * dpr * overscan),
      Math.round(height * dpr * overscan),
    );
    theme();
  }
  function point(event: PointerEvent): Point {
    const rect = host.getBoundingClientRect();
    return { x: event.clientX - rect.left, y: event.clientY - rect.top };
  }
  function down(event: PointerEvent) {
    if (event.button !== 0) return;
    pointers.add(event.pointerId);
    renderer.domElement.setPointerCapture(event.pointerId);
    if (pointers.size > 1) {
      pinch = true;
      drag = null;
      velocity = { x: 0, y: 0 };
      wake();
      return;
    }
    if (pinch) return;
    velocity = { x: 0, y: 0 };
    const p = point(event);
    drag = {
      id: event.pointerId,
      start: p,
      last: p,
      at: performance.now(),
      moved: false,
    };
  }
  function move(event: PointerEvent) {
    if (!drag || drag.id !== event.pointerId || pinch) return;
    const p = point(event), now = performance.now();
    const dx = p.x - drag.last.x, dy = p.y - drag.last.y;
    drag.moved ||= Math.hypot(p.x - drag.start.x, p.y - drag.start.y) > 6;
    if (drag.moved) {
      const limit = bounds();
      pan.x = THREE.MathUtils.clamp(pan.x + dx, -limit.x - 36, limit.x + 36);
      pan.y = THREE.MathUtils.clamp(pan.y + dy, -limit.y - 36, limit.y + 36);
      const dt = Math.max(8, now - drag.at);
      velocity = {
        x: THREE.MathUtils.clamp(dx / dt, -2, 2),
        y: THREE.MathUtils.clamp(dy / dt, -2, 2),
      };
      host.dataset.dragging = "true";
    }
    drag.last = p;
    drag.at = now;
    wake();
  }
  function openAt(p: Point) {
    const scenePoint = lensPoint(p, width, height, lens.uniforms.bend.value);
    const index = cardAtPoint(
      scenePoint,
      pan,
      zoom,
      pitch,
      size,
      Infinity,
      cornerRadius,
    );
    const item = index >= 0 ? canvasDisplayCard(items, index) : undefined;
    if (
      item && explorePostHref(item, tiles.get(item.id)?.primaryReady ?? false)
    ) {
      callbacks.open(item.id);
    }
  }
  function up(event: PointerEvent) {
    pointers.delete(event.pointerId);
    if (drag?.id === event.pointerId) {
      if (!drag.moved && event.type === "pointerup" && !pinch) {
        openAt(point(event));
      }
      if (performance.now() - drag.at > 80 || event.type !== "pointerup") {
        velocity = { x: 0, y: 0 };
      }
      drag = null;
    }
    if (!pointers.size) pinch = false;
    delete host.dataset.dragging;
    wake();
  }
  function wheel(event: WheelEvent) {
    if (event.ctrlKey) return;
    event.preventDefault();
    const factor = event.deltaMode === 1
      ? 16
      : event.deltaMode === 2
      ? height
      : 1;
    const limit = bounds();
    pan.x = THREE.MathUtils.clamp(
      pan.x - event.deltaX * factor,
      -limit.x - 36,
      limit.x + 36,
    );
    pan.y = THREE.MathUtils.clamp(
      pan.y - event.deltaY * factor,
      -limit.y - 36,
      limit.y + 36,
    );
    velocity = { x: 0, y: 0 };
    wake();
  }
  function key(event: KeyboardEvent) {
    const shifts: Record<string, Point> = {
      ArrowLeft: { x: 90, y: 0 },
      ArrowRight: { x: -90, y: 0 },
      ArrowUp: { x: 0, y: 90 },
      ArrowDown: { x: 0, y: -90 },
    };
    const shift = shifts[event.key];
    if (shift) {
      event.preventDefault();
      pan.x += shift.x;
      pan.y += shift.y;
      wake();
    }
    if (event.key === "Enter") {
      event.preventDefault();
      openAt({ x: width / 2, y: height / 2 });
    }
  }
  function blur() {
    drag = null;
    pointers.clear();
    pinch = false;
    velocity = { x: 0, y: 0 };
    delete host.dataset.dragging;
    wake();
  }
  function visibility() {
    if (document.hidden) {
      cancelAnimationFrame(frame);
      frame = 0;
      velocity = { x: 0, y: 0 };
      drag = null;
    } else {
      previous = 0;
      wake();
    }
  }
  function lost(event: Event) {
    event.preventDefault();
    callbacks.unavailable();
  }
  const canvas = renderer.domElement;
  canvas.addEventListener("pointerdown", down);
  canvas.addEventListener("pointermove", move);
  canvas.addEventListener("pointerup", up);
  canvas.addEventListener("pointercancel", up);
  canvas.addEventListener("lostpointercapture", up);
  window.addEventListener("blur", blur);
  canvas.addEventListener("wheel", wheel, { passive: false });
  canvas.addEventListener("keydown", key);
  canvas.addEventListener("webglcontextlost", lost);
  document.addEventListener("visibilitychange", visibility);
  const observer = new ResizeObserver(resize);
  observer.observe(host);
  const themeObserver = new MutationObserver(theme);
  themeObserver.observe(document.documentElement, {
    attributes: true,
    attributeFilter: ["data-mantine-color-scheme"],
  });
  resize();
  theme();
  return {
    update(next: ExploreDisplayCard[]) {
      // Drop revoked textures and cancel their fetches synchronously, even in a
      // hidden tab. The next draw must not reuse a previously approved image.
      const retained = new Set(next.map((item) => item.id));
      for (const item of items) {
        const tile = tiles.get(item.id);
        if (tile && !retained.has(item.id)) remove(item.id, tile);
      }
      items = next;
      wake();
    },
    destroy() {
      disposed = true;
      cancelAnimationFrame(frame);
      observer.disconnect();
      themeObserver.disconnect();
      document.removeEventListener("visibilitychange", visibility);
      canvas.removeEventListener("pointerdown", down);
      canvas.removeEventListener("pointermove", move);
      canvas.removeEventListener("pointerup", up);
      canvas.removeEventListener("pointercancel", up);
      canvas.removeEventListener("lostpointercapture", up);
      window.removeEventListener("blur", blur);
      canvas.removeEventListener("wheel", wheel);
      canvas.removeEventListener("keydown", key);
      canvas.removeEventListener("webglcontextlost", lost);
      for (const [id, tile] of tiles) remove(id, tile);
      placeholder.dispose();
      geometry.dispose();
      outputGeometry.dispose();
      lens.dispose();
      target.dispose();
      renderer.dispose();
      canvas.remove();
    },
  };
}
