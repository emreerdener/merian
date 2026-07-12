"use client";

import { Carousel } from "@mantine/carousel";
import { Badge, Box, Group, Image, Text } from "@mantine/core";
import { useEffect, useMemo, useRef, useState } from "react";
import type { ExplorePostMediaItem, ExploreReferenceImage } from "@/lib/explore";
import { buildExploreVisualSlides } from "@/lib/exploreVisualMedia";

type ExploreMediaCarouselProps = {
  mediaItems: ExplorePostMediaItem[];
  heroImageUrl: string | null;
  referenceImages: ExploreReferenceImage[];
  altText: string;
};

const mediaFrameHeight = "clamp(240px, 56.25vw, 430px)";

export function ExploreMediaCarousel({
  mediaItems,
  heroImageUrl,
  referenceImages,
  altText,
}: ExploreMediaCarouselProps) {
  const [activeIndex, setActiveIndex] = useState(0);
  const videoElements = useRef(new Map<number, HTMLVideoElement>());
  const slides = useMemo(() => buildExploreVisualSlides({
    mediaItems,
    heroImageUrl,
    referenceImages,
  }), [mediaItems, heroImageUrl, referenceImages]);

  useEffect(() => {
    for (const [index, video] of videoElements.current) {
      if (index === activeIndex) {
        video.muted = true;
        void video.play().catch(() => {
          // Browser autoplay policies may still reject playback. Native controls
          // and the poster remain available for user-initiated playback.
        });
      } else {
        video.pause();
        video.currentTime = 0;
      }
    }
  }, [activeIndex, slides]);

  if (!slides.length) return null;

  return (
    <Box style={{ position: "relative", width: "100%", height: mediaFrameHeight, overflow: "hidden" }}>
      <Carousel
        withIndicators={slides.length > 1}
        withControls={slides.length > 1}
        height={mediaFrameHeight}
        onSlideChange={setActiveIndex}
        emblaOptions={{ loop: slides.length > 1, align: "start", slidesToScroll: 1 }}
      >
        {slides.map((slide, index) => (
          <Carousel.Slide key={`${slide.url}-${index}`} style={{ position: "relative", height: "100%" }}>
            {slide.kind === "video" ? (
              <video
                ref={(element) => {
                  if (element) videoElements.current.set(index, element);
                  else videoElements.current.delete(index);
                }}
                src={slide.url}
                poster={slide.posterUrl ?? undefined}
                aria-label={`${altText} video ${index + 1}`}
                controls
                playsInline
                muted
                preload="metadata"
                style={{ width: "100%", height: "100%", objectFit: "cover", display: "block", background: "black" }}
              >
                Your browser does not support video playback.
              </video>
            ) : (
              <Image
                src={slide.url}
                alt={`${altText} - Slide ${index + 1}`}
                h="100%"
                w="100%"
                fit="cover"
                fallbackSrc="/image-placeholder.svg"
              />
            )}
            {slide.kind === "image" && slide.source ? (
              <Box
                style={{
                  position: "absolute", bottom: 0, left: 0, right: 0, padding: "16px",
                  background: "linear-gradient(to top, rgba(0,0,0,0.85) 0%, rgba(0,0,0,0.4) 60%, rgba(0,0,0,0) 100%)",
                  display: "flex", justifyContent: "space-between", alignItems: "center", color: "white", zIndex: 2,
                }}
              >
                <Text size="xs" fw={700} style={{ letterSpacing: "0.5px" }}>REFERENCE IMAGE</Text>
                <Group gap={6} align="center">
                  <Badge size="xs" variant="filled" style={{ backgroundColor: "var(--mantine-color-text)", color: "var(--mantine-color-body)" }}>
                    {slide.source.toUpperCase()}
                  </Badge>
                </Group>
              </Box>
            ) : null}
          </Carousel.Slide>
        ))}
      </Carousel>
    </Box>
  );
}
