"use client";

import { Carousel } from "@mantine/carousel";
import { Badge, Box, Group, Image, Text } from "@mantine/core";

type ImageCarouselProps = {
  heroImageUrl: string;
  referenceImages: Array<{ url: string; source: string }>;
  altText: string;
};

export function ImageCarousel({
  heroImageUrl,
  referenceImages,
  altText,
}: ImageCarouselProps) {
  // Combine user image and reference images
  const slides = [
    { url: heroImageUrl, isHero: true, source: "" },
    ...referenceImages.map((img) => ({ url: img.url, isHero: false, source: img.source })),
  ];

  return (
    <Box style={{ position: "relative", width: "100%", height: 600, overflow: "hidden" }}>
      <Carousel
        withIndicators
        height="100%"
        emblaOptions={{
          loop: true,
          align: "start",
          slidesToScroll: 1,
        }}
      >
        {slides.map((slide, index) => (
          <Carousel.Slide key={`${slide.url}-${index}`} style={{ position: "relative", height: "100%" }}>
            <Image
              src={slide.url}
              alt={`${altText} - Slide ${index + 1}`}
              h={600}
              w="100%"
              fit="cover"
              fallbackSrc="/image-placeholder.svg"
            />
            {!slide.isHero && (
              <Box
                style={{
                  position: "absolute",
                  bottom: 0,
                  left: 0,
                  right: 0,
                  padding: "16px",
                  background: "linear-gradient(to top, rgba(0,0,0,0.85) 0%, rgba(0,0,0,0.4) 60%, rgba(0,0,0,0) 100%)",
                  display: "flex",
                  justifyContent: "space-between",
                  alignItems: "center",
                  color: "white",
                  zIndex: 2,
                }}
              >
                <Text size="xs" fw={700} style={{ letterSpacing: "0.5px" }}>
                  REFERENCE IMAGE
                </Text>
                <Group gap={6} align="center">
                  <Badge
                    size="xs"
                    variant="filled"
                    style={{
                      backgroundColor: "var(--mantine-color-text)",
                      color: "var(--mantine-color-body)",
                    }}
                  >
                    {slide.source.toUpperCase()}
                  </Badge>
                </Group>
              </Box>
            )}
          </Carousel.Slide>
        ))}
      </Carousel>
    </Box>
  );
}
