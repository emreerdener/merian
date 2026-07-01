import type { Metadata } from "next";
import Image from "next/image";
import {
  Anchor,
  Badge,
  Box,
  Card,
  Container,
  Group,
  SimpleGrid,
  Stack,
  Text,
  Title,
} from "@mantine/core";
import { IconLeaf } from "@tabler/icons-react";
import { WaitlistForm } from "@/components/WaitlistForm";
import { fetchExploreFeedPosts } from "@/lib/explore";

export const metadata: Metadata = {
  title: "Merian Beta Waitlist",
  description:
    "Join the Merian beta group for early access to ecological discovery tools built for the field.",
};

export default async function HomePage() {
  const posts = await fetchExploreFeedPosts(16);

  return (
    <Stack gap={0}>
      <Box className="splash-page">
        <Container size="lg" className="splash-page__inner">
          <Stack gap="xl" className="splash-page__copy">
            <Stack gap="md">
              <Badge
                className="splash-eyebrow"
                variant="light"
                leftSection={<IconLeaf size={14} />}
              >
                Beta group now forming
              </Badge>
              <Title order={1} className="splash-title">
                Merian
              </Title>
              <Text className="splash-lede">
                A field companion for curious naturalists: identify living things,
                keep context with every observation, and help shape the public
                Explore community before launch.
              </Text>
            </Stack>

            <WaitlistForm />

            <Group gap="lg" className="splash-proof">
              <Text component="span">Early iOS access</Text>
              <Text component="span">Field notes</Text>
              <Text component="span">Privacy-first sharing</Text>
            </Group>
          </Stack>

          <Box className="splash-art" aria-hidden="true">
            <Image
              src="/assets/waitlist/explore-base.png"
              alt="Merian app interface on mobile screen showing field observations"
              width={901}
              height={901}
              priority
              sizes="(max-width: 768px) 86vw, 46vw"
            />
          </Box>
        </Container>
      </Box>

      {/* Explore Feed 4x4 Grid Section */}
      <Container size="lg" py={{ base: "xl", md: "50px" }}>
        <Stack gap="xl">
          <Stack gap="xs">
            <Title order={2} size="h2" fw={800}>
              Community Discoveries
            </Title>
            <Text c="dimmed" size="md">
              Recent observations shared by naturalists in the field. Tap any discovery to explore details.
            </Text>
          </Stack>

          {posts.length ? (
            <SimpleGrid cols={{ base: 2, sm: 3, md: 4 }} spacing="md">
              {posts.map((post) => (
                <Anchor
                  key={post.postId}
                  href={`/explore/post/${post.postId}`}
                  style={{ textDecoration: "none", color: "inherit" }}
                >
                  <Card
                    p={0}
                    radius="lg"
                    withBorder
                    className="explore-grid-card"
                    shadow="none"
                  >
                    <Box style={{ position: "relative", paddingTop: "100%", overflow: "hidden" }}>
                      <img
                        src={post.heroImageUrl}
                        alt={post.speciesCommonName || "Observation"}
                        className="explore-grid-image"
                      />
                      <Box className="explore-grid-overlay">
                        <Text size="sm" fw={700} truncate>
                          {post.speciesCommonName || "Unknown Species"}
                        </Text>
                        <Text size="xs" style={{ opacity: 0.8 }} truncate>
                          {post.speciesScientificName ? post.speciesScientificName : "Explore species"}
                        </Text>
                      </Box>
                    </Box>
                  </Card>
                </Anchor>
              ))}
            </SimpleGrid>
          ) : (
            <Text c="dimmed" ta="center" py="xl">
              No recent discoveries found. Check back later!
            </Text>
          )}
        </Stack>
      </Container>
    </Stack>
  );
}
