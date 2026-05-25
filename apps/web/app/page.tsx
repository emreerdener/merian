import type { Metadata } from "next";
import Image from "next/image";
import {
  Badge,
  Box,
  Container,
  Group,
  SimpleGrid,
  Stack,
  Text,
  ThemeIcon,
  Title
} from "@mantine/core";
import {
  IconCamera,
  IconChartDots3,
  IconLeaf,
  IconMapPin,
  IconSparkles
} from "@tabler/icons-react";
import { WaitlistForm } from "@/components/WaitlistForm";

export const metadata: Metadata = {
  title: "Merian Beta Waitlist",
  description:
    "Join the Merian beta group for early access to ecological discovery tools built for the field."
};

const betaHighlights = [
  {
    icon: IconCamera,
    title: "Capture what you find",
    description:
      "Use photos, sound, and short field notes to turn everyday encounters into structured observations."
  },
  {
    icon: IconSparkles,
    title: "Review richer insights",
    description:
      "See candidate identifications, useful context, and prompts that help you notice the details that matter."
  },
  {
    icon: IconMapPin,
    title: "Share with care",
    description:
      "Control location privacy while contributing discoveries to a calmer public Explore feed."
  }
];

export default function HomePage() {
  return (
    <Box className="waitlist-page">
      <Box component="section" className="waitlist-hero">
        <Container size="lg" className="waitlist-hero__inner">
          <Stack gap="xl" className="waitlist-hero__copy">
            <Stack gap="md">
              <Badge
                className="waitlist-eyebrow"
                variant="light"
                leftSection={<IconLeaf size={14} />}
              >
                Beta group now forming
              </Badge>
              <Title order={1} className="waitlist-hero__title">
                Merian
              </Title>
              <Text className="waitlist-hero__lede">
                A field companion for curious naturalists: identify living things,
                keep context with every observation, and help shape the public
                Explore community before launch.
              </Text>
            </Stack>

            <WaitlistForm />

            <Group gap="lg" className="waitlist-proof">
              <Text component="span">Early iOS access</Text>
              <Text component="span">Field notes</Text>
              <Text component="span">Privacy-first sharing</Text>
            </Group>
          </Stack>

          <Box className="waitlist-hero__art" aria-hidden="true">
            <Image
              src="/assets/waitlist/explore-base.png"
              alt=""
              width={901}
              height={901}
              priority
              sizes="(max-width: 768px) 86vw, 46vw"
            />
          </Box>
        </Container>
      </Box>

      <Box component="section" className="waitlist-section waitlist-section--light">
        <Container size="lg">
          <SimpleGrid cols={{ base: 1, sm: 3 }} spacing="lg">
            {betaHighlights.map((item) => {
              const Icon = item.icon;

              return (
                <Stack key={item.title} gap="sm" className="waitlist-feature">
                  <ThemeIcon size={40} radius="xl" variant="light" color="green">
                    <Icon size={20} />
                  </ThemeIcon>
                  <Title order={2}>{item.title}</Title>
                  <Text c="dimmed">{item.description}</Text>
                </Stack>
              );
            })}
          </SimpleGrid>
        </Container>
      </Box>

      <Box component="section" className="waitlist-section waitlist-section--field">
        <Container size="lg">
          <SimpleGrid cols={{ base: 1, md: 2 }} spacing={{ base: "xl", md: 64 }}>
            <Stack gap="lg" justify="center">
              <Badge variant="filled" color="dark" w="fit-content">
                Built with beta testers
              </Badge>
              <Title order={2} className="waitlist-section__title">
                Help tune the app for real walks, gardens, coastlines, and backyards.
              </Title>
              <Text size="lg" c="dimmed">
                We are inviting a small group to test capture flows, insight quality,
                privacy defaults, and the public sharing experience. Join the list and
                we will reach out as beta seats open.
              </Text>
              <Group gap="xs">
                <ThemeIcon radius="xl" variant="light" color="teal">
                  <IconChartDots3 size={18} />
                </ThemeIcon>
                <Text fw={700}>Your feedback shapes the launch roadmap.</Text>
              </Group>
            </Stack>

            <Box className="waitlist-field-art" aria-hidden="true">
              <Image
                src="/assets/waitlist/heron.png"
                alt=""
                width={1313}
                height={1313}
                sizes="(max-width: 768px) 86vw, 38vw"
              />
            </Box>
          </SimpleGrid>
        </Container>
      </Box>
    </Box>
  );
}
