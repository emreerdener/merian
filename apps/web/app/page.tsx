import type { Metadata } from "next";
import Image from "next/image";
import {
  Badge,
  Box,
  Container,
  Group,
  Stack,
  Text,
  Title
} from "@mantine/core";
import { IconLeaf } from "@tabler/icons-react";
import { WaitlistForm } from "@/components/WaitlistForm";

export const metadata: Metadata = {
  title: "Merian Beta Waitlist",
  description:
    "Join the Merian beta group for early access to ecological discovery tools built for the field."
};

export default function HomePage() {
  return (
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
  );
}

