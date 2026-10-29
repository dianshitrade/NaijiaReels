import { Body, Controller, Get, HttpCode, HttpStatus, Param, Post, UseGuards } from '@nestjs/common';
import { z } from 'zod';
import { AuthUser, CurrentUser, JwtGuard } from '../auth/jwt.guard';
import { AppException, ErrorCodes } from '../common/app.exception';
import { parse } from '../common/validate';
import { PlayService } from './play.service';

const unlockBody = z.object({ method: z.enum(['coin', 'ad', 'vip']), adRewardToken: z.string().optional() });

@Controller('episodes')
@UseGuards(JwtGuard)
export class PlayController {
  constructor(private readonly play: PlayService) {}

  @Get(':id/play')
  playEpisode(@CurrentUser() user: AuthUser, @Param('id') id: string) {
    return this.play.play(user.userId, id);
  }

  @Post(':id/unlock')
  @HttpCode(200)
  unlock(@CurrentUser() user: AuthUser, @Param('id') id: string, @Body() body: unknown) {
    const b = parse(unlockBody, body);
    if (b.method === 'ad' && !b.adRewardToken) {
      throw new AppException(HttpStatus.BAD_REQUEST, ErrorCodes.AD_TOKEN_REQUIRED, 'adRewardToken required');
    }
    if (b.method !== 'coin') {
      throw new AppException(HttpStatus.NOT_IMPLEMENTED, ErrorCodes.NOT_IMPLEMENTED, `Unlock method ${b.method} not implemented yet`);
    }
    return this.play.unlockWithCoins(user.userId, id);
  }
}
