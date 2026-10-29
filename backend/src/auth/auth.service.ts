import { HttpStatus, Injectable } from '@nestjs/common';
import { AppException, ErrorCodes } from '../common/app.exception';
import { PrismaService } from '../prisma/prisma.service';
import { WalletService } from '../wallet/wallet.service';
import { TokenService } from './token.service';

export const GUEST_BONUS_COINS = 100;

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly tokens: TokenService,
    private readonly wallet: WalletService,
  ) {}

  async guest(input: { deviceId: string; platform?: string; appVersion?: string }, ip?: string) {
    const existing = await this.prisma.device.findUnique({ where: { deviceId: input.deviceId }, include: { user: true } });
    let user = existing?.user;
    if (existing) {
      await this.prisma.device.update({
        where: { id: existing.id },
        data: { lastIp: ip, platform: input.platform ?? existing.platform, appVersion: input.appVersion ?? existing.appVersion },
      });
    } else {
      user = await this.prisma.$transaction(async (tx) => {
        const u = await tx.user.create({ data: { nickname: `Guest_${input.deviceId.slice(-4)}`, guest: true } });
        await tx.device.create({
          data: { deviceId: input.deviceId, userId: u.id, platform: input.platform, appVersion: input.appVersion, lastIp: ip },
        });
        await this.wallet.credit(tx, { userId: u.id, amountCoins: GUEST_BONUS_COINS, reason: 'signup_bonus', idempotencyKey: `signup:${u.id}` });
        return u;
      });
    }
    const u = user!;
    return { ...this.tokens.issue(u.id, input.deviceId), user: { id: u.id, nickname: u.nickname, guest: u.guest } };
  }

  async refresh(refreshToken: string) {
    const p = this.tokens.verify(refreshToken, 'refresh');
    const u = await this.prisma.user.findUnique({ where: { id: p.sub } });
    if (!u) throw new AppException(HttpStatus.UNAUTHORIZED, ErrorCodes.REFRESH_INVALID, 'Refresh token invalid');
    return { ...this.tokens.issue(u.id, p.did), user: { id: u.id, nickname: u.nickname, guest: u.guest } };
  }
}
