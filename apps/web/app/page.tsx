import type { Metadata } from "next";
import Image from "next/image";
import {
  Anchor,
  Box,
  Button,
  Card,
  Container,
  Group,
  SimpleGrid,
  Stack,
  Text,
  Title,
} from "@mantine/core";
import {
  IconArrowDown,
  IconArrowUpRight,
  IconLeaf,
  IconVolume,
} from "@tabler/icons-react";
import { WaitlistForm } from "@/components/WaitlistForm";
import { fetchExploreFeedPosts } from "@/lib/explore";
import { exploreGridPosterUrl } from "@/lib/exploreMedia";
import { siteConfig } from "@/lib/site";

export const metadata: Metadata = {
  title: "Discover the nature around you",
  description:
    "Meet nearby nature with Naturebook. Identify living things, keep your discoveries, explore shared observations, and join the beta.",
};

const journey = [
  {
    image: "compass",
    title: "Something catches your eye.",
    description:
      "A leaf, a wing, a sound. Start with whatever makes you stop and wonder. No big adventure required.",
  },
  {
    image: "camera",
    title: "Make it a discovery.",
    description:
      "Use Naturebook to help identify it. Keep a photo and a field note so you can come back to what you found.",
  },
  {
    image: "journal-open",
    title: "Share a little of your world.",
    description:
      "Choose which observations to post publicly. Your everyday find can be the start of someone else’s curiosity.",
  },
];

export default async function HomePage() {
  const posts = await fetchExploreFeedPosts(24);
  const ctaHref = siteConfig.appStoreUrl ?? "#waitlist";
  const ctaLabel = siteConfig.appStoreUrl
    ? "Download Naturebook"
    : "Join the Naturebook beta";

  return (
    <Box className="home-page">
      <section className="home-hero" aria-labelledby="home-title">
        <Container size="xl" className="home-hero__inner">
          <Stack gap="lg" className="home-hero__copy">
            <Text className="home-eyebrow">
              <IconLeaf size={17} aria-hidden="true" />{" "}
              A little curiosity goes a long way
            </Text>
            <Title order={1} id="home-title" className="home-title">
              Go outside.<br />Get <em>curious.</em>
            </Title>
            <Text className="home-hero__lede">
              Your world is wilder than you think.
            </Text>
            <Text className="home-hero__description">
              Meet the bird on your fence. Get to know that funny-looking fern.
              Turn “what is that?” into a discovery worth keeping with
              Naturebook.
            </Text>
            <Group gap="lg" mt="sm">
              <Button
                component="a"
                href={ctaHref}
                size="lg"
                className="home-primary"
                rightSection={<IconArrowUpRight size={19} />}
              >
                {ctaLabel}
              </Button>
              <Anchor href="#explore" className="home-text-link">
                Explore discoveries <IconArrowDown size={18} />
              </Anchor>
            </Group>
            <Text size="sm" className="home-hero__footnote">
              A companion for your next walk, and every little wonder along the
              way.
            </Text>
          </Stack>
          <Box className="home-hero__art" aria-hidden="true">
            <span className="home-hero__orbit" />
            <Image
              className="home-hero__phone"
              src="/assets/waitlist/sweet-acacia-mockup.png"
              alt=""
              width={1000}
              height={2000}
              priority
              unoptimized
              sizes="(max-width: 768px) 75vw, 34vw"
            />
            <Image
              className="home-hero__frog"
              src="/assets/naturebook/frog.png"
              alt=""
              width={240}
              height={240}
              unoptimized
            />
            <span className="home-hero__sticker">
              Oh, hey<br />nature. ↗
            </span>
            <span className="home-hero__caption">
              A closer look, in the app.
            </span>
          </Box>
        </Container>
      </section>

      <div className="home-ribbon" aria-hidden="true">
        Little things. <IconLeaf size={22} /> Big discoveries.
      </div>

      <Container
        component="section"
        size="xl"
        className="home-section"
        id="explore"
        aria-labelledby="discover-title"
      >
        <div className="home-section-heading">
          <div>
            <Text className="home-eyebrow">Community discoveries</Text>
            <Title order={2} id="discover-title" className="home-heading">
              Everyday wonders.<br />
              <em>Worth a closer look.</em>
            </Title>
          </div>
          <Text className="home-section-description">
            A garden visitor. A lunchtime surprise. Explore recent public
            observations from the Naturebook community.
          </Text>
        </div>
        {posts.length
          ? (
            <SimpleGrid cols={{ base: 1, xs: 2, md: 3, lg: 4 }} spacing="lg">
              {posts.map((post) => {
                const poster = exploreGridPosterUrl(post);
                return (
                  <Anchor
                    key={post.postId}
                    href={`/explore/post/${post.postId}`}
                    underline="never"
                    c="inherit"
                    className="home-observation-link"
                  >
                    <Card
                      p={0}
                      radius="lg"
                      withBorder
                      className="explore-grid-card"
                      h="100%"
                    >
                      <Box className="explore-grid-media">
                        {poster
                          ? (
                            <img
                              src={poster}
                              alt={post.speciesCommonName ||
                                "Shared observation"}
                              className="explore-grid-image"
                              loading="lazy"
                              decoding="async"
                            />
                          )
                          : (
                            <Box
                              className="explore-grid-fallback"
                              aria-label="Audio observation"
                            >
                              <IconVolume size={48} aria-hidden="true" />
                            </Box>
                          )}
                        <span
                          className="explore-grid-action"
                          aria-hidden="true"
                        >
                          <IconArrowUpRight size={20} />
                        </span>
                      </Box>
                      <Stack gap={5} p="md">
                        <Text fw={750} lineClamp={2}>
                          {post.speciesCommonName || "An everyday discovery"}
                        </Text>
                        {post.speciesScientificName && (
                          <Text size="sm" c="dimmed" fs="italic" truncate>
                            {post.speciesScientificName}
                          </Text>
                        )}
                        <Text size="xs" c="dimmed" mt="xs" truncate>
                          Shared by {post.authorName || "a Naturebook observer"}
                        </Text>
                      </Stack>
                    </Card>
                  </Anchor>
                );
              })}
            </SimpleGrid>
          )
          : (
            <Box className="home-empty">
              <Image
                src="/assets/naturebook/compass.png"
                alt=""
                width={110}
                height={110}
                unoptimized
              />
              <Title order={3}>There’s always more to discover.</Title>
              <Text c="dimmed">
                No public discoveries to show right now. Come back soon to see
                what people are finding.
              </Text>
            </Box>
          )}
      </Container>

      <Container
        component="section"
        size="xl"
        className="home-section home-about"
        id="about"
        aria-labelledby="about-title"
      >
        <div className="home-about__intro">
          <Text className="home-eyebrow">Follow your curiosity</Text>
          <Title order={2} id="about-title" className="home-heading">
            Small finds.<br />
            <em>A bigger picture.</em>
          </Title>
          <Text>
            Naturebook helps you learn about the living world around you, keep
            your discoveries, and connect through what you notice.
          </Text>
        </div>
        <SimpleGrid cols={{ base: 1, sm: 3 }} spacing="lg" mt="xl">
          {journey.map((step, index) => (
            <article className="home-journey" key={step.image}>
              <div className="home-journey__art">
                <span>0{index + 1}</span>
                <Image
                  src={`/assets/naturebook/${step.image}.png`}
                  alt=""
                  width={240}
                  height={220}
                  unoptimized
                />
              </div>
              <Title order={3}>{step.title}</Title>
              <Text>{step.description}</Text>
            </article>
          ))}
        </SimpleGrid>
        <Text className="home-sharing-note">
          Keeping a record and publishing a community post are different
          choices. Submitted scans also contribute Scientific Data under
          Naturebook’s terms.{" "}
          <Anchor href="/privacy-choices">
            Read about sharing and data choices <IconArrowUpRight size={14} />
          </Anchor>
        </Text>
      </Container>

      <Container
        component="section"
        size="xl"
        className="home-section home-invitation"
        aria-labelledby="invitation-title"
      >
        <div className="home-invitation__panel">
          <Stack gap="lg" className="home-invitation__copy">
            <Text className="home-eyebrow">Go on. See what you find.</Text>
            <Title order={2} id="invitation-title" className="home-heading">
              Your next walk<br />just got interesting.
            </Title>
            <Text>
              Learn the names. Keep the moments. Get to know a whole world
              that’s right under your nose.
            </Text>
            {siteConfig.appStoreUrl
              ? (
                <Button
                  component="a"
                  href={siteConfig.appStoreUrl}
                  size="lg"
                  radius="xl"
                  className="header-cta-button"
                  w="fit-content"
                >
                  Download Naturebook
                </Button>
              )
              : (
                <>
                  <Text fw={650}>Join the beta for early access.</Text>
                  <WaitlistForm />
                </>
              )}
          </Stack>
          <Image
            className="home-invitation__art"
            src="/assets/naturebook/nature-scene.png"
            alt=""
            width={560}
            height={560}
            unoptimized
          />
        </div>
      </Container>
    </Box>
  );
}
