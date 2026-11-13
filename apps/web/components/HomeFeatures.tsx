"use client";

import { useEffect, useRef, useState } from "react";
import {
  IconArrowLeft,
  IconArrowRight,
  IconCheck,
  IconEye,
  IconLeaf,
  IconLock,
  IconVolume,
} from "@tabler/icons-react";
import styles from "./HomeFeatures.module.css";

const features = [
  {
    id: "identify",
    title: "Put a name to your wonder",
    description:
      "A leaf, a wing, a tiny detail. Get to know the living things around you.",
  },
  {
    id: "listen",
    title: "Listen a little closer",
    description:
      "Start with a sound. Discover the wildlife you can hear, even when you can’t see it.",
  },
  {
    id: "journal",
    title: "Keep your discoveries",
    description:
      "Bring your photos and field notes together. Make a record you’ll love coming back to.",
  },
  {
    id: "explore",
    title: "See what others notice",
    description:
      "Explore public discoveries from the community. There’s always something new to notice.",
  },
  {
    id: "share",
    title: "Choose what you share",
    description:
      "Keep a personal record, then choose which observations to publish to the community.",
  },
] as const;

type FeatureId = typeof features[number]["id"];
const photo = (name: string) => `/assets/hero-nature/${name}.webp`;

/** Illustrative, replaceable previews; never presented as real observation data. */
function FeaturePreview({ id }: { id: FeatureId }) {
  if (id === "identify") {
    return (
      <span className={styles.capture}>
        <img src={photo("foliage")} alt="" loading="lazy" />
        <span className={styles.viewfinder}>
          <span className={styles.scan} />
        </span>
        <span className={styles.result}>
          <IconLeaf size={17} />
          <span>
            A closer look<br />
            <strong>A new discovery</strong>
          </span>
          <IconCheck size={16} />
        </span>
      </span>
    );
  }
  if (id === "listen") {
    return (
      <span className={styles.listening}>
        <span className={styles.soundPhoto}>
          <img src={photo("kingfisher")} alt="" loading="lazy" />
          <span className={styles.soundRing} />
        </span>
        <span className={styles.waveform}>
          {Array.from(
            { length: 25 },
            (_, i) => (
              <i
                key={i}
                style={{
                  height: `${12 + (i * 17 % 37)}px`,
                  animationDelay: `${i * -0.12}s`,
                }}
              />
            ),
          )}
        </span>
        <span className={styles.soundLabel}>
          <IconVolume size={14} /> A little closer to nature
        </span>
      </span>
    );
  }
  if (id === "journal") {
    return (
      <span className={styles.journal}>
        <span className={styles.noteBack}>
          <img src={photo("blossom")} alt="" loading="lazy" />
        </span>
        <span className={styles.noteFront}>
          <img src={photo("leaves")} alt="" loading="lazy" />
          <span>On a morning walk</span>
          <i />
          <i />
        </span>
        <span className={styles.saved}>
          <IconCheck size={14} /> A moment, remembered
        </span>
      </span>
    );
  }
  if (id === "explore") {
    return (
      <span className={styles.discovery}>
        {["macaw", "blossom", "fox", "woodland"].map((name) => (
          <span key={name}>
            <img src={photo(name)} alt="" loading="lazy" />
          </span>
        ))}
        <span className={styles.discoveryLabel}>
          <IconEye size={15} /> A world worth noticing
        </span>
      </span>
    );
  }
  return (
    <span className={styles.sharing}>
      <span className={styles.sharePhoto}>
        <img src={photo("deer")} alt="" loading="lazy" />
      </span>
      <span className={styles.shareChoice}>
        <span>
          <IconLock size={14} /> Your record
        </span>
        <span>
          <IconEye size={14} /> Public post
        </span>
        <i />
      </span>
      <span className={styles.shareCaption}>Your discovery. Your choice.</span>
    </span>
  );
}

function FeatureCard({ feature }: { feature: typeof features[number] }) {
  const preview = useRef<HTMLDivElement>(null);
  const [running, setRunning] = useState(false);
  useEffect(() => {
    const element = preview.current;
    if (!element) return;
    let visible = false;
    const update = () => setRunning(visible && !document.hidden);
    const observer = new IntersectionObserver(([entry]) => {
      visible = entry.isIntersecting;
      update();
    });
    observer.observe(element);
    document.addEventListener("visibilitychange", update);
    return () => {
      observer.disconnect();
      document.removeEventListener("visibilitychange", update);
    };
  }, []);
  return (
    <article className={styles.card}>
      <div
        ref={preview}
        className={styles.preview}
        data-running={running}
        aria-hidden="true"
      >
        <span className={styles.artwork}>
          <FeaturePreview id={feature.id} />
        </span>
      </div>
      <h3>{feature.title}</h3>
      <p>{feature.description}</p>
    </article>
  );
}

export function HomeFeatures() {
  const track = useRef<HTMLDivElement>(null);
  const [ends, setEnds] = useState({ start: true, end: false });
  useEffect(() => {
    const element = track.current;
    if (!element) return;
    const update = () =>
      setEnds({
        start: element.scrollLeft < 2,
        end:
          element.scrollLeft + element.clientWidth >= element.scrollWidth - 2,
      });
    const resize = new ResizeObserver(update);
    resize.observe(element);
    element.addEventListener("scroll", update, { passive: true });
    update();
    return () => {
      resize.disconnect();
      element.removeEventListener("scroll", update);
    };
  }, []);
  function scroll(direction: number) {
    const element = track.current;
    if (!element) return;
    const card = element.firstElementChild?.getBoundingClientRect().width ??
      280;
    element.scrollBy({
      left: direction * (card + 24),
      behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches
        ? "instant"
        : "smooth",
    });
  }
  return (
    <section
      className={styles.section}
      id="features"
      aria-labelledby="features-title"
    >
      <div className={styles.heading}>
        <div>
          <p className={styles.eyebrow}>Made for your curiosity</p>
          <h2 id="features-title">Discover nature, your way.</h2>
        </div>
        <div className={styles.controls}>
          <button
            type="button"
            onClick={() => scroll(-1)}
            disabled={ends.start}
            aria-label="Previous features"
          >
            <IconArrowLeft size={20} />
          </button>
          <button
            type="button"
            onClick={() => scroll(1)}
            disabled={ends.end}
            aria-label="Next features"
          >
            <IconArrowRight size={20} />
          </button>
        </div>
      </div>
      <div className={styles.track} ref={track}>
        {features.map((feature) => (
          <FeatureCard key={feature.id} feature={feature} />
        ))}
      </div>
    </section>
  );
}
