import type { Metadata } from "next";
import { notFound } from "next/navigation";
import type { ComponentType, ReactNode } from "react";
import {
  Avatar,
  Badge,
  Button,
  Card,
  Container,
  Divider,
  Group,
  Image,
  SimpleGrid,
  Stack,
  Text,
  ThemeIcon,
  Title,
} from "@mantine/core";
import {
  IconArrowUpRight,
  IconBook,
  IconCalendar,
  IconCloud,
  IconHeart,
  IconMapPin,
  IconMessageCircle,
  IconNotes,
  IconPhoto,
  IconSparkles,
  IconTag,
} from "@tabler/icons-react";
import {
  fetchExplorePost,
  fetchExplorePostPage,
  type ExplorePost,
} from "@/lib/explore";
import {
  compactSpeciesTitle,
  nativeExplorePostUrl,
  postTitle,
} from "@/lib/formatting";

type ExplorePostPageProps = {
  params: Promise<{
    postId: string;
  }>;
};

type ObservationRow = {
  icon: ComponentType<{ size?: number }>;
  label: string;
  value: string;
};

export const revalidate = 300;

export async function generateMetadata({
  params,
}: ExplorePostPageProps): Promise<Metadata> {
  const { postId } = await params;
  const post = await fetchExplorePost(postId);

  if (!post) {
    return {
      title: "Discovery not found",
      robots: {
        index: false,
        follow: false,
      },
    };
  }

  const title = postTitle(post.speciesCommonName, post.publicLocationLabel);
  const description = compactSpeciesTitle(
    post.speciesCommonName,
    post.speciesScientificName,
  );
  const canonicalPath = `/explore/post/${post.postId}`;

  return {
    title,
    description: `${description} shared on Merian.`,
    alternates: {
      canonical: canonicalPath,
    },
    openGraph: {
      type: "article",
      title,
      description: `${description} shared on Merian.`,
      url: canonicalPath,
      siteName: "Merian",
      images: [
        {
          url: post.heroImageUrl,
          alt: title,
        },
      ],
    },
    twitter: {
      card: "summary_large_image",
      title,
      description: `${description} shared on Merian.`,
      images: [post.heroImageUrl],
    },
  };
}

export default async function ExplorePostPage({ params }: ExplorePostPageProps) {
  const { postId } = await params;
  const data = await fetchExplorePostPage(postId);

  if (!data) {
    notFound();
  }

  const { post, detail } = data;
  const title = postTitle(post.speciesCommonName, post.publicLocationLabel);
  const speciesLabel = compactSpeciesTitle(
    post.speciesCommonName,
    post.speciesScientificName,
  );
  const appStoreUrl = process.env.NEXT_PUBLIC_APP_STORE_URL;
  const hashtags = detail?.hashtags.length ? detail.hashtags : post.hashtags;
  const observationRows = buildObservationRows(post);
  const conservationStatus = normalizedIucnStatus(detail?.iucnRedListStatus);
  const hasOverview = Boolean(conservationStatus || detail?.wikipediaOverview);
  const authorLabel = post.authorUsername
    ? `@${post.authorUsername}`
    : "Shared on Merian";

  return (
    <Container size="lg" py={{ base: "md", sm: "xl" }}>
      <Stack gap="lg">
        <Card withBorder shadow="sm" radius="md" p={0}>
          <Card.Section>
            <Image
              src={post.heroImageUrl}
              alt={title}
              fit="cover"
              mah={680}
              fallbackSrc="/image-placeholder.svg"
            />
          </Card.Section>

          <Stack gap="lg" p={{ base: "md", sm: "xl" }}>
            <Group justify="space-between" align="flex-start" gap="md">
              <Group gap="sm">
                <Avatar
                  src={post.authorAvatarUrl}
                  alt={post.authorName}
                  radius="xl"
                  size="md"
                />
                <Stack gap={2}>
                  <Group gap="xs">
                    <Text fw={700}>{post.authorName}</Text>
                    {post.authorIsPro ? <Badge size="xs">Pro</Badge> : null}
                  </Group>
                  <Text size="sm" c="dimmed">
                    {authorLabel}
                  </Text>
                </Stack>
              </Group>

              <Group gap="xs">
                <Badge leftSection={<IconHeart size={13} />} variant="light">
                  {post.likeCount}
                </Badge>
                <Badge
                  leftSection={<IconMessageCircle size={13} />}
                  variant="light"
                  color="gray"
                >
                  {post.commentCount}
                </Badge>
              </Group>
            </Group>

            <Stack gap="xs" align="center">
              <Text fw={700} c="dimmed" tt="uppercase" size="xs">
                Merian Explore
              </Text>
              <Title order={1} ta="center">
                {post.speciesCommonName || title}
              </Title>
              {post.speciesScientificName ? (
                <Text size="lg" c="dimmed" fs="italic" ta="center">
                  {post.speciesScientificName}
                </Text>
              ) : null}
              {detail?.aiReasoning ? (
                <Text maw={760} ta="center">
                  {detail.aiReasoning}
                </Text>
              ) : null}
            </Stack>

            {hashtags.length ? (
              <Group justify="center" gap="xs">
                {hashtags.map((tag) => (
                  <Badge
                    key={tag}
                    variant="light"
                    leftSection={<IconTag size={12} />}
                  >
                    {tag}
                  </Badge>
                ))}
              </Group>
            ) : null}

            <Group justify="center">
              <Button
                component="a"
                href={nativeExplorePostUrl(post.postId)}
                rightSection={<IconArrowUpRight size={18} />}
              >
                Open in Merian
              </Button>
              {appStoreUrl ? (
                <Button component="a" href={appStoreUrl} variant="light">
                  Get the app
                </Button>
              ) : (
                <Button component="a" href="/" variant="light">
                  Join the beta
                </Button>
              )}
            </Group>
          </Stack>
        </Card>

        {detail?.fieldNotes ? (
          <InfoCard icon={IconNotes} title="Field notes">
            <Text>{detail.fieldNotes}</Text>
          </InfoCard>
        ) : null}

        {detail?.referenceImages.length ? (
          <InfoCard icon={IconPhoto} title="Reference images">
            <SimpleGrid cols={{ base: 1, sm: 2, md: 3 }} spacing="md">
              {detail.referenceImages.map((image) => (
                <Card key={image.url} withBorder radius="md" p="xs">
                  <Card.Section>
                    <Image
                      src={image.url}
                      alt={`${speciesLabel} reference image`}
                      h={220}
                      fit="cover"
                      fallbackSrc="/image-placeholder.svg"
                    />
                  </Card.Section>
                  <Group justify="space-between" mt="sm">
                    <Text size="sm" fw={600}>
                      Source
                    </Text>
                    <Badge variant="light">{image.source}</Badge>
                  </Group>
                </Card>
              ))}
            </SimpleGrid>
          </InfoCard>
        ) : null}

        {hasOverview ? (
          <InfoCard icon={IconBook} title="Overview">
            <Stack gap="md">
              {conservationStatus ? (
                <KeyValueRow
                  label="Conservation"
                  value={conservationStatus}
                />
              ) : null}
              {detail?.wikipediaOverview ? (
                <Text>{detail.wikipediaOverview}</Text>
              ) : null}
              {detail?.wikipediaUrl ? (
                <Button
                  component="a"
                  href={detail.wikipediaUrl}
                  target="_blank"
                  rel="noreferrer"
                  variant="light"
                  w="fit-content"
                  rightSection={<IconArrowUpRight size={16} />}
                >
                  Read source
                </Button>
              ) : null}
            </Stack>
          </InfoCard>
        ) : null}

        {observationRows.length ? (
          <InfoCard icon={IconSparkles} title="Observation">
            <SimpleGrid cols={{ base: 1, sm: 2 }} spacing="md">
              {observationRows.map((row) => (
                <Group key={`${row.label}-${row.value}`} gap="sm" wrap="nowrap">
                  <ThemeIcon variant="light" radius="xl" size="lg">
                    <row.icon size={18} />
                  </ThemeIcon>
                  <Stack gap={0}>
                    <Text size="xs" c="dimmed" tt="uppercase" fw={700}>
                      {row.label}
                    </Text>
                    <Text fw={600}>{row.value}</Text>
                  </Stack>
                </Group>
              ))}
            </SimpleGrid>
          </InfoCard>
        ) : null}

        {detail?.alternativeCommonNames.length ? (
          <InfoCard icon={IconTag} title="Also known as">
            <Group gap="xs">
              {detail.alternativeCommonNames.map((name) => (
                <Badge key={name} variant="default">
                  {name}
                </Badge>
              ))}
            </Group>
          </InfoCard>
        ) : null}

        {detail?.taxonomy.length ? (
          <InfoCard icon={IconBook} title="Taxonomy">
            <Stack gap="sm">
              {detail.taxonomy.map((row, index) => (
                <Stack key={`${row.label}-${row.value}`} gap="sm">
                  {index > 0 ? <Divider /> : null}
                  <KeyValueRow label={row.label} value={row.value} />
                </Stack>
              ))}
            </Stack>
          </InfoCard>
        ) : null}
      </Stack>
    </Container>
  );
}

function InfoCard({
  icon: Icon,
  title,
  children,
}: {
  icon: ComponentType<{ size?: number }>;
  title: string;
  children: ReactNode;
}) {
  return (
    <Card withBorder shadow="sm" radius="md" p={{ base: "md", sm: "lg" }}>
      <Stack gap="md">
        <Group gap="sm">
          <ThemeIcon variant="light" radius="xl" size="lg">
            <Icon size={18} />
          </ThemeIcon>
          <Title order={2} size="h3">
            {title}
          </Title>
        </Group>
        {children}
      </Stack>
    </Card>
  );
}

function KeyValueRow({ label, value }: { label: string; value: string }) {
  return (
    <Group justify="space-between" align="flex-start" gap="md">
      <Text size="xs" c="dimmed" tt="uppercase" fw={700}>
        {label}
      </Text>
      <Text fw={600} ta="right">
        {value}
      </Text>
    </Group>
  );
}

function buildObservationRows(post: ExplorePost) {
  const rows: ObservationRow[] = [];

  if (post.publicLocationLabel) {
    rows.push({
      icon: IconMapPin,
      label: "Location",
      value: post.publicLocationLabel,
    });
  }

  const observed = observationContext(post.currentMonth, post.timeOfDay);
  if (observed) {
    rows.push({
      icon: IconCalendar,
      label: "Observed",
      value: observed,
    });
  }

  const weather = weatherLabel(post.weatherCondition, post.weatherTemperatureF);
  if (weather) {
    rows.push({
      icon: IconCloud,
      label: "Weather",
      value: weather,
    });
  }

  const shared = sharedDateLabel(post.sharedAt);
  if (shared) {
    rows.push({
      icon: IconCalendar,
      label: "Shared",
      value: shared,
    });
  }

  return rows;
}

function observationContext(month?: number | null, timeOfDay?: string | null) {
  const monthName = month ? monthNames[month - 1] : null;
  const cleanTime = timeOfDay?.trim();

  if (monthName && cleanTime) {
    return `${monthName}, ${cleanTime}`;
  }

  return monthName ?? cleanTime ?? null;
}

function weatherLabel(
  condition?: string | null,
  temperature?: number | null,
) {
  const cleanCondition = condition?.trim();
  const cleanTemperature = typeof temperature === "number" && Number.isFinite(temperature)
    ? `${Math.round(temperature)}F`
    : null;

  if (cleanCondition && cleanTemperature) {
    return `${cleanCondition}, ${cleanTemperature}`;
  }

  return cleanCondition ?? cleanTemperature;
}

function sharedDateLabel(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return null;
  }

  return new Intl.DateTimeFormat("en", {
    month: "long",
    day: "numeric",
    year: "numeric",
  }).format(date);
}

function normalizedIucnStatus(value?: string | null) {
  const normalized = value?.trim().toLowerCase().replaceAll("_", " ");
  if (
    !normalized ||
    normalized === "not applicable" ||
    normalized === "data deficient"
  ) {
    return null;
  }

  if (normalized.includes("not evaluated")) return "Not evaluated";
  if (normalized.includes("least concern")) return "Not at risk";
  if (normalized.includes("near threatened")) return "Near threatened";
  if (normalized.includes("critically endangered")) {
    return "Critically endangered";
  }
  if (normalized.includes("endangered")) return "Endangered";
  if (normalized.includes("vulnerable")) return "Vulnerable";
  if (normalized.includes("extinct in the wild")) return "Extinct in the wild";
  if (normalized.includes("extinct")) return "Extinct";

  return normalized.charAt(0).toUpperCase() + normalized.slice(1);
}

const monthNames = [
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December",
];
