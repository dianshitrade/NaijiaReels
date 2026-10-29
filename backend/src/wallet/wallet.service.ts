import { HttpStatus, Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { AppException, ErrorCodes } from '../common/app.exception';
import { PrismaService } from '../prisma/prisma.service';

type Tx = Prisma.TransactionClient;

export interface CoinChange {
  userId: string;
  amountCoins: number;
  reason: string;
  idempotencyKey: string;
  refType?: string;
  refId?: string;
}

/**
 * The ONLY place allowed to change coin balances.
 * Every change must run inside a caller-provided transaction and writes a coin_ledger row.
 */
@Injectable()
export class WalletService {
  constructor(private readonly prisma: PrismaService) {}

  async getWallet(userId: string) {
    const w = await this.prisma.wallet.findUnique({ where: { userId } });
    const u = await this.prisma.user.findUnique({ where: { id: userId }, select: { vipUntil: true } });
    return { balanceCoins: w?.balanceCoins ?? 0, bonusCoins: w?.bonusCoins ?? 0, vipUntil: u?.vipUntil?.toISOString() ?? null };
  }

  async credit(tx: Tx, c: CoinChange): Promise<number> {
    this.assertPositive(c.amountCoins);
    const w = await tx.wallet.upsert({
      where: { userId: c.userId },
      create: { userId: c.userId, balanceCoins: c.amountCoins },
      update: { balanceCoins: { increment: c.amountCoins }, version: { increment: 1 } },
    });
    await this.writeLedger(tx, c, c.amountCoins, w.balanceCoins);
    return w.balanceCoins;
  }

  async debit(tx: Tx, c: CoinChange): Promise<number> {
    this.assertPositive(c.amountCoins);
    const res = await tx.wallet.updateMany({
      where: { userId: c.userId, balanceCoins: { gte: c.amountCoins } },
      data: { balanceCoins: { decrement: c.amountCoins }, version: { increment: 1 } },
    });
    if (res.count !== 1) {
      throw new AppException(HttpStatus.PAYMENT_REQUIRED, ErrorCodes.INSUFFICIENT_COINS, 'Insufficient coins');
    }
    const w = await tx.wallet.findUniqueOrThrow({ where: { userId: c.userId } });
    await this.writeLedger(tx, c, -c.amountCoins, w.balanceCoins);
    return w.balanceCoins;
  }

  async listTransactions(userId: string, page: number, size: number) {
    const rows = await this.prisma.coinLedger.findMany({
      where: { userId },
      orderBy: { createdAt: 'desc' },
      skip: (page - 1) * size,
      take: size + 1,
    });
    return {
      items: rows.slice(0, size).map((r) => ({
        id: r.id,
        deltaCoins: r.deltaCoins,
        balanceAfterCoins: r.balanceAfterCoins,
        reason: r.reason,
        refId: r.refId,
        createdAt: r.createdAt.toISOString(),
      })),
      page,
      size,
      hasMore: rows.length > size,
    };
  }

  private assertPositive(n: number): void {
    if (!Number.isInteger(n) || n <= 0) throw new Error(`coin amount must be a positive integer, got ${n}`);
  }

  private async writeLedger(tx: Tx, c: CoinChange, delta: number, balanceAfter: number): Promise<void> {
    await tx.coinLedger.create({
      data: {
        userId: c.userId,
        deltaCoins: delta,
        balanceAfterCoins: balanceAfter,
        reason: c.reason,
        refType: c.refType,
        refId: c.refId,
        idempotencyKey: c.idempotencyKey,
      },
    });
  }
}
