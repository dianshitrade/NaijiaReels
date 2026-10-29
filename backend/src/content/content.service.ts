import { HttpStatus, Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { AppException, ErrorCodes } from '../common/app.exception';
import { PrismaService } from '../prisma/prisma.service';

const dramaInclude = { tags: true } satisfies Prisma.DramaInclude;
type DramaRow = Prisma.DramaGetPayload<{ include: typeof dramaInclude }>;

export function toDrama(d: DramaRow) {
  return {
    id: d.id,
    title: d.title,
    coverUrl: d.coverUrl,
    tags: d.tags.map((t) => t.slug),
    episodeCount: d.episodeCount,
    description: d.description,
  };
}

@Injectable()
export class ContentService {
  constructor(private readonly prisma: PrismaService) {}

  async home() {
    const dramas = await this.prisma.drama.findMany({
      where: { status: 'published' },
      include: dramaInclude,
      orderBy: { createdAt: 'desc' },
      take: 20,
    });
    const items = dramas.map(toDrama);
    return { banners: items.slice(0, 3), sections: [{ title: 'Trending', items }, { title: 'New Releases', items: [...items].reverse() }] };
  }

  async list(tag: string | undefined, page: number, size: number) {
    const where: Prisma.DramaWhereInput = { status: 'published', ...(tag ? { tags: { some: { slug: tag } } } : {}) };
    const rows = await this.prisma.drama.findMany({
      where,
      include: dramaInclude,
      orderBy: { createdAt: 'desc' },
      skip: (page - 1) * size,
      take: size + 1,
    });
    return { items: rows.slice(0, size).map(toDrama), page, size, hasMore: rows.length > size };
  }

  async detail(id: string, userId?: string) {
    const d = await this.prisma.drama.findFirst({
      where: { id, status: 'published' },
      include: { ...dramaInclude, episodes: { orderBy: { episodeNo: 'asc' } } },
    });
    if (!d) throw new AppException(HttpStatus.NOT_FOUND, ErrorCodes.NOT_FOUND, 'Drama not found');
    const unlocked = userId
      ? new Set(
          (await this.prisma.unlock.findMany({ where: { userId, episode: { dramaId: id } }, select: { episodeId: true } })).map((u) => u.episodeId),
        )
      : new Set<string>();
    return {
      ...toDrama(d),
      episodes: d.episodes.map((e) => ({
        id: e.id,
        episodeNo: e.episodeNo,
        title: e.title,
        durationSec: e.durationSec,
        free: e.free,
        locked: !e.free && !unlocked.has(e.id),
        priceCoins: e.priceCoins,
      })),
    };
  }
}
