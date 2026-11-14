import type { Metadata } from "next";
import {
  Anchor,
  Box,
  Button,
  Container,
  Group,
  SimpleGrid,
  Stack,
  Text,
  Title,
} from "@mantine/core";
import { IconArrowDown, IconArrowUpRight } from "@tabler/icons-react";
import { WaitlistForm } from "@/components/WaitlistForm";
import { ExploreHero } from "@/components/ExploreHero";
import { HomeFeatures } from "@/components/HomeFeatures";
import { HeroDots } from "@/components/HeroDots";
import { fetchExploreFeedPosts } from "@/lib/explore";
import { siteConfig } from "@/lib/site";

export const metadata: Metadata = {
  alternates: { canonical: "/about" },
  title: "About Naturebook",
  description:
    "Meet nearby nature with Naturebook. Identify living things, keep your discoveries, explore shared observations, and join the beta.",
};

const journey = [
  {
    title: "Something catches your eye",
    description:
      "A leaf, a wing, a sound. Start with whatever makes you stop and wonder. No big adventure required.",
  },
  {
    title: "Make it a discovery",
    description:
      "Use Naturebook to help identify it. Keep a photo and a field note so you can come back to what you found.",
  },
  {
    title: "Share a little of your world",
    description:
      "Choose which observations to post publicly. Your everyday find can be the start of someone else’s curiosity.",
  },
];

export default async function AboutPage({
  searchParams,
}: {
  searchParams: Promise<{ hero?: string }>;
}) {
  const variant = (await searchParams).hero === "mesh" ? "mesh" : "radial";
  const posts = fetchExploreFeedPosts(24).catch(() => []);
  const ctaHref = siteConfig.appStoreUrl ?? "#waitlist";
  const ctaLabel = siteConfig.appStoreUrl
    ? "Download Naturebook"
    : "Join the beta";

  return (
    <Box className="home-page">
      <section
        className="home-hero home-hero--centered"
        aria-labelledby="home-title"
        data-hero-variant={variant}
      >
        <HeroDots />
        <Container size="xl" className="home-hero__inner">
          <Stack gap="lg" className="home-hero__copy">
            <Title order={1} id="home-title" className="home-title">
              Identify the natural world around you
            </Title>
          </Stack>
          <ExploreHero
            variant={variant}
            images={posts.then((items) =>
              items.flatMap((post) => {
                const poster = `/api/explore/poster/${post.postId}`;
                return poster ? [poster] : [];
              })
            )}
          />
        </Container>
        <a
          className="home-hero__next"
          href="#features"
          aria-label="Explore Naturebook features"
        >
          <IconArrowDown size={20} />
        </a>
      </section>

      <HomeFeatures />

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
            Small discoveries, lasting connections
          </Title>
          <Text>
            Naturebook helps you learn about the living world around you, keep
            your discoveries, and connect through what you notice.
          </Text>
        </div>
        <SimpleGrid cols={{ base: 1, sm: 3 }} spacing="lg" mt="xl">
          {journey.map((step) => (
            <article className="home-journey" key={step.title}>
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
            <Text className="home-eyebrow">
              Your next discovery starts here
            </Text>
            <Title order={2} id="invitation-title" className="home-heading">
              Take a closer look
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
        </div>
      </Container>
    </Box>
  );
}
