/* Idempotent seed: 3 placeholder vertical dramas x 6 episodes (HLS under backend/media). */
import { PrismaClient } from '@prisma/client';

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
const FREE_EPISODES = 2;
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
        durationSec: 10,
        hlsPath: `${d.slug}/ep${n}/master.m3u8`,
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
