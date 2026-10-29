import { HttpStatus, Inject, Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { AppException, ErrorCodes } from '../common/app.exception';
import { ENV } from '../config/config.module';
import type { Env } from '../config/env';
import { PrismaService } from '../prisma/prisma.service';

const dramaInclude = { tags: true } satisfies Prisma.DramaInclude;
type DramaRow = Prisma.DramaGetPayload<{ include: typeof dramaInclude }>;

/** Resolve a stored cover path (`<slug>/cover.jpg`, `/media/<slug>/cover.jpg` or absolute URL) to `${MEDIA_BASE_URL}/<slug>/cover.jpg`. */
export function resolveCoverUrl(coverUrl: string | null, mediaBaseUrl: string): string | null {
  if (!coverUrl) return null;
  if (/^https?:\/\//i.test(coverUrl)) return coverUrl;
  const rel = coverUrl.replace(/^\/+/, '').replace(/^media\//, '');
  return `${mediaBaseUrl.replace(/\/+$/, '')}/${rel}`;
}

export function toDrama(d: DramaRow, mediaBaseUrl = '') {
  return {
    id: d.id,
    title: d.title,
    coverUrl: mediaBaseUrl ? resolveCoverUrl(d.coverUrl, mediaBaseUrl) : d.coverUrl,
    tags: d.tags.map((t) => t.slug),
    episodeCount: d.episodeCount,
    description: d.description,
  };
}

@Injectable()
export class ContentService {
  constructor(
    private readonly prisma: PrismaService,
    @Inject(ENV) private readonly env: Env,
  ) {}

  private drama(d: DramaRow) {
    return toDrama(d, this.env.MEDIA_BASE_URL);
  }

  async home() {
    const dramas = await this.prisma.drama.findMany({
      where: { status: 'published' },
      include: dramaInclude,
      orderBy: { createdAt: 'desc' },
      take: 20,
    });
    const items = dramas.map((d) => this.drama(d));
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
    return { items: rows.slice(0, size).map((d) => this.drama(d)), page, size, hasMore: rows.length > size };
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
      ...this.drama(d),
      episodes: d.episodes.map((e) => ({
        id: e.id,
        episodeNo: e.episodeNo,
        title: e.title,
        durationSec: e.durationSec,
        free: e.free,
        locked: !e.free && !unlocked.has(e.id),
        priceCoins: e.priceCoins,
        coverUrl: resolveCoverUrl(e.coverPath, this.env.MEDIA_BASE_URL),
      })),
    };
  }
}
