import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { AuthUser, CurrentUser, JwtGuard } from '../auth/jwt.guard';
import { pageQuery, parse } from '../common/validate';
import { WalletService } from './wallet.service';

@Controller('wallet')
@UseGuards(JwtGuard)
export class WalletController {
  constructor(private readonly wallet: WalletService) {}

  @Get()
  get(@CurrentUser() user: AuthUser) {
    return this.wallet.getWallet(user.userId);
  }

  @Get('transactions')
  transactions(@CurrentUser() user: AuthUser, @Query() q: unknown) {
    const { page, size } = parse(pageQuery, q);
    return this.wallet.listTransactions(user.userId, page, size);
  }
}
