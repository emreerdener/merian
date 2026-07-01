import type { Metadata } from "next";
import { notFound } from "next/navigation";
import type { ReactNode } from "react";
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
  fetchExplorePost,
  fetchExplorePostPage,
  type ExplorePost,
} from "@/lib/explore";
import { compactSpeciesTitle, postTitle } from "@/lib/formatting";
import {
  IconAlertTriangle,
  IconCalendar,
  IconCloud,
  IconBinoculars,
  IconMapPin,
  IconUser,
} from "@tabler/icons-react";

type ExplorePostPageProps = {
  params: Promise<{
    postId: string;
  }>;
};

type ObservationRow = {
  symbol: string;
  label: string;
  value: string;
};

export const revalidate = 300;

// MARK: - Metadata Generation
export async function generateMetadata({
  params,
}: ExplorePostPageProps): Promise<Metadata> {
  const { postId } = await params;
  let post: ExplorePost | null = null;
  try {
    post = await fetchExplorePost(postId);
  } catch (error) {
    console.error("explore_post_metadata_fetch_failed", {
      post_id: postId,
      error: error instanceof Error ? error.message : String(error),
    });
  }

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

// MARK: - Page Component
export default async function ExplorePostPage({
  params,
}: ExplorePostPageProps) {
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
  const hashtags = detail?.hashtags.length ? detail.hashtags : post.hashtags;
  const observationRows = buildObservationRows(post);
  const conservationStatus = normalizedIucnStatus(detail?.iucnRedListStatus);
  const hasOverview = Boolean(conservationStatus || detail?.wikipediaOverview);

  const hazardType = detail?.hazardType?.trim().toLowerCase() || "none";
  let hazardTitle = "Toxic";
  let hazardSubtitle = "This species may be harmful. Avoid physical contact.";
  let hazardColor = "yellow";

  if (hazardType === "venomous") {
    hazardTitle = "Venomous";
    hazardSubtitle = "Can inject venom through bite or sting. Do not handle.";
    hazardColor = "red";
  } else if (hazardType === "poisonous") {
    hazardTitle = "Toxic";
    hazardSubtitle = "This species may be harmful. Avoid physical contact.";
    hazardColor = "red";
  } else if (hazardType === "allergenic") {
    hazardTitle = "Allergenic";
    hazardSubtitle =
      "May trigger severe allergic reactions in some individuals.";
    hazardColor = "yellow";
  } else if (hazardType === "irritant") {
    hazardTitle = "Irritant";
    hazardSubtitle = "May cause skin or eye irritation on contact.";
    hazardColor = "yellow";
  }

  return (
    <Container size="sm" py={{ base: "md", sm: "xl" }}>
      <Stack gap="lg">
        <Card withBorder shadow="sm" radius="lg" p={0}>
          <Image
            src={post.heroImageUrl}
            alt={title}
            fit="cover"
            mah={600}
            fallbackSrc="/image-placeholder.svg"
          />

          <Stack gap="lg" p={{ base: "md", sm: "xl" }}>
            <Group justify="space-between" align="flex-start" gap="md">
              <Group gap="sm">
                <Avatar
                  src={post.authorAvatarUrl || undefined}
                  alt={post.authorName}
                  radius="xl"
                  size="md"
                >
                  <IconUser size={18} />
                </Avatar>
                <Stack gap={2}>
                  <Group gap="xs">
                    <Text fw={700}>
                      {post.authorUsername
                        ? `@${post.authorUsername}`
                        : post.authorName}
                    </Text>
                    {post.authorIsPro ? (
                      <Badge
                        size="xs"
                        variant="filled"
                        style={{
                          backgroundColor: "var(--mantine-color-text)",
                          color: "var(--mantine-color-body)",
                        }}
                      >
                        Pro
                      </Badge>
                    ) : null}
                  </Group>
                  {post.publicLocationLabel ? (
                    <Text size="sm" c="dimmed">
                      {post.publicLocationLabel}
                    </Text>
                  ) : null}
                </Stack>
              </Group>

              <Group gap="xs">
                <Badge variant="default">{post.likeCount} likes</Badge>
                <Badge variant="default">{post.commentCount} comments</Badge>
              </Group>
            </Group>

            <Stack gap="xs" align="center">
              <Stack gap={0} align="center">
                {post.speciesScientificName ? (
                  <Text size="lg" c="dimmed" fs="italic" ta="center">
                    {post.speciesScientificName}
                  </Text>
                ) : null}
                <Title order={1} ta="center">
                  {post.speciesCommonName || title}
                </Title>
              </Stack>
              {detail?.aiReasoning ? (
                <Text maw={760} ta="center">
                  {detail.aiReasoning}
                </Text>
              ) : null}
            </Stack>

            {hashtags.length ? (
              <Group justify="center" gap="xs">
                {hashtags.map((tag) => (
                  <Badge key={tag} variant="light">
                    {tag.startsWith("#") ? tag : `#${tag}`}
                  </Badge>
                ))}
              </Group>
            ) : null}

            {hazardType !== "none" ? (
              <Card
                withBorder
                radius="lg"
                p="md"
                shadow="none"
                style={{
                  backgroundColor: `var(--mantine-color-${hazardColor}-light)`,
                  maxWidth: 600,
                  width: "100%",
                  margin: "0 auto",
                }}
              >
                <Group gap="md" align="center" wrap="nowrap">
                  <ThemeIcon
                    variant="light"
                    color={hazardColor}
                    size="xl"
                    radius="md"
                  >
                    <IconAlertTriangle size={32} />
                  </ThemeIcon>
                  <Stack gap={2}>
                    <Text
                      size="xs"
                      fw={700}
                      style={{ letterSpacing: "1px" }}
                      tt="uppercase"
                      c={`${hazardColor}.8`}
                    >
                      Caution
                    </Text>
                    <Text fw={700} size="md">
                      {hazardTitle}
                    </Text>
                    <Text size="sm">{hazardSubtitle}</Text>
                  </Stack>
                </Group>
              </Card>
            ) : null}
          </Stack>
        </Card>

        {detail?.fieldNotes ? (
          <InfoCard title="Field notes">
            <Text>{detail.fieldNotes}</Text>
          </InfoCard>
        ) : null}

        {detail?.referenceImages.length ? (
          <InfoCard title="Reference images">
            <SimpleGrid cols={{ base: 1, sm: 2, md: 3 }} spacing="md">
              {detail.referenceImages.map((image) => (
                <Card key={image.url} withBorder radius="lg" p="xs">
                  <Image
                    src={image.url}
                    alt={`${speciesLabel} reference image`}
                    h={220}
                    fit="cover"
                    fallbackSrc="/image-placeholder.svg"
                    radius="lg"
                  />
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
          <InfoCard title="Overview">
            <Stack gap="md">
              {conservationStatus ? (
                <KeyValueRow label="Conservation" value={conservationStatus} />
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
                  variant="outline"
                  w="fit-content"
                >
                  Read source
                </Button>
              ) : null}
            </Stack>
          </InfoCard>
        ) : null}

        {observationRows.length ? (
          <InfoCard title="Observation">
            <SimpleGrid cols={{ base: 1, sm: 2 }} spacing="md">
              {observationRows.map((row) => {
                let iconNode = null;
                if (row.symbol === "L") {
                  iconNode = <IconMapPin size={18} />;
                } else if (row.symbol === "D") {
                  iconNode = <IconBinoculars size={18} />;
                } else if (row.symbol === "W") {
                  iconNode = <IconCloud size={18} />;
                } else if (row.symbol === "S") {
                  iconNode = <IconCalendar size={18} />;
                }

                return (
                  <Group
                    key={`${row.label}-${row.value}`}
                    gap="sm"
                    wrap="nowrap"
                  >
                    <ThemeIcon variant="default" radius="xl" size="lg">
                      {iconNode}
                    </ThemeIcon>
                    <Stack gap={0}>
                      <Text size="xs" c="dimmed" tt="uppercase" fw={700}>
                        {row.label}
                      </Text>
                      <Text fw={600}>{row.value}</Text>
                    </Stack>
                  </Group>
                );
              })}
            </SimpleGrid>
          </InfoCard>
        ) : null}

        {detail?.alternativeCommonNames.length ? (
          <InfoCard title="Also known as">
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
          <InfoCard title="Taxonomy">
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

// MARK: - Subcomponents
function InfoCard({ title, children }: { title: string; children: ReactNode }) {
  return (
    <Card withBorder shadow="sm" radius="lg" p={{ base: "md", sm: "lg" }}>
      <Stack gap="md">
        <Title order={2} size="h3">
          {title}
        </Title>
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

// MARK: - Helpers & Constants
function buildObservationRows(post: ExplorePost) {
  const rows: ObservationRow[] = [];

  if (post.publicLocationLabel) {
    rows.push({
      symbol: "L",
      label: "Location",
      value: post.publicLocationLabel,
    });
  }

  const observed = observationContext(post.currentMonth, post.timeOfDay);
  if (observed) {
    rows.push({
      symbol: "D",
      label: "Observed",
      value: observed,
    });
  }

  const weather = weatherLabel(post.weatherCondition, post.weatherTemperatureF);
  if (weather) {
    rows.push({
      symbol: "W",
      label: "Weather",
      value: weather,
    });
  }

  const shared = sharedDateLabel(post.sharedAt);
  if (shared) {
    rows.push({
      symbol: "S",
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

function weatherLabel(condition?: string | null, temperature?: number | null) {
  const cleanCondition = condition?.trim();
  const cleanTemperature =
    typeof temperature === "number" && Number.isFinite(temperature)
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
