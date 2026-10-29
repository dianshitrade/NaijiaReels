import { HttpStatus, Inject, Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { AppException, ErrorCodes } from '../common/app.exception';
import { ENV } from '../config/config.module';
import type { Env } from '../config/env';
import { PrismaService } from '../prisma/prisma.service';

const dramaInclude = { tags: true, seasons: { orderBy: { seasonNo: 'asc' } } } satisfies Prisma.DramaInclude;
type DramaRow = Prisma.DramaGetPayload<{ include: typeof dramaInclude }>;

/** Resolve a stored cover path (`<slug>/cover.jpg`, `/media/<slug>/cover.jpg` or absolute URL) to `${MEDIA_BASE_URL}/<slug>/cover.jpg`. */
export function resolveCoverUrl(coverUrl: string | null, mediaBaseUrl: string): string | null {
  if (!coverUrl) return null;
  if (/^https?:\/\//i.test(coverUrl)) return coverUrl;
  const rel = coverUrl.replace(/^\/+/, '').replace(/^media\//, '');
  return `${mediaBaseUrl.replace(/\/+$/, '')}/${rel}`;
}

type SeasonRow = { seasonNo: number; title: string | null; coverPath: string | null };

/** Drama cover: season 1 cover when present, else the drama-level cover (fallback). */
export function dramaCoverUrl(d: { coverUrl: string | null; seasons?: SeasonRow[] }, mediaBaseUrl = ''): string | null {
  const s1 = d.seasons?.find((s) => s.seasonNo === 1 && s.coverPath);
  const raw = s1?.coverPath ?? d.coverUrl;
  return mediaBaseUrl ? resolveCoverUrl(raw, mediaBaseUrl) : raw;
}

/** Map season rows to API shape (sorted by seasonNo, absolute cover URLs, null when no cover). */
export function toSeasons(rows: SeasonRow[] | undefined, mediaBaseUrl: string) {
  return [...(rows ?? [])]
    .sort((a, b) => a.seasonNo - b.seasonNo)
    .map((s) => ({ seasonNo: s.seasonNo, title: s.title, coverUrl: resolveCoverUrl(s.coverPath, mediaBaseUrl) }));
}

export function toDrama(d: DramaRow, mediaBaseUrl = '') {
  return {
    id: d.id,
    title: d.title,
    coverUrl: dramaCoverUrl(d, mediaBaseUrl),
    tags: d.tags.map((t) => t.slug),
    episodeCount: d.episodeCount,
    description: d.description,
  };
}

/** Sort dramas by release time (createdAt), newest first, without mutating the input. */
export function newestFirst<T extends { createdAt: Date }>(rows: T[]): T[] {
  return [...rows].sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime());
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
    const newReleases = newestFirst(dramas).map((d) => this.drama(d));
    return { banners: items.slice(0, 3), sections: [{ title: 'Trending', items }, { title: 'New Releases', items: newReleases }] };
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
      seasons: toSeasons(d.seasons, this.env.MEDIA_BASE_URL),
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
