/* Idempotent seed: 3 placeholder vertical dramas x 6 episodes (HLS under backend/media). */
import { Prisma, PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

const TAGS = [
  { slug: 'romance', name: 'Romance' },
  { slug: 'family', name: 'Family' },
  { slug: 'comedy', name: 'Comedy' },
  { slug: 'drama', name: 'Drama' },
];

const DRAMAS = [
  { id: 'dr_mama', slug: 'mama-in-law-wahala', title: 'Mama-in-Law Wahala', tags: ['family', 'comedy'], description: 'A new bride versus the most formidable mother-in-law in Lagos.' },
  { id: 'dr_lagos', slug: 'lagos-hustle', title: 'Lagos Hustle', tags: ['drama'], description: 'Three friends, one city, endless hustle.' },
  { id: 'dr_prince', slug: 'village-prince', title: 'The Village Prince', tags: ['romance', 'drama'], description: 'A royal heir hides among villagers to find true love.' },
];

const EPISODES = 6;
// Fixed createdAt drives home/list ordering (createdAt desc): Mama-in-Law Wahala first.
const CREATED_AT: Record<string, string> = {
  dr_mama: '2026-10-03T00:00:00.000Z',
  dr_prince: '2026-10-02T00:00:00.000Z',
  dr_lagos: '2026-10-01T00:00:00.000Z',
};
// Per-episode covers (relative to MEDIA_BASE_URL), keyed by `${dramaId}_ep${n}`.
const EPISODE_COVERS: Record<string, string> = {
  dr_mama_ep1: 'mama-in-law-wahala/ep1/cover.jpg',
  dr_mama_ep2: 'mama-in-law-wahala/ep2/cover.jpg',
};
// Subtitle tracks (BCP-47 lang, display label); files live at <slug>/ep<n>/subs/<lang>.vtt.
const SUB_LANGS: [string, string][] = [
  ['en', 'English'],
  ['pcm', 'Naija Pidgin'],
  ['yo', 'Yorùbá'],
  ['ig', 'Igbo'],
  ['ha', 'Hausa'],
  ['fr', 'Français'],
];
const EPISODES_WITH_SUBS = new Set(['dr_mama_ep1', 'dr_mama_ep2']);
const FREE_EPISODES = 2;
// Real (non-placeholder) episode durations in seconds, keyed by `${dramaId}_ep${n}`.
const REAL_DURATIONS: Record<string, number> = { dr_mama_ep1: 86, dr_mama_ep2: 88 };
const PRICE_COINS = 30;

async function main(): Promise<void> {
  for (const t of TAGS) {
    await prisma.tag.upsert({ where: { slug: t.slug }, create: t, update: { name: t.name } });
  }
  for (const d of DRAMAS) {
    const data = {
      title: d.title,
      description: d.description,
      coverUrl: `${d.slug}/cover.jpg`,
      status: 'published',
      createdAt: new Date(CREATED_AT[d.id]),
      episodeCount: EPISODES,
      tags: { set: [], connect: d.tags.map((slug) => ({ slug })) },
    };
    await prisma.drama.upsert({
      where: { id: d.id },
      create: { id: d.id, ...data, tags: { connect: d.tags.map((slug) => ({ slug })) } },
      update: data,
    });
    for (let n = 1; n <= EPISODES; n++) {
      const free = n <= FREE_EPISODES;
      const ep = {
        title: `Episode ${n}`,
        durationSec: REAL_DURATIONS[`${d.id}_ep${n}`] ?? 10,
        hlsPath: `${d.slug}/ep${n}/master.m3u8`,
        coverPath: EPISODE_COVERS[`${d.id}_ep${n}`] ?? null,
        subtitles: EPISODES_WITH_SUBS.has(`${d.id}_ep${n}`)
          ? SUB_LANGS.map(([lang, label]) => ({ lang, label, path: `${d.slug}/ep${n}/subs/${lang}.vtt` }))
          : Prisma.DbNull,
        free,
        priceCoins: free ? 0 : PRICE_COINS,
      };
      await prisma.episode.upsert({
        where: { dramaId_episodeNo: { dramaId: d.id, episodeNo: n } },
        create: { id: `${d.id}_ep${n}`, dramaId: d.id, episodeNo: n, ...ep },
        update: ep,
      });
    }
  }
  console.log(`seeded ${DRAMAS.length} dramas x ${EPISODES} episodes`);
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
