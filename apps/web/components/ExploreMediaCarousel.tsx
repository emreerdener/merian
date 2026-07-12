"use client";

import { Carousel } from "@mantine/carousel";
import { Badge, Box, Center, Group, Image, Text, ThemeIcon } from "@mantine/core";
import { IconVolume } from "@tabler/icons-react";
import { useEffect, useMemo, useRef, useState } from "react";
import type { ExplorePostMediaItem, ExploreReferenceImage } from "@/lib/explore";
import { buildExploreVisualSlides } from "@/lib/exploreVisualMedia";
import { ExploreBoostedAudio } from "@/components/ExploreBoostedAudio";

type ExploreMediaCarouselProps = {
  mediaItems: ExplorePostMediaItem[];
  heroImageUrl: string | null;
  referenceImages: ExploreReferenceImage[];
  altText: string;
  postId: string;
};

export function ExploreMediaCarousel({
  mediaItems,
  heroImageUrl,
  referenceImages,
  altText,
  postId,
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
    <Box style={{ position: "relative", width: "100%", aspectRatio: "1 / 1", overflow: "hidden" }}>
      <Carousel
        withIndicators={slides.length > 1}
        withControls={slides.length > 1}
        height="100%"
        style={{ position: "absolute", inset: 0 }}
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
                loop
                autoPlay={index === activeIndex}
                preload="metadata"
                style={{ width: "100%", height: "100%", objectFit: "cover", display: "block", background: "black" }}
              >
                Your browser does not support video playback.
              </video>
            ) : slide.kind === "audio" ? (
              <>
                {slide.spectrogramUrl ? (
                  <Image
                    src={slide.spectrogramUrl}
                    alt={`Spectrogram for ${altText}`}
                    h="100%"
                    w="100%"
                    fit="cover"
                    fallbackSrc="/image-placeholder.svg"
                  />
                ) : (
                  <Center h="100%" style={{ background: "linear-gradient(145deg, var(--mantine-color-blue-1), var(--mantine-color-indigo-3))" }}>
                    <ThemeIcon size={80} radius="xl" variant="light" aria-hidden="true">
                      <IconVolume size={40} />
                    </ThemeIcon>
                  </Center>
                )}
                <Box
                  style={{
                    position: "absolute",
                    left: 0,
                    right: 0,
                    bottom: slides.length > 1 ? 28 : 0,
                    padding: "48px 16px 16px",
                    background: "linear-gradient(to top, rgba(0,0,0,0.78), rgba(0,0,0,0))",
                    zIndex: 2,
                  }}
                >
                  <ExploreBoostedAudio audioUrl={slide.url} postId={postId} altText={altText} />
                </Box>
              </>
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
