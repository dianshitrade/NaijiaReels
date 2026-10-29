import { HttpStatus, Inject, Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { AppException, ErrorCodes } from '../common/app.exception';
import { ENV } from '../config/config.module';
import type { Env } from '../config/env';
import { PrismaService } from '../prisma/prisma.service';
import { WalletService } from '../wallet/wallet.service';
import { resolveCoverUrl } from '../content/content.service';
import { signMediaUrl } from './media-signer';

const PLAY_URL_TTL_SEC = 2 * 60 * 60;

@Injectable()
export class PlayService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly wallet: WalletService,
    @Inject(ENV) private readonly env: Env,
  ) {}

  private async episode(id: string) {
    const e = await this.prisma.episode.findUnique({ where: { id } });
    if (!e) throw new AppException(HttpStatus.NOT_FOUND, ErrorCodes.NOT_FOUND, 'Episode not found');
    return e;
  }

  async play(userId: string, episodeId: string) {
    const e = await this.episode(episodeId);
    if (!e.free) {
      const u = await this.prisma.unlock.findUnique({ where: { userId_episodeId: { userId, episodeId } } });
      if (!u) {
        throw new AppException(HttpStatus.FORBIDDEN, ErrorCodes.EPISODE_LOCKED, 'Episode locked', {
          priceCoins: e.priceCoins,
          vipAvailable: false,
          adAvailable: false,
        });
      }
    }
    return {
      ...signMediaUrl(this.env.MEDIA_BASE_URL, e.hlsPath, this.env.MEDIA_SIGN_SECRET, PLAY_URL_TTL_SEC),
      coverUrl: resolveCoverUrl(e.coverPath, this.env.MEDIA_BASE_URL),
    };
  }

  async unlockWithCoins(userId: string, episodeId: string) {
    const e = await this.episode(episodeId);
    if (e.free) {
      const w = await this.wallet.getWallet(userId);
      return { episodeId, method: 'coin', balanceCoins: w.balanceCoins };
    }
    try {
      const balanceCoins = await this.prisma.$transaction(async (tx) => {
        const existing = await tx.unlock.findUnique({ where: { userId_episodeId: { userId, episodeId } } });
        if (existing) return (await tx.wallet.findUnique({ where: { userId } }))?.balanceCoins ?? 0;
        await tx.unlock.create({ data: { userId, episodeId, method: 'coin', costCoins: e.priceCoins } });
        return this.wallet.debit(tx, {
          userId,
          amountCoins: e.priceCoins,
          reason: 'unlock',
          refType: 'episode',
          refId: episodeId,
          idempotencyKey: `unlock:${userId}:${episodeId}`,
        });
      });
      return { episodeId, method: 'coin', balanceCoins };
    } catch (err) {
      // concurrent duplicate unlock -> treat as idempotent success
      if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === 'P2002') {
        const w = await this.wallet.getWallet(userId);
        return { episodeId, method: 'coin', balanceCoins: w.balanceCoins };
      }
      throw err;
    }
  }
}
